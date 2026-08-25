#!/usr/bin/env python3
"""Tests for github_threads' pagination and response-shape handling.

This module is what finds OPEN review findings on a PR, so a silent partial
fetch here reports a clean review on a PR that still has outstanding findings.
Every test below therefore fakes a `gh` that pages, and asserts the WHOLE set
comes back — not that the call was made.

The fake stands at the subprocess seam (`github_threads.subprocess`), which is
the outermost edge this module owns: everything inside it — argv construction,
`-f`/`-F` flag selection, cursor threading, JSON parsing, JSONL splitting —
runs for real. Nothing here reaches into a private helper's internals, so the
loops can be rewritten freely as long as they still return every page.
[LAW:behavior-not-structure]

No test touches the network; the fake refuses any argv it was not taught.

Run: python3 github_threads.test.py
"""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "github_threads", os.path.join(HERE, "github_threads.py")
)
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)

failures = []


def check(name, condition, detail=""):
    print(f"ok   - {name}" if condition else f"FAIL - {name}: {detail}")
    if not condition:
        failures.append(name)


def check_raises(name, exc_type, fn, must_mention=()):
    try:
        fn()
    except exc_type as e:
        missing = [m for m in must_mention if m not in str(e)]
        check(name, not missing, f"message {str(e)!r} omits {missing}")
    except BaseException as e:  # noqa: BLE001 - the wrong error type IS the failure
        check(name, False, f"raised {type(e).__name__}: {e}")
    else:
        check(name, False, "did not raise")


# --- the fake gh ----------------------------------------------------------


class FakeGh:
    """A `gh` binary made of data. Substituted for the subprocess module.

    Two things it deliberately refuses rather than tolerates: an argv the test
    did not teach it, and more calls than any correct loop could make. The
    second is what turns a runaway pagination loop into a failed test instead
    of a hung suite.
    """

    CALL_CAP = 25
    PIPE = -1

    def __init__(self, handler):
        self.handler = handler
        self.calls = []

    def check_output(self, argv, text=True, stderr=None):
        assert argv[0] == "gh", argv
        args = list(argv[1:])
        self.calls.append(args)
        if len(self.calls) > self.CALL_CAP:
            raise RuntimeError(f"runaway pagination: {len(self.calls)} gh calls")
        return self.handler(args)


def install(handler):
    fake = FakeGh(handler)
    gt.subprocess = fake
    return fake


def gh_vars(args):
    """The `-f`/`-F key=value` pairs off a gh argv, as gh would read them."""
    out = {}
    i = 0
    while i < len(args):
        if args[i] in ("-f", "-F"):
            key, _, value = args[i + 1].partition("=")
            out[key] = value
            i += 2
        else:
            i += 1
    return out


# --- fixtures -------------------------------------------------------------


def comment(login, body):
    return {"author": {"login": login}, "body": body}


def thread_node(tid, comments, has_next=False, end=None):
    return {
        "id": tid, "isResolved": False, "path": "a.py", "line": 7,
        "comments": {
            "pageInfo": {"hasNextPage": has_next, "endCursor": end},
            "nodes": comments,
        },
    }


def threads_page(nodes, has_next=False, end=None):
    return {"data": {"repository": {"pullRequest": {"reviewThreads": {
        "pageInfo": {"hasNextPage": has_next, "endCursor": end},
        "nodes": nodes,
    }}}}}


def comments_page(nodes, has_next=False, end=None):
    return {"data": {"node": {"comments": {
        "pageInfo": {"hasNextPage": has_next, "endCursor": end},
        "nodes": nodes,
    }}}}


def paged_graphql(thread_pages, comment_pages=None):
    """A gh whose GraphQL answers are keyed by the cursor it was handed.

    An ABSENT cursor variable is the first page — that is the contract
    `_graphql` documents (omitted, not empty). A cursor sent as the empty
    string is a bug this fake refuses to paper over.
    """
    comment_pages = comment_pages or {}

    def handler(args):
        if args[:2] != ["api", "graphql"]:
            raise AssertionError(f"unexpected gh call: {args}")
        variables = gh_vars(args)
        if "cursor" in variables and variables["cursor"] == "":
            raise AssertionError("cursor sent as empty string, not omitted")
        cursor = variables.get("cursor")
        pages = thread_pages if "reviewThreads(" in variables["query"] else comment_pages
        if cursor not in pages:
            raise AssertionError(f"no fixture page for cursor {cursor!r}")
        return json.dumps(pages[cursor])

    return handler


PR = "https://github.com/o/r/pull/7"


# --- multi-page thread fetch ---------------------------------------------

fake = install(paged_graphql({
    None: threads_page([thread_node("t1", [comment("bot", "one")]),
                        thread_node("t2", [comment("bot", "two")])],
                       has_next=True, end="cursor-A"),
    "cursor-A": threads_page([thread_node("t3", [comment("bot", "three")])],
                             has_next=True, end="cursor-B"),
    "cursor-B": threads_page([thread_node("t4", [comment("bot", "four")])]),
}))
findings = gt.fetch(PR)["findings"]
check("threads: every page accumulates",
      [f["thread_id"] for f in findings] == ["t1", "t2", "t3", "t4"],
      f'got {[f["thread_id"] for f in findings]}')
