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
the close-out itself - the launcher resolved to its own path, the read-and-commit half
of git, and the handoff contract - and everything else is denied, reads included: the
ceiling is a limit on context, so a tool that grows context cannot be part of
respecting it. Not the destructive half of git either, because uncommitted work is
what a handoff carries and `git reset --hard` is how a session loses it.
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
import string
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
# Big enough that the newest assistant record is in the first read essentially always,
# small enough that being wrong about that costs one more seek rather than the file.
TAIL_CHUNK = 256 * 1024

# {launcher} arrives shell-quoted. The agent runs that line verbatim, and a plugin
# root like ~/Library/Application Support/... would otherwise split into two arguments
# and lose the only exit from the block.
INSTRUCTION = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum. Close it out now so the next session can pick the work back up. Commit or push everything outstanding first - a handoff across a reset loses whatever is not committed - then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with, so it says what you were doing, exactly where you stopped, and the next concrete step. Quote it with single quotes and nothing else - no $(...), no heredoc, no double quotes - writing an apostrophe as '\\''. Newlines inside the quotes are fine. Do not start new work, and do not ask the user whether to finalize."""

# Repeated on every refused call, so it states the way out and stops - the ceiling is
# a context problem and the denial must not itself become a context cost.
DENIAL = """CONTEXT CEILING: this session is at ~{tokens:,} tokens, past the {ceiling:,} hard maximum, so new work is refused until it closes out. This tool call was NOT run. `git {git}` are still permitted: get anything outstanding committed, then run the close-out:
    {launcher} '<handoff message>'
Load Skill(memento:message-in-a-bottle) for the handoff contract. That message is the ONLY thing the next session wakes up with. Do not retry this call, and do not ask the user whether to finalize."""

# The close-out, attempted in a form the parser will not accept. It needs its own words
# because an ordinary denial and a misquoted close-out otherwise read identically, and an
# agent that cannot tell "you may not do this" from "you may, but not spelled that way"
# retries the same spelling. Observed live, session 3b20dc93: it reached for
# `--reset compact "$(cat <<'EOF' ... EOF)"` - the standard idiom for long multi-line
# text - and spent two denials and ~10k tokens discovering that the plain form was
# wanted. The gate refusing its own way out is the worst failure it has.
MISQUOTED = """CONTEXT CEILING: this IS the close-out, and it was NOT run - because of how the command is written, not because closing out is refused. Rewrite it and run it again.
The handoff must be ONE single-quoted argument. No $(...), no backticks, no heredoc, no double quotes: the gate cannot tell what those would run, so it refuses them. Newlines inside the single quotes are fine, so a long multi-paragraph message needs nothing special. Write an apostrophe as '\\'' - end the quote, backslash-quote, reopen. Run exactly this shape:
    {launcher} '<handoff message>'"""

# Reads are NOT open, though the argument for opening them is seductive: a handoff
# should not be written blind. It does not survive the ceiling being a *context* limit.
# Every Read grows the session the gate exists to stop growing - one large file pulled
# in while ostensibly closing out defeats the close-out - and the two things a handoff
# actually needs are recall, which is already in context, and the state of the tree,
# which `git status` and `git diff` supply through the git that stays permitted.
CLOSEOUT_SKILL = "memento:message-in-a-bottle"
# What a close-out needs of git: see the tree, and get what is outstanding committed and
# pushed. The rest is denied by default, and the destructive half of git is the reason -
# `git reset --hard`, `git clean -xdf`, `git checkout -- .` all destroy precisely the
# uncommitted work a handoff exists to carry across a reset. A session thrashing near
# the ceiling is the one most likely to reach for them, so permitting git wholesale
# would have let this gate defeat its own purpose while reporting that it held.
# `branch` is absent on purpose: `git branch -D` is as destructive as the rest, and what
# a handoff wants from it - which branch am I on - `git status` and `git rev-parse`
# already answer. Narrowing the list is the fix; a list of forbidden *flags* would be the
# same blocklist mistake one layer down.
GIT_SUBCOMMANDS = frozenset(("status", "diff", "log", "show", "rev-parse",
                             "add", "commit", "push"))
