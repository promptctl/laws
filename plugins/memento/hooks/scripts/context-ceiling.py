#!/usr/bin/env python3
"""The context ceiling: a session past the hard token maximum may not start new
work until it has run the message-in-a-bottle close-out.

Two events, because one of them is not enough.

Stop has teeth in a session that stops - {"decision": "block"} refuses the stop and
hands `reason` back as the agent's next instruction. But an autonomous session never
stops. Measured on a real 1M-window run: 757 assistant records, every one of them
stop_reason "tool_use", not a single end_turn. It crossed 350k at record 461 and
reached 909k with the gate never once consulted, while short interactive sessions in
the same period blocked at ~408k exactly as designed. A goal-driven or otherwise
looping session comes to rest only once the work is done - which is precisely the
session the ceiling exists to catch, and precisely the session Stop cannot see.

[LAW:no-ambient-temporal-coupling] a ceiling enforced only at an incidental lifecycle
event is enforced by luck. So it is also enforced where a loop cannot avoid it:
PreToolUse fires on every tool call. Above the ceiling the permitted set narrows to
the close-out itself - the launcher, git, and the reads needed to write an accurate
handoff - and everything else is denied.
[LAW:types-are-the-program] starting new work above the ceiling stops being
discouraged and becomes unrepresentable.

Denial cannot wedge a session: it withholds tools, never the exit. An agent that
cannot close out - no tmux, no iTerm2, the `claude --bg-pty-host` case - ends its
turn and reports, which is the correct terminal state for a session that has run out
of room. That is why PreToolUse needs no spent-attempt escape valve and keeps no
state of its own: there is nothing to unwedge.

Anything unexpected - no transcript_path, an unreadable file, a bad ceiling, an
unknown event - raises, and Python's traceback on stderr with exit 1 is exactly
Claude Code's non-blocking error: the session continues and the breakage is visible.
"""

import json
import os
import shlex
import sys
from pathlib import Path

CEILING = int(os.environ.get("MEMENTO_CONTEXT_CEILING", 350_000))
PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAUNCHER = os.path.join(PLUGIN_ROOT, "skills", "message-in-a-bottle", "bin", "finalize-session")
# Everything the next request will carry: fresh input, cache written, cache read,
# and what the model just wrote back.
COUNTED = ("input_tokens", "cache_creation_input_tokens",
           "cache_read_input_tokens", "output_tokens")

# {launcher} arrives shell-quoted. The agent runs that line verbatim, and a plugin
# root like ~/Library/Application Support/... would otherwise split into two arguments
# and lose the only exit from the block.
INSTRUCTION = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum. Close it out now so the next session can pick the work back up. Commit or push everything outstanding first - a handoff across a reset loses whatever is not committed - then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with, so it says what you were doing, exactly where you stopped, and the next concrete step. Do not start new work, and do not ask the user whether to finalize."""

# Repeated on every refused call, so it states the way out and stops - the ceiling is
# a context problem and the denial must not itself become a context cost.
DENIAL = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum, so new work is refused until it closes out. This tool call was NOT run. git and file reads are still permitted: commit anything outstanding, then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with. Do not retry this call, and do not ask the user whether to finalize."""

# Reads inform the handoff and cannot create work, so they stay open: a close-out
# written blind is a close-out the next session cannot use.
CLOSEOUT_READS = ("Read", "Grep", "Glob")
CLOSEOUT_SKILL = "memento:message-in-a-bottle"
LAUNCHER_NAME = os.path.basename(LAUNCHER)
OPERATORS = ("&&", "||", ";", ";;", "|", "&")


def segments(command):
    """The command's pipeline segments, tokenized the way the shell will tokenize it.

    Parsed, not pattern-matched. A regex split on ';' '|' '&' also cuts inside quotes,
    and the handoff message is free prose that routinely contains all three - so the
    first live run of this gate denied the close-out itself, splitting
    `finalize-session '...no next step; if the user says X...'` at the semicolon and
    judging the remainder as new work. The one call that is the way out was the one
    call refused."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    parts, current = [], []
    for token in lexer:
        if token in OPERATORS:
            parts.append(current)
            current = []
        else:
            current.append(token)
    parts.append(current)
    return [part for part in parts if part]


def context_tokens(transcript_path):
    """Tokens in this session's context, read from the transcript because no hook
    payload carries the number.

    Sidechain records are a different conversation - a dispatched subagent writes
    into this same file, and reading its usage would report a session that just
    crossed 350k as sitting at 20k. Compaction needs no handling: it shrinks the
    following record, so the latest one tracks the drop."""
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


def is_closeout(tool_name, tool_input):
    """Whether this call is part of closing the session out, and so still permitted
    above the ceiling.

    Default-deny: an unrecognised tool is new work. That is what keeps the set honest
    as tools are added - a tool nobody thought about here is refused, not waved
    through, so the gap shows up as a blocked close-out rather than as a session that
    quietly kept working past the ceiling."""
    if tool_name in CLOSEOUT_READS:
        return True
    if tool_name == "Skill":
        return tool_input.get("skill") == CLOSEOUT_SKILL
    if tool_name == "Bash":
        try:
            parts = segments(tool_input.get("command", ""))
        except ValueError:
            return False  # an unbalanced quote - what the shell would run is unclear
        # Judged on what each segment *runs*, not on what it mentions: a command that
        # merely quotes the launcher's path inside an argument is not the close-out.
        return bool(parts) and all(
            part[0] == "git" or os.path.basename(part[0]) == LAUNCHER_NAME
            for part in parts)
    return False


def stop(hook, tokens):
    """Blocked once, never twice: a second block would spend more context on the
    problem that IS too much context, so the agent gets one forced chance and then the
    gate opens - saying so where the user can see it, because a ceiling that quietly
    gave up would be worse than no ceiling at all.

    The message claims the count and that the chance is spent, and leaves whether the
    close-out ran conditional. Deliberately: the compliant path - block, finalize,
    stop again - is exactly when stop_hook_active is true, so asserting failure would
    call every successful close-out a failure. The flag is also Claude Code's
    transcript-wide "a Stop hook blocked the last stop", not this hook's own, so a
    second Stop hook could open this gate with its block; the wording holds there too."""
    if hook.get("stop_hook_active"):
        return {"systemMessage": f"memento: context ceiling breached (~{tokens:,} > "
                                 f"{CEILING:,}) and this session has spent its one forced "
                                 f"close-out attempt, so the stop proceeds. If the close-out "
                                 f"did not run, the next session starts with nothing."}
    return {"decision": "block", "reason": reason(INSTRUCTION, tokens)}


def pretool(hook, tokens):
    """The close-out is the only work left, so it is the only work permitted."""
    if is_closeout(hook["tool_name"], hook.get("tool_input") or {}):
        return None
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason(DENIAL, tokens)}}


def reason(template, tokens):
    return template.format(tokens=tokens, ceiling=CEILING, launcher=shlex.quote(LAUNCHER))


# The event arrives as argv rather than read from the payload, so a registration that
# points the wrong event at this script fails here instead of being silently handled
# as the other one.
EVENTS = {"stop": stop, "pretool": pretool}

event = EVENTS[sys.argv[1]]
hook = json.load(sys.stdin)
tokens = context_tokens(hook["transcript_path"])

# [LAW:dataflow-not-control-flow] the measurement runs on every event; only the value
# it produces decides whether anything is emitted.
verdict = event(hook, tokens) if tokens >= CEILING else None
if verdict:
    print(json.dumps(verdict))
