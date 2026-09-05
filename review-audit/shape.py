#!/usr/bin/env python3
"""Derive one row per reviewer finding (and one per PR) from the raw PR JSON that
fetch.py writes. Pure: every fact here is a function of the PR file alone.

    review-audit/shape.py --data review-audit/data --out review-audit/derived

Facts derived per finding: which review round raised it, the commit it was raised
against, whether that commit landed after the first review (so the finding is on a
change made in response to review), whether that commit is one an earlier reply
named as a fix, the PR author's replies, a first-pass response class read from the
reply's opening words, and the fix commit the reply names. The response class is a
lexical hint for triage, never a verdict - the reviewing subagents read the text.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SEVERITY = re.compile(r"\*\*\[S([1-5])\]\*\*")
LAW = re.compile(r"\[LAW:([a-z-]+)\]")
FIX_SHA = re.compile(r"\b(?:fixed|landed|addressed|done|resolved|shipped|now)\s+in\s+`?([0-9a-f]{7,40})`?", re.I)
ANY_SHA = re.compile(r"`([0-9a-f]{7,40})`")

# Opening-words classes, checked in order; the first match wins.  [LAW:one-source-of-truth]
# for the lexical hint - the subagent prompt quotes these same classes back.
RESPONSE_HINTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("already_fixed", ("already fixed", "already-fixed", "already_fixed", "already addressed", "already landed", "correct at the time", "already resolved", "already the case", "where this was resolved", "resolution: already")),
    ("different_fix", ("plan: different", "different fix", "different_fix", "real issue, wrong fix", "premise holds", "right problem, wrong fix", "the premise is correct but", "valid premise", "premise is right")),
    ("pushback", ("plan: no", "plan: invalid", "plan: reject", "plan: push", "plan: declin", "plan: not ", "invalid", "pushing back", "push back", "pushback", "rejected", "not valid", "disagree", "not a bug", "not an issue", "no change", "leaving as", "won't change", "declin", "false positive", "this is intentional", "intentional", "by design", "working as intended", "no:", "plan: keep", "pre-existing", "premise is slightly off", "premise is off", "premise is wrong", "documented limitation", "unchanged spine code", "the limitation is documented", "out of scope", "not in scope")),
    ("accept", ("plan: valid", "plan: agreed", "plan: accept", "plan: real", "plan: yes", "plan: correct", "plan: fix", "plan: true", "valid", "agreed", "good catch", "correct", "accepted", "real", "yes", "fixing", "will fix", "fixed", "landed", "applied", "addressed", "resolved by", "true", "confirmed", "right", "done")),
)


def hint(reply: str) -> str:
    """First-pass response class from a reply's first 200 characters."""
    head = reply.replace("*", "").replace("_", " ").strip().lower()[:200]
    for cls, needles in RESPONSE_HINTS:
        if any(n in head for n in needles):
            return cls
    return "unclear"


def resolve_sha(short: str, commits: list[dict]) -> str | None:
    """The PR commit a short sha names, or None when it names none of them
    (squash targets, other branches). Typed absence, not a silent skip."""
    hits = [c["commit"]["oid"] for c in commits if c["commit"]["oid"].startswith(short)]
    return hits[0] if len(hits) == 1 else None


