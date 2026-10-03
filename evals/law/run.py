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
prompt). Each run is `claude -p --bare` in a fresh working directory and a fresh,
empty CLAUDE_CONFIG_DIR: --bare skips hooks, plugins, auto-memory and CLAUDE.md
discovery, and the empty config dir holds no installed plugin to resolve. The harness
reads what the session reports loading and refuses a run that loaded anything but
Claude Code's builtins.

--bare authenticates with ANTHROPIC_API_KEY only. When it is unset, the key is read
from the macOS keychain item `anthropic-api-key`.

Writes <out>/runs/<run>.json (one record per run, schema/run-record.schema.json),
<out>/transcripts/, <out>/diffs/ and <out>/summaries/<scenario>.json
(schema/case-summary.schema.json).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import jsonschema

import sensitivity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SKILL_PATH = "plugins/laws/skills/code/SKILL.md"
RUN_SCHEMA = json.loads((HERE / "schema" / "run-record.schema.json").read_text())
MAX_TURNS = 40
RUN_TIMEOUT_SECS = 1200
ORACLE_TIMEOUT_SECS = 600
# Local build residue never reaches the agent (it differs per checkout and names the case's
# path) and never reaches a committed diff.
RESIDUE = ("__pycache__", ".pytest_cache")
FIXTURE_IGNORE = shutil.ignore_patterns(*RESIDUE)
# The only variables the session sees besides its config dir and key; anything else in the
# operator's shell (other credentials, CLAUDE_CODE_* switches) would leak or change the run.
PASSED_ENV = ("PATH", "LANG", "LC_ALL", "TMPDIR")


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
    cases = []
    for root in sorted(d for d in law_dir.iterdir() if d.is_dir()):
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


