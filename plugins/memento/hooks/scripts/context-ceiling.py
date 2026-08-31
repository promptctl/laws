#!/usr/bin/env python3
"""The context ceiling: a session past the hard token maximum may not start new work
until it has run the message-in-a-bottle close-out.

Two events, because one is not enough. Stop has teeth in a session that stops; an
autonomous session never stops, and that is exactly the session the ceiling exists to
catch. [LAW:no-ambient-temporal-coupling] so it is also enforced on PreToolUse, where a
loop cannot avoid it. Denial withholds tools, never the exit, so it cannot wedge a
session - which is why PreToolUse needs no spent-attempt valve and keeps no state.

This bounds a session that would talk itself into continuing, not one trying to escape:
git is permitted by name, so an executable the agent planted under that name is out of
scope, as is a git reconfigured to run something else.

Anything unexpected raises: the traceback with exit 1 is Claude Code's non-blocking
error, so the session continues and the breakage is visible.
"""

import fcntl
import json
import math
import os
import shlex
import shutil
import string
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_CEILING = 250_000
CEILING_FILE = Path(os.environ.get("MEMENTO_CEILING_FILE")
                    or Path.home() / ".claude" / "memento" / "context-ceiling")
DISABLING_WORDS = ("off", "none", "never", "disabled")
LOG_FILE = Path(os.environ.get("MEMENTO_CEILING_LOG")
                or Path.home() / ".claude" / "memento" / "context-ceiling.log")
LOG_CAP = 2_000_000
PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAUNCHER = os.path.join(PLUGIN_ROOT, "skills", "message-in-a-bottle", "bin", "finalize-session")
CLOSEOUT_SKILL = "memento:message-in-a-bottle"
EVERY_PROMPT_COMPONENT = ("input_tokens", "cache_creation_input_tokens",
                          "cache_read_input_tokens", "output_tokens")
TAIL_CHUNK = 256 * 1024

# `reset --hard`, `clean -xdf`, `checkout -- .` and `branch -D` destroy the uncommitted work
# a handoff exists to carry across a reset; `push --force` and `commit --amend` destroy it
# once it is committed. Reading cannot destroy anything, so those subcommands take any
# flags; the writing ones take only the flags a close-out needs.
# Enough to see the tree and get outstanding work committed and pushed. Arguments are not
# inspected, so `push --force` is permitted up here knowingly: git's argument surface is
# unbounded, and every rule tried against it refused more real close-out work than it
# prevented. A gate that blocks the commit is worse than one that permits a force-push.
PERMITTED_GIT = frozenset(("status", "diff", "log", "show", "rev-parse",
                           "add", "commit", "push"))
# The global options that may precede the subcommand, and how many tokens each takes. `-c`
# is not among them: `git -c alias.x='!sh -c ...' x` defines an alias that runs anything.
GLOBAL_GIT = {"-C": 1, "--no-pager": 0}
# Recognised by the launcher only as its first argument (its own `case "${1:-}"`). They take
# a pid to kill and a binary to run, so they are refused where it reads them.
WORKER_MODES = frozenset(("--worker", "--iterm-worker", "--detached-worker"))
LEFT_ALONE_BY_THE_SHELL = frozenset(string.ascii_letters + string.digits + "_@%+=:,./-")
ENDS_WORD = frozenset(" \t")
ENDS_STATEMENT = frozenset("&|;\n")
EXPANDS_IN_DOUBLE_QUOTES = frozenset("$`\\")

INSTRUCTION = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum. Close it out now so the next session can pick the work back up. Commit or push everything outstanding first - a handoff across a reset loses whatever is not committed - then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with, so it says what you were doing, exactly where you stopped, and the next concrete step. Quote it with single quotes and nothing else - no $(...), no heredoc, no double quotes - writing an apostrophe as '\\''. Newlines inside the quotes are fine. Do not start new work, and do not ask the user whether to finalize."""