def derive(repo: str, pr: dict) -> tuple[dict, list[dict]]:
    author = (pr["author"] or {}).get("login") or "ghost"
    commits = pr["commits"]
    oid_index = {c["commit"]["oid"]: i for i, c in enumerate(commits)}
    committed_at = {c["commit"]["oid"]: c["commit"]["committedDate"] for c in commits}

    # A round is one review submission by anyone other than the PR author.
    # The author's own COMMENTED reviews are only the containers GitHub wraps
    # around thread replies, so they are not rounds.
    rounds = [r for r in pr["reviews"] if ((r["author"] or {}).get("login") or "ghost") != author]
    round_of_review = {r["id"]: i for i, r in enumerate(rounds)}
    first_review_at = rounds[0]["submittedAt"] if rounds else None
    reviewer_logins = sorted({(r["author"] or {}).get("login") or "ghost" for r in rounds})

    threads = pr["reviewThreads"]
    # Fix shas named in author replies, keyed by the time they were named, so a
    # later finding can be tested against fixes named before it was raised.
    named_fixes: list[tuple[str, str]] = []  # (createdAt, full sha)
    for t in threads:
        for c in t["comments"]:
            if ((c["author"] or {}).get("login") or "ghost") != author:
                continue
            for short in FIX_SHA.findall(c["body"]):
                full = resolve_sha(short, commits)
                if full:
                    named_fixes.append((c["createdAt"], full))

    findings: list[dict] = []
    for t in threads:
        if not t["comments"]:
            continue
        root = t["comments"][0]
        root_author = (root["author"] or {}).get("login") or "ghost"
        if root_author == author:
            continue  # the author's own thread, not a finding
        orig = (root["originalCommit"] or {}).get("oid")
        review_id = (root["pullRequestReview"] or {}).get("id")
        replies = [
            {"author": (c["author"] or {}).get("login") or "ghost", "createdAt": c["createdAt"], "body": c["body"]}
            for c in t["comments"][1:]
        ]
        author_replies = [r for r in replies if r["author"] == author]
        first_reply = author_replies[0]["body"] if author_replies else ""
        fix_shas = sorted({s for r in author_replies for s in FIX_SHA.findall(r["body"])})
        orig_at = committed_at.get(orig)
        findings.append({
            "repo": repo,
            "number": pr["number"],
            "url": pr["url"],
            "thread_id": t["id"],
            "reviewer": root_author,
            "path": t["path"],
            "line": t["line"],
            "original_line": t["originalLine"],
            "round": round_of_review.get(review_id),
            "n_rounds": len(rounds),
            "severity": int(m.group(1)) if (m := SEVERITY.search(root["body"])) else None,
            "laws_cited": sorted(set(LAW.findall(root["body"]))),
            "body": root["body"],
            "diff_hunk": root["diffHunk"],
            "original_commit": orig,
            "original_commit_index": oid_index.get(orig, -1),
            "raised_at": root["createdAt"],
            # The commit the finding was raised against landed after the first review:
            # the finding is on a change made during review, not on the original PR.
            "on_post_review_commit": bool(first_review_at and orig_at and orig_at > first_review_at),
            # ...and that commit is one the author named as a fix before this finding appeared.
            "on_named_fix_commit": any(sha == orig and at < root["createdAt"] for at, sha in named_fixes),
            "replies": replies,
            "n_author_replies": len(author_replies),
            "response_hint": hint(first_reply) if author_replies else "none",
            "laws_in_replies": sorted({l for r in author_replies for l in LAW.findall(r["body"])}),
            "fix_shas_named": fix_shas,
            "is_resolved": t["isResolved"],
            "resolved_by": (t["resolvedBy"] or {}).get("login"),
            "is_outdated": t["isOutdated"],
        })

    per_round = [
        {
            "index": i,
            "author": (r["author"] or {}).get("login") or "ghost",
            "state": r["state"],
            "submitted_at": r["submittedAt"],
            "commit": (r["commit"] or {}).get("oid"),
            "inline_comments": r["comments"]["totalCount"],
            "findings": sum(1 for f in findings if f["round"] == i),
            "body": r["body"],
        }
        for i, r in enumerate(rounds)
    ]
    pr_row = {
        "repo": repo,
        "number": pr["number"],
        "url": pr["url"],
        "title": pr["title"],
        "author": author,
        "state": pr["state"],
        "created_at": pr["createdAt"],
        "merged_at": pr["mergedAt"],
        "additions": pr["additions"],
        "deletions": pr["deletions"],
        "changed_files": pr["changedFiles"],
        "n_commits": len(commits),
        "reviewers": reviewer_logins,
        "n_rounds": len(rounds),
        "rounds": per_round,
        "n_findings": len(findings),
        "n_findings_on_post_review_commits": sum(f["on_post_review_commit"] for f in findings),
        "n_findings_on_named_fixes": sum(f["on_named_fix_commit"] for f in findings),
        "response_hints": {cls: sum(f["response_hint"] == cls for f in findings) for cls, _ in RESPONSE_HINTS + (("unclear", ()), ("none", ()))},
        "issue_comments": [{"author": (c["author"] or {}).get("login") or "ghost", "createdAt": c["createdAt"], "body": c["body"]} for c in pr["comments"]],
    }
    return pr_row, findings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)

    pr_rows: list[dict] = []
    finding_rows: list[dict] = []
    for path in sorted(args.data.glob("*/*.json")):
        pr_row, findings = derive(path.parent.name, json.loads(path.read_text()))
        pr_rows.append(pr_row)
        finding_rows.extend(findings)
    if not pr_rows:  # [LAW:no-silent-failure]
        raise SystemExit(f"no PR files under {args.data}")

    args.out.mkdir(parents=True, exist_ok=True)
    for name, rows in (("prs.jsonl", pr_rows), ("findings.jsonl", finding_rows)):
        (args.out / name).write_text("".join(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n" for r in rows))
    print(f"{len(pr_rows)} PRs, {len(finding_rows)} findings -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
