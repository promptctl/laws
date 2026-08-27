#!/usr/bin/env python3
"""GitHub review-thread primitives shared by every provider whose findings
land as PR review threads.

[LAW:one-source-of-truth] the GraphQL thread read, the canonical Finding
shape, and the verified resolve mutation live here once. A provider that
posts ordinary GitHub review threads imports these instead of minting a
second copy that drifts.
"""

from __future__ import annotations

import json
import re
import subprocess


def gh(*args: str) -> str:
    """All shell-outs through one function. [LAW:single-enforcer]"""
    return subprocess.check_output(
        ["gh", *args], text=True, stderr=subprocess.PIPE
    ).strip()


def parse_pr(url: str) -> tuple[str, str, int]:
    m = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", url)
    if not m:
        raise ValueError(f"Not a PR URL: {url}")
    return m.group(1), m.group(2), int(m.group(3))


def head_sha(owner: str, repo: str, pr_num: int) -> str:
    return gh("api", f"repos/{owner}/{repo}/pulls/{pr_num}", "--jq", ".head.sha")


_THREADS_QUERY = (
    "query($owner:String!,$repo:String!,$num:Int!,$cursor:String){"
    "  repository(owner:$owner,name:$repo){"
    "    pullRequest(number:$num){"
    "      reviewThreads(first:100,after:$cursor){"
    "        pageInfo{ hasNextPage endCursor }"
    "        nodes{ id isResolved path line"
    "          comments(first:100){"
    "            pageInfo{ hasNextPage endCursor }"
    "            nodes{ author{login} body } } } } } } }"
)

_COMMENTS_QUERY = (
    "query($id:ID!,$cursor:String){"
    "  node(id:$id){ ... on PullRequestReviewThread {"
    "    comments(first:100,after:$cursor){"
    "      pageInfo{ hasNextPage endCursor }"
    "      nodes{ author{login} body } } } } }"
)


