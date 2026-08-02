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


def _fetch_threads(owner: str, repo: str, pr_num: int) -> list[dict]:
    query = (
        "query($owner:String!,$repo:String!,$num:Int!){"
        "  repository(owner:$owner,name:$repo){"
        "    pullRequest(number:$num){"
        "      reviewThreads(first:100){"
        "        nodes{ id isResolved path line"
        "          comments(first:20){ nodes{ author{login} body } } } } } } }"
    )
    out = gh(
        "api", "graphql",
        "-f", f"query={query}",
        "-F", f"owner={owner}", "-F", f"repo={repo}", "-F", f"num={pr_num}",
        "--jq", ".data.repository.pullRequest.reviewThreads.nodes",
    )
    threads = json.loads(out) if out else []
    # jq renders a null pullRequest as the string "null" with HTTP 200; that
    # means the PR is missing or inaccessible — an error, never an empty
    # finding set. [LAW:no-silent-failure]
    if not isinstance(threads, list):
        raise RuntimeError(
            f"reviewThreads query returned {threads!r} for {owner}/{repo}#{pr_num} "
            "— the PR is missing or inaccessible, not thread-free."
        )
    # [LAW:no-silent-failure] the page caps are explicit; hitting one means
    # findings exist that this fetch did not return — that must halt, not
    # quietly read as the full set.
    if len(threads) >= 100:
        raise RuntimeError(
            "PR has 100+ review threads — pagination is not implemented and "
            "this fetch is incomplete. Do not treat it as the full finding set."
        )
    for t in threads:
        if len(t.get("comments", {}).get("nodes") or []) >= 20:
            raise RuntimeError(
                f"Thread {t['id']} has 20+ comments — pagination is not "
                "implemented and the thread chain is incomplete."
            )
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
    """
    owner, repo, pr_num = parse_pr(pr_url)
    out = gh(
        "api", f"repos/{owner}/{repo}/pulls/{pr_num}/reviews?per_page=100",
        "--jq", "[.[] | {review_id: .id, state, type: .user.type, "
                "author: .user.login, commit_id}]",
    )
    reviews = json.loads(out) if out else []
    # [LAW:no-silent-failure] past the page cap a blocking review may exist
    # unseen — that would leave it undismissed and silently block the merge.
    if len(reviews) >= 100:
        raise RuntimeError(
            "PR has 100+ posted reviews — pagination is not implemented and the "
            "change-request set is incomplete. Do not treat it as the full set."
        )
    blocking = [
        {"review_id": r["review_id"], "author": r["author"],
         "commit_id": r["commit_id"]}
        for r in reviews
        if r["state"] == "CHANGES_REQUESTED" and r["type"] == "Bot"
    ]
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
