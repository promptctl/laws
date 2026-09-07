#!/usr/bin/env python3
"""Run classifying agents over batches of PR-review packets, one agent per batch.

    review-audit/run_batches.py --list [--repo NAME]
    review-audit/run_batches.py batch-081-links-issue-tracker batch-082-links-issue-tracker

Each agent reads `prompts/classify.md`, reads its batch's packets, and writes
`verdicts/<batch-id>.jsonl`. The agent runs with no shell and no web tools, so the
packet is the whole world it can see: the same batch judged twice consults the same
bytes, and nothing here spends a GitHub call. Everything the classifier used to fetch
live now rides in the packet - see `bundle.py`.

Re-runnable: a batch whose PRs are all judged already is skipped, so an interrupted run
resumes by being run again. Judged means a verdict record names the PR - never that a
file of a particular name exists. Batch ids are positional, so re-bundling renames them
and a name says nothing about what was judged. `report.judged_prs` is the one definition
and `check.py` is the judge of whether a verdict file is good; this script runs it once
at the end and reports what it says.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from report import batch_judged, judged_prs, load_jsonl, load_verdicts

# The agent reads packets and writes one verdict file. It gets no shell and no network:
# determinism enforced by the harness, not requested in prose. Verified against the CLI -
# `--allowedTools` alone does NOT deny Bash; only `--disallowedTools` does.
DENIED = ["Bash", "WebFetch", "WebSearch", "Task"]


def envelope(batch_id: str, prompt: Path, packets: list[Path], out: Path) -> str:
    """The one-turn instruction handed to an agent. The craft lives in classify.md;
    this only says which batch, which files, and where the answer goes."""
    listing = "\n".join(f"- {p}" for p in packets)
    return (
        f"Read {prompt} and follow it exactly.\n\n"
        f"Batch id: {batch_id}\n\n"
        f"Your packets, all of them:\n{listing}\n\n"
        f"Write your verdicts to exactly this path: {out}\n"
    )


def run_one(batch: dict, prompt: Path, bundles: Path, verdicts: Path, model: str) -> tuple[str, str]:
    """Judge one batch. Returns (batch id, "" if it produced a parseable file else why not)."""
    bid = batch["id"]
    out = verdicts / f"{bid}.jsonl"
    packets = [bundles / batch["repo"] / f"{n}.md" for n in batch["prs"]]
    missing = [str(p) for p in packets if not p.exists()]
    if missing:  # [LAW:no-silent-failure] a packet gone means bundle.py has not been re-run
        return bid, f"packets missing (run bundle.py): {missing[:3]}"

    proc = subprocess.run(
        ["claude", "-p", envelope(bid, prompt, packets, out),
         "--model", model,
         "--disallowedTools", *DENIED,
         "--permission-mode", "dontAsk",
         "--output-format", "json"],
        text=True, capture_output=True,
    )
    if proc.returncode != 0:  # [LAW:no-silent-failure]
        return bid, f"claude exited {proc.returncode}: {proc.stderr.strip()[:300]}"
    try:
        report = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return bid, f"claude output was not JSON: {proc.stdout[:300]}"
    if report.get("is_error"):
        return bid, f"agent reported an error: {str(report.get('result'))[:300]}"
    if not out.exists():
        return bid, f"agent wrote no file; it said: {str(report.get('result'))[:300]}"
    for n, line in enumerate(out.read_text().splitlines(), 1):
        if line.strip():
            try:
                json.loads(line)
            except json.JSONDecodeError as e:
                return bid, f"{out.name}:{n} is not JSON: {e}"
    return bid, ""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("batches", nargs="*", help="batch ids to run; omit with --list to see what is unjudged")
    ap.add_argument("--bundles", type=Path, default=Path("review-audit/bundles"))
    ap.add_argument("--verdicts", type=Path, default=Path("review-audit/verdicts"))
    ap.add_argument("--derived", type=Path, default=Path("review-audit/derived"))
    ap.add_argument("--prompt", type=Path, default=Path("review-audit/prompts/classify.md"))
    ap.add_argument("--repo", help="with --list, only batches of this repo")
    ap.add_argument("--list", action="store_true", help="print unjudged batch ids and exit, running nothing")
    ap.add_argument("--workers", type=int, default=3, help="batches judged at once")
    ap.add_argument("--model", default="opus")
    args = ap.parse_args(argv)

    index = json.loads((args.bundles / "batches.json").read_text())
    # [LAW:one-source-of-truth] check.py answers "is this judged" the same way, from the
    # same function. A filename answered it differently, and the two clocks disagreed.
    judged = judged_prs(r for rows in load_verdicts(args.verdicts).values() for r in rows)
    unjudged = [b for b in index if not batch_judged(b, judged)]

    if args.list:
        rows = [b for b in unjudged if args.repo in (None, b["repo"])]
        for b in rows:
            print(f"{b['id']}\t{b['findings']} findings\tPRs {b['prs']}")
        print(f"{len(rows)} unjudged batches, {sum(b['findings'] for b in rows)} findings", file=sys.stderr)
        return 0

    if not args.batches:  # [LAW:no-silent-failure] refuse to guess what to spend on
        raise SystemExit("name the batch ids to run, or pass --list to see what is unjudged")
    by_id = {b["id"]: b for b in index}
    unknown = [b for b in args.batches if b not in by_id]
    if unknown:  # [LAW:parse-dont-validate] every id resolves before any agent starts
        raise SystemExit(f"no such batch in {args.bundles / 'batches.json'}: {unknown}")
    wanted, done = [], []
    for b in (by_id[i] for i in args.batches):
        (done if batch_judged(b, judged) else wanted).append(b)
    if done:  # skipping is fine; skipping silently is not
        print(f"already judged, not re-running: {' '.join(b['id'] for b in done)}", file=sys.stderr)

    # [LAW:no-silent-failure] the batch is not fully judged and its output name is already
    # taken. Writing there would destroy judged verdicts, so refuse before spending
    # anything - and say which of the two causes it is, because the remedies differ.
    taken = []
    for b in wanted:
        path = args.verdicts / f"{b['id']}.jsonl"
        if not path.exists():
            continue
        covered = {r["pr"] for r in load_jsonl(path) if "pr" in r}
        mine = {f"{b['repo']}#{n}" for n in b["prs"]}
        stray = len(covered - mine)
        taken.append(
            f"  {b['id']}: {path.name} judges {len(covered & mine)} of this batch's {len(mine)} PRs"
            + (f", plus {stray} that are not in it" if stray else "")
            + f"; missing here: {sorted(mine - covered)}"
        )
    if taken:
        raise SystemExit(
            "verdict files already occupy the output path of batches that are not fully judged:\n"
            + "\n".join(taken)
            + "\n\nEither the batch grew since its file was written (new PRs arrived), or a "
            "re-bundle gave a different batch this positional id. Judge the missing PRs into "
            "the existing file, or move that file aside to redo the batch whole."
        )

    prompt = args.prompt.resolve()
    if not prompt.exists():
        raise SystemExit(f"no classifier prompt at {prompt}")
    args.verdicts.mkdir(parents=True, exist_ok=True)

    failures = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        run = lambda b: run_one(b, prompt, args.bundles.resolve(), args.verdicts.resolve(), args.model)
        for bid, why in pool.map(run, wanted):
            print(f"{bid}: {why or 'ok'}", file=sys.stderr)
            if why:
                failures.append(bid)

    # [LAW:single-enforcer] check.py decides whether a verdict file is good. Not this script.
    print("\n--- check.py ---", file=sys.stderr)
    checked = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "check.py"),
         "--derived", str(args.derived), "--verdicts", str(args.verdicts),
         "--batches", str(args.bundles / "batches.json")],
        text=True,
    )
    if failures:
        print(f"\n{len(failures)} batches produced nothing usable, re-run them by name: {' '.join(failures)}", file=sys.stderr)
    return 1 if failures or checked.returncode else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