def api_key() -> str:
    if os.environ.get("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]
    found = subprocess.run(
        ["security", "find-generic-password", "-s", "anthropic-api-key", "-w"], capture_output=True, text=True
    )
    if found.returncode != 0 or not found.stdout.strip():
        die("ANTHROPIC_API_KEY is unset and the keychain has no `anthropic-api-key` item (--bare needs an API key)")
    return found.stdout.strip()


def parse_stream(lines: list[str]) -> tuple[dict, dict]:
    """The session's init message and its result message, from stream-json output."""
    messages = [json.loads(line) for line in lines if line.strip()]
    inits = [m for m in messages if m.get("type") == "system" and m.get("subtype") == "init"]
    results = [m for m in messages if m.get("type") == "result"]
    if not inits or not results:
        raise RuntimeError(f"session output has {len(inits)} init and {len(results)} result messages")
    return inits[0], results[-1]


def exit_reason(proc: subprocess.CompletedProcess) -> str:
    """Why a session failed: its result message names an API error ("Credit balance is too
    low") that stderr leaves empty."""
    said = ""
    for line in proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue  # a failing CLI may print plain text; the transcript keeps it verbatim
        if isinstance(message, dict) and message.get("type") == "result":
            said = str(message.get("result", ""))
    return f"{said} {proc.stderr.strip()[-2000:]}".strip()


def isolation_of(init: dict) -> dict:
    plugins = init.get("plugins") or []
    foreign = [p["name"] for p in plugins if p.get("path") != "builtin"]
    if foreign:
        raise RuntimeError(f"session loaded non-builtin plugins {foreign}: isolation is broken")
    if init.get("mcp_servers"):
        raise RuntimeError(f"session loaded MCP servers {init['mcp_servers']}: isolation is broken")
    return {"plugins": sorted(p["name"] for p in plugins), "mcp_servers": [], "tools": sorted(init.get("tools") or [])}


def run_one(case: Case, arm: Arm, repeat: int, model: str, key: str, out: Path) -> dict:
    run_id = run_id_of(case, arm, repeat)
    stem = run_id.replace("/", ".")
    log(f"start {run_id}")
    with tempfile.TemporaryDirectory(prefix="law-eval-run-") as tmp:
        workdir, pristine = Path(tmp) / "work", Path(tmp) / "fixture"
        config, home = Path(tmp) / "config", Path(tmp) / "home"
        shutil.copytree(case.root / "fixture", workdir, ignore=FIXTURE_IGNORE)
        shutil.copytree(case.root / "fixture", pristine, ignore=FIXTURE_IGNORE)
        config.mkdir()
        home.mkdir()
        argv = [
            "claude", "-p", "--bare",
            "--model", model,
            "--output-format", "stream-json", "--verbose",
            "--dangerously-skip-permissions",
            "--max-turns", str(MAX_TURNS),
        ]
        if arm.guidance_text is not None:
            guidance_file = Path(tmp) / "guidance.md"
            guidance_file.write_text(arm.guidance_text)
            argv += ["--append-system-prompt-file", str(guidance_file)]
        started = datetime.now(timezone.utc)
        clock = time.monotonic()
        proc = subprocess.run(
            argv,
            input=(case.root / "request.md").read_text(),
            cwd=workdir,
            env={
                **{k: os.environ[k] for k in PASSED_ENV if k in os.environ},
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
                "ANTHROPIC_API_KEY": key,
            },
            capture_output=True,
            text=True,
            timeout=RUN_TIMEOUT_SECS,
        )
        duration_ms = int((time.monotonic() - clock) * 1000)
        # Transcripts are committed with the results; the agent can run `env`.
        if key in proc.stdout:
            raise RuntimeError(f"{run_id}: the session output contains the API key; transcript not written")
        transcript = out / "transcripts" / f"{stem}.jsonl"
        transcript.write_text(proc.stdout)
        if proc.returncode != 0:
            raise RuntimeError(f"{run_id}: claude exited {proc.returncode}: {exit_reason(proc)}")
        init, result = parse_stream(proc.stdout.splitlines())
        if init.get("model") != model:
            raise RuntimeError(f"{run_id}: asked for model {model}, session reported {init.get('model')}")
        isolation = isolation_of(init)

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
        if key in changes.stdout:
            raise RuntimeError(f"{run_id}: the agent wrote the API key into its work dir; diff not written")
        diff.write_text(changes.stdout)

        oracle = subprocess.run(
            [sys.executable, str(case.root / "oracle.py"), str(workdir)],
            capture_output=True, text=True, timeout=ORACLE_TIMEOUT_SECS,
        )
        if oracle.returncode != 0:
            raise RuntimeError(f"{run_id}: oracle failed: {oracle.stderr.strip()[-2000:]}")
        verdict = json.loads(oracle.stdout)

    usage = result.get("usage") or {}
    record = {
        "schema_version": 1,
        "run_id": run_id,
        "law": case.law,
        "case": case.id,
        "case_sha256": case.sha256,
        "arm": {"name": arm.name, "guidance": arm.guidance},
        "repeat": repeat,
        "model": {"requested": model, "session": init["model"], "billed": sorted((result.get("modelUsage") or {}).keys())},
        "claude_code_version": init.get("claude_code_version", ""),
        "started_at": started.isoformat(),
        "duration_ms": duration_ms,
        "turns": result.get("num_turns", 0),
        "tokens": {
            "input": usage.get("input_tokens", 0),
            "output": usage.get("output_tokens", 0),
            "cache_read": usage.get("cache_read_input_tokens", 0),
            "cache_creation": usage.get("cache_creation_input_tokens", 0),
        },
        "cost_usd": result.get("total_cost_usd", 0.0),
        "session": {
            "session_id": init.get("session_id", ""),
            "is_error": bool(result.get("is_error")),
            "terminal_reason": str(result.get("terminal_reason") or result.get("subtype") or ""),
        },
        "isolation": isolation,
        "oracle": verdict,
        "transcript": str(transcript.relative_to(out)),
        "diff": str(diff.relative_to(out)),
    }
    jsonschema.validate(record, RUN_SCHEMA)
    (out / "runs" / f"{stem}.json").write_text(json.dumps(record, indent=2) + "\n")
    log(
        f"done  {run_id}: {verdict['verdict']} ({verdict['detail']}); turns={record['turns']} "
        f"out_tokens={record['tokens']['output']} cost=${record['cost_usd']:.2f} {duration_ms // 1000}s"
    )
    return record


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
    key = api_key()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = (args.out or HERE / "results" / args.law / stamp).resolve()
    if out.exists() and any(out.iterdir()):
        die(f"results directory already has contents: {out}")
    for sub in ("runs", "transcripts", "diffs"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    log(f"{len(cases)} case(s) x {len(arms)} arm(s) x {args.repeats} repeat(s) on {args.model} -> {out}")

    jobs = [(case, arm, n) for case in cases for arm in arms for n in range(1, args.repeats + 1)]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [(run_id_of(case, arm, n), pool.submit(run_one, case, arm, n, args.model, key, out)) for case, arm, n in jobs]
        failures = []
        for run_id, future in futures:
            try:
                future.result()
            except Exception as error:  # every failure is collected and reported below, then fails the command
                failures.append({"run_id": run_id, "error": f"{type(error).__name__}: {error}"})
                log(f"FAILED {run_id}: {error}")
    # A summary counts only the runs that have records; this file is what says others are missing.
    if failures:
        (out / "failed-runs.json").write_text(json.dumps(failures, indent=2) + "\n")
    listing = "\n  ".join(f"{f['run_id']}: {f['error']}" for f in failures)

    if len(failures) == len(jobs):
        die(f"every run failed:\n  {listing}")
    summaries = sensitivity.summarize(sensitivity.load_records(out))
    sensitivity.write_summaries(out, summaries)
    print(sensitivity.table(summaries))
    print(f"\nresults: {out}")
    if failures:
        die(f"{len(failures)} of {len(jobs)} runs failed and have no record (see failed-runs.json):\n  {listing}")


if __name__ == "__main__":
    main()
