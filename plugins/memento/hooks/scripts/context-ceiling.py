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
the close-out itself - the launcher, git, and the handoff contract - and everything
else is denied, reads included: the ceiling is a limit on context, so a tool that
grows context cannot be part of respecting it.
[LAW:types-are-the-program] starting new work above the ceiling stops being
discouraged and becomes unrepresentable.

Denial cannot wedge a session: it withholds tools, never the exit. An agent that
cannot close out - no tmux, no iTerm2, the `claude --bg-pty-host` case - ends its
turn and reports, which is the correct terminal state for a session that has run out
of room. That is why PreToolUse needs no spent-attempt escape valve and keeps no
state of its own: there is nothing to unwedge.

The ceiling itself is configurable while sessions run, because the hook is a fresh
process per event: MEMENTO_CONTEXT_CEILING in the environment, else the number written
in ~/.claude/memento/context-ceiling, else 350k. A value that does not parse exits with
one line naming where to fix it - that is a person's mistake and deserves a sentence,
not a stack trace.

Anything unexpected - no transcript_path, an unreadable transcript, an unknown event -
raises, and Python's traceback on stderr with exit 1 is exactly Claude Code's
non-blocking error: the session continues and the breakage is visible.
"""

import json
import math
import os
import shlex
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_CEILING = 350_000
# Re-read on every invocation, which is what makes it a live knob: the hook is a fresh
# process per event, so a number written here takes effect on the very next tool call.
# The environment variable cannot do that - it is fixed when the session launches.
CEILING_FILE = Path(os.environ.get("MEMENTO_CEILING_FILE")
                    or Path.home() / ".claude" / "memento" / "context-ceiling")
# Written by a person who wants the gate to stop, so the spellings that obviously mean
# that all work rather than one blessed token.
DISABLED = ("off", "none", "never", "disabled")
LOG_FILE = Path(os.environ.get("MEMENTO_CEILING_LOG")
                or Path.home() / ".claude" / "memento" / "context-ceiling.log")
LOG_CAP = 2_000_000
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
DENIAL = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum, so new work is refused until it closes out. This tool call was NOT run. git is still permitted: commit anything outstanding, then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with. Do not retry this call, and do not ask the user whether to finalize."""

# Reads are NOT open, though the argument for opening them is seductive: a handoff
# should not be written blind. It does not survive the ceiling being a *context* limit.
# Every Read grows the session the gate exists to stop growing - one large file pulled
# in while ostensibly closing out defeats the close-out - and the two things a handoff
# actually needs are recall, which is already in context, and the state of the tree,
# which `git status` and `git diff` supply through the git that stays permitted.
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


def parse_ceiling(written, source):
    """The ceiling a configured value names, or a clean refusal saying where to fix it.

    [LAW:no-silent-failure] a typo must not read as the default. A file saying 50000
    that quietly enforced 350000 would be a ceiling its author believes they moved and
    did not - worse than no ceiling at all, because they would trust it. So a value
    that does not parse stops the hook loudly, naming the source and what it read,
    rather than falling back to a number nobody asked for."""
    text = written.strip()
    if text.lower() in DISABLED:
        # [LAW:dataflow-not-control-flow] disabling is a value the same comparison
        # consumes, not a branch around the comparison.
        return math.inf
    digits = text.replace("_", "")
    if digits.isdigit():
        return int(digits)
    sys.exit(f"memento context ceiling: {source} should hold a number of tokens or one "
             f"of {'/'.join(DISABLED)}, but reads {text!r}. Fix it or remove it.")


def resolve_ceiling():
    """The ceiling in force for this invocation.

    [LAW:single-enforcer] the one place the ceiling is decided, so the precedence
    between the two ways of saying it exists once rather than at each reader. The
    environment wins because it is an explicit instruction to this process - a test or
    a one-off probe - and a process launched with an override should not be overruled
    by an ambient file it never mentioned."""
    override = os.environ.get("MEMENTO_CONTEXT_CEILING")
    if override is not None:
        return parse_ceiling(override, "MEMENTO_CONTEXT_CEILING")
    try:
        written = CEILING_FILE.read_text()
    except FileNotFoundError:
        return DEFAULT_CEILING
    # `> the-file` is how a shell clears a setting, so an empty file reads as
    # unconfigured rather than as a value that failed to parse.
    return parse_ceiling(written, CEILING_FILE) if written.strip() else DEFAULT_CEILING


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


