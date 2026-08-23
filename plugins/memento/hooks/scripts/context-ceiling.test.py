#!/usr/bin/env python3
"""Unit tests for the context-ceiling hooks.

Each case feeds a synthetic transcript and a synthetic hook payload - the shapes
Claude Code actually delivers, taken from real session files under
~/.claude/projects - to the hook as a subprocess, and asserts the visible
contract: the JSON it emits and the exit code it returns.

[LAW:behavior-not-structure] the hook is driven the way Claude Code drives it, so
these tests survive any rewrite of its internals and fail only when the contract
does. Nothing here imports the module or reaches inside it.

Run: python3 context-ceiling.test.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "context-ceiling.py")
PLUGIN_ROOT = os.path.dirname(os.path.dirname(HERE))
LAUNCHER = os.path.join(PLUGIN_ROOT, "skills", "message-in-a-bottle", "bin", "finalize-session")

CEILING = 350_000

passed = 0
failed = 0


def ok(name: str) -> None:
    global passed
    passed += 1
    print(f"ok   - {name}")


def bad(name: str, detail: str) -> None:
    global failed
    failed += 1
    print(f"FAIL - {name}: {detail}")


def check(name: str, condition: bool, detail: str = "") -> None:
    ok(name) if condition else bad(name, detail)


# --- transcript builders --------------------------------------------------------------


def assistant(tokens: int, *, sidechain: bool = False, command: str | None = None) -> dict:
    """An assistant record carrying `tokens` of context, optionally running a Bash command."""
    content: list[dict] = [{"type": "text", "text": "..."}]
    if command is not None:
        content.append(
            {"type": "tool_use", "id": "toolu_x", "name": "Bash", "input": {"command": command}}
        )
    return {
        "type": "assistant",
        "isSidechain": sidechain,
        "message": {
            "content": content,
            "usage": {
                "input_tokens": 2,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": tokens - 2,
                "output_tokens": 0,
            },
        },
    }


def user(text: str = "hi") -> dict:
    return {"type": "user", "isSidechain": False, "message": {"content": text}}


def transcript(records: list[dict]) -> str:
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    for record in records:
        handle.write(json.dumps(record) + "\n")
    handle.close()
    return handle.name


# --- driver ---------------------------------------------------------------------------


def run(mode: str, records: list[dict], *, stop_hook_active: bool = False,
        agent_id: str = "", ceiling: str | None = None,
        payload: dict | None = None) -> tuple[int, dict | None, str]:
    """Invoke the hook exactly as Claude Code does. Returns (exit code, parsed stdout, stderr)."""
    path = transcript(records)
    body = {"session_id": "s-1", "transcript_path": path, "cwd": HERE,
            "hook_event_name": "Stop" if mode == "gate" else "PostToolUse",
            "stop_hook_active": stop_hook_active}
    if agent_id:
        body["agent_id"] = agent_id
    if payload is not None:
        body = payload

    env = dict(os.environ)
    env.pop("MEMENTO_CONTEXT_CEILING", None)
    if ceiling is not None:
        env["MEMENTO_CONTEXT_CEILING"] = ceiling

    try:
        result = subprocess.run(
            [sys.executable, HOOK, mode], input=json.dumps(body),
            capture_output=True, text=True, env=env,
        )
    finally:
        os.unlink(path)

    out = json.loads(result.stdout) if result.stdout.strip() else None
    return result.returncode, out, result.stderr


UNDER = [user(), assistant(100_000)]
OVER = [user(), assistant(360_000)]


# --- the ceiling ----------------------------------------------------------------------

code, out, _ = run("gate", UNDER)
check("under the ceiling, the gate emits nothing", code == 0 and out is None, f"{code} {out}")

code, out, _ = run("notice", UNDER)
check("under the ceiling, the notice emits nothing", code == 0 and out is None, f"{code} {out}")

code, out, _ = run("gate", OVER)
check("over the ceiling, the gate blocks the stop",
      code == 0 and out is not None and out.get("decision") == "block", f"{code} {out}")
check("the block reason names the launcher",
      out is not None and LAUNCHER in out.get("reason", ""), str(out))
check("the block reason names the ceiling and the count",
      out is not None and "350,000" in out["reason"] and "360,000" in out["reason"], str(out))

code, out, _ = run("notice", OVER)
context = (out or {}).get("hookSpecificOutput", {})
check("over the ceiling, the notice injects context",
      code == 0 and context.get("hookEventName") == "PostToolUse"
      and LAUNCHER in context.get("additionalContext", ""), f"{code} {out}")

# The count is the sum of every prompt component plus the output, so a session
# whose cache read alone is under the ceiling can still be over it.
split = [user(), {"type": "assistant", "isSidechain": False, "message": {"content": [],
         "usage": {"input_tokens": 1_000, "cache_creation_input_tokens": 40_000,
                   "cache_read_input_tokens": 300_000, "output_tokens": 12_000}}}]
code, out, _ = run("gate", split)
check("the count sums input, cache write, cache read and output",
      out is not None and out.get("decision") == "block" and "353,000" in out["reason"], str(out))


# --- one block, not a loop ------------------------------------------------------------

code, out, _ = run("gate", OVER, stop_hook_active=True)
check("a second stop is not blocked again",
      code == 0 and out is not None and "decision" not in out, f"{code} {out}")
check("giving up is loud rather than silent",
      out is not None and "NOT closed out" in out.get("systemMessage", ""), str(out))


# --- already finalized ----------------------------------------------------------------

finalized = [user(), assistant(360_000, command=f"{LAUNCHER} /next")]
code, out, _ = run("gate", finalized)
check("a session that ran the launcher is allowed to stop", code == 0 and out is None, f"{code} {out}")

env_prefixed = [user(), assistant(360_000, command=f"FINALIZE_DRY_RUN=1 {LAUNCHER} /next")]
code, out, _ = run("gate", env_prefixed)
check("an env-prefixed launcher run counts as finalizing", code == 0 and out is None, f"{code} {out}")

chained = [user(), assistant(360_000, command=f"cd /tmp && {LAUNCHER} /next")]
code, out, _ = run("gate", chained)
check("a chained launcher run counts as finalizing", code == 0 and out is None, f"{code} {out}")

# Reading the launcher is not running it. A substring match would pass this and
# let a session that only opened the file stop without closing out.
mentioned = [user(), assistant(360_000, command=f"head -60 {LAUNCHER}")]
code, out, _ = run("gate", mentioned)
check("reading the launcher does not count as finalizing",
      out is not None and out.get("decision") == "block", f"{code} {out}")

quoted = [user(), assistant(360_000, command=f"echo 'run {LAUNCHER} later'")]
code, out, _ = run("gate", quoted)
check("naming the launcher in an argument does not count as finalizing",
      out is not None and out.get("decision") == "block", f"{code} {out}")


# --- sidechains are a different conversation ------------------------------------------

# A subagent's record is last in the file and reports a small context. Reading it
# would report this session as nowhere near the ceiling.
masked = [user(), assistant(360_000), assistant(20_000, sidechain=True)]
code, out, _ = run("gate", masked)
check("a trailing subagent record does not mask the session's own count",
      out is not None and out.get("decision") == "block", f"{code} {out}")

# And the converse: a busy subagent must not push a small session over.
inflated = [user(), assistant(90_000), assistant(900_000, sidechain=True)]
code, out, _ = run("gate", inflated)
check("a subagent's own context does not count against the session",
      code == 0 and out is None, f"{code} {out}")

code, out, _ = run("notice", OVER, agent_id="agent_deadbeef")
check("a subagent is never told to close out the session", code == 0 and out is None, f"{code} {out}")


# --- compaction -----------------------------------------------------------------------

compacted = [user(), assistant(360_000), user(), assistant(40_000)]
code, out, _ = run("gate", compacted)
check("a compacted session reads as its post-compaction size", code == 0 and out is None, f"{code} {out}")


# --- the tail window grows ------------------------------------------------------------

# The usage record is buried behind more than one window's worth of later records,
# so a fixed-size tail read would find no usage and report zero.
buried = [assistant(360_000)] + [user("x" * 4000) for _ in range(120)]
code, out, _ = run("gate", buried)
check("the tail window grows until it reaches the last usage record",
      out is not None and out.get("decision") == "block", f"{code} {out}")


# --- a session with nothing in it -----------------------------------------------------

code, out, _ = run("gate", [user()])
check("a transcript with no assistant record reads as zero", code == 0 and out is None, f"{code} {out}")


# --- configuration --------------------------------------------------------------------

code, out, _ = run("gate", UNDER, ceiling="50000")
check("the ceiling override is honoured",
      out is not None and out.get("decision") == "block" and "50,000" in out["reason"], f"{code} {out}")

code, out, err = run("gate", UNDER, ceiling="lots")
check("an unparseable ceiling fails loudly rather than defaulting",
      code == 1 and out is None and "MEMENTO_CONTEXT_CEILING" in err, f"{code} {out} {err}")


# --- broken input -------------------------------------------------------------------

code, out, err = run("gate", UNDER, payload={"session_id": "s-1"})
check("a payload with no transcript_path fails loudly",
      code == 1 and out is None and "transcript_path" in err, f"{code} {out} {err}")

result = subprocess.run([sys.executable, HOOK, "gate"], input="not json",
                        capture_output=True, text=True)
check("unparseable stdin fails loudly",
      result.returncode == 1 and not result.stdout.strip(), str(result))

result = subprocess.run([sys.executable, HOOK, "wat"], input="{}", capture_output=True, text=True)
check("an unknown mode fails loudly", result.returncode == 1 and "expected one of" in result.stderr,
      str(result))


# --- packaging ------------------------------------------------------------------------

# The hook derives the launcher path from its own location, so a move that breaks
# the layout has to fail here rather than in a live session's close-out.
check("the launcher the hook points at exists", os.access(LAUNCHER, os.X_OK), LAUNCHER)

hooks_json = os.path.join(PLUGIN_ROOT, "hooks", "hooks.json")
registered = json.load(open(hooks_json))["hooks"]
check("both events are registered",
      set(registered) == {"PostToolUse", "Stop"}, str(list(registered)))
commands = {event: [h["command"] for entry in entries for h in entry["hooks"]]
            for event, entries in registered.items()}
check("each event runs the mode this file tests",
      all(any(f"context-ceiling.py\" {mode}" in command for command in commands[event])
          for event, mode in (("PostToolUse", "notice"), ("Stop", "gate"))), str(commands))
check("the hook is executable", os.access(HOOK, os.X_OK), HOOK)


print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
