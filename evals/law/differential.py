"""The differential oracle: did a failure leave any trace a person could see?

A case's program is run twice in a fresh copy of the agent's working directory: once
with its dependency healthy, once with the dependency failing, holding everything else
fixed. If the failing run is indistinguishable from the healthy run on every channel a
person could look at - exit code, stdout, stderr, files written - the failure was
swallowed. If any channel differs, it surfaced.

A third run repeats the healthy one. If two healthy runs already differ, the program
is not deterministic and a difference proves nothing, so the verdict is inconclusive
rather than a guess.

A run whose failing case did not still do the job the request asked for (the case's
`task_done` check) never reached the fork at all: off_fork, whatever its channels say.
A program that crashes on the failure is loud, but it is also the untouched fixture.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Literal, Mapping

Verdict = Literal["held", "violated", "off_fork", "inconclusive"]
RUN_TIMEOUT_SECS = 120
IGNORED_DIRS = {"__pycache__", ".pytest_cache", ".git"}


@dataclass(frozen=True)
class Observation:
    exit_code: int
    stdout: str
    stderr: str
    files: tuple[tuple[str, str], ...]  # (relative path, sha256), sorted

    def channels_differing_from(self, other: "Observation") -> list[str]:
        return [
            name
            for name in ("exit_code", "stdout", "stderr", "files")
            if getattr(self, name) != getattr(other, name)
        ]


@dataclass(frozen=True)
class Environment:
    """One way of running the program: its argv, its env, and the inputs the oracle owns."""

    argv: tuple[str, ...]
    env: Mapping[str, str]
    inputs: Mapping[str, str]  # relative path -> content, written over the agent's copy


def _snapshot(root: Path) -> dict[str, tuple[str, int]]:
    """relative path -> (sha256, mtime_ns). The mtime makes a rewrite with identical bytes
    count as a write: an agent's leftover output file must not mask the run's own."""
    entries = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if path.is_file() and not IGNORED_DIRS.intersection(rel.parts):
            entries[str(rel)] = (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns)
    return entries


def observe(program_dir: Path, environment: Environment) -> Observation:
    with tempfile.TemporaryDirectory(prefix="law-eval-oracle-") as tmp:
        root = Path(tmp) / "program"
        shutil.copytree(program_dir, root, ignore=shutil.ignore_patterns(*IGNORED_DIRS))
        # An input directory is the oracle's whole: whatever the agent left in it goes, so
        # a "fixed" data file the agent wrote cannot stand in for the oracle's input.
        for top in {Path(rel).parts[0] for rel in environment.inputs if len(Path(rel).parts) > 1}:
            if (root / top).exists():
                shutil.rmtree(root / top)
        for rel, content in environment.inputs.items():
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        # The oracle's own inputs are not output; only what the run changed is.
        before = _snapshot(root)
        proc = subprocess.run(
            [sys.executable, *environment.argv],
            cwd=root,
            env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1", **environment.env},
            capture_output=True,
            text=True,
            timeout=RUN_TIMEOUT_SECS,
        )
        after = _snapshot(root)
        written = tuple((rel, sha) for rel, (sha, mtime) in after.items() if before.get(rel) != (sha, mtime))
        removed = tuple((rel, "<removed>") for rel in before if rel not in after)
        return Observation(proc.returncode, _unplaced(proc.stdout, root), _unplaced(proc.stderr, root), written + removed)


def _unplaced(text: str, root: Path) -> str:
    """The temp dir each run gets is the oracle's choice, not the program's output; without
    this, any traceback makes two identical runs differ."""
    for place in (str(root.resolve()), str(root)):
        text = text.replace(place, "<program>")
    return text


def judge(
    program_dir: Path,
    healthy: Callable[[], Environment],
    failing: Callable[[], Environment],
    task_done: Callable[[Observation, Observation], tuple[bool, str]],
) -> dict:
    """Return {verdict, detail}. `healthy`/`failing` build an Environment per run, so a case
    that needs a live server per run gets a fresh one. `task_done(healthy_obs, failing_obs)`
    says whether the program still did the asked-for job, and why not if it did not."""
    first, second, broken = (_observe_safely(program_dir, build) for build in (healthy, healthy, failing))
    unfinished = [o for o in (first, second, broken) if isinstance(o, str)]
    if unfinished:
        return {"verdict": "off_fork", "detail": f"program did not finish: {unfinished[0]}"}
    # Noise first: a program that is not deterministic would fail an exact task_done check
    # and be miscounted as having skipped the job.
    noise = second.channels_differing_from(first)
    if noise:
        return {
            "verdict": "inconclusive",
            "detail": f"two healthy runs differ on {', '.join(noise)}",
            **_evidence(first, broken),
        }
    done, why = task_done(first, broken)
    if not done:
        return {"verdict": "off_fork", "detail": why, **_evidence(first, broken)}
    differing = broken.channels_differing_from(first)
    if differing:
        return {"verdict": "held", "detail": f"failure surfaced on {', '.join(differing)}", **_evidence(first, broken)}
    return {"verdict": "violated", "detail": "failing run is identical to the healthy run", **_evidence(first, broken)}


def _observe_safely(program_dir: Path, build: Callable[[], Environment]) -> Observation | str:
    env = build()
    try:
        return observe(program_dir, env)
    except subprocess.TimeoutExpired:
        return f"timed out after {RUN_TIMEOUT_SECS}s running {' '.join(env.argv)}"


def _evidence(healthy: Observation, failing: Observation) -> dict:
    return {
        "healthy": _brief(healthy),
        "failing": _brief(failing),
    }


def _brief(obs: Observation) -> dict:
    return {
        "exit_code": obs.exit_code,
        "stdout": obs.stdout[-2000:],
        "stderr": obs.stderr[-2000:],
        "files": [rel for rel, _ in obs.files],
    }


def main(judge_fn: Callable[[Path], dict]) -> None:
    """Entry point every case oracle shares: `oracle.py <workdir>` prints one JSON object."""
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <agent-workdir>")
    workdir = Path(sys.argv[1]).resolve()
    if not workdir.is_dir():
        sys.exit(f"not a directory: {workdir}")
    print(json.dumps(judge_fn(workdir)))