# The characters the shell leaves alone outside quotes - shlex.quote's own safe set.
# None of them expands, substitutes, redirects, groups, or globs, so a word built only
# from these reaches the command exactly as written here.
INERT = frozenset(string.ascii_letters + string.digits + "_@%+=:,./-")
ENDS_WORD = frozenset(" \t")
# Every character bash builds a control operator from, plus the newline that IS one.
# Held as a set of characters rather than a list of operators so that "&&", "||", "|",
# ";", ";;", "|&", ";;&" and any future spelling made of them all end a segment - the
# thing an enumeration of operators cannot promise.
ENDS_SEGMENT = frozenset("&|;\n")
# What expands inside double quotes: parameter and command substitution, and the
# escape that hides them. A double-quoted span with none of these is as inert as a
# single-quoted one, which is the only reason double quotes are allowed at all.
EXPANDS = frozenset("$`\\")


def segments(command):
    """The commands this string runs - or ValueError, meaning what it runs is unclear.

    Parsed, not pattern-matched, and every character is default-reject. The earlier
    version of this went the other way: tokenize with shlex, then split on an
    enumerated list of operators. That list can never be finished. `&&` `||` `;` `|`
    were listed; `|&` was not, so `git status |& rm -rf x` read as one git segment.
    A bare newline is a statement separator too, but shlex spends it as whitespace, so
    `git status\\nrm -rf x` read as one git segment as well. And `$(...)` inside a
    quoted argument is opaque to any tokenizer while the shell happily runs it. Three
    reported bypasses, one cause: a blocklist over a grammar that keeps growing.

    [LAW:parse-dont-validate] so the question changed from "does this string contain
    anything I know is dangerous" to "is this string one I can prove is plain" - every
    unquoted character must be one the shell is known to leave alone, single quotes are
    inert by bash's own guarantee (which is what lets the handoff message stay free
    prose), double quotes are allowed only when they contain nothing that expands, and
    anything else at all raises. What comes back is therefore the words the shell will
    actually run, not a guess at them.

    This governs which *tools* run, not what a trusted tool is then asked to do: `git`
    is permitted whole, so a git invocation that reconfigures git to run something else
    is outside what this can see. The ceiling is a limit on a session that would talk
    itself into continuing, not a sandbox around one trying to escape."""
    parts, words, word = [], [], []
    index = 0
    while index < len(command):
        char = command[index]
        index += 1
        if char == "'":
            close = command.find("'", index)
            if close < 0:
                raise ValueError("unterminated single quote")
            word.append(command[index:close])
            index = close + 1
        elif char == '"':
            close = command.find('"', index)
            if close < 0:
                raise ValueError("unterminated double quote")
            span = command[index:close]
            if EXPANDS & set(span):
                raise ValueError(f"expansion inside double quotes: {span!r}")
            word.append(span)
            index = close + 1
        # The middle of `'it'\''s'`, the one way to put an apostrophe in a
        # single-quoted argument - and handoff prose is full of apostrophes. A
        # backslash before a quote is the only escape accepted; every other use of it
        # falls through to the raise below.
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


def configured(written):
    """Whether a source is saying anything at all.

    `> the-file` and `VAR=` are the same gesture - the shell's two ways of clearing a
    setting - so neither blank is a value that failed to parse; both are silence, and
    silence falls through to the next source.

    [LAW:one-source-of-truth] one rule, because a rule kept per source drifts per source,
    and it had: the file honoured this and the environment did not, so an exported-empty
    MEMENTO_CONTEXT_CEILING reached `parse_ceiling`, matched neither the disabling words
    nor a digit, and exited the process at import - before the payload was ever read.
    Which, by this module's own semantics, is a non-blocking error: the ceiling simply
    stopped being enforced for that call. Copying the check into the second reader would
    have fixed that instance and left the third reader free to forget it again."""
    return bool(written.strip())


