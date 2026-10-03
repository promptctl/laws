"""One run: a session under a spec, a list of prompts, and exactly one of run.json or
failure.json left in the run dir. This is the entry point an eval calls."""
from __future__ import annotations

import re
from pathlib import Path

from . import HarnessError, record
from .session import Session, Spec

# The run id names the tmux session, and tmux rewrites "." in a session name to "_".
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def run(spec: Spec, prompts: list[str], run_dir: Path, run_id: str) -> dict:
    """Returns the run record, written to <run_dir>/run.json. On any failure writes
    <run_dir>/failure.json and raises the HarnessError; there is no third outcome."""
    if not RUN_ID_RE.match(run_id):
        raise HarnessError("spec", f"run id {run_id!r} must match {RUN_ID_RE.pattern}")
    if not prompts:
        raise HarnessError("spec", "a run needs at least one prompt")
    if run_dir.exists() and any(run_dir.iterdir()):
        raise HarnessError("spec", f"run dir already has contents: {run_dir}")
    run_dir.mkdir(parents=True, exist_ok=True)
    session = Session(spec, run_dir, run_id)
    try:
        with session:
            for prompt in prompts:
                session.turn(prompt)
        result = record.build(session)
    except BaseException as raised:
        # A defect in the harness itself is still a failed run, recorded as one, and so is
        # a run stopped from outside (Ctrl-C), which then keeps propagating as itself.
        if isinstance(raised, HarnessError):
            error = raised
        elif isinstance(raised, Exception):
            error = HarnessError("internal", f"{type(raised).__name__}: {raised}")
        else:
            error = HarnessError("interrupted", f"{type(raised).__name__}: {raised}")
        if error is not raised:
            for note in getattr(raised, "__notes__", []):
                error.add_note(note)
        captured = None if session.transcript_path is None else session.transcript_path.relative_to(run_dir).as_posix()
        record.write(run_dir / "failure.json", record.failure(run_id, error, captured))
        if not isinstance(raised, Exception):
            raise
        raise error from raised
    record.write(run_dir / "run.json", result)
    return result
