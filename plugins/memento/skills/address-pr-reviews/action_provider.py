#!/usr/bin/env python3
"""GitHub Action PR review provider — implements the provider contract for the
coding-agent-review GitHub Action reviewer.

The reviewer is a GitHub Action (brandon-fryslie/coding-agent-review)
that runs on pull_request (opened, synchronize) and posts a formal PR review
with inline comments — i.e. ordinary resolvable review threads, authored by
github-actions.

Lifecycle owner is the *workflow run*, not `reviewRequests`. [LAW:no-ambient-temporal-coupling]
`wait` blocks on that owner — the run keyed to the current head SHA — never
on event-stream timing or comment counts.

Its findings land as review threads, so there is no second stream to join.
`fetch` reads the threads and nothing else. [LAW:one-source-of-truth]
"""

from __future__ import annotations

import json
import subprocess
import time
from typing import Optional

# [LAW:one-source-of-truth] thread fetch, Finding shape, and verified resolve
# are the shared GitHub primitives — imported, never copied. Import resolution
# is owned by provider_loader (loaded path) or script-mode sys.path (direct).
import github_threads
from github_threads import (  # noqa: F401  (contract surface)
    fetch,
    resolve,
    change_requests,
    dismiss_review,
)

CAPABILITIES = {
    "resolve":        True,   # GitHub review threads are resolvable
    "trigger":        False,  # fires automatically on push via GitHub Action
    "setup_check":    True,   # checks that code-review.yml workflow is installed
    "dismiss_review": True,   # github-actions posts a dismissible CHANGES_REQUESTED review
}

# The workflow file this provider watches. [LAW:one-source-of-truth]
WORKFLOW_FILE = "code-review.yml"

REGISTER_TIMEOUT_S = 300
COMPLETION_TIMEOUT_S = 3600
POLL_INTERVAL_S = 8


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _latest_run(owner: str, repo: str, sha: str) -> Optional[dict]:
    out = github_threads.gh(
        "api",
        f"repos/{owner}/{repo}/actions/workflows/{WORKFLOW_FILE}/runs"
        f"?head_sha={sha}&per_page=1",
        "--jq", ".workflow_runs",
    )
    runs = json.loads(out) if out else []
    return runs[0] if runs else None


# ---------------------------------------------------------------------------
# Contract: setup_check
# ---------------------------------------------------------------------------

def setup_check(owner: str, repo: str) -> dict:
    """Verify code-review.yml workflow is installed on the repo."""
    try:
        state = github_threads.gh(
            "api", f"repos/{owner}/{repo}/actions/workflows/{WORKFLOW_FILE}",
            "--jq", ".state",
        )
        if state == "active":
            return {"installed": True, "message": f"{WORKFLOW_FILE} is active"}
        return {
            "installed": False,
            "message": (
                f"{WORKFLOW_FILE} exists but state is '{state}' — "
                "check Actions settings on this repo."
            ),
        }
    except subprocess.CalledProcessError:
        return {
            "installed": False,
            "message": (
                f"review workflow ({WORKFLOW_FILE}) not found on "
                f"{owner}/{repo} — run the agent-code-review-setup skill in this "
                "repo and merge it to the default branch first."
            ),
        }


# ---------------------------------------------------------------------------
# Contract: wait
# ---------------------------------------------------------------------------

def wait(pr_url: str) -> dict:
    """Block until the GitHub Action run for the current head SHA completes."""
    owner, repo, pr_num = github_threads.parse_pr(pr_url)
    sha = github_threads.head_sha(owner, repo, pr_num)
    start = time.time()
    run: Optional[dict] = None
    while True:
        run = _latest_run(owner, repo, sha)
        if run and run.get("status") == "completed":
            return {
                "status":     "completed",
                "conclusion": run.get("conclusion"),
                "sha":        sha,
                "url":        run.get("html_url"),
            }
        deadline = COMPLETION_TIMEOUT_S if run else REGISTER_TIMEOUT_S
        if time.time() - start >= deadline:
            break
        time.sleep(POLL_INTERVAL_S)
    if run is None:
        raise RuntimeError(
            f"No review run ({WORKFLOW_FILE}) registered for {sha} within "
            f"{REGISTER_TIMEOUT_S}s. Is the workflow installed on this repo "
            "(run the agent-code-review-setup skill) and are Actions enabled?"
        )
    raise RuntimeError(
        f"review run for {sha} did not complete within {COMPLETION_TIMEOUT_S}s "
        f"(status: {run.get('status')}). The runner may be wedged: {run.get('html_url')}"
    )


# ---------------------------------------------------------------------------
# Contract: fetch / resolve — re-exported from github_threads at the top of
# this module; the reviewer's findings are ordinary GitHub review threads.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# CLI shim — lets the provider be invoked directly. The skill's SKILL.md
# drives the provider through provider_loader, not this module.
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="GitHub Action PR review provider (direct)")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("wait", "fetch"):
        p = sub.add_parser(name)
        p.add_argument("pr_url")
        p.set_defaults(func=globals()[name])
    p_resolve = sub.add_parser("resolve")
    p_resolve.add_argument("thread_id")
    p_resolve.set_defaults(func=resolve)

    args = parser.parse_args()
    try:
        if args.command in ("wait", "fetch"):
            print(json.dumps(args.func(args.pr_url), indent=2))
        else:
            print(json.dumps(args.func(args.thread_id), indent=2))
    except subprocess.CalledProcessError as e:
        msg = (e.stderr or "").strip() or str(e)
        print(f"ERROR ({args.command}): {msg}", file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, ValueError) as e:
        print(f"ERROR ({args.command}): {e}", file=sys.stderr)
        sys.exit(1)