def log(hook, tokens, verdict):
    """One line per invocation, including - especially - the ones that permit.

    [LAW:no-silent-failure] a hook that allows emits nothing on stdout, and nothing is
    exactly what a hook that never ran emits. That ambiguity is not theoretical: it hid
    a ceiling that had been dead for a day, and it is unresolvable from the outside
    because both cases look like silence. The log is the only place the difference
    exists, so it records what was seen and decided every time, not just at the
    interesting moments - a log that spoke up only when the gate fired would leave the
    dead-gate case looking exactly like the quiet one all over again.

    Its own failure is reported but not fatal. Raising here would exit non-zero on every
    event and take the gate down with the instrumentation, which inverts the point of
    having it."""
    line = (f"{datetime.now().isoformat(timespec='seconds')} "
            f"session={str(hook.get('session_id'))[:8]} event={hook.get('hook_event_name')} "
            f"tokens={tokens} ceiling={CEILING} tool={hook.get('tool_name', '-')} "
            f"-> {verdict}\n")
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        # Truncate rather than rotate: this is a diagnostic tail, and a cap keeps a
        # per-tool-call writer from growing without bound on a long autonomous run.
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > LOG_CAP:
            LOG_FILE.write_text(f"[truncated at {LOG_CAP} bytes]\n")
        with LOG_FILE.open("a") as handle:
            handle.write(line)
    except OSError as failure:
        print(f"memento context ceiling: cannot write {LOG_FILE}: {failure}", file=sys.stderr)


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
        return "spent", {"systemMessage": f"memento: context ceiling breached (~{tokens:,} > "
                                 f"{CEILING:,}) and this session has spent its one forced "
                                 f"close-out attempt, so the stop proceeds. If the close-out "
                                          f"did not run, the next session starts with nothing."}
    return "block", {"decision": "block", "reason": reason(INSTRUCTION, tokens)}


def pretool(hook, tokens):
    """The close-out is the only work left, so it is the only work permitted."""
    if is_closeout(hook["tool_name"], hook.get("tool_input") or {}):
        return "allow-closeout", None
    return "deny", {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                           "permissionDecision": "deny",
                                           "permissionDecisionReason": reason(DENIAL, tokens)}}


def reason(template, tokens):
    return template.format(tokens=tokens, ceiling=CEILING, launcher=shlex.quote(LAUNCHER))


# Keyed on the name Claude Code puts in the payload, never on an argv the registration
# has to restate. [LAW:one-source-of-truth] the harness already names the event it is
# delivering; a copy in the command line is a second map of that fact, maintained by
# hand, free to drift - and it drifted. Registrations for this script exist in every
# cached plugin version a session might still be running, three of them invoking it
# bare and two more with an older pair of verbs, so requiring argv turned a stale
# registration into an IndexError traceback in a live session. Reading the payload
# makes every one of those spellings work, including the ones already on disk.
CEILING = resolve_ceiling()
EVENTS = {"Stop": stop, "PreToolUse": pretool}

hook = json.load(sys.stdin)
event = EVENTS[hook["hook_event_name"]]
tokens = context_tokens(hook["transcript_path"])

# [LAW:dataflow-not-control-flow] the measurement runs on every event, and every
# invocation leaves a log line; only the value produced decides what is emitted.
# The label comes back from the handler that decided rather than being re-derived here
# from the shape of the payload - [LAW:one-source-of-truth], the decision is named once,
# where it is made.
label, verdict = ("allow-under", None) if tokens < CEILING else event(hook, tokens)
log(hook, tokens, label)
if verdict:
    print(json.dumps(verdict))
