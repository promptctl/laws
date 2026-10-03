"""The run record: one schema-conforming JSON document per finished session, built only
from what the session's own transcript and the harness's own launch inputs say."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import jsonschema

from . import HarnessError, transcript
from .session import Session

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"
RUN_SCHEMA = json.loads((SCHEMA_DIR / "run-record.schema.json").read_text())
FAILURE_SCHEMA = json.loads((SCHEMA_DIR / "failure.schema.json").read_text())


def admitted(session: Session) -> dict:
    spec = session.spec
    prompt = spec.append_system_prompt
    return {
        "plugins": [{"name": p.name, **p.provenance} for p in session.pinned],
        "append_system_prompt": None if prompt is None else {
            "path": str(prompt), "sha256": hashlib.sha256(prompt.read_bytes()).hexdigest()},
        "hook_events": sorted({e for p in session.pinned for e in p.hook_events} | set(spec.settings.get("hooks", {}))),
        "mcp_servers": sorted((spec.mcp_config or {}).get("mcpServers", {})),
    }


def isolation_violations(loaded: transcript.Loaded, allowed: dict, work_dir: Path) -> list[str]:
    """Everything the session loaded that the caller did not admit. A CLAUDE.md counts as
    admitted only inside the caller's work dir; the owner's, the config dir's or any
    parent directory's is foreign."""
    plugin_names = {p["name"] for p in allowed["plugins"]}
    found = []
    found += [f"CLAUDE.md {path}" for path in loaded.claude_md if not Path(path).resolve().is_relative_to(work_dir)]
    found += [f"hook {event}" for event in loaded.hooks if event not in allowed["hook_events"]]
    found += [f"plugin skill {name}" for name in loaded.plugin_skills if name.split(":", 1)[0] not in plugin_names]
    found += [f"plugin agent {name}" for name in loaded.plugin_agents if name.split(":", 1)[0] not in plugin_names]
    found += [f"MCP server {name}" for name in loaded.mcp_servers if name not in allowed["mcp_servers"]]
    return found


def build(session: Session) -> dict:
    """The record of a closed session, refused unless the session was what it was asked
    to be: the requested model and no other, the pinned binary, nothing loaded beyond what
    was admitted."""
    if session.transcript_path is None:
        raise HarnessError("record", "the session is not closed; its transcript has not been captured")
    records = transcript.load(session.transcript_path)
    spec, binary = session.spec, session.binary
    served = transcript.served_models(records)
    if served != [spec.model]:
        raise HarnessError("model", f"asked for {spec.model}; the session was served by {served or 'nothing'}")
    versions = transcript.claude_versions(records)
    if versions != [binary.version]:
        raise HarnessError("binary", f"resolved Claude Code {binary.version}; the transcript records {versions}")
    allowed = admitted(session)
    loaded = transcript.loaded(records)
    foreign = isolation_violations(loaded, allowed, spec.work_dir)
    if foreign:
        raise HarnessError("isolation", f"the session loaded what the caller did not admit: {foreign}")
    turns = transcript.turns(records)
    record = {
        "schema_version": 1,
        "run_id": session.run_id,
        "session_id": session.session_id,
        "started_at": session.started_at.isoformat(),
        "duration_ms": int((datetime.now(timezone.utc) - session.started_at).total_seconds() * 1000),
        "claude": {"path": str(binary.path), "version": binary.version, "version_pinned": spec.claude_version is not None},
        "auth": {"method": session.auth.method, "provider": session.auth.provider},
        "model": {"requested": spec.model, "served": served},
        "admitted": allowed,
        "loaded": loaded.as_record(),
        "turns": [{"prompt_sha256": hashlib.sha256(t.prompt.encode()).hexdigest(), "reply": t.reply,
                   "duration_ms": t.duration_ms} for t in turns],
        "tokens": transcript.tokens(records),
        "work_dir": str(spec.work_dir),
        "transcript": session.transcript_path.relative_to(session.run_dir).as_posix(),
    }
    jsonschema.validate(record, RUN_SCHEMA)
    return record


def failure(run_id: str, error: HarnessError, transcript_path: str | None) -> dict:
    record = {"schema_version": 1, "run_id": run_id, "stage": error.stage, "error": error.message,
              "transcript": transcript_path}
    jsonschema.validate(record, FAILURE_SCHEMA)
    return record


def write(path: Path, record: dict) -> None:
    path.write_text(json.dumps(record, indent=2) + "\n")