def resolve_ceiling():
    """The ceiling in force for this invocation.

    [LAW:single-enforcer] the one place the ceiling is decided, so the precedence
    between the two ways of saying it exists once rather than at each reader. The
    environment wins because it is an explicit instruction to this process - a test or
    a one-off probe - and a process launched with an override should not be overruled
    by an ambient file it never mentioned."""
    override = os.environ.get("MEMENTO_CONTEXT_CEILING", "")
    if configured(override):
        return parse_ceiling(override, "MEMENTO_CONTEXT_CEILING")
    try:
        written = CEILING_FILE.read_text()
    except FileNotFoundError:
        return DEFAULT_CEILING
    return parse_ceiling(written, CEILING_FILE) if configured(written) else DEFAULT_CEILING


def lines_backward(handle, end):
    """The file's lines newest-first, reading only as far back as the caller consumes.

    The whole file used to be read for every measurement, which was affordable while
    only Stop measured - once per turn. PreToolUse measures on every tool call, and the
    transcript only grows, so re-reading it whole made the cost of a long autonomous
    run quadratic in its own transcript: the 757-call session in the module docstring
    would have re-scanned tens of megabytes 757 times to answer a question whose answer
    is always in the last few kilobytes.

    [LAW:dataflow-not-control-flow] the reader does not decide how far back is far
    enough; it yields, and whoever is looking stops when it has found what it wants."""
    tail = b""
    while end > 0:
        start = max(0, end - TAIL_CHUNK)
        handle.seek(start)
        pieces = (handle.read(end - start) + tail).split(b"\n")
        # The first piece began before `start`, so it is only the tail of its line -
        # unless start is 0, where there is nothing earlier and the line is whole.
        tail = b"" if start == 0 else pieces.pop(0)
        yield from reversed(pieces)
        end = start


