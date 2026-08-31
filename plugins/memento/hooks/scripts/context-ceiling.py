#!/usr/bin/env python3
"""The context ceiling: a session past the hard token maximum may not start new work
until it has run the message-in-a-bottle close-out.

Two events, because one is not enough. Stop has teeth in a session that stops; an
autonomous session never stops, and that is exactly the session the ceiling exists to
catch. [LAW:no-ambient-temporal-coupling] a ceiling enforced only at an incidental
lifecycle event is enforced by luck, so PreToolUse enforces it where a loop cannot avoid
it: above the ceiling the permitted set narrows to the close-out and everything else is
denied, reads included - a tool that grows context cannot be part of respecting a limit on
context. [LAW:types-are-the-program] new work above the ceiling is unrepresentable.

Denial withholds tools, never the exit, so it cannot wedge a session - which is why
PreToolUse needs no spent-attempt valve and keeps no state. Anything unexpected raises,
and the traceback with exit 1 is Claude Code's non-blocking error: the session continues
and the breakage is visible.
"""

import fcntl
import json
import math
import os
import shlex
import string
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_CEILING = 250_000
# Re-read per invocation, which is what makes it a live knob: the hook is a fresh process
# per event, where the environment variable is fixed when the session launches.
CEILING_FILE = Path(os.environ.get("MEMENTO_CEILING_FILE")
                    or Path.home() / ".claude" / "memento" / "context-ceiling")
# Written by a person who wants the gate to stop, so every spelling that means that works.
DISABLED = ("off", "none", "never", "disabled")
LOG_FILE = Path(os.environ.get("MEMENTO_CEILING_LOG")
                or Path.home() / ".claude" / "memento" / "context-ceiling.log")
LOG_CAP = 2_000_000
PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAUNCHER = os.path.join(PLUGIN_ROOT, "skills", "message-in-a-bottle", "bin", "finalize-session")
CLOSEOUT_SKILL = "memento:message-in-a-bottle"
# Everything the next request will carry, not just the newest slice.
COUNTED = ("input_tokens", "cache_creation_input_tokens",
           "cache_read_input_tokens", "output_tokens")
# Big enough that the newest assistant record is in the first read essentially always.
TAIL_CHUNK = 256 * 1024

# See the tree, and get what is outstanding committed and pushed. The destructive half of
# git is why the rest is denied: `reset --hard`, `clean -xdf`, `checkout -- .` and
# `branch -D` destroy exactly the uncommitted work a handoff carries across a reset. A list
# of forbidden *flags* would be the same blocklist mistake one layer down.
GIT_SUBCOMMANDS = frozenset(("status", "diff", "log", "show", "rev-parse",
                             "add", "commit", "push"))
# shlex.quote's own safe set: none of these expands, substitutes, redirects, groups or
# globs, so a word built only from them reaches the command exactly as written.
INERT = frozenset(string.ascii_letters + string.digits + "_@%+=:,./-")
ENDS_WORD = frozenset(" \t")
# Characters, not an enumeration of operators, so "&&", "||", "|&", ";;" and any future
# spelling made of them all end a segment. The bare newline is a separator too.
ENDS_SEGMENT = frozenset("&|;\n")
# What expands inside double quotes - a span with none of these is as inert as a
# single-quoted one, which is the only reason double quotes are allowed at all.
EXPANDS = frozenset("$`\\")

# {launcher} arrives shell-quoted: the agent runs the line verbatim, and a plugin root like
# ~/Library/Application Support/... would otherwise split and lose the only exit.
INSTRUCTION = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum. Close it out now so the next session can pick the work back up. Commit or push everything outstanding first - a handoff across a reset loses whatever is not committed - then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with, so it says what you were doing, exactly where you stopped, and the next concrete step. Quote it with single quotes and nothing else - no $(...), no heredoc, no double quotes - writing an apostrophe as '\\''. Newlines inside the quotes are fine. Do not start new work, and do not ask the user whether to finalize."""

