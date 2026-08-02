#!/usr/bin/env python3
"""Adversarial PR review provider — runs a headless Claude agent (default
sonnet) as a hostile reviewer and posts its findings as a formal GitHub
review with inline comments, i.e. ordinary resolvable review threads.

[LAW:effects-at-boundaries] the agent computes: it reads the diff (plus
read-only repo context) and returns findings as JSON data. This module acts:
it posts the review, anchors comments to the diff, and verifies GitHub
accepted it. The nondeterministic part never touches the world.

[LAW:one-source-of-truth] the posted review carries a marker comment binding
it to the head SHA it reviewed. GitHub is the only record of "this SHA was
reviewed" — there is no local state to drift.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Import resolution is owned by provider_loader (loaded path) or script-mode
# sys.path (direct execution). [LAW:single-enforcer]
import github_threads
from github_threads import fetch, resolve  # noqa: F401  (contract surface)

CAPABILITIES = {
    "resolve":        True,   # findings are GitHub review threads
    "trigger":        True,   # the reviewer runs only when explicitly invoked
    "setup_check":    True,   # verifies claude + gh are usable
    "dismiss_review": False,  # posts COMMENT reviews (can't block own PR) — nothing to dismiss
}

MODEL_ENV = "ADVERSARIAL_REVIEW_MODEL"
DEFAULT_MODEL = "sonnet"
PROMPT_FILE = Path(__file__).parent / "adversarial_prompt.md"
REVIEW_TIMEOUT_S = 1200

# Embedded in the review body; binds a posted review to the SHA it reviewed.
MARKER_FMT = "<!-- adversarial-review sha={sha} -->"
MARKER_RE = re.compile(r"<!-- adversarial-review sha=([0-9a-f]{7,40}) -->")


# ---------------------------------------------------------------------------
# Diff anchoring — the set of (path, new-side line) GitHub will accept
# ---------------------------------------------------------------------------

def commentable_lines(diff_text: str) -> dict[str, set[int]]:
    """Parse a unified diff into {path: commentable new-side line numbers}.

    GitHub accepts inline review comments only on lines present in the diff
    (added or context, RIGHT side). [LAW:types-are-the-program] this set is
    the domain of legal anchors; computing it up front means an illegal
    anchor is caught here, not as an opaque 422 from the API.
    """
    lines_by_path: dict[str, set[int]] = {}
    path = None
    new_line = 0
    in_hunk = False
    for raw in diff_text.splitlines():
        # File sections begin at "diff --git"; an added content line can never
        # render as one (it would carry a leading '+'). Header matches are
        # only legal outside hunks — "+++ b/x" *inside* a hunk is an added
        # line whose content is "++ b/x", not a header.
        if raw.startswith("diff --git "):
            path = None
            in_hunk = False
        elif not in_hunk and raw.startswith("+++ b/"):
            path = raw[6:]
            lines_by_path.setdefault(path, set())
        elif not in_hunk and raw.startswith("+++ /dev/null"):
            path = None
        elif raw.startswith("@@") and path is not None:
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw)
            if not m:
                raise RuntimeError(f"Unparseable hunk header: {raw!r}")
            new_line = int(m.group(1))
            in_hunk = True
        elif in_hunk and path is not None:
            if raw.startswith("+") or raw.startswith(" "):
                lines_by_path[path].add(new_line)
                new_line += 1
            # '-' lines exist only on the old side; counter does not advance
    return lines_by_path


def anchor(finding: dict, legal: dict[str, set[int]]) -> dict:
    """Return the finding with a legal (path, line) anchor, or anchored=False.

    [LAW:no-silent-failure] a re-anchored or unanchorable finding is annotated
    in its body — the reader always sees what happened to it.
    """
    path, line = finding.get("file"), finding.get("line")
    if path in legal and line in legal[path]:
        return {**finding, "anchored": True}
    if path in legal and legal[path]:
        nearest = min(legal[path], key=lambda n: abs(n - line))
        body = (f"{finding['body']}\n\n*(anchored to nearest diff line "
                f"{nearest}; reviewer cited line {line})*")
        return {**finding, "line": nearest, "body": body, "anchored": True}
    return {**finding, "anchored": False}


# ---------------------------------------------------------------------------
# The reviewer agent — pure: context in, findings JSON out
# ---------------------------------------------------------------------------

def _contract_violation(text: str) -> str | None:
    """Check the reviewer's output against the contract; return a human-
    readable violation, or None when it conforms.

    LLM output is a trust boundary: fences or stray prose around the JSON are
    normalized here, once. Everything else — a bare finding, a top-level
    array, missing keys — is a violation named precisely so it can be fed
    back for one corrective attempt. [LAW:types-are-the-program]"""
    start = text.find("{")
    array_start = text.find("[")
    if array_start != -1 and (start == -1 or array_start < start):
        return "output is a JSON array; the contract requires one object with keys summary, findings"
    if start == -1:
        return "output contains no JSON object"
    try:
        result, _ = json.JSONDecoder().raw_decode(text[start:])
    except json.JSONDecodeError as e:
        return f"output is not valid JSON ({e})"
    if not isinstance(result.get("findings"), list) or "summary" not in result:
        return (
            "JSON object is missing required keys: the contract is "
            '{"summary": str, "findings": [...]} — a bare finding object is not the envelope'
        )
    # [LAW:types-are-the-program] the strongest true theorem about a finding:
    # file/title/body are non-empty strings, line is an int — anchor() and
    # _post_review() downstream assume exactly this, never re-check.
    typed = {"file": str, "title": str, "body": str, "line": int, "severity": str}
    severities = {"blocker", "major", "minor"}
    for i, f in enumerate(result["findings"]):
        missing = typed.keys() - f.keys()
        if missing:
            return f"finding {i} is missing keys {sorted(missing)}"
        for key, t in typed.items():
            if not isinstance(f[key], t) or isinstance(f[key], bool):
                return (
                    f'finding {i} key "{key}" must be {t.__name__}, '
                    f"got {f[key]!r} — a file-level concern still cites the "
                    "nearest relevant diff line as an integer"
                )
        if f["severity"] not in severities:
            return (
                f'finding {i} severity must be one of {sorted(severities)}, '
                f"got {f['severity']!r}"
            )
    return None


def _parse_result(text: str) -> dict:
    result, _ = json.JSONDecoder().raw_decode(text[text.find("{"):])
    return result


def _claude_once(prompt: str, model: str) -> str:
    proc = subprocess.run(
        ["claude", "-p", "--model", model, "--output-format", "json",
         "--allowedTools", "Read,Grep,Glob"],
        input=prompt, capture_output=True, text=True, timeout=REVIEW_TIMEOUT_S,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Reviewer agent exited {proc.returncode}: {proc.stderr.strip()[:2000]}"
        )
    envelope = json.loads(proc.stdout)
    if envelope.get("is_error") or envelope.get("subtype") != "success":
        raise RuntimeError(f"Reviewer agent failed: {json.dumps(envelope)[:2000]}")
    return envelope["result"].strip()


def _run_reviewer(prompt: str, model: str) -> dict:
    """One review, with a single bounded corrective retry on contract
    violation — the violation is quoted back to the model. A second
    violation is a hard failure carrying the full raw output as evidence.
    [LAW:no-silent-failure]"""
    text = _claude_once(prompt, model)
    violation = _contract_violation(text)
    if violation is None:
        return _parse_result(text)
    correction = (
        f"{prompt}\n\n---\nYour previous reply violated the output contract: "
        f"{violation}.\nYour previous reply was:\n{text[:6000]}\n\n"
        "Re-emit your review now as a SINGLE JSON object with exactly the keys "
        '"summary" and "findings" (the findings array may carry the same '
        "content). Output nothing but that object."
    )
    text = _claude_once(correction, model)
    violation = _contract_violation(text)
    if violation is not None:
        raise RuntimeError(
            f"Reviewer violated the output contract twice ({violation}). "
            f"Raw output:\n{text}"
        )
    return _parse_result(text)


def _build_prompt(owner: str, repo: str, pr_num: int, sha: str, diff: str) -> str:
    meta = json.loads(github_threads.gh(
        "pr", "view", str(pr_num), "--repo", f"{owner}/{repo}",
        "--json", "title,body",
    ))
    prior = fetch(f"https://github.com/{owner}/{repo}/pull/{pr_num}")["findings"]
    prior_block = json.dumps(
        [{"file": f["file"], "line": f["line_start"], "resolved": f["is_resolved"],
          "thread": [c["body"][:400] for c in f["thread_comments"]]}
         for f in prior],
        indent=1,
    )
    values = {
        "pr_title":      meta.get("title") or "",
        "pr_body":       (meta.get("body") or "")[:4000],
        "head_sha":      sha,
        "prior_threads": prior_block,
        "diff":          diff,
    }
    # Single-pass substitution: substituted content is never rescanned, so a
    # PR title/body containing "{diff}" (externally controlled text) cannot
    # inject into later fields. [LAW:single-enforcer]
    return re.sub(
        r"\{(pr_title|pr_body|head_sha|prior_threads|diff)\}",
        lambda m: values[m.group(1)],
        PROMPT_FILE.read_text(),
    )


# ---------------------------------------------------------------------------
# Posting — deterministic effect, verified
# ---------------------------------------------------------------------------

def _our_review_for(owner: str, repo: str, pr_num: int, sha: str) -> dict | None:
    out = github_threads.gh(
        "api", f"repos/{owner}/{repo}/pulls/{pr_num}/reviews?per_page=100",
        "--jq", "[.[] | {body, html_url, state}]",
    )
    reviews = json.loads(out) if out else []
    # [LAW:no-silent-failure] reviews come oldest-first; past the page cap the
    # marker review may exist unseen, which would break idempotency (duplicate
    # review) or stall wait() — halt rather than answer from a partial set.
    if len(reviews) >= 100:
        raise RuntimeError(
            "PR has 100+ posted reviews — pagination is not implemented and "
            "the SHA-marker idempotency check is incomplete."
        )
    for review in reviews:
        m = MARKER_RE.search(review.get("body") or "")
        if m and m.group(1) == sha:
            return review
    return None


def _post_review(owner: str, repo: str, pr_num: int, sha: str,
                 summary: str, anchored: list[dict], unanchored: list[dict]) -> dict:
    body = f"## Adversarial review\n\n{summary}\n"
    if unanchored:
        body += "\n### Findings outside the diff (not thread-anchorable)\n"
        for f in unanchored:
            body += f"\n- **{f['title']}** — `{f.get('file')}:{f.get('line')}`\n  {f['body']}\n"
    body += f"\n{MARKER_FMT.format(sha=sha)}\n"
    payload = {
        "commit_id": sha,
        # COMMENT, not REQUEST_CHANGES: GitHub forbids blocking reviews on
        # one's own PR, and the loop's convergence signal is thread state,
        # not review verdict.
        "event": "COMMENT",
        "body": body,
        "comments": [
            {"path": f["file"], "line": f["line"], "side": "RIGHT",
             "body": f"**{f['title']}** ({f['severity']})\n\n{f['body']}"}
            for f in anchored
        ],
    }
    proc = subprocess.run(
        ["gh", "api", f"repos/{owner}/{repo}/pulls/{pr_num}/reviews",
         "--method", "POST", "--input", "-"],
        input=json.dumps(payload), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Posting review failed: {proc.stderr.strip()[:2000]}\n"
            f"Payload comments: {json.dumps(payload['comments'])[:1000]}"
        )
    posted = json.loads(proc.stdout)
    if not posted.get("id"):
        raise RuntimeError(f"GitHub did not confirm the review: {proc.stdout[:1000]}")
    return posted


# ---------------------------------------------------------------------------
# Contract: setup_check / trigger / wait
# ---------------------------------------------------------------------------

def setup_check(owner: str, repo: str) -> dict:
    for binary in ("claude", "gh"):
        if not shutil.which(binary):
            return {"installed": False,
                    "message": f"`{binary}` is not on PATH — install it first."}
    auth = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if auth.returncode != 0:
        return {"installed": False,
                "message": f"gh is not authenticated: {auth.stderr.strip()[:500]}"}
    if not PROMPT_FILE.exists():
        return {"installed": False,
                "message": f"Reviewer prompt missing: {PROMPT_FILE}"}
    return {"installed": True,
            "message": f"claude + gh ready; model={os.environ.get(MODEL_ENV, DEFAULT_MODEL)}"}


def trigger(pr_url: str) -> dict:
    """Run the adversarial reviewer for the current head SHA and post the
    review. Idempotent per SHA: an existing marker review means done."""
    owner, repo, pr_num = github_threads.parse_pr(pr_url)
    refs = json.loads(github_threads.gh(
        "api", f"repos/{owner}/{repo}/pulls/{pr_num}",
        "--jq", "{head: .head.sha, base: .base.sha}",
    ))
    sha = refs["head"]
    if _our_review_for(owner, repo, pr_num, sha):
        return {"triggered": True, "note": f"review for {sha[:9]} already posted"}

    # [LAW:no-ambient-temporal-coupling] the diff is a pure function of the
    # SHAs captured above — never "the PR's diff right now", which a push
    # between calls would silently rebind. [LAW:one-source-of-truth] this one
    # value feeds both the reviewer's context and the anchor domain.
    diff = github_threads.gh(
        "api", "-H", "Accept: application/vnd.github.diff",
        f"repos/{owner}/{repo}/compare/{refs['base']}...{sha}",
    )
    if not diff:
        raise RuntimeError(f"PR #{pr_num} has an empty diff — nothing to review.")

    model = os.environ.get(MODEL_ENV, DEFAULT_MODEL)
    result = _run_reviewer(_build_prompt(owner, repo, pr_num, sha, diff), model)
    legal = commentable_lines(diff)
    placed = [anchor(f, legal) for f in result["findings"]]
    posted = _post_review(
        owner, repo, pr_num, sha, result["summary"],
        anchored=[f for f in placed if f["anchored"]],
        unanchored=[f for f in placed if not f["anchored"]],
    )
    return {"triggered": True, "review_url": posted.get("html_url"),
            "findings": len(placed)}


def wait(pr_url: str) -> dict:
    """Synchronous provider: trigger() already posted before returning, so
    wait verifies the marker review exists for the current head SHA.
    [LAW:no-silent-failure] absence means trigger never ran or never posted —
    that must halt the loop, not read as a clean review."""
    owner, repo, pr_num = github_threads.parse_pr(pr_url)
    sha = github_threads.head_sha(owner, repo, pr_num)
    review = _our_review_for(owner, repo, pr_num, sha)
    if review is None:
        raise RuntimeError(
            f"No adversarial review posted for head SHA {sha} — call "
            "provider.trigger(pr_url) first; this provider does not fire on push."
        )
    return {"status": "completed", "conclusion": "success", "sha": sha,
            "url": review.get("html_url")}


# ---------------------------------------------------------------------------
# CLI shim — direct invocation for testing and ad-hoc runs
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Adversarial PR review provider (direct)")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("trigger", "wait", "fetch"):
        p = sub.add_parser(name)
        p.add_argument("pr_url")
    p_resolve = sub.add_parser("resolve")
    p_resolve.add_argument("thread_id")
    p_setup = sub.add_parser("setup_check")
    p_setup.add_argument("owner")
    p_setup.add_argument("repo")

    args = parser.parse_args()
    try:
        if args.command == "resolve":
            out = resolve(args.thread_id)
        elif args.command == "setup_check":
            out = setup_check(args.owner, args.repo)
        else:
            out = globals()[args.command](args.pr_url)
        print(json.dumps(out, indent=2))
    except subprocess.TimeoutExpired as e:
        print(
            f"ERROR ({args.command}): reviewer agent exceeded "
            f"{REVIEW_TIMEOUT_S}s and was killed ({e.cmd[0]}).",
            file=sys.stderr,
        )
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        msg = (e.stderr or "").strip() or str(e)
        print(f"ERROR ({args.command}): {msg}", file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, ValueError) as e:
        print(f"ERROR ({args.command}): {e}", file=sys.stderr)
        sys.exit(1)