def context_tokens(transcript_path):
    """Tokens in this session's context, read from the transcript because no hook
    payload carries the number.

    Sidechain records are a different conversation - a dispatched subagent writes
    into this same file, and reading its usage would report a session that just
    crossed 350k as sitting at 20k. Compaction needs no handling: it shrinks the
    following record, so the latest one tracks the drop."""
    with open(transcript_path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        for line in lines_backward(handle, handle.tell()):
            try:
                record = json.loads(line)
            except ValueError:
                continue  # a blank line, or the tail of a write still in flight
            if record.get("type") == "assistant" and not record.get("isSidechain"):
                usage = record["message"].get("usage")
                if usage:
                    return sum(usage.get(field, 0) for field in COUNTED)
    return 0


def permitted(part):
    """Whether this one command is part of closing the session out.

    The two programs are matched by different questions, and the asymmetry is the design
    rather than an oversight. The launcher is ONE file, so the question is *identity*:
    resolved, not name-matched, because any other executable that happens to be called
    finalize-session would otherwise answer "is this the close-out" by spelling alone,
    and the gate would go on to record a close-out that never happened. git is not one
    file - `/usr/bin/git` and `/opt/homebrew/bin/git` are both genuinely git - so the
    question is *role*, and a name is what carries a role.

    Resolving git the way the launcher is resolved is the symmetry this looks like it
    wants, and it is wrong: on a machine whose PATH names the Homebrew git, `git` and
    `/usr/bin/git` resolve to two different files, so the gate would silently bless
    whichever one PATH happened to name and refuse every other real git on the box. The
    literal `part[0] == "git"` it replaces had the same shape of bug, one step earlier:
    a fully-qualified `/usr/bin/git commit` was refused while the denial message went on
    promising that git still worked.

    Matching by name accepts a git the agent planted under a path of its own. That is in
    scope for a sandbox and out of scope here, for the reason the module docstring
    already gives: this bounds a session that would talk itself into continuing, not one
    trying to escape."""
    if os.path.basename(part[0]) == "git":
        # The subcommand is the second word, with no global option allowed before it.
        # Skipping options would mean knowing which of them take a value, and `git -c`
        # takes one that can define an alias running anything at all - so refusing the
        # whole shape is both the simpler rule and the tighter one.
        return len(part) > 1 and part[1] in GIT_SUBCOMMANDS
    return os.path.realpath(part[0]) == os.path.realpath(LAUNCHER)


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
        return bool(parts) and all(permitted(part) for part in parts)
    return False


def launched(tool_name, tool_input):
    """Whether this call is the launcher itself, rather than something the close-out is
    merely allowed to do on the way there.

    `is_closeout` is too generous to answer this: it says yes to `git status`, which is
    permitted during a close-out but is not one."""
    if tool_name != "Bash":
        return False
    try:
        parts = segments(tool_input.get("command", ""))
    except ValueError:
        return False
    return any(os.path.realpath(part[0]) == os.path.realpath(LAUNCHER) for part in parts)


def last_tool_call(transcript_path):
    """The most recent tool this session invoked, as (name, input).

    The transcript is the only record of it - no hook payload carries what the session
    did before this event - and it is the same file the count comes from, read the same
    way, so this costs one more tail read on the rare event that asks."""
    with open(transcript_path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        for line in lines_backward(handle, handle.tell()):
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get("type") != "assistant" or record.get("isSidechain"):
                continue
            for block in reversed(record["message"].get("content") or []):
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    return block.get("name"), block.get("input") or {}
    return None, {}


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
    second Stop hook could open this gate with its block; the wording holds there too.

    A session that just ran the launcher is not asked to run it again. Observed live:
    the close-out was permitted at 19:49:25, and four seconds later this handler blocked
    the stop and instructed the agent to close out - which a compliant agent obeys,
    scheduling a second handoff into the same pane behind the first. The contract says
    the turn is over once the launcher is called, so a stop arriving right after that
    call is the stop the contract asked for, not one to refuse."""
    if launched(*last_tool_call(hook["transcript_path"])):
        return "closed-out", {"systemMessage": f"memento: the close-out ran at ~{tokens:,} "
                                               f"tokens, past the {CEILING:,} ceiling, so "
                                               f"the stop proceeds."}
    if hook.get("stop_hook_active"):
        return "spent", {"systemMessage": f"memento: context ceiling breached (~{tokens:,} > "
                                 f"{CEILING:,}) and this session has spent its one forced "
                                 f"close-out attempt, so the stop proceeds. If the close-out "
                                          f"did not run, the next session starts with nothing."}
    return "block", {"decision": "block", "reason": reason(INSTRUCTION, tokens)}


def pretool(hook, tokens):
    """The close-out is the only work left, so it is the only work permitted.

    A refused call that names the launcher was trying to leave, not trying to stay, and
    is told which of the two it hit. [LAW:dataflow-not-control-flow] one value chooses
    the words and the log line together, so the log says which denial an agent is stuck
    on - the diagnostic that was missing when a live session spent two attempts on a
    heredoc and the log recorded both as plain `deny`."""
    tool_name, tool_input = hook["tool_name"], hook.get("tool_input") or {}
    if is_closeout(tool_name, tool_input):
        return "allow-closeout", None
    misquoted = tool_name == "Bash" and LAUNCHER in (tool_input.get("command") or "")
    return ("deny-misquoted" if misquoted else "deny",
            {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                    "permissionDecision": "deny",
                                    "permissionDecisionReason":
                                        reason(MISQUOTED if misquoted else DENIAL, tokens)}})


def reason(template, tokens):
    # [LAW:one-source-of-truth] the denial names the permitted git subcommands, and
    # names them by reading the set that decides them - a hand-kept second list would
    # be a promise to the agent that the gate is free to stop keeping. Templates that
    # do not mention a field simply ignore it.
    return template.format(tokens=tokens, ceiling=CEILING,
                           git="/".join(sorted(GIT_SUBCOMMANDS)),
                           launcher=shlex.quote(LAUNCHER))


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
