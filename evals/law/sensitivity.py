#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema>=4"]
# ///
"""Read a results directory's run records into one sensitivity record per case.

    evals/law/sensitivity.py <results-dir>

Rewrites <results-dir>/summaries/<scenario>.json from runs/*.json and prints the table.
run.py calls the same functions at the end of a run, so a summary is always derived
from the records on disk and never kept as a second copy of them.

A reading compares one arm against the no-guidance arm `none`, on the runs that
reached the fork (held or violated; off_fork and inconclusive runs measure nothing):

  unmeasurable       fewer than half of either arm's runs reached the fork
  saturated          every on-fork control run already held: the law costs text and buys nothing here
  separate           the arms' held/violated counts differ at p < 0.05 (two-sided Fisher exact)
  indistinguishable  anything else
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from math import comb
from pathlib import Path

import jsonschema

HERE = Path(__file__).resolve().parent
RUN_SCHEMA = json.loads((HERE / "schema" / "run-record.schema.json").read_text())
SUMMARY_SCHEMA = json.loads((HERE / "schema" / "case-summary.schema.json").read_text())
VERDICTS = ("held", "violated", "off_fork", "inconclusive")
CONTROL = "none"
ALPHA = 0.05


def fisher_two_sided(a: int, b: int, c: int, d: int) -> float:
    """p-value of the 2x2 table [[a, b], [c, d]] under fixed margins."""
    row1, col1, n = a + b, a + c, a + b + c + d

    def p(x: int) -> float:
        return comb(col1, x) * comb(n - col1, row1 - x) / comb(n, row1)

    observed = p(a)
    lo, hi = max(0, row1 + col1 - n), min(row1, col1)
    # The tolerance keeps tables whose probability equals the observed one up to float error.
    return min(1.0, sum(p(x) for x in range(lo, hi + 1) if p(x) <= observed * (1 + 1e-9)))


def reading(control: dict, arm: dict) -> tuple[str, float | None]:
    on_fork = lambda counts: counts["held"] + counts["violated"]  # noqa: E731
    if any(on_fork(c) * 2 < c["runs"] or c["runs"] == 0 for c in (control, arm)):
        return "unmeasurable", None
    if control["violated"] == 0:
        return "saturated", None
    p = fisher_two_sided(arm["held"], arm["violated"], control["held"], control["violated"])
    return ("separate" if p < ALPHA else "indistinguishable"), p


def summarize(records: list[dict]) -> list[dict]:
    by_case: dict[str, list[dict]] = {}
    for record in records:
        by_case.setdefault(record["case"], []).append(record)
    summaries = []
    for case, runs in sorted(by_case.items()):
        arms: dict[str, dict] = {}
        for name in sorted({r["arm"]["name"] for r in runs}, key=lambda n: (n != CONTROL, n)):
            mine = sorted((r for r in runs if r["arm"]["name"] == name), key=lambda r: r["repeat"])
            counts = Counter(r["oracle"]["verdict"] for r in mine)
            arms[name] = {"runs": len(mine), **{v: counts[v] for v in VERDICTS}, "run_ids": [r["run_id"] for r in mine]}
        comparisons = []
        if CONTROL in arms:
            for name in arms:
                if name != CONTROL:
                    label, p = reading(arms[CONTROL], arms[name])
                    comparisons.append({"control": CONTROL, "arm": name, "reading": label, "p_value": p})
        summary = {
            "schema_version": 1,
            "law": runs[0]["law"],
            "case": case,
            "models": sorted({r["model"]["session"] for r in runs}),
            "arms": arms,
            "comparisons": comparisons,
        }
        jsonschema.validate(summary, SUMMARY_SCHEMA)
        summaries.append(summary)
    return summaries


def load_records(results_dir: Path) -> list[dict]:
    paths = sorted((results_dir / "runs").glob("*.json"))
    if not paths:
        sys.exit(f"no run records under {results_dir / 'runs'}")
    records = [json.loads(p.read_text()) for p in paths]
    for path, record in zip(paths, records):
        try:
            jsonschema.validate(record, RUN_SCHEMA)
        except jsonschema.ValidationError as error:
            sys.exit(f"{path} does not conform to the run-record schema: {error.message}")
    return records


def write_summaries(results_dir: Path, summaries: list[dict]) -> None:
    out = results_dir / "summaries"
    out.mkdir(exist_ok=True)
    for summary in summaries:
        (out / f"{summary['case'].split('/')[1]}.json").write_text(json.dumps(summary, indent=2) + "\n")


def table(summaries: list[dict]) -> str:
    lines = [f"{'case':<34} {'arm':<16} {'held':>4} {'viol':>4} {'off':>4} {'inc':>4}   reading vs none"]
    for s in summaries:
        readings = {c["arm"]: c for c in s["comparisons"]}
        for name, c in s["arms"].items():
            r = readings.get(name)
            note = "" if r is None else r["reading"] + ("" if r["p_value"] is None else f" (p={r['p_value']:.3f})")
            lines.append(f"{s['case']:<34} {name:<16} {c['held']:>4} {c['violated']:>4} {c['off_fork']:>4} {c['inconclusive']:>4}   {note}")
        lines.append(f"{'':<34} models: {', '.join(s['models'])}")
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <results-dir>")
    results_dir = Path(sys.argv[1]).resolve()
    summaries = summarize(load_records(results_dir))
    write_summaries(results_dir, summaries)
    print(table(summaries))


if __name__ == "__main__":
    main()