# Repeated on every refused call, so it states the way out and stops - the ceiling is a
# context problem and the denial must not itself become a context cost.
DENIAL = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum, so new work is refused until it closes out. This tool call was NOT run. `git {git}` are still permitted: get anything outstanding committed, then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with. Do not retry this call, and do not ask the user whether to finalize."""

# A misquoted close-out needs its own words: an agent that cannot tell "you may not do
# this" from "you may, but not spelled that way" retries the same spelling, and the gate
# refusing its own way out is the worst failure it has.
MISQUOTED = """CONTEXT CEILING: this IS the close-out, and it was NOT run - because of how the command is written, not because closing out is refused. Rewrite it and run it again.
The handoff must be ONE single-quoted argument. No $(...), no backticks, no heredoc, no double quotes: the gate cannot tell what those would run, so it refuses them. Newlines inside the single quotes are fine, so a long multi-paragraph message needs nothing special. Write an apostrophe as '\\'' - end the quote, backslash-quote, reopen. Run exactly this shape:
    {launcher} '<handoff message>'"""

# What a call above the ceiling can be, and the whole of it. These double as the log's
# verdict labels because they are the same fact: what the gate decided this call was.
CLOSEOUT, MISQUOTED_CLOSEOUT, NEW_WORK = "allow-closeout", "deny-misquoted", "deny"
# [LAW:one-source-of-truth] which classification is refused, and in which words, decided
# here rather than at the branch that emits. The close-out's absence is what permits it.
DENIALS = {NEW_WORK: DENIAL, MISQUOTED_CLOSEOUT: MISQUOTED}


def segments(command):
    """The commands this string runs - or ValueError, meaning what it runs is unclear.

    [LAW:parse-dont-validate] every character is default-reject: not "does this contain
    something known to be dangerous" but "is this one I can prove is plain", because a
    blocklist over shell grammar can never be finished. Governs which *tools* run, not
    what a trusted tool is then asked to do."""
    parts, words, word = [], [], []
    index = 0
    while index < len(command):
        char = command[index]
        index += 1
        if char in "'\"":
            close = command.find(char, index)
            if close < 0:
                raise ValueError(f"unterminated {char} quote")
            span = command[index:close]
            # Single quotes are inert by bash's own guarantee, which is what lets the
            # handoff stay free prose. Double quotes only when nothing expands.
            if char == '"' and EXPANDS & set(span):
                raise ValueError(f"expansion inside double quotes: {span!r}")
            word.append(span)
            index = close + 1
        # The middle of `'it'\''s'`, the one way to put an apostrophe in a single-quoted
        # argument - and handoff prose is full of them.
        elif char == "\\" and command[index:index + 1] == "'":
            word.append("'")
            index += 1
        elif char in INERT:
            word.append(char)
        elif char in ENDS_WORD or char in ENDS_SEGMENT:
            if word:
                words.append("".join(word))
                word = []
            if char in ENDS_SEGMENT and words:
                parts.append(words)
                words = []
        else:
            raise ValueError(f"shell-active character {char!r} in {command!r}")
    if word:
        words.append("".join(word))
    if words:
        parts.append(words)
    return parts


def read_text(path):
    """An absent file and an empty one both say nothing, so they read the same."""
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""


def resolve_ceiling():
    """The ceiling in force: the environment, else the file, else the default.

    [LAW:dataflow-not-control-flow] one loop over a sequence of sources, so precedence,
    blankness and parsing are each stated once - a rule kept per reader drifts per reader.
    [LAW:no-silent-failure] a typo must not read as the default: a ceiling its author
    believes they moved and did not is worse than none, because they would trust it."""
    for source, written in (("MEMENTO_CONTEXT_CEILING", os.environ.get("MEMENTO_CONTEXT_CEILING", "")),
                            (CEILING_FILE, read_text(CEILING_FILE))):
        text = written.strip()
        if not text:
            continue  # `> the-file` and `VAR=` are the same gesture: silence, not a value
        if text.lower() in DISABLED:
            # Disabling is a value the same comparison consumes, not a branch around it.
            return math.inf
        if text.replace("_", "").isdigit():
            return int(text.replace("_", ""))
        sys.exit(f"memento context ceiling: {source} should hold a number of tokens or one "
                 f"of {'/'.join(DISABLED)}, but reads {text!r}. Fix it or remove it.")
    return DEFAULT_CEILING


def records_backward(transcript_path):
    """This session's records, newest first, reading only as far back as the caller
    consumes. Sidechains are a different conversation - a subagent writes into this same
    file - so they never reach a caller and no caller repeats the rule. Reading the whole
    file made a per-tool-call measurement quadratic in a transcript whose answer is always
    in the last few kilobytes."""
    with open(transcript_path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        end = handle.tell()
        tail = b""
        while end > 0:
            start = max(0, end - TAIL_CHUNK)
            handle.seek(start)
            pieces = (handle.read(end - start) + tail).split(b"\n")
            # The first piece began before `start`, so it is only the tail of its line -
            # unless start is 0, where there is nothing earlier and the line is whole.
            tail = b"" if start == 0 else pieces.pop(0)
            for line in reversed(pieces):
                try:
                    record = json.loads(line)
                except ValueError:
                    continue  # a blank line, or the tail of a write still in flight
                if not record.get("isSidechain"):
                    yield record
            end = start


def context_tokens(transcript_path):
    """Tokens in context, from the transcript because no hook payload carries the number.
    Compaction shrinks the following record, so the newest one tracks the drop."""
    for record in records_backward(transcript_path):
        if record.get("type") == "assistant":
            usage = record["message"].get("usage")
            if usage:
                return sum(usage.get(field, 0) for field in COUNTED)
    return 0


def last_tool_call(transcript_path):
    """The most recent tool this session invoked, as (name, input, ran). `ran` comes off
    the call's own result - a refused or failed call carries `is_error`, a successful one
    carries no such key - and reading newest-first meets the result before the call, so one
    pass answers both halves."""
    failed = set()
    for record in records_backward(transcript_path):
        content = record.get("message", {}).get("content")
        for block in reversed(content if isinstance(content, list) else []):
            if not isinstance(block, dict):
                continue
            if block.get("is_error"):
                failed.add(block.get("tool_use_id"))
            if block.get("type") == "tool_use":
                return (block.get("name"), block.get("input") or {},
                        block.get("id") not in failed)
    return None, {}, False


def permitted(part):
    """Whether this one command is part of closing the session out.

    The two programs are matched by different questions, and the asymmetry is the design.
    The launcher is ONE file, so the question is *identity* - resolved, or anything named
    finalize-session answers by spelling alone and the gate records a close-out that never
    happened. git is not one file (/usr/bin/git and /opt/homebrew/bin/git are both real
    git), so the question is *role*; resolving it would bless whichever git PATH names."""
    if os.path.basename(part[0]) == "git":
        # The subcommand is the second word, with no global option before it: skipping
        # options means knowing which take a value, and `git -c` takes one that can define
        # an alias running anything at all.
        return len(part) > 1 and part[1] in GIT_SUBCOMMANDS
    return os.path.realpath(part[0]) == os.path.realpath(LAUNCHER)


def classify(tool_name, tool_input):
    """What this call is above the ceiling: the close-out, the close-out written in a form
    the parser cannot read, or new work. Default-deny, so a tool nobody thought about here
    surfaces as a blocked close-out rather than a session quietly working past the ceiling.
    [LAW:types-are-the-program] three names covering the whole domain, so the verdict, the
    wording and the log label read one value instead of each re-deriving it."""
    if tool_name == "Skill":
        return CLOSEOUT if tool_input.get("skill") == CLOSEOUT_SKILL else NEW_WORK
    if tool_name != "Bash":
        return NEW_WORK
    # The outermost edge: this arrives as JSON on stdin from outside the process, so it is
    # accepted liberally here, at the checkpoint, and nowhere inland
    # [LAW:parse-dont-validate]. An empty command parses to no segments and is refused
    # below by the same rule that refuses everything else, with no case of its own.
    command = tool_input.get("command") or ""
    try:
        parts = segments(command)
    except ValueError:
        # Only for a command that *starts* with the launcher: one that merely mentions its
        # path is not a session trying to leave. shlex's tolerance is right here and wrong
        # in `segments` - permission is already decided, and when the quoting is what
        # broke, whitespace is what is left to split on.
        try:
            words = shlex.split(command)
        except ValueError:
            words = command.split()
        return (MISQUOTED_CLOSEOUT
                if words and os.path.realpath(words[0]) == os.path.realpath(LAUNCHER)
                else NEW_WORK)
    # Judged on what each segment *runs*, not what it mentions.
    return CLOSEOUT if parts and all(permitted(part) for part in parts) else NEW_WORK


def launched(tool_name, tool_input, ran):
    """Whether this call is the launcher itself and actually ran, rather than something the
    close-out is merely allowed to do on the way there - `classify` says yes to `git
    status`, permitted during a close-out but not one. [FRAMING:representation] a denied
    call is written into the transcript exactly like one that ran, so without `ran` the
    gate's success and its total defeat spell identically: the command text maps what was
    attempted, only the result records what happened."""
    if not ran or tool_name != "Bash":
        return False
    try:
        parts = segments(tool_input.get("command") or "")
    except ValueError:
        return False
    return any(os.path.realpath(part[0]) == os.path.realpath(LAUNCHER) for part in parts)


def log(hook, tokens, verdict):
    """One line per invocation, including - especially - the ones that permit.
    [LAW:no-silent-failure] a hook that allows emits nothing, and nothing is exactly what a
    hook that never ran emits; the log is the only place that difference exists. Its own
    failure is reported but not fatal - raising would take the gate down with the
    instrumentation."""
    line = (f"{datetime.now().isoformat(timespec='seconds')} "
            f"session={str(hook.get('session_id'))[:8]} event={hook.get('hook_event_name')} "
            f"tokens={tokens} ceiling={CEILING} tool={hook.get('tool_name', '-')} "
            f"-> {verdict}\n")
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        # [LAW:no-ambient-temporal-coupling] PreToolUse makes concurrent writers ordinary,
        # so check, truncate and append happen on one handle under one lock rather than as
        # three steps whose interleaving decides which lines survive.
        with LOG_FILE.open("a") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            if os.fstat(handle.fileno()).st_size > LOG_CAP:
                handle.truncate(0)
                handle.write(f"[truncated at {LOG_CAP} bytes]\n")
            handle.write(line)
    except OSError as failure:
        print(f"memento context ceiling: cannot write {LOG_FILE}: {failure}", file=sys.stderr)


def stop(hook, tokens):
    """Blocked once, never twice: a second block would spend more context on the problem
    that IS too much context, so the agent gets one forced chance and then the gate opens -
    loudly, because a ceiling that quietly gave up is worse than none. That message leaves
    whether the close-out ran conditional, deliberately: the compliant path (block,
    finalize, stop again) is exactly when stop_hook_active is true, so asserting failure
    would call every successful close-out a failure. A session that just ran the launcher
    is not asked to run it again - the contract ends the turn at that call."""
    if launched(*last_tool_call(hook["transcript_path"])):
        return "closed-out", {"systemMessage": f"memento: the close-out ran at ~{tokens:,} "
                                               f"tokens, past the {CEILING:,} ceiling, so "
                                               f"the stop proceeds."}
    if hook.get("stop_hook_active"):
        return "spent", {"systemMessage": f"memento: context ceiling breached (~{tokens:,} > "
                                          f"{CEILING:,}) and this session has spent its one "
                                          f"forced close-out attempt, so the stop proceeds. "
                                          f"If the close-out did not run, the next session "
                                          f"starts with nothing."}
    return "block", {"decision": "block", "reason": reason(INSTRUCTION, tokens)}


def pretool(hook, tokens):
    """The close-out is the only work left, so it is the only work permitted.
    [LAW:dataflow-not-control-flow] one value chooses the words and the log line together,
    so the log says which denial an agent is stuck on."""
    label = classify(hook["tool_name"], hook.get("tool_input") or {})
    template = DENIALS.get(label)
    if template is None:
        return label, None
    return label, {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                          "permissionDecision": "deny",
                                          "permissionDecisionReason": reason(template, tokens)}}


def reason(template, tokens):
    # [LAW:one-source-of-truth] the denial names the permitted git subcommands by reading
    # the set that decides them; a hand-kept second list would be a promise to the agent
    # the gate is free to stop keeping. Templates ignore fields they do not mention.
    return template.format(tokens=tokens, ceiling=CEILING,
                           git="/".join(sorted(GIT_SUBCOMMANDS)),
                           launcher=shlex.quote(LAUNCHER))


# Keyed on the name Claude Code puts in the payload, never on an argv the registration has
# to restate. [LAW:one-source-of-truth] the harness already names the event it delivers; a
# copy in the command line is a second map of it, free to drift - and it drifted, turning a
# stale registration into a traceback in a live session.
CEILING = resolve_ceiling()
EVENTS = {"Stop": stop, "PreToolUse": pretool}

hook = json.load(sys.stdin)
event = EVENTS[hook["hook_event_name"]]
tokens = context_tokens(hook["transcript_path"])

# [LAW:dataflow-not-control-flow] the measurement runs on every event and every invocation
# leaves a log line; only the value produced decides what is emitted, and the label comes
# back from the handler that decided rather than being re-derived from the payload.
label, verdict = ("allow-under", None) if tokens < CEILING else event(hook, tokens)
log(hook, tokens, label)
if verdict:
    print(json.dumps(verdict))
