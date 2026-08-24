#!/usr/bin/env python3
"""Unit tests for the context-ceiling hook.

Each case feeds a synthetic transcript and the Stop payload Claude Code actually
delivers to the hook as a subprocess, and asserts the JSON it emits.
[LAW:behavior-not-structure] it is driven the way the harness drives it, so a
rewrite of the internals cannot break these.

Run: python3 context-ceiling.test.py
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "context-ceiling.py")
LAUNCHER = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                        "skills", "message-in-a-bottle", "bin", "finalize-session")
failures = []


def check(name, condition, detail=""):
    print(f"ok   - {name}" if condition else f"FAIL - {name}: {detail}")
    if not condition:
        failures.append(name)


def assistant(tokens, sidechain=False):
    return {"type": "assistant", "isSidechain": sidechain, "message": {"usage": {
        "input_tokens": 2, "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": tokens - 2, "output_tokens": 0}}}


def run(records, stop_hook_active=False, ceiling=None, hook=HOOK,
        event="stop", tool_name=None, tool_input=None, argv=()):
    """Invoke the hook as Claude Code does. Returns (exit code, parsed stdout, stderr)."""
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    handle.write("".join(json.dumps(r) + "\n" for r in records))
    handle.close()
    env = {k: v for k, v in os.environ.items() if k != "MEMENTO_CONTEXT_CEILING"}
    if ceiling:
        env["MEMENTO_CONTEXT_CEILING"] = ceiling
    payload = {"session_id": "s-1", "transcript_path": handle.name,
               "hook_event_name": "Stop" if event == "stop" else "PreToolUse",
               "stop_hook_active": stop_hook_active}
    if tool_name is not None:
        payload["tool_name"] = tool_name
        payload["tool_input"] = tool_input or {}
    try:
        # No argv: the event is read from the payload, and every registration spelling
        # still on disk - bare, or carrying one of three historical verbs - reaches the
        # same handler. `argv` exists so those spellings can be exercised below.
        done = subprocess.run([sys.executable, hook] + list(argv), text=True,
                              capture_output=True, env=env, input=json.dumps(payload))
    finally:
        os.unlink(handle.name)
    return done.returncode, json.loads(done.stdout) if done.stdout.strip() else None, done.stderr


def denies(tool_name, tool_input=None, tokens=360_000):
    """Whether PreToolUse refuses this call at the given context size."""
    _, out, err = run([user, assistant(tokens)], event="pretool",
                      tool_name=tool_name, tool_input=tool_input)
    if err.strip():
        raise AssertionError(err)
    if out is None:
        return False
    return out["hookSpecificOutput"]["permissionDecision"] == "deny"


def launcher_argv(reason):
    """The close-out command line from the block reason, tokenized the way the shell
    the agent pastes it into will tokenize it.

    Anchored on the launcher's own filename rather than a line offset, so rewording
    the instruction cannot quietly move what these assertions cover. Returns None
    when no line parses into an invocation of the launcher - which is what a path
    that lost its quoting looks like from here."""
    for line in reason.splitlines():
        try:
            argv = shlex.split(line)
        except ValueError:
            continue  # an unbalanced quote, which is itself a failure to parse
        if argv and os.path.basename(argv[0]) == "finalize-session":
            return argv
    return None


user = {"type": "user", "isSidechain": False, "message": {"content": "hi"}}

code, out, _ = run([user, assistant(100_000)])
check("under the ceiling, the stop is allowed", code == 0 and out is None, f"{code} {out}")

code, out, _ = run([user, assistant(360_000)])
check("over the ceiling, the stop is blocked", out and out.get("decision") == "block", f"{code} {out}")
check("the reason names the launcher, the count and the ceiling",
      out and LAUNCHER in out["reason"] and "360,000" in out["reason"]
      and "350,000" in out["reason"], str(out))

# Every prompt component counts, so a cache read alone under the ceiling can still be over it.
_, out, _ = run([user, {"type": "assistant", "isSidechain": False, "message": {"usage": {
    "input_tokens": 1_000, "cache_creation_input_tokens": 40_000,
    "cache_read_input_tokens": 300_000, "output_tokens": 12_000}}}])
check("the count sums input, cache write, cache read and output",
      out and "353,000" in out["reason"], str(out))

# A subagent writes into the same transcript. Its record must neither mask a session
# that is over the ceiling nor push one over that is not.
_, out, _ = run([user, assistant(360_000), assistant(20_000, sidechain=True)])
check("a trailing subagent record does not mask the session's count",
      out and out.get("decision") == "block", str(out))
code, out, _ = run([user, assistant(90_000), assistant(900_000, sidechain=True)])
check("a subagent's context does not count against the session", code == 0 and out is None, str(out))

code, out, _ = run([user, assistant(360_000), user, assistant(40_000)])
check("a compacted session reads as its post-compaction size", code == 0 and out is None, str(out))

code, out, _ = run([user, assistant(360_000)], stop_hook_active=True)
check("a stop already blocked once is not blocked again",
      code == 0 and out and "decision" not in out, f"{code} {out}")
check("giving up is loud rather than silent",
      out and "context ceiling breached" in out.get("systemMessage", "")
      and "360,000" in out.get("systemMessage", ""), str(out))
# The compliant path - block, finalize, stop again - is exactly when stop_hook_active is
# true, so this message must not call a successful close-out a failure.
check("giving up does not claim the close-out failed",
      out and "If the close-out did not run" in out.get("systemMessage", "")
      and "was NOT closed out" not in out.get("systemMessage", ""), str(out))

code, out, _ = run([user], ceiling="1")
check("a transcript with no assistant record reads as zero", code == 0 and out is None, str(out))

_, out, _ = run([user, assistant(100_000)], ceiling="50000")
check("the ceiling override is honoured",
      out and out.get("decision") == "block" and "50,000" in out["reason"], str(out))

# --- PreToolUse: the gate an autonomous session cannot loop around -------------------
# A session that never ends a turn never reaches Stop. These cover the event that fires
# on every tool call instead, and the accept/reject table for what stays permitted.

check("under the ceiling PreToolUse permits new work",
      not denies("Write", {"file_path": "/tmp/x", "content": "y"}, tokens=100_000))

for tool, tool_input in (("Write", {"file_path": "/tmp/x", "content": "y"}),
                         ("Edit", {"file_path": "/tmp/x"}),
                         ("Task", {"prompt": "go build something"}),
                         ("WebFetch", {"url": "https://example.com"}),
                         ("SomeToolInventedNextRelease", {})):
    check(f"above the ceiling {tool} is denied", denies(tool, tool_input))

for tool in ("Read", "Grep", "Glob"):
    check(f"above the ceiling {tool} stays permitted - the handoff must not be written blind",
          not denies(tool, {"file_path": "/tmp/x", "pattern": "y"}))

check("above the ceiling the handoff contract may still be loaded",
      not denies("Skill", {"skill": "memento:message-in-a-bottle"}))
check("above the ceiling any other skill is denied - a new craft is new work",
      denies("Skill", {"skill": "laws:code"}))

check("above the ceiling git is permitted, so outstanding work can be committed",
      not denies("Bash", {"command": "git status"}))
check("a multi-part git command is permitted",
      not denies("Bash", {"command": "git add -A && git commit -m 'wip'"}))
check("the close-out itself is permitted",
      not denies("Bash", {"command": f"{shlex.quote(LAUNCHER)} '/next'"}))
check("above the ceiling an unrelated command is denied",
      denies("Bash", {"command": "npm run build"}))

# Regression, from the first live run of this gate. The handoff message is free prose
# and routinely contains shell separators; splitting on them by pattern cut the
# close-out in half and denied the one call that is the way out. Verbatim, minus the
# absolute path, from the permission_denials of that run.
check("a handoff message containing a semicolon is still the close-out",
      not denies("Bash", {"command": f"{shlex.quote(LAUNCHER)} --reset clear "
                                     "'Task DONE. No outstanding work and no next "
                                     "step; wait for the user instruction.'"}))
check("a handoff message containing pipes and ampersands is still the close-out",
      not denies("Bash", {"command": f"{shlex.quote(LAUNCHER)} "
                                     "'ran a | b and c && d; see notes'"}))
check("a handoff message containing backticks and dollars is still the close-out",
      not denies("Bash", {"command": f"{shlex.quote(LAUNCHER)} "
                                     "'fixed `$PATH` handling in the installer'"}))
# The launcher must be what the segment RUNS, not something it happens to quote.
check("merely naming the launcher inside an argument is not the close-out",
      denies("Bash", {"command": f"echo 'run {LAUNCHER} later' > /tmp/note"}))
check("an unbalanced quote is denied rather than crashing the gate",
      denies("Bash", {"command": "git commit -m 'unbalanced"}))
# Judging the command by its first segment would wave this through, and the second half
# is exactly the new work the ceiling exists to stop.
check("git chained to new work is denied, not waved through on its first segment",
      denies("Bash", {"command": "git commit -m 'wip' && npm run build"}))
check("an empty command is denied rather than reading as a permitted no-op",
      denies("Bash", {"command": "   "}))

_, out, _ = run([user, assistant(360_000)], event="pretool",
                tool_name="Write", tool_input={"file_path": "/tmp/x"})
# Read through the absent case rather than subscripting it, so a regression that stops
# denying reports as a failure here instead of a traceback that hides the other cases.
denial = (out or {}).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
check("the denial names the count, the ceiling and the launcher",
      "360,000" in denial and "350,000" in denial and LAUNCHER in denial, str(out))
# The agent must not report the denied call as done, nor burn the remaining context
# retrying it - both are how a ceiling breach turns into corrupted work.
check("the denial says the call did not run and must not be retried",
      "NOT run" in denial and "Do not retry" in denial, str(out))
check("the close-out line in the denial parses as one launcher invocation",
      launcher_argv(denial) == [LAUNCHER, "<handoff message>"], str(out))

# Regression, from a live session. The event used to be read from argv, so the three
# cached registrations that invoke this script bare - versions a session may still be
# running - crashed it with an IndexError on every turn. The payload names the event;
# requiring the registration to restate it is a second copy of that fact, and it drifted.
for spelling, argv in (("bare, as the cached Stop registrations invoke it", ()),
                       ("carrying the current argv", ("stop",)),
                       ("carrying an older verb", ("gate",))):
    code, out, err = run([user, assistant(360_000)], argv=argv)
    check(f"invoked {spelling}, the ceiling still blocks",
          code == 0 and out and out.get("decision") == "block", f"{code} {out} {err}")

# An event this script has no handler for is a wiring mistake, and must be loud rather
# than silently handled as whichever handler happened to be first.
done = subprocess.run([sys.executable, HOOK], text=True, capture_output=True,
                      input=json.dumps({"hook_event_name": "PreCompact",
                                        "transcript_path": "/nonexistent"}))
check("an unhandled event fails loudly", done.returncode == 1 and "PreCompact" in done.stderr,
      str(done))

code, out, err = run([user], ceiling="lots")
check("an unparseable ceiling fails loudly", code == 1 and "lots" in err, f"{code} {err}")

done = subprocess.run([sys.executable, HOOK], text=True, capture_output=True,
                      input=json.dumps({"hook_event_name": "Stop"}))
check("a payload with no transcript_path fails loudly",
      done.returncode == 1 and "transcript_path" in done.stderr, str(done))

_, out, _ = run([user, assistant(360_000)])
check("the close-out line parses as one launcher invocation",
      launcher_argv(out["reason"]) == [LAUNCHER, "<handoff message>"],
      str(launcher_argv(out["reason"])))

# The agent runs that line verbatim, and a plugin root can contain a space
# (~/Library/Application Support/...). Unquoted, the shell would split the path and the
# only exit from the block would fail to execute - so the hook is run from a spaced
# path here rather than trusted to be quoted.
spaced_root = os.path.join(tempfile.mkdtemp(), "ceiling test")
spaced_hook = os.path.join(spaced_root, "hooks", "scripts", os.path.basename(HOOK))
os.makedirs(os.path.dirname(spaced_hook))
shutil.copy(HOOK, spaced_hook)
spaced_launcher = os.path.join(spaced_root, "skills", "message-in-a-bottle",
                               "bin", "finalize-session")
try:
    _, out, _ = run([user, assistant(360_000)], hook=spaced_hook)
    check("a launcher path containing a space survives the shell",
          launcher_argv(out["reason"]) == [spaced_launcher, "<handoff message>"],
          str(launcher_argv(out["reason"])))
finally:
    shutil.rmtree(os.path.dirname(spaced_root))

# The hook derives the launcher path from its own location, so a move that breaks the
# layout has to fail here rather than in a live session's close-out.
check("the launcher the hook points at exists", os.access(LAUNCHER, os.X_OK), LAUNCHER)
registered = json.load(open(os.path.join(os.path.dirname(HERE), "hooks.json")))["hooks"]
# Stop alone is what let a 757-turn autonomous session reach 909k without the gate ever
# being consulted, so "registered on both" is the fix and this is the test that holds it.
check("the hook is registered on Stop and PreToolUse",
      sorted(registered) == ["PreToolUse", "Stop"], str(registered))
# PreToolUse with a matcher would police only some tools, and the tools left unpoliced
# are exactly where new work would continue.
check("PreToolUse is registered for every tool, not a matched subset",
      "matcher" not in registered["PreToolUse"][0], str(registered["PreToolUse"][0]))
# Registering the event is half the wiring; pointing it at this script is the other half,
# and a move that updates one without the other would otherwise pass silently.
for hook_event in ("Stop", "PreToolUse"):
    command = registered[hook_event][0]["hooks"][0]["command"]
    check(f"the {hook_event} command runs this script from the plugin root",
          os.path.basename(HOOK) in command and "${CLAUDE_PLUGIN_ROOT}" in command, command)
    # An argv here would read as the thing that selects the handler. It is not - the
    # payload is - and a registration that looks authoritative is how the two drifted.
    check(f"the {hook_event} command passes no event argv",
          command.rstrip().endswith('"'), command)
check("the hook is executable", os.access(HOOK, os.X_OK), HOOK)

print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
