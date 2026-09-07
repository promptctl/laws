#!/usr/bin/env python3
"""Check every verdict file against the batch it claims to cover: each PR record
present, each finding of those PRs judged exactly once, every enum value legal.
Prints one line per file and exits non-zero when any file fails, so a failed batch
can be re-dispatched by name.

    review-audit/check.py --derived review-audit/derived --verdicts review-audit/verdicts --batches review-audit/bundles/batches.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

from report import batch_judged, finding_ids, judged_prs, load_jsonl, load_verdicts

ENUMS = {
    "premise": {"correct", "partly", "wrong", "uncertain"},
    "response": {"accepted_fix", "accepted_premise_different_fix", "pushed_back", "already_fixed", "no_response", "mixed"},
    "response_correct": {"yes", "no", "uncertain"},
    "should_have": {"accepted_fix", "accepted_premise_different_fix", "pushed_back", "already_fixed", "mixed", None},
    "cause_kind": {"incomplete_fix", "regression_from_fix", "comment_drift_from_fix", "same_gap_other_instance", "new_scope", None},
    "law_citation_apt": {"yes", "no", "n/a"},
}


def check_rows(rows: list[dict], expected_by_pr: dict[str, set[str]]) -> list[str]:
    """Problems with one verdict file's rows; empty when it is whole. Pure."""
    problems: list[str] = []
    prs = [r["pr"] for r in rows if "pr" in r]
    findings = Counter(r["finding"] for r in rows if "finding" in r)
    for pr in prs:
        if pr not in expected_by_pr:
            problems.append(f"unknown PR {pr}")
            continue
        missing = sorted(expected_by_pr[pr] - set(findings))
        if missing:
            problems.append(f"{pr}: {len(missing)} findings unjudged, e.g. {missing[:3]}")
    covered = set().union(*(expected_by_pr.get(pr, set()) for pr in prs))
    for fid, n in findings.items():
        if n > 1:
            problems.append(f"{fid} judged {n} times")
        if fid not in covered:
            problems.append(f"{fid} judged but its PR has no PR record here")
    for r in rows:
        if "finding" not in r:
            continue
        for field, legal in ENUMS.items():
            if r.get(field) not in legal:
                problems.append(f"{r['finding']}: {field}={r.get(field)!r}")
        if r.get("response_correct") == "no" and not r.get("should_have"):
            problems.append(f"{r['finding']}: response_correct=no without should_have")
        if r.get("caused_by") and not r.get("cause_kind"):
            problems.append(f"{r['finding']}: caused_by without cause_kind")
    if not prs:
        problems.append("no PR record")
    return problems


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--derived", type=Path, required=True)
    ap.add_argument("--verdicts", type=Path, required=True)
    ap.add_argument("--batches", type=Path, required=True)
    args = ap.parse_args(argv)

    expected_by_pr: dict[str, set[str]] = defaultdict(set)
    for fid in finding_ids(load_jsonl(args.derived / "findings.jsonl")):
        expected_by_pr[fid.rsplit("/", 1)[0]].add(fid)

    by_file = load_verdicts(args.verdicts)
    failed = 0
    for path, rows in by_file.items():
        problems = check_rows(rows, expected_by_pr)
        status = "ok" if not problems else f"FAIL ({len(problems)}): " + "; ".join(problems[:4])
        failed += bool(problems)
        print(f"{path.name}: {status}")

    # [LAW:no-silent-failure] a finding judged by two files is a duplicate no per-file
    # check can see, and it double-counts in every report.py table. Batch ids renumber
    # on a re-bundle, so a PR can land in a differently-named batch and be judged twice.
    owners: dict[str, set[str]] = defaultdict(set)
    for path, rows in by_file.items():
        for r in rows:
            if "finding" in r:
                owners[r["finding"]].add(path.name)
    for fid, names in sorted(owners.items()):
        if len(names) > 1:
            failed += 1
            print(f"{fid}: judged by {len(names)} files: {' '.join(sorted(names))}")

    judged = judged_prs(r for rows in by_file.values() for r in rows)
    batches = json.loads(args.batches.read_text())
    pending = [b["id"] for b in batches if not batch_judged(b, judged)]
    print(f"\n{len(batches) - len(pending)} of {len(batches)} batches fully judged; {len(judged)} PRs; {failed} problems", file=sys.stderr)
    print("pending: " + " ".join(pending) if pending else "pending: none", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
