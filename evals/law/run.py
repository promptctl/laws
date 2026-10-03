#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema>=4"]
# ///
"""Run one law's eval cases under a set of arms and print its sensitivity record.

    evals/law/run.py <law> [--arm none --arm skill:HEAD] [--repeats 5]
                           [--model claude-opus-5-5] [--jobs 4] [--out DIR]

Every case directory under cases/<law>/ holds `fixture/` (the agent's starting working
directory), `request.md` (the one message it is sent) and `oracle.py` (reads the
agent's finished working directory and prints {verdict, detail}).

An arm is `none` (Claude Code's own system prompt and nothing else) or `skill:<git-ref>`
(plugins/laws/skills/code/SKILL.md as it was at that ref, appended to the system
prompt). Each run is one session on harness/ (repo root) in a fresh copy of the fixture:
the interactive TUI on the subscription login, admitting nothing but the arm's guidance.

Writes <out>/runs/<run>/ (the harness's run dir: run.json or failure.json, and the
transcript, which stays out of git: it carries the login's account identity),
<out>/records/<run>.json (schema/run-record.schema.json), <out>/diffs/ and
<out>/summaries/<scenario>.json (schema/case-summary.schema.json).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import jsonschema

import sensitivity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "harness"))

from harness import run as harness_run  # noqa: E402
from harness import tmux  # noqa: E402
from harness.session import Spec, tmux_name  # noqa: E402

SKILL_PATH = "plugins/laws/skills/code/SKILL.md"
ORACLE_TIMEOUT_SECS = 600
# Local build residue never reaches the agent (it differs per checkout and names the case's
# path) and never reaches a committed diff.
RESIDUE = ("__pycache__", ".pytest_cache")
FIXTURE_IGNORE = shutil.ignore_patterns(*RESIDUE)


def log(message: str) -> None:
    print(f"[law-eval] {message}", file=sys.stderr, flush=True)


def die(message: str) -> None:
    sys.exit(f"ERROR [law-eval]: {message}")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, check=True, capture_output=True, text=True).stdout


@dataclass(frozen=True)
class Arm:
    name: str
    guidance_text: str | None
    guidance: dict | None  # the record's arm.guidance

    @property
    def slug(self) -> str:
        return re.sub(r"[^a-z0-9]+", "-", self.name.lower()).strip("-")


def resolve_arm(spec: str) -> Arm:
    if spec == "none":
        return Arm("none", None, None)
    if not spec.startswith("skill:") or spec == "skill:":
        die(f"an arm is `none` or `skill:<git-ref>`, not {spec!r}")
    ref = spec.removeprefix("skill:")
    try:
        commit = git("rev-parse", "--verify", f"{ref}^{{commit}}").strip()
        text = git("show", f"{commit}:{SKILL_PATH}")
    except subprocess.CalledProcessError as error:
        die(f"arm {spec}: cannot read {SKILL_PATH} at {ref}: {error.stderr.strip()}")
    digest = hashlib.sha256(text.encode()).hexdigest()
    return Arm(spec, text, {"path": SKILL_PATH, "ref": ref, "commit": commit, "sha256": digest})


@dataclass(frozen=True)
class Case:
    law: str
    scenario: str
    root: Path
    sha256: str  # of everything that decides a verdict: fixture, request, oracle, differential.py

    @property
    def id(self) -> str:
        return f"{self.law}/{self.scenario}"


def load_cases(law: str) -> list[Case]:
    law_dir = HERE / "cases" / law
    if not law_dir.is_dir():
        known = sorted(p.name for p in (HERE / "cases").iterdir() if p.is_dir())
        die(f"no cases for law {law!r}; laws with cases: {', '.join(known)}")
    # A name the record schema refuses would cost every run of the case a full session first.
    name_pattern = re.compile(sensitivity.RUN_SCHEMA["properties"]["law"]["pattern"])
    cases = []
    for root in sorted(d for d in law_dir.iterdir() if d.is_dir()):
        for name in (law, root.name):
            if not name_pattern.match(name):
                die(f"case {law}/{root.name}: {name!r} must match {name_pattern.pattern}")
        for part in ("fixture", "request.md", "oracle.py"):
            if not (root / part).exists():
                die(f"case {law}/{root.name} is missing {part}")
        cases.append(Case(law, root.name, root, case_digest(root)))
    return cases


def case_digest(root: Path) -> str:
    """Ties a verdict to the exact case and oracle code that produced it."""
    files = sorted(p for p in (root / "fixture").rglob("*") if p.is_file() and not set(RESIDUE) & set(p.parts))
    files += [root / "request.md", root / "oracle.py", HERE / "differential.py"]
    digest = hashlib.sha256()
    for path in files:
        name = path.relative_to(HERE).as_posix()
        digest.update(f"{name}\0{hashlib.sha256(path.read_bytes()).hexdigest()}\n".encode())
    return digest.hexdigest()


def run_id_of(case: Case, arm: Arm, repeat: int) -> str:
    return f"{case.law}/{case.scenario}/{arm.slug}/r{repeat}"


def harness_run_id_of(run_id: str) -> str:
    # A harness run id names a tmux session, and tmux allows no "/" or ".".
    return run_id.replace("/", "_")


def run_one(case: Case, arm: Arm, repeat: int, model: str, out: Path) -> dict:
    run_id = run_id_of(case, arm, repeat)
    stem = harness_run_id_of(run_id)
    log(f"start {run_id}")
    with tempfile.TemporaryDirectory(prefix="law-eval-run-") as tmp:
        # Resolved: the harness judges isolation on resolved paths, and macOS's temp dir is a symlink.
        workdir, pristine = Path(tmp).resolve() / "work", Path(tmp).resolve() / "fixture"
        shutil.copytree(case.root / "fixture", workdir, ignore=FIXTURE_IGNORE)
        shutil.copytree(case.root / "fixture", pristine, ignore=FIXTURE_IGNORE)
        guidance_file = None
        if arm.guidance_text is not None:
            guidance_file = Path(tmp) / "guidance.md"
            guidance_file.write_text(arm.guidance_text)
        # The file's closing newline is not part of the message; the harness refuses a
        # prompt with surrounding whitespace rather than trimming it.
        request = (case.root / "request.md").read_text().removesuffix("\n")
        spec = Spec(work_dir=workdir, model=model, append_system_prompt=guidance_file)
        session = harness_run.run(spec, [request], out / "runs" / stem, stem)

        diff = out / "diffs" / f"{stem}.diff"
        for residue in [p for name in RESIDUE for p in workdir.rglob(name)]:
            shutil.rmtree(residue, ignore_errors=True)
        # `git diff --no-index` exits 1 when the trees differ, which is the expected case.
        changes = subprocess.run(
            ["git", "diff", "--no-index", "--", pristine.name, workdir.name],
            cwd=tmp, capture_output=True, text=True,
        )
        if changes.returncode not in (0, 1):
            raise RuntimeError(f"{run_id}: diffing the work dir failed: {changes.stderr.strip()}")
        diff.write_text(changes.stdout)

        oracle = subprocess.run(
            [sys.executable, str(case.root / "oracle.py"), str(workdir)],
            capture_output=True, text=True, timeout=ORACLE_TIMEOUT_SECS,
        )
        if oracle.returncode != 0:
            raise RuntimeError(f"{run_id}: oracle failed: {oracle.stderr.strip()[-2000:]}")
        verdict = json.loads(oracle.stdout)

    record = {
        "schema_version": 2,
        "run_id": run_id,
        "law": case.law,
        "case": case.id,
        "case_sha256": case.sha256,
        "arm": {"name": arm.name, "guidance": arm.guidance},
        "repeat": repeat,
        "model": model,
        "oracle": verdict,
        "session": f"runs/{stem}/run.json",
        "diff": str(diff.relative_to(out)),
    }
    jsonschema.validate(record, sensitivity.RUN_SCHEMA)
    (out / "records" / f"{stem}.json").write_text(json.dumps(record, indent=2) + "\n")
    log(
        f"done  {run_id}: {verdict['verdict']} ({verdict['detail']}); "
        f"out_tokens={session['tokens']['output']} {session['duration_ms'] // 1000}s"
    )
    return record


def stop_runs(pool: ThreadPoolExecutor, futures: list[tuple[str, Future]]) -> None:
    """Ctrl-C reaches only the main thread. Queued runs are dropped, and ending each live
    run's tmux session makes its harness turn fail at the next poll and record it."""
    pool.shutdown(wait=False, cancel_futures=True)
    for run_id, future in futures:
        if future.running():
            tmux.kill(tmux_name(harness_run_id_of(run_id)))
    pool.shutdown(wait=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("law", help="a directory name under evals/law/cases, e.g. no-silent-failure")
    parser.add_argument("--arm", action="append", dest="arms", help="none | skill:<git-ref> (repeatable; default: none, skill:HEAD)")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--model", default="claude-opus-5-5")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--out", type=Path, help="results directory (default: evals/law/results/<law>/<UTC time>)")
    args = parser.parse_args()

    if args.repeats < 1:
        die("--repeats must be at least 1")
    arm_specs = args.arms or ["none", "skill:HEAD"]
    if len(set(arm_specs)) != len(arm_specs):
        die(f"an arm is named twice: {arm_specs}")
    arms = [resolve_arm(spec) for spec in arm_specs]
    if len({a.slug for a in arms}) != len(arms):
        die(f"two arms share a slug: {[a.slug for a in arms]}")
    cases = load_cases(args.law)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = (args.out or HERE / "results" / args.law / stamp).resolve()
    if out.exists() and any(out.iterdir()):
        die(f"results directory already has contents: {out}")
    for sub in ("runs", "records", "diffs"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    log(f"{len(cases)} case(s) x {len(arms)} arm(s) x {args.repeats} repeat(s) on {args.model} -> {out}")

    jobs = [(case, arm, n) for case in cases for arm in arms for n in range(1, args.repeats + 1)]
    pool = ThreadPoolExecutor(max_workers=args.jobs)
    futures = [(case, arm, run_id_of(case, arm, n), pool.submit(run_one, case, arm, n, args.model, out)) for case, arm, n in jobs]
    failures = []
    try:
        for case, arm, run_id, future in futures:
            try:
                future.result()
            except Exception as error:  # every failure is collected and reported below, then fails the command
                failures.append({"run_id": run_id, "case": case.id, "arm": arm.name, "error": f"{type(error).__name__}: {error}"})
                log(f"FAILED {run_id}: {error}")
    except KeyboardInterrupt:
        stop_runs(pool, [(run_id, future) for _, _, run_id, future in futures])
        die(f"interrupted; partial results in {out}")
    pool.shutdown(wait=True)
    # A summary counts these in its arm's runs; they are the runs with no record.
    if failures:
        (out / "failed-runs.json").write_text(json.dumps(failures, indent=2) + "\n")
    listing = "\n  ".join(f"{f['run_id']}: {f['error']}" for f in failures)

    if len(failures) == len(jobs):
        die(f"every run failed:\n  {listing}")
    summaries = sensitivity.summarize(*sensitivity.load_results(out))
    sensitivity.write_summaries(out, summaries)
    print(sensitivity.table(summaries))
    print(f"\nresults: {out}")
    if failures:
        die(f"{len(failures)} of {len(jobs)} runs failed and have no record (see failed-runs.json):\n  {listing}")


if __name__ == "__main__":
    main()
