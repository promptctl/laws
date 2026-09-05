#!/usr/bin/env python3
"""Join the reviewing agents' verdicts onto the derived findings and print the
aggregate tables the analysis reads from. Pure over derived/*.jsonl and
verdicts/*.jsonl.

    review-audit/report.py --derived review-audit/derived --verdicts review-audit/verdicts [--out review-audit/derived/joined.jsonl]

Every finding id in the verdicts must exist in the derived findings and vice
versa for the PRs that were reviewed; a mismatch is an error, not a footnote.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as e:  # [LAW:no-silent-failure]
            raise SystemExit(f"{path}:{n}: not JSON: {e}\n{line[:200]}")
    return rows


def finding_ids(findings: list[dict]) -> dict[str, dict]:
    """`<repo>#<number>/F<i>` for every derived finding, i counting per PR in raised order.
    [LAW:one-source-of-truth] the same ordering bundle.py renders."""
    by_pr: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for f in findings:
        by_pr[(f["repo"], f["number"])].append(f)
    ids: dict[str, dict] = {}
    for (repo, number), fs in by_pr.items():
        for i, f in enumerate(sorted(fs, key=lambda f: (f["raised_at"], f["thread_id"])), 1):
            ids[f"{repo}#{number}/F{i}"] = f
    return ids


def table(title: str, counter: Counter, total: int | None = None) -> str:
    total = total if total is not None else sum(counter.values())
    lines = [f"### {title}", "", "| key | n | % |", "|---|---|---|"]
    for key, n in counter.most_common():
        lines.append(f"| {key} | {n} | {100 * n / total:.0f}% |" if total else f"| {key} | {n} | |")
    return "\n".join(lines) + "\n"


def cross(title: str, rows: list[tuple[str, str]]) -> str:
    """A two-way count table."""
    a_keys = sorted({a for a, _ in rows})
    b_keys = sorted({b for _, b in rows})
    c = Counter(rows)
    lines = [f"### {title}", "", "| | " + " | ".join(b_keys) + " | total |", "|---|" + "---|" * (len(b_keys) + 1)]
    for a in a_keys:
        lines.append(f"| {a} | " + " | ".join(str(c[(a, b)]) for b in b_keys) + f" | {sum(c[(a, b)] for b in b_keys)} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--derived", type=Path, required=True)
    ap.add_argument("--verdicts", type=Path, required=True)
    ap.add_argument("--out", type=Path, help="write joined finding rows here as JSONL")
    args = ap.parse_args(argv)

    findings = finding_ids(load_jsonl(args.derived / "findings.jsonl"))
    prs = {f"{p['repo']}#{p['number']}": p for p in load_jsonl(args.derived / "prs.jsonl")}

    finding_verdicts: dict[str, dict] = {}
    pr_verdicts: dict[str, dict] = {}
    for path in sorted(args.verdicts.glob("*.jsonl")):
        for row in load_jsonl(path):
            if "finding" in row:
                if row["finding"] in finding_verdicts:
                    raise SystemExit(f"{path}: duplicate verdict for {row['finding']}")
                if row["finding"] not in findings:
                    raise SystemExit(f"{path}: verdict for unknown finding {row['finding']}")
                finding_verdicts[row["finding"]] = row | {"batch": path.stem}
            elif "pr" in row:
                if row["pr"] not in prs:
                    raise SystemExit(f"{path}: verdict for unknown PR {row['pr']}")
                pr_verdicts[row["pr"]] = row | {"batch": path.stem}
            else:
                raise SystemExit(f"{path}: row is neither a finding nor a PR verdict: {json.dumps(row)[:200]}")

    reviewed_prs = set(pr_verdicts)
    expected = {fid for fid, f in findings.items() if f"{f['repo']}#{f['number']}" in reviewed_prs}
    missing = sorted(expected - set(finding_verdicts))
    if missing:
        print(f"WARNING: {len(missing)} findings of reviewed PRs have no verdict, e.g. {missing[:5]}", file=sys.stderr)

    joined = [findings[fid] | {"id": fid, "verdict": v} for fid, v in finding_verdicts.items()]
    if args.out:
        args.out.write_text("".join(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n" for r in joined))

    era = lambda f: "copilot" if f["reviewer"].startswith("copilot") else ("copirate" if f["reviewer"] == "github-actions" else "human")
    out: list[str] = []
    out.append(f"## Coverage\n\n{len(pr_verdicts)} PRs with verdicts of {len(prs)} derived · {len(joined)} findings with verdicts of {len(findings)} derived\n")
    out.append(table("response (what the agent did)", Counter(r["verdict"]["response"] for r in joined)))
    out.append(table("premise (was the reviewer right)", Counter(r["verdict"]["premise"] for r in joined)))
    out.append(cross("response × response_correct", [(r["verdict"]["response"], r["verdict"]["response_correct"]) for r in joined]))
    out.append(cross("response × should_have", [(r["verdict"]["response"], r["verdict"]["should_have"]) for r in joined]))
    out.append(cross("premise × response", [(r["verdict"]["premise"], r["verdict"]["response"]) for r in joined]))
    out.append(cross("era × response_correct", [(era(r), r["verdict"]["response_correct"]) for r in joined]))
    caused = [r for r in joined if r["verdict"].get("caused_by")]
    out.append(f"### findings caused by an earlier fix\n\n{len(caused)} of {len(joined)} ({100 * len(caused) / max(1, len(joined)):.0f}%)\n")
    out.append(table("cause_kind", Counter(r["verdict"]["cause_kind"] or "null" for r in caused)))
    out.append(cross("cause_kind × era", [(r["verdict"]["cause_kind"] or "null", era(r)) for r in caused]))
    out.append(cross("flag vs verdict: on_named_fix_commit × caused_by set", [(str(r["on_named_fix_commit"]), str(bool(r["verdict"].get("caused_by")))) for r in joined]))
    out.append(cross("flag vs verdict: on_post_review_commit × caused_by set", [(str(r["on_post_review_commit"]), str(bool(r["verdict"].get("caused_by")))) for r in joined]))
    cited = [r for r in joined if r["verdict"].get("law_cited_by_agent")]
    out.append(cross("law citation aptness × response", [(r["verdict"]["law_citation_apt"], r["verdict"]["response"]) for r in cited]))
    law_apt: Counter = Counter()
    for r in cited:
        for law in r["verdict"]["law_cited_by_agent"]:
            law_apt[(law, r["verdict"]["law_citation_apt"])] += 1
    out.append(cross("law × aptness", [k for k, n in law_apt.items() for _ in range(n)]))
    out.append(table("severity of findings caused by fixes", Counter(f"S{r['severity']}" if r["severity"] else "none" for r in caused)))
    rounds = Counter(v["rounds"] for v in pr_verdicts.values())
    out.append(table("rounds per PR", rounds))
    avoidable = sum(v["avoidable_rounds"] for v in pr_verdicts.values())
    total_rounds = sum(v["rounds"] for v in pr_verdicts.values())
    out.append(f"### avoidable rounds\n\n{avoidable} of {total_rounds} rounds ({100 * avoidable / max(1, total_rounds):.0f}%) across {len(pr_verdicts)} PRs; {sum(1 for v in pr_verdicts.values() if v['avoidable_rounds'])} PRs had at least one\n")
    out.append(table("chain lengths", Counter(len(c) for v in pr_verdicts.values() for c in v.get("chains", []))))
    out.append(table("per repo: findings caused by fixes / findings", Counter(r["repo"] for r in caused)))
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