def _graphql(query: str, **variables) -> dict:
    """One GraphQL shell-out. [LAW:single-enforcer]

    [LAW:dataflow-not-control-flow] the variable's Python type picks the flag:
    `gh -F` type-infers its value, which would coerce an all-digit cursor or node
    id into a number and break the query, so strings go through `-f` (always raw)
    and ints through `-F`. A `None` cursor is *omitted* rather than sent empty —
    an undeclared nullable variable is null to GraphQL, whereas `-f cursor=` is
    the empty string, which is not a valid cursor.
    """
    args = ["api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        if value is None:
            continue
        args += ["-F" if isinstance(value, int) else "-f", f"{key}={value}"]
    return json.loads(gh(*args))


def _response_path(data: dict, *path: str, subject: str) -> dict:
    """Walk the response path a query asked for, or name the field that failed.

    [LAW:single-enforcer] the one place this module asks "did GraphQL give us the
    shape we asked for". Every null along the path comes back with HTTP 200, so
    without this the only signal is a bare `TypeError: 'NoneType' object is not
    subscriptable` at whichever accessor happened to touch it first — and each
    accessor would otherwise carry its own hand-written copy of the check.

    [LAW:no-silent-failure] a null on the path means the object is missing or
    inaccessible, which is an error, never an empty result set.
    """
    node: object = data
    for depth, field in enumerate(path):
        child = node.get(field) if isinstance(node, dict) else None
        if child is None:
            raise RuntimeError(
                f"GraphQL response for {subject} has no "
                f"{'.'.join(path[:depth + 1])} (querying {'.'.join(path)}) — "
                "that object is missing or inaccessible, not empty."
            )
        node = child
    return node


def _next_cursor(block: dict, *, subject: str) -> str | None:
    """The cursor naming the page after this one, or None when this page is last.

    [LAW:single-enforcer] the one place this module decides whether pagination
    continues, so both loops obey the same rule and neither can drift into
    trusting a convention the other checks.

    [LAW:no-silent-failure] `hasNextPage` true paired with no `endCursor` is a
    contradiction — another page is promised and nothing names it. Relay's
    convention says it cannot happen; GitHub's contract does not guarantee it.
    Both of the alternatives to raising are worse than a loud error: looping on
    a null cursor makes `_graphql` omit the argument and re-read page one
    forever (an unbounded hang with no error and no timeout), and stopping here
    would return a partial set as if it were whole — the exact silent partial
    fetch this pagination exists to prevent.
    """
    page_info = block["pageInfo"]
    if not page_info["hasNextPage"]:
        return None
    cursor = page_info.get("endCursor")
    if not cursor:
        raise RuntimeError(
            f"GraphQL pagination for {subject} promised another page "
            f"(hasNextPage true) but named no endCursor (got {cursor!r}). "
            "The next page cannot be requested and the set read so far is "
            "incomplete — do not treat it as the whole set."
        )
    return cursor


def _page_of_threads(owner: str, repo: str, pr_num: int, cursor: str | None) -> dict:
    data = _graphql(_THREADS_QUERY, owner=owner, repo=repo, num=pr_num, cursor=cursor)
    return _response_path(
        data, "data", "repository", "pullRequest", "reviewThreads",
        subject=f"{owner}/{repo}#{pr_num} review threads",
    )


def _complete_comments(thread: dict) -> None:
    """Walk a single thread's remaining comment pages onto its first page.

    Nested connections are why this loop is hand-written rather than delegated to
    `gh --paginate`: that flag walks one top-level connection, and the comment
    pages hang off each thread node. A truncated chain is not cosmetic — the loop
    reads `thread_comments` to see its own prior plan and the reviewer's replies,
    so dropping the tail would re-plan a finding that was already answered.
    """
    subject = f"comments of review thread {thread['id']}"
    block = thread["comments"]
    cursor = _next_cursor(block, subject=subject)
    while cursor is not None:
        data = _graphql(_COMMENTS_QUERY, id=thread["id"], cursor=cursor)
        block = _response_path(data, "data", "node", "comments", subject=subject)
        thread["comments"]["nodes"].extend(block["nodes"])
        cursor = _next_cursor(block, subject=subject)


def _fetch_threads(owner: str, repo: str, pr_num: int) -> list[dict]:
    """Every review thread on the PR, with every comment on each.

    Completeness is structural: both loops run until GitHub reports `hasNextPage`
    false, so there is no post-hoc count to compare against a page cap. The
    previous version read one page and raised when it filled, which was the right
    refusal — a partial set read as complete would report a PR clean while
    findings sat unread — but a PR that survives several review rounds crosses 100
    threads as a matter of course, and at that point the loop cannot run at all.
    [LAW:no-silent-failure] is satisfied by returning the whole set, not by
    detecting that we failed to — and when a page promises a successor it does
    not name, `_next_cursor` raises rather than let an unwalkable set pass as
    complete or the loop spin forever.
    """
    threads: list[dict] = []
    cursor: str | None = None
    while True:
        block = _page_of_threads(owner, repo, pr_num, cursor)
        threads.extend(block["nodes"])
        cursor = _next_cursor(block, subject=f"{owner}/{repo}#{pr_num} review threads")
        if cursor is None:
            break
    for thread in threads:
        _complete_comments(thread)
    return threads


def _build_findings(threads: list[dict]) -> list[dict]:
    """[LAW:dataflow-not-control-flow] one shape for every finding — reviewer-
    authored and human-authored threads are the same primitive, never separate
    code paths."""
    findings = []
    for t in threads:
        nodes = t.get("comments", {}).get("nodes") or []
        first = nodes[0] if nodes else {}
        findings.append({
            "file":            t.get("path"),
            "line_start":      t.get("line"),
            "line_end":        t.get("line"),
            "body":            first.get("body", ""),
            "author":          (first.get("author") or {}).get("login"),
            "thread_id":       t["id"],
            "is_resolved":     t.get("isResolved", False),
            "thread_comments": [
                {"author": (c.get("author") or {}).get("login"), "body": c.get("body", "")}
                for c in nodes
            ],
        })
    return findings


def fetch(pr_url: str) -> dict:
    """Return all review threads as canonical findings."""
    owner, repo, pr_num = parse_pr(pr_url)
    threads = _fetch_threads(owner, repo, pr_num)
    return {"findings": _build_findings(threads)}


def resolve(thread_id: str) -> dict:
    """Resolve one review thread and verify GitHub confirms it.
    [LAW:no-silent-failure] raises RuntimeError if confirmation is absent."""
    confirmed = gh(
        "api", "graphql",
        "-f", "query=mutation($id:ID!){resolveReviewThread(input:{threadId:$id})"
              "{thread{isResolved}}}",
        "-F", f"id={thread_id}",
        "--jq", ".data.resolveReviewThread.thread.isResolved",
    )
    if confirmed != "true":
        raise RuntimeError(
            f"resolveReviewThread did not confirm resolution for {thread_id} "
            f"(got {confirmed!r}). The thread is NOT resolved — do not move on."
        )
    return {"thread_id": thread_id, "is_resolved": True}


def change_requests(pr_url: str) -> dict:
    """Return the automated reviewer's blocking reviews — the CHANGES_REQUESTED
    reviews this round must dismiss once its findings are addressed.

    [LAW:no-silent-failure] scoped to Bot authors: a human's CHANGES_REQUESTED
    is cleared only by that human re-reviewing, never auto-dismissed. `.user.type`
    is the verified discriminator — a User can't even post CHANGES_REQUESTED on
    their own PR, so every blocking review here is a non-author, and Bot vs User
    is exactly automated-reviewer vs human.

    Read at fetch-time and dismissed by id at round end. [LAW:one-source-of-truth]
    the dismiss set is what was read and addressed, never re-derived after a push
    — the push's fresh re-review carries a new id this read never saw.

    `--paginate` walks every page of the reviews endpoint. A PR that survives
    several review rounds accumulates a review per round per re-run and crosses
    100 easily; a single-page read would silently omit the blocking review and
    leave the merge stuck with nothing to point at. Completeness is structural
    here rather than a count this function has to check afterwards.

    With `--jq`, gh applies the filter per page and concatenates the results, so
    a filter emitting one object per line yields JSONL across the whole set —
    the one shape that survives page boundaries. (A filter wrapping each page in
    `[...]` would emit one array *per page* and not parse as a single document.)
    """
    owner, repo, pr_num = parse_pr(pr_url)
    out = gh(
        "api", "--paginate", f"repos/{owner}/{repo}/pulls/{pr_num}/reviews",
        "--jq", '.[] | select(.state=="CHANGES_REQUESTED" and .user.type=="Bot")'
                ' | {review_id: .id, author: .user.login, commit_id}',
    )
    blocking = [json.loads(line) for line in out.splitlines() if line.strip()]
    return {"reviews": blocking}


def dismiss_review(pr_url: str, review_id: int, message: str) -> dict:
    """Dismiss one stale CHANGES_REQUESTED review with an explanatory message
    and verify GitHub recorded the dismissal.
    [LAW:no-silent-failure] raises RuntimeError if the review is not DISMISSED."""
    owner, repo, pr_num = parse_pr(pr_url)
    state = gh(
        "api", "--method", "PUT",
        f"repos/{owner}/{repo}/pulls/{pr_num}/reviews/{review_id}/dismissals",
        "-f", f"message={message}",
        "-f", "event=DISMISS",
        "--jq", ".state",
    )
    if state != "DISMISSED":
        raise RuntimeError(
            f"Dismissing review {review_id} was not confirmed (state={state!r}). "
            "The review still blocks the PR — do not treat the round as closed."
        )
    return {"review_id": review_id, "is_dismissed": True}
