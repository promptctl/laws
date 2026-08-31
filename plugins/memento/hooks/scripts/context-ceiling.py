#!/usr/bin/env python3
"""The context ceiling: a session past the hard token maximum may not end its
turn until it has run the message-in-a-bottle close-out.

Stop is the hook with teeth - {"decision": "block"} refuses the stop and hands
`reason` back as the agent's next instruction, so finalizing stops being advice
and becomes the only way out of the turn. Deliberately not a PreToolUse deny:
committing outstanding work and running the launcher are themselves tool calls,
so locking the tools would lock the exit. The cost is turn granularity - a long
tool loop can overshoot inside one turn - which the margin below the window absorbs.

Anything unexpected raises, and Python's traceback on stderr with exit 1 is exactly
Claude Code's non-blocking error: the session continues and the breakage is visible.
"""

import json
import os
import shlex
import sys
from pathlib import Path

# The one source of truth for the threshold. Nothing else in this repo names it:
# the instruction, the give-up message and the tests all read it from here.
CEILING = int(os.environ.get("MEMENTO_CONTEXT_CEILING", 250_000))
LAUNCHER = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "skills", "message-in-a-bottle", "bin", "finalize-session",
)
# Everything the next request will carry, not just the newest slice.
COUNTED = ("input_tokens", "cache_creation_input_tokens",
           "cache_read_input_tokens", "output_tokens")

# {launcher} arrives shell-quoted: the agent runs that line verbatim, and a plugin root
# like ~/Library/Application Support/... would otherwise split into two arguments and
# lose the only exit from the block.
INSTRUCTION = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum. Close it out now so the next session can pick the work back up. Commit or push everything outstanding first - a handoff across a reset loses whatever is not committed - then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with, so it says what you were doing, exactly where you stopped, and the next concrete step. Do not start new work, and do not ask the user whether to finalize."""


def context_tokens(transcript_path):
    """Tokens in this session's context, read from the transcript because no hook
    payload carries the number.

    Sidechain records are a different conversation - a dispatched subagent writes into
    this same file, and reading its usage would report a breached session as sitting at
    20k. Compaction needs no handling: it shrinks the following record."""
    for line in reversed(Path(transcript_path).read_bytes().split(b"\n")):
        try:
            record = json.loads(line)
        except ValueError:
            continue  # a blank line, or the tail of a write still in flight
        if record.get("type") == "assistant" and not record.get("isSidechain"):
            usage = record["message"].get("usage")
            if usage:
                return sum(usage.get(field, 0) for field in COUNTED)
    return 0


hook = json.load(sys.stdin)
tokens = context_tokens(hook["transcript_path"])

if tokens >= CEILING:
    # One forced chance, then the gate opens: a second block would spend more context on
    # the problem that IS too much context. Giving up says so where the user can see it.
    #
    # That message leaves whether the close-out ran conditional, deliberately - the
    # compliant path (block, finalize, stop again) is exactly when stop_hook_active is
    # true, so asserting failure would call every successful close-out a failure.
    print(json.dumps(
        {"systemMessage": f"memento: context ceiling breached (~{tokens:,} > "
                          f"{CEILING:,}) and this session has spent its one forced "
                          f"close-out attempt, so the stop proceeds. If the close-out "
                          f"did not run, the next session starts with nothing."}
        if hook.get("stop_hook_active") else
        {"decision": "block",
         "reason": INSTRUCTION.format(tokens=tokens, ceiling=CEILING,
                                      launcher=shlex.quote(LAUNCHER))}
    ))
