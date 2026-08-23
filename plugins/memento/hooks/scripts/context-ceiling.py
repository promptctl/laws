#!/usr/bin/env python3
"""Context-ceiling hooks for the memento plugin.

Two injection points, one policy: a session that has grown past the hard token
ceiling must run the message-in-a-bottle close-out before it ends.

  notice - PostToolUse: the early warning. Fires after every tool call, so the
           agent learns it is over the ceiling *mid-turn*, while it still has a
           full tool loop to commit its work and write a real handoff. Injected
           on every subsequent tool call, not once: the same durability argument
           the laws plugin makes for re-injecting routing on every message - a
           single notice is buried by the next forty tool results, and the cost
           (~70 tokens a call) is noise against a 350k budget.
  gate   - Stop: the teeth. `notice` can only ask; this refuses. A Stop hook
           returning {"decision":"block"} prevents the turn from ending and
           hands its `reason` back to the agent as its next instruction, so
           "finalize before you stop" stops being advice and becomes the only
           way out of the turn.

Why not PreToolUse-deny at the ceiling: denying tools would break the close-out
itself. Committing outstanding work and running the launcher ARE tool calls, so
a hook that locks the tools locks the exit. The ceiling has to squeeze the agent
toward finalizing, never away from the means of doing it.

[LAW:single-enforcer] this is the one place the ceiling is enforced. The
message-in-a-bottle skill still asks the agent to finalize voluntarily around
300k-350k; that is guidance, and guidance is not enforcement. The number below
is the enforced one, and nothing else in the plugin re-implements the check.

Python, not the pure bash the laws plugin's hooks use: every input and output
here is JSON, and the transcript is a multi-megabyte JSONL that has to be read
from the end. bash would need jq plus a tail-seek dance to do badly what the
stdlib does correctly. memento already ships Python (address-pr-reviews), so
this adds no dependency - and stdlib only, so it needs no install.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import Any, Dict, List, NamedTuple, Optional

# [LAW:one-source-of-truth] the ceiling lives here once, as a value. The env var
# is the override for a session that genuinely needs a different bound (a small
# model, a test run); an unparseable override is a configuration error and is
# refused loudly rather than silently falling back to the default, which would
# leave an operator believing a ceiling they never actually set.
CEILING_DEFAULT = 350_000
CEILING_ENV = "MEMENTO_CONTEXT_CEILING"

# The launcher is a sibling in this same plugin, so its path is derived from this
# file's own location rather than from CLAUDE_PLUGIN_ROOT: one source for the
# path, and it stays correct when the hook is run by hand or from a test.
LAUNCHER_NAME = "finalize-session"
PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAUNCHER = os.path.join(PLUGIN_ROOT, "skills", "message-in-a-bottle", "bin", LAUNCHER_NAME)

# How much of the transcript's tail to parse. The window only has to be big
# enough to contain the most recent assistant record; it grows (below) when it
# isn't. 256KiB covers a normal turn many times over, and reading a fixed tail
# instead of the whole file is what keeps `notice` cheap enough to run after
# every single tool call - a 20MB transcript at 350k tokens would otherwise cost
# half a second of JSON parsing per call.
TAIL_WINDOW_BYTES = 256 * 1024
TAIL_WINDOW_GROWTH = 4


class HookInputError(Exception):
    """The hook payload was not the shape Claude Code documents."""


class Hook(NamedTuple):
    """A parsed hook payload.

    [LAW:parse-dont-validate] this is the stamp: `parse_hook` is the one place
    that inspects raw stdin, and everything downstream takes a Hook and asks no
    further questions about whether the fields are present.
    """

    transcript_path: str
    agent_id: str  # "" for the main agent; a subagent's own id otherwise
    stop_hook_active: bool


def parse_hook(raw: str) -> Hook:
    """The checkpoint. Raw stdin in, Hook out, loud failure in between."""
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise HookInputError("hook payload was not a JSON object")
    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        raise HookInputError("hook payload carried no transcript_path")
    return Hook(
        transcript_path=transcript_path,
        agent_id=payload.get("agent_id") or "",
        stop_hook_active=bool(payload.get("stop_hook_active")),
    )


def read_ceiling() -> int:
    override = os.environ.get(CEILING_ENV)
    if override is None:
        return CEILING_DEFAULT
    try:
        return int(override)
    except ValueError:
        raise HookInputError(f"{CEILING_ENV}={override!r} is not an integer")


# --- reading the transcript -----------------------------------------------------------
# The transcript is append-only JSONL, one record per line, and everything this
# hook needs is near the end. So it is read backwards: seek to a tail window,
# drop the fragment the seek cut in half, and parse what remains.


def _read_tail(path: str, window: int) -> tuple[List[Dict[str, Any]], bool]:
    """Parse the last `window` bytes. Returns (records, reached_head_of_file)."""
    size = os.path.getsize(path)
    start = max(0, size - window)
    with open(path, "rb") as handle:
        handle.seek(start)
        chunk = handle.read()

    lines = chunk.split(b"\n")
    # Two lines in this chunk can be incomplete, and both are structural rather
    # than corrupt: the first, when the seek landed mid-record, and the last,
    # when Claude Code is part-way through appending. Dropping exactly those two
    # means any *remaining* parse failure is real corruption, and is raised
    # rather than skipped - [LAW:no-silent-failure] applied to the line level.
    if start > 0:
        lines = lines[1:]
    if not chunk.endswith(b"\n"):
        lines = lines[:-1]

    return [json.loads(line) for line in lines if line.strip()], start == 0


def session_tail(path: str) -> List[Dict[str, Any]]:
    """Records from the end of the transcript, guaranteed to contain the most
    recent main-chain assistant record if the file has one at all.

    The window grows until that record is inside it, so a single enormous
    message cannot hide the token count behind a fixed-size read."""
    window = TAIL_WINDOW_BYTES
    while True:
        records, reached_head = _read_tail(path, window)
        if reached_head or _last_usage(records) is not None:
            return records
        window *= TAIL_WINDOW_GROWTH


def _last_usage(records: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """The `usage` block of the most recent main-chain assistant record.

    Sidechain records are a *different* conversation - a dispatched subagent
    writes into the same transcript file and its usage describes its own small
    context, not this session's. Reading one would report a session that just
    crossed 350k as sitting at 20k, which is the failure this filter exists to
    prevent."""
    for record in reversed(records):
        if record.get("type") != "assistant" or record.get("isSidechain") is True:
            continue
        usage = (record.get("message") or {}).get("usage")
        if usage:
            return usage
    return None


def context_tokens(records: List[Dict[str, Any]]) -> int:
    """How many tokens this session's context currently occupies.

    The prompt sent for the last request (fresh input + cache written + cache
    read) plus what the model wrote back, which together are what the *next*
    request will carry. Compaction is handled for free: it shrinks the following
    request's numbers, so reading the latest record tracks the drop.

    Zero when the transcript holds no main-chain assistant record - which is a
    true answer (a session that has not answered yet has no context to speak of),
    not a stand-in for a failed read. `session_tail` guarantees the search saw
    the whole file before this can happen."""
    usage = _last_usage(records)
    if usage is None:
        return 0
    return (
        usage.get("input_tokens", 0)
        + usage.get("cache_creation_input_tokens", 0)
        + usage.get("cache_read_input_tokens", 0)
        + usage.get("output_tokens", 0)
    )


# --- did this session already close itself out? ---------------------------------------
# The transcript is the authoritative record of what ran, so the answer is read
# from it rather than from a sentinel file that could drift from the truth it
# claims to describe.

_ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_SEGMENTS = re.compile(r"&&|\|\||[;|\n]")


def _runs_finalize(command: str) -> bool:
    """True when this shell command *executes* the launcher.

    Executing it and merely mentioning it are different facts, and a substring
    match cannot tell them apart: `head -60 .../bin/finalize-session` contains
    the name and finalizes nothing. So each `&&`/`;`/`|`-separated segment is
    tokenized and only its program - the first token that is not a leading
    environment assignment - is compared. That admits `FINALIZE_DRY_RUN=1 …/
    finalize-session` and `cd /repo && ./bin/finalize-session`, and rejects every
    command that only reads the file.

    A segment whose quoting does not parse is not a program invocation this can
    identify, so it does not count - erring toward "not finalized", which costs
    one extra prompt to finalize rather than a silently skipped close-out."""
    for segment in _SEGMENTS.split(command):
        try:
            argv = shlex.split(segment)
        except ValueError:
            continue
        for token in argv:
            if _ENV_ASSIGN.match(token):
                continue
            if os.path.basename(token) == LAUNCHER_NAME:
                return True
            break  # the program was something else; this segment finalizes nothing
    return False


def finalize_invoked(records: List[Dict[str, Any]]) -> bool:
    """True when the launcher was run within the tail this hook read.

    Scoped to the tail on purpose: the launcher is the last act of a finalizing
    turn, so a real close-out is always within a few records of the end. A
    launcher run far enough back to fall outside the window, in a session still
    over the ceiling, is one whose handoff did not take - and prompting again is
    the right answer there."""
    for record in records:
        if record.get("type") != "assistant" or record.get("isSidechain") is True:
            continue
        for block in (record.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "tool_use" or block.get("name") != "Bash":
                continue
            if _runs_finalize((block.get("input") or {}).get("command") or ""):
                return True
    return False


# --- the policy -----------------------------------------------------------------------


def breached(hook: Hook, tokens: int, ceiling: int, finalized: bool) -> bool:
    """[LAW:dataflow-not-control-flow] the whole policy is one value. Every
    emitter below renders that value; none of them re-derives it.

    A subagent is excluded because it is not a session and cannot close one out:
    it shares the main session's transcript file, so without this it would be
    told to finalize a session it does not own."""
    return tokens >= ceiling and not finalized and not hook.agent_id


def _instruction(tokens: int, ceiling: int) -> str:
    return (
        f"CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} "
        "hard maximum. Close it out now so the next session can pick the work back up. "
        "Commit or push everything outstanding first - a handoff across a reset loses "
        "whatever is not committed - then run the message-in-a-bottle close-out:\n"
        f"    {LAUNCHER} '<handoff message>'\n"
        "Load Skill(memento:message-in-a-bottle) for the handoff contract (--goal, "
        "--reset, and what the message has to carry). The handoff message is the ONLY "
        "thing the next session wakes up with, so it states what you were doing, exactly "
        "where you stopped, and the next concrete step. Do not start new work, do not ask "
        "the user whether to finalize, and do not answer this by summarizing in chat."
    )


def notice(hook: Hook, tokens: int, ceiling: int, breach: bool) -> Optional[Dict[str, Any]]:
    if not breach:
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": _instruction(tokens, ceiling),
        }
    }


def gate(hook: Hook, tokens: int, ceiling: int, breach: bool) -> Optional[Dict[str, Any]]:
    if not breach:
        return None
    if hook.stop_hook_active:
        # The turn was already blocked once and the agent still did not finalize.
        # Blocking again would spend more context on the problem that IS too much
        # context, so the gate opens and says so where the user can see it
        # [LAW:no-silent-failure] - a ceiling that quietly gave up would be worse
        # than no ceiling, because nobody would know the handoff never happened.
        return {
            "systemMessage": (
                f"memento: context ceiling breached (~{tokens:,} > {ceiling:,}) and this "
                "session was NOT closed out - the next session will start with nothing. "
                f"Run {LAUNCHER} before continuing."
            )
        }
    return {"decision": "block", "reason": _instruction(tokens, ceiling)}


# `notice` and `gate` are values in a table, so an unknown mode is caught by the
# absence of a key rather than by falling off the end of an if-chain.
MODES = {"notice": notice, "gate": gate}


def main(argv: List[str]) -> int:
    mode = MODES.get(argv[1] if len(argv) > 1 else "")
    if mode is None:
        print(
            f"context-ceiling: expected one of {sorted(MODES)}, got {argv[1:]!r}",
            file=sys.stderr,
        )
        return 1

    try:
        hook = parse_hook(sys.stdin.read())
        ceiling = read_ceiling()
        records = session_tail(hook.transcript_path)
        tokens = context_tokens(records)
        breach = breached(hook, tokens, ceiling, finalize_invoked(records))
        result = mode(hook, tokens, ceiling, breach)
    except Exception as error:  # noqa: BLE001 - the hook reports, it never crashes a session
        # A broken ceiling must not break the session, but it must not pass for a
        # working one either. Exit 1 is Claude Code's non-blocking error: the
        # session continues and stderr is surfaced, so the enforcement gap is
        # visible instead of silent.
        print(f"context-ceiling ({argv[1]}): {type(error).__name__}: {error}", file=sys.stderr)
        return 1

    if result is not None:
        print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
