#!/usr/bin/env python3
"""Render one markdown packet per PR from shape.py's derived rows, for a reviewing
agent to read. Pure rendering; the facts come from derived/*.jsonl.

    review-audit/bundle.py --derived review-audit/derived --out review-audit/bundles [--min-findings 1]

Also writes <out>/batches.json: PR packets grouped into batches of bounded size so
one reviewing agent reads one batch. Finding ids are `<repo>#<number>/F<i>` with i
counting findings in the order they were raised; the id is the join key every
downstream verdict carries. [LAW:one-source-of-truth]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

HUNK_TAIL_LINES = 30
ROUND_BODY_CHARS = 1800


def tail(text: str, n: int) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-n:]) if len(lines) > n else text


def render(pr: dict, findings: list[dict]) -> str:
    key = f"{pr['repo']}#{pr['number']}"
    out: list[str] = []
    out.append(f"# {key}: {pr['title']}")
    out.append(f"{pr['url']}  ")
    out.append(
        f"author `{pr['author']}` · state {pr['state']} · created {pr['created_at']} · merged {pr['merged_at']} · "
        f"+{pr['additions']}/-{pr['deletions']} in {pr['changed_files']} files · {pr['n_commits']} commits · "
        f"reviewers {', '.join(pr['reviewers']) or 'none'}"
    )
    out.append("")
    out.append("## Review rounds")
    out.append("")
    out.append("| round | reviewer | state | commit | inline comments | findings here |")
    out.append("|---|---|---|---|---|---|")
    for r in pr["rounds"]:
        out.append(f"| {r['index']} | {r['author']} | {r['state']} | {(r['commit'] or '')[:7]} | {r['inline_comments']} | {r['findings']} |")
    out.append("")
    for r in pr["rounds"]:
        if r["body"].strip():
            body = r["body"].split("\n---\n\n💡")[0].strip()
            body = body[:ROUND_BODY_CHARS] + (" …[trimmed]" if len(body) > ROUND_BODY_CHARS else "")
            out.append(f"<details><summary>round {r['index']} summary by {r['author']} ({r['state']}, {r['submitted_at']})</summary>\n\n{body}\n\n</details>")
            out.append("")
    out.append("## Findings")
    out.append("")
    for i, f in enumerate(findings, 1):
        flags = []
        if f["on_named_fix_commit"]:
            flags.append(f"ON-NAMED-FIX-COMMIT {f['original_commit'][:7]}")
        elif f["on_post_review_commit"]:
            flags.append(f"ON-POST-REVIEW-COMMIT {f['original_commit'][:7]}")
        sev = f"S{f['severity']}" if f["severity"] else "no-severity"
        out.append(f"### {key}/F{i} — round {f['round']}, {sev}, `{f['path']}:{f['line'] or f['original_line'] or '?'}`" + (f"  **[{' · '.join(flags)}]**" if flags else ""))
        out.append(f"thread `{f['thread_id']}` · raised {f['raised_at']} · resolved: {f['is_resolved']}" + (f" by {f['resolved_by']}" if f["resolved_by"] else "") + f" · outdated: {f['is_outdated']} · reply-hint: {f['response_hint']}")
        out.append("")
        out.append(f"**{f['reviewer']} wrote:**")
        out.append("")
        out.append(f["body"].strip())
        out.append("")
        if f["diff_hunk"]:
            out.append(f"<details><summary>diff hunk (last {HUNK_TAIL_LINES} lines)</summary>\n\n```diff\n{tail(f['diff_hunk'], HUNK_TAIL_LINES)}\n```\n\n</details>")
            out.append("")
        for j, r in enumerate(f["replies"], 1):
            out.append(f"**reply {j} by {r['author']} ({r['createdAt']}):**")
            out.append("")
            out.append(r["body"].strip())
            out.append("")
        if not f["replies"]:
            out.append("_no replies_")
            out.append("")
    if pr["issue_comments"]:
        out.append("## Issue comments")
        out.append("")
        for c in pr["issue_comments"]:
            out.append(f"**{c['author']} ({c['createdAt']}):**\n\n{c['body'].strip()}\n")
    return "\n".join(out) + "\n"


def batches(packets: list[tuple[str, int, int, int]], max_findings: int, max_bytes: int) -> list[dict]:
    """Group (repo, number, n_findings, n_bytes) into batches under both caps,
    never splitting a PR and never mixing repos. A PR larger than a cap is its
    own batch."""
    by_repo: dict[str, list[tuple[int, int, int]]] = defaultdict(list)
    for repo, number, n, size in packets:
        by_repo[repo].append((number, n, size))
    result: list[dict] = []
    for repo in sorted(by_repo):
        current: list[int] = []
        count = size_sum = 0
        for number, n, size in sorted(by_repo[repo]):
            if current and (count + n > max_findings or size_sum + size > max_bytes):
                result.append({"repo": repo, "prs": current, "findings": count, "bytes": size_sum})
                current, count, size_sum = [], 0, 0
            current.append(number)
            count += n
            size_sum += size
        if current:
            result.append({"repo": repo, "prs": current, "findings": count, "bytes": size_sum})
    for i, b in enumerate(result):
        b["id"] = f"batch-{i:03d}-{b['repo']}"
    return result


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--derived", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--min-findings", type=int, default=1, help="skip PRs with fewer findings than this")
    ap.add_argument("--batch-findings", type=int, default=45, help="max findings per batch")
    ap.add_argument("--batch-bytes", type=int, default=250_000, help="max packet bytes per batch")
    args = ap.parse_args(argv)

    prs = [json.loads(l) for l in (args.derived / "prs.jsonl").read_text().splitlines()]
    findings = [json.loads(l) for l in (args.derived / "findings.jsonl").read_text().splitlines()]
    by_pr: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for f in findings:
        by_pr[(f["repo"], f["number"])].append(f)

    packets: list[tuple[str, int, int, int]] = []
    for pr in prs:
        fs = sorted(by_pr[(pr["repo"], pr["number"])], key=lambda f: (f["raised_at"], f["thread_id"]))
        if len(fs) < args.min_findings:
            continue
        path = args.out / pr["repo"] / f"{pr['number']}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        text = render(pr, fs)
        path.write_text(text)
        packets.append((pr["repo"], pr["number"], len(fs), len(text.encode())))
    if not packets:  # [LAW:no-silent-failure]
        raise SystemExit("no PR reached --min-findings; nothing rendered")

    bs = batches(packets, args.batch_findings, args.batch_bytes)
    (args.out / "batches.json").write_text(json.dumps(bs, indent=1) + "\n")
    print(f"{len(packets)} packets, {sum(p[2] for p in packets)} findings, {len(bs)} batches -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
