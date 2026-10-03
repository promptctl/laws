"""Pure readers of a Claude Code session transcript (the JSONL it writes per session).

The transcript is the session's own record of what it loaded and what it said, so every
fact the harness asserts about a session is read here rather than off the screen or out
of the model's mouth. The format is Claude Code's, not a published contract, so each
reader refuses a transcript that lacks the record it depends on: a renamed record makes
a check fail, never pass.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from . import HarnessError


def parse(text: str) -> list[dict]:
    records = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as error:
            raise HarnessError("transcript", f"line {number} is not JSON: {error}") from None
    return records


def load(path: Path) -> list[dict]:
    return parse(path.read_text())


def _attachments(records: list[dict], kind: str) -> list[dict]:
    return [r["attachment"] for r in records if r.get("type") == "attachment" and r["attachment"].get("type") == kind]


def _require_attachments(records: list[dict], kind: str) -> list[dict]:
    found = _attachments(records, kind)
    if not found:
        raise HarnessError("transcript", f"the transcript has no '{kind}' record; the reader cannot tell what the session loaded")
    return found


def _is_prompt(record: dict) -> bool:
    """A user message the session received as a typed prompt (not a tool result or a meta line)."""
    return (
        record.get("type") == "user"
        and not record.get("isMeta")
        and not record.get("isSidechain")
        and isinstance(record.get("message", {}).get("content"), str)
    )


def prompts(records: list[dict]) -> list[str]:
    return [r["message"]["content"] for r in records if _is_prompt(r)]


@dataclass(frozen=True)
class Turn:
    prompt: str
    reply: str
    duration_ms: int


def turns(records: list[dict]) -> list[Turn]:
    """Every finished turn: a prompt, the assistant text after it, and the turn_duration
    record that closes it. A prompt with no closing record yet is not a turn."""
    finished: list[Turn] = []
    prompt: str | None = None
    texts: list[str] = []
    for record in records:
        if _is_prompt(record):
            prompt, texts = record["message"]["content"], []
        elif record.get("type") == "assistant" and not record.get("isSidechain") and prompt is not None:
            texts += [b["text"] for b in record["message"].get("content", []) if b.get("type") == "text"]
        elif record.get("type") == "system" and record.get("subtype") == "turn_duration" and prompt is not None:
            finished.append(Turn(prompt, "\n\n".join(texts), int(record.get("durationMs", 0))))
            prompt, texts = None, []
    return finished


def served_models(records: list[dict]) -> list[str]:
    """Every model the API answered with, from the responses themselves."""
    return sorted({r["message"]["model"] for r in records if r.get("type") == "assistant" and r["message"].get("model")})


def claude_versions(records: list[dict]) -> list[str]:
    return sorted({r["version"] for r in records if r.get("version")})


def tokens(records: list[dict]) -> dict[str, int]:
    """Usage summed once per API message: Claude Code writes one record per content block,
    each carrying the whole message's usage."""
    usage_by_message: dict[str, dict] = {}
    for r in records:
        if r.get("type") == "assistant" and r["message"].get("id"):
            usage_by_message[r["message"]["id"]] = r["message"].get("usage") or {}
    keys = {"input": "input_tokens", "output": "output_tokens",
            "cache_read": "cache_read_input_tokens", "cache_creation": "cache_creation_input_tokens"}
    return {name: sum(int(u.get(key) or 0) for u in usage_by_message.values()) for name, key in keys.items()}


@dataclass(frozen=True)
class Loaded:
    """What the session put in front of the model besides Claude Code's own builtins."""
    claude_md: tuple[str, ...]
    hooks: tuple[str, ...]
    plugin_skills: tuple[str, ...]
    plugin_agents: tuple[str, ...]
    mcp_servers: tuple[str, ...]

    def as_record(self) -> dict:
        return {k: list(v) for k, v in self.__dict__.items()}


def loaded(records: list[dict]) -> Loaded:
    """Read the loaded set from the session's own records.

    skill_listing and agent_listing_delta are required: every session writes them, so their
    absence means the format moved and nothing below could be trusted. CLAUDE.md files,
    hooks and MCP servers each appear only when something loaded, so their absence is the
    clean answer; verify.py's positive controls are what prove those readers still see a
    load when one happens.
    """
    skills = {n for a in _require_attachments(records, "skill_listing") for n in a.get("names", [])}
    agent_records = _require_attachments(records, "agent_listing_delta")
    agents = {t for a in agent_records for t in a.get("addedTypes", [])}
    builtin_agents = {t for a in agent_records for t in a.get("builtInTypes", [])}
    claude_md = sorted({f["path"] for a in _attachments(records, "instructions") for f in a.get("files", [])})
    # Every hook outcome Claude Code records is an attachment typed hook_<outcome> carrying
    # the event that fired it, so the prefix catches an outcome this reader has never seen.
    hook_records = [r["attachment"] for r in records
                    if r.get("type") == "attachment" and str(r["attachment"].get("type", "")).startswith("hook_")]
    if any(not a.get("hookEvent") for a in hook_records):
        raise HarnessError("transcript", "a hook record carries no hookEvent; the reader cannot tell which hook ran")
    hooks = sorted({a["hookEvent"] for a in hook_records})
    mcp = set()
    for a in _attachments(records, "mcp_instructions_delta"):
        mcp |= set(a.get("addedNames", []))
    for a in _attachments(records, "deferred_tools_delta"):
        mcp |= {s if isinstance(s, str) else s.get("name", str(s)) for s in a.get("failedMcpServers", []) + a.get("pendingMcpServers", [])}
        mcp |= {n.split("__")[1] for n in a.get("addedNames", []) + a.get("surfacedNames", []) if n.startswith("mcp__")}
    plugin_skills = sorted(n for n in skills if ":" in n)
    plugin_agents = sorted(agents - builtin_agents)
    return Loaded(tuple(claude_md), tuple(hooks), tuple(plugin_skills), tuple(plugin_agents), tuple(sorted(mcp)))