DENIAL = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum, so new work is refused until it closes out. This tool call was NOT run. `git {git}` are still permitted: get anything outstanding committed, then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with. Do not retry this call, and do not ask the user whether to finalize."""

MISQUOTED = """CONTEXT CEILING: this IS the close-out, and it was NOT run - because of how the command is written, not because closing out is refused. Rewrite it and run it again.
The handoff must be ONE single-quoted argument. No $(...), no backticks, no heredoc, no double quotes: the gate cannot tell what those would run, so it refuses them. Newlines inside the single quotes are fine, so a long multi-paragraph message needs nothing special. Write an apostrophe as '\\'' - end the quote, backslash-quote, reopen. Run exactly this shape:
    {launcher} '<handoff message>'"""

CLOSEOUT, MISQUOTED_CLOSEOUT, NEW_WORK = "allow-closeout", "deny-misquoted", "deny"
REFUSALS = {NEW_WORK: DENIAL, MISQUOTED_CLOSEOUT: MISQUOTED}


def same_file(one, other):
    """A bare name is resolved the way the shell resolves it; the identity check still runs
    afterwards, so an impostor found on PATH is still not the launcher."""
    found = shutil.which(one) if os.path.basename(one) == one else one
    return bool(found) and os.path.realpath(found) == os.path.realpath(other)


def statements(command):
    """The commands this string runs - or ValueError, meaning what it runs is unclear.
    [LAW:parse-dont-validate] every character is default-reject, because a blocklist over
    shell grammar can never be finished."""
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
            if char == '"' and EXPANDS_IN_DOUBLE_QUOTES & set(span):
                raise ValueError(f"expansion inside double quotes: {span!r}")
            word.append(span)
            index = close + 1
        elif char == "\\" and command[index:index + 1] == "'":
            word.append("'")  # the middle of `'it'\''s'`, and handoffs are full of them
            index += 1
        elif char in LEFT_ALONE_BY_THE_SHELL:
            word.append(char)
        elif char in ENDS_WORD or char in ENDS_STATEMENT:
            if word:
                words.append("".join(word))
                word = []
            if char in ENDS_STATEMENT and words:
                parts.append(words)
                words = []
        else:
            raise ValueError(f"shell-active character {char!r} in {command!r}")
    if word:
        words.append("".join(word))
    if words:
        parts.append(words)
    return parts


def written_at(path):
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""


def resolve_ceiling():
    """The ceiling in force: the environment, else the file, else the default.
    [LAW:no-silent-failure] a typo must not read as the default - a ceiling its author
    believes they moved and did not is worse than none."""
    for source, written in (("MEMENTO_CONTEXT_CEILING", os.environ.get("MEMENTO_CONTEXT_CEILING", "")),
                            (CEILING_FILE, written_at(CEILING_FILE))):
        text = written.strip()
        if not text:
            continue
        if text.lower() in DISABLING_WORDS:
            return math.inf
        if text.replace("_", "").isdigit():
            return int(text.replace("_", ""))
        sys.exit(f"memento context ceiling: {source} should hold a number of tokens or one "
                 f"of {'/'.join(DISABLING_WORDS)}, but reads {text!r}. Fix it or remove it.")
    return DEFAULT_CEILING


def records_newest_first(transcript_path):
    """This session's records, reading only as far back as the caller consumes. Sidechains
    are a subagent's conversation, so they never reach a caller."""
    with open(transcript_path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        end = handle.tell()
        straddling_head = b""
        while end > 0:
            start = max(0, end - TAIL_CHUNK)
            handle.seek(start)
            lines = (handle.read(end - start) + straddling_head).split(b"\n")
            straddling_head = b"" if start == 0 else lines.pop(0)
            for line in reversed(lines):
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not record.get("isSidechain"):
                    yield record
            end = start


def context_tokens(transcript_path):
    for record in records_newest_first(transcript_path):
        if record.get("type") == "assistant":
            usage = record["message"].get("usage")
            if usage:
                return sum(usage.get(field, 0) for field in EVERY_PROMPT_COMPONENT)
    return 0


def starts_a_turn(record):
    content = record.get("message", {}).get("content")
    blocks = content if isinstance(content, list) else []
    return record.get("type") == "user" and not any(
        isinstance(block, dict) and block.get("type") == "tool_result" for block in blocks)


def closed_out(transcript_path):
    """Whether the launcher ran successfully in the turn now ending - bounded at the turn,
    because crediting an older one would wave through every later breach in a transcript the
    tmux transport compacts in place. [FRAMING:representation] a denied call is written into
    the transcript exactly like one that ran, so only the result says it happened."""
    errored = set()
    for record in records_newest_first(transcript_path):
        if starts_a_turn(record):
            return False
        content = record.get("message", {}).get("content")
        for block in reversed(content if isinstance(content, list) else []):
            if not isinstance(block, dict):
                continue
            if block.get("is_error"):
                errored.add(block.get("tool_use_id"))
            if (block.get("type") == "tool_use" and block.get("id") not in errored
                    and launched(block.get("name"), block.get("input") or {})):
                return True
    return False


def permitted(statement):
    """git is matched by role, because it is many files; the launcher by identity, because
    it is one, and anything else wearing that name is not the close-out."""
    program, *arguments = statement
    if os.path.basename(program) == "git":
        return permitted_git(arguments)
    return same_file(program, LAUNCHER) and permitted_launcher(arguments)


def permitted_git(arguments):
    """Which subcommand runs, found past any global options. What it is then asked to do is
    not read."""
    index = 0
    while index < len(arguments) and arguments[index] in GLOBAL_GIT:
        index += 1 + GLOBAL_GIT[arguments[index]]
    return index < len(arguments) and arguments[index] in PERMITTED_GIT


def permitted_launcher(arguments):
    """Everything past a worker mode is a message the launcher reads verbatim, so only the
    first argument is worth looking at."""
    return not arguments or arguments[0] not in WORKER_MODES


def reaching_for_launcher(command):
    """Whether an unparseable command was trying to leave. shlex's tolerance is right here
    and wrong in `statements`: permission is already decided, and when the quoting is what
    broke, whitespace is what is left to split on."""
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    return bool(words) and same_file(words[0], LAUNCHER)


def classify(tool_name, tool_input):
    """What this call is above the ceiling. Default-deny, so a tool nobody thought about
    here surfaces as a blocked close-out rather than a session working past the ceiling."""
    if tool_name == "Skill":
        return CLOSEOUT if tool_input.get("skill") == CLOSEOUT_SKILL else NEW_WORK
    if tool_name != "Bash":
        return NEW_WORK
    command = tool_input.get("command") or ""
    try:
        parts = statements(command)
    except ValueError:
        return MISQUOTED_CLOSEOUT if reaching_for_launcher(command) else NEW_WORK
    return CLOSEOUT if parts and all(permitted(part) for part in parts) else NEW_WORK


def launched(tool_name, tool_input):
    if tool_name != "Bash":
        return False
    try:
        parts = statements(tool_input.get("command") or "")
    except ValueError:
        return False
    return any(same_file(part[0], LAUNCHER) and permitted_launcher(part[1:])
               for part in parts)


def log(hook, tokens, verdict):
    """[LAW:no-silent-failure] a hook that allows emits nothing, and so does one that never
    ran; the log is the only place that difference exists. Its own failure is reported but
    not fatal - raising would take the gate down with the instrumentation."""
    line = (f"{datetime.now().isoformat(timespec='seconds')} "
            f"session={str(hook.get('session_id'))[:8]} event={hook.get('hook_event_name')} "
            f"tokens={tokens} ceiling={CEILING} tool={hook.get('tool_name', '-')} "
            f"-> {verdict}\n")
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        # PreToolUse makes concurrent writers ordinary, so the cap check, the truncation and
        # the append are one locked sequence rather than three racing steps.
        with LOG_FILE.open("a") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            if os.fstat(handle.fileno()).st_size > LOG_CAP:
                handle.truncate(0)
                handle.write(f"[truncated at {LOG_CAP} bytes]\n")
            handle.write(line)
    except OSError as failure:
        print(f"memento context ceiling: cannot write {LOG_FILE}: {failure}", file=sys.stderr)


def stop(hook, tokens):
    """Blocked once, never twice: a second block spends more context on the problem that IS
    too much context. The give-up message leaves whether the close-out ran conditional,
    because the compliant path is exactly when stop_hook_active is true."""
    if closed_out(hook["transcript_path"]):
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
    """The close-out is the only work left, so it is the only work permitted."""
    label = classify(hook["tool_name"], hook.get("tool_input") or {})
    template = REFUSALS.get(label)
    if template is None:
        return label, None
    return label, {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                          "permissionDecision": "deny",
                                          "permissionDecisionReason": reason(template, tokens)}}


def reason(template, tokens):
    return template.format(tokens=tokens, ceiling=CEILING,
                           git="/".join(sorted(PERMITTED_GIT)),
                           launcher=shlex.quote(LAUNCHER))


CEILING = resolve_ceiling()
EVENTS = {"Stop": stop, "PreToolUse": pretool}

hook = json.load(sys.stdin)
event = EVENTS[hook["hook_event_name"]]
tokens = context_tokens(hook["transcript_path"])

label, verdict = ("allow-under", None) if tokens < CEILING else event(hook, tokens)
log(hook, tokens, label)
if verdict:
    print(json.dumps(verdict))
