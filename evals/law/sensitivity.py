#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema>=4"]
# ///
"""Read a results directory's run records into one sensitivity record per case.

    evals/law/sensitivity.py <results-dir>

Rewrites <results-dir>/summaries/<scenario>.json from records/*.json and failed-runs.json
and prints the table. run.py calls the same functions at the end of a run, so a summary
is always derived from the files on disk and never kept as a second copy of them.

A reading compares one arm against the no-guidance arm in the same context (`none`, or
`none+diluted` for a diluted arm), on the runs that reached the fork (held or violated;
off_fork and inconclusive runs measure nothing, and neither does a failed run, which has
no record). Held is always the outcome the law wants: on an over-firing case it means
the agent added no ceremony, so `regressed` there is guidance that over-fires.

  unmeasurable       fewer than half of either arm's runs, failed ones included, reached the fork
  separate           the arm held more often than the control, at p < 0.05 (two-sided Fisher exact)
  regressed          the arm violated more often than the control, at p < 0.05
  saturated          no on-fork run of either arm violated: the law costs text and buys
                     nothing here
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
DILUTED = "+diluted"
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
    if any(on_fork(c) * 2 < c["runs"] + c["failed"] for c in (control, arm)):
        return "unmeasurable", None
    p = fisher_two_sided(arm["held"], arm["violated"], control["held"], control["violated"])
    if p < ALPHA:
        arm_rate = arm["held"] / (arm["held"] + arm["violated"])
        control_rate = control["held"] / (control["held"] + control["violated"])
        return ("separate" if arm_rate > control_rate else "regressed"), p
    return ("saturated" if control["violated"] == arm["violated"] == 0 else "indistinguishable"), p


def summarize(records: list[dict], failures: list[dict]) -> list[dict]:
    """One summary per case. A case's records must all come from one digest of its code
    and one model, and an arm's from one guidance text: a reading pooled across any of
    them measures none of them."""
    by_case: dict[str, list[dict]] = {}
    for record in records:
        by_case.setdefault(record["case"], []).append(record)
    failed_by_case: dict[str, list[dict]] = {}
    for failure in failures:
        failed_by_case.setdefault(failure["case"], []).append(failure)
    summaries = []
    for case in sorted(by_case.keys() | failed_by_case.keys()):
        runs, failed = by_case.get(case, []), failed_by_case.get(case, [])
        digests = {r["case_sha256"] for r in runs}
        if len(digests) > 1:
            sys.exit(f"{case}: records come from {len(digests)} different case digests {sorted(digests)}; summarize each separately")
        models = {r["model"] for r in runs}
        if len(models) > 1:
            sys.exit(f"{case}: records come from {len(models)} models {sorted(models)}; summarize each separately")
        arms: dict[str, dict] = {}
        names = {r["arm"]["name"] for r in runs} | {f["arm"] for f in failed}
        for name in sorted(names, key=lambda n: (n.removesuffix(DILUTED) != CONTROL, n)):
            mine = sorted((r for r in runs if r["arm"]["name"] == name), key=lambda r: r["repeat"])
            guidance = {json.dumps([r["arm"]["guidance"], r["arm"]["context"]], sort_keys=True) for r in mine}
            if len(guidance) > 1:
                sys.exit(f"{case} arm {name}: records come from {len(guidance)} different guidance texts or contexts; summarize each separately")
            counts = Counter(r["oracle"]["verdict"] for r in mine)
            arms[name] = {
                "runs": len(mine),
                **{v: counts[v] for v in VERDICTS},
                "failed": sum(f["arm"] == name for f in failed),
                "run_ids": [r["run_id"] for r in mine],
            }
        comparisons = []
        for name in arms:
            control = CONTROL + (DILUTED if name.endswith(DILUTED) else "")
            if name != control and control in arms:
                label, p = reading(arms[control], arms[name])
                comparisons.append({"control": control, "arm": name, "reading": label, "p_value": p})
        summary = {
            "schema_version": 3,
            "law": case.split("/")[0],
            "case": case,
            # A failed run carries these too, so a case whose every run failed still has them.
            "case_kind": (runs or failed)[0]["case_kind"],
            "split": (runs or failed)[0]["split"],
            "model": next(iter(models), None),
            "arms": arms,
            "comparisons": comparisons,
        }
        jsonschema.validate(summary, SUMMARY_SCHEMA)
        summaries.append(summary)
    return summaries


def load_results(results_dir: Path) -> tuple[list[dict], list[dict]]:
    """The run records, and the runs that ended without one (failed-runs.json, written by
    run.py only when some run failed)."""
    paths = sorted((results_dir / "records").glob("*.json"))
    if not paths:
        sys.exit(f"no run records under {results_dir / 'records'}")
    records = [json.loads(p.read_text()) for p in paths]
    for path, record in zip(paths, records):
        try:
            jsonschema.validate(record, RUN_SCHEMA)
        except jsonschema.ValidationError as error:
            sys.exit(f"{path} does not conform to the run-record schema: {error.message}")
    failed_path = results_dir / "failed-runs.json"
    failures = json.loads(failed_path.read_text()) if failed_path.exists() else []
    return records, failures


def write_summaries(results_dir: Path, summaries: list[dict]) -> None:
    out = results_dir / "summaries"
    out.mkdir(exist_ok=True)
    for summary in summaries:
        (out / f"{summary['case'].split('/')[1]}.json").write_text(json.dumps(summary, indent=2) + "\n")


def table(summaries: list[dict]) -> str:
    lines = [f"{'case':<40} {'arm':<24} {'held':>4} {'viol':>4} {'off':>4} {'inc':>4} {'fail':>4}   reading vs its control"]
    for s in summaries:
        readings = {c["arm"]: c for c in s["comparisons"]}
        for name, c in s["arms"].items():
            r = readings.get(name)
            note = "" if r is None else r["reading"] + ("" if r["p_value"] is None else f" (p={r['p_value']:.3f})")
            lines.append(f"{s['case']:<40} {name:<24} {c['held']:>4} {c['violated']:>4} {c['off_fork']:>4} {c['inconclusive']:>4} {c['failed']:>4}   {note}")
        lines.append(f"{'':<40} {s['case_kind']}, {s['split']}; model: {s['model']}")
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <results-dir>")
    results_dir = Path(sys.argv[1]).resolve()
    summaries = summarize(*load_results(results_dir))
    write_summaries(results_dir, summaries)
    print(table(summaries))


if __name__ == "__main__":
    main()