check("threads: last page's content survives",
      findings[-1]["body"] == "four", f"got {findings[-1]['body']!r}")
check("threads: first request omits the cursor variable",
      "cursor" not in gh_vars(fake.calls[0]), f"got {fake.calls[0]}")
check("threads: later requests thread the endCursor through",
      [gh_vars(c).get("cursor") for c in fake.calls[:3]] == [None, "cursor-A", "cursor-B"],
      f"got {[gh_vars(c).get('cursor') for c in fake.calls[:3]]}")


# --- multi-page comment fetch inside _complete_comments -------------------

fake = install(paged_graphql(
    thread_pages={
        None: threads_page([thread_node(
            "t1", [comment("bot", "c1")], has_next=True, end="cc-A")]),
    },
    comment_pages={
        "cc-A": comments_page([comment("human", "c2")], has_next=True, end="cc-B"),
        "cc-B": comments_page([comment("bot", "c3")]),
    },
))
bodies = [c["body"] for c in gt.fetch(PR)["findings"][0]["thread_comments"]]
check("comments: every page accumulates onto the thread",
      bodies == ["c1", "c2", "c3"], f"got {bodies}")


# --- cursor omission is end-of-pages, not a page to fetch -----------------
# A final page reports hasNextPage false and OMITS endCursor entirely. The loop
# must stop there rather than fetching a null cursor (which re-reads page one
# forever) or treating the missing field as a hard error.

fake = install(paged_graphql({
    None: threads_page([thread_node("t1", [comment("bot", "one")])], has_next=True,
                       end="cursor-A"),
    "cursor-A": {"data": {"repository": {"pullRequest": {"reviewThreads": {
        "pageInfo": {"hasNextPage": False},
        "nodes": [thread_node("t2", [comment("bot", "two")])],
    }}}}},
}))
findings = gt.fetch(PR)["findings"]
check("cursor omission: loop terminates on the endCursor-less last page",
      [f["thread_id"] for f in findings] == ["t1", "t2"],
      f'got {[f["thread_id"] for f in findings]}')
check("cursor omission: no extra page was requested",
      len(fake.calls) == 2, f"made {len(fake.calls)} gh calls: {fake.calls}")


# --- --paginate + --jq JSONL concatenation in change_requests -------------
# Real gh applies the --jq filter per page and concatenates the results, so the
# body is JSONL spanning page boundaries — with a trailing newline per page,
# which is why blank lines have to survive parsing.

def reviews_handler(args):
    if args[:2] != ["api", "--paginate"]:
        raise AssertionError(f"unexpected gh call: {args}")
    if args[2] != "repos/o/r/pulls/7/reviews":
        raise AssertionError(f"unexpected endpoint: {args[2]}")
    page_one = '{"review_id": 11, "author": "bot", "commit_id": "aaa"}\n'
    page_two = '{"review_id": 12, "author": "bot", "commit_id": "bbb"}\n'
    return (page_one + "\n" + page_two).strip()


fake = install(reviews_handler)
reviews = gt.change_requests(PR)["reviews"]
check("change_requests: JSONL from every page is parsed",
      [r["review_id"] for r in reviews] == [11, 12], f"got {reviews}")
check("change_requests: asks gh to walk every page",
      "--paginate" in fake.calls[0], f"got {fake.calls[0]}")


# --- response-shape helper: a null at each level names that field ----------

def null_at(*, repository=..., pull_request=..., review_threads=...):
    inner = {}
    if review_threads is not ...:
        inner["reviewThreads"] = review_threads
    pr = inner if pull_request is ... else pull_request
    repo = {"pullRequest": pr} if repository is ... else repository
    return lambda args: json.dumps({"data": {"repository": repo}})


for field, handler in [
    ("data.repository", null_at(repository=None)),
    ("data.repository.pullRequest", null_at(pull_request=None)),
    ("data.repository.pullRequest.reviewThreads", null_at(review_threads=None)),
]:
    install(handler)
    check_raises(f"shape: null {field} raises a diagnosable error",
                 RuntimeError, lambda: gt.fetch(PR), must_mention=(field, "o/r#7"))

install(lambda args: json.dumps({"notdata": {}}))
check_raises("shape: null data raises a diagnosable error",
             RuntimeError, lambda: gt.fetch(PR), must_mention=("data",))


def null_node_handler(args):
    variables = gh_vars(args)
    if "reviewThreads(" in variables["query"]:
        return json.dumps(threads_page([thread_node(
            "t1", [comment("bot", "c1")], has_next=True, end="cc-A")]))
    return json.dumps({"data": {"node": None}})


install(null_node_handler)
check_raises("shape: null data.node in the comment page names that field",
             RuntimeError, lambda: gt.fetch(PR),
             must_mention=("data.node", "t1"))


print(f"\n{len(failures)} failing" if failures else "\nall passing")
sys.exit(1 if failures else 0)
