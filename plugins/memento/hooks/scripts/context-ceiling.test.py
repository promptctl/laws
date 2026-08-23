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


def run(records, stop_hook_active=False, ceiling=None, hook=HOOK):
    """Invoke the hook as Claude Code does. Returns (exit code, parsed stdout, stderr)."""
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    handle.write("".join(json.dumps(r) + "\n" for r in records))
    handle.close()
    env = {k: v for k, v in os.environ.items() if k != "MEMENTO_CONTEXT_CEILING"}
    if ceiling:
        env["MEMENTO_CONTEXT_CEILING"] = ceiling
    try:
        done = subprocess.run([sys.executable, hook], text=True, capture_output=True, env=env,
                              input=json.dumps({"session_id": "s-1", "hook_event_name": "Stop",
                                                "transcript_path": handle.name,
                                                "stop_hook_active": stop_hook_active}))
    finally:
        os.unlink(handle.name)
    return done.returncode, json.loads(done.stdout) if done.stdout.strip() else None, done.stderr


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

code, out, err = run([user], ceiling="lots")
check("an unparseable ceiling fails loudly", code == 1 and "lots" in err, f"{code} {err}")

done = subprocess.run([sys.executable, HOOK], input="{}", text=True, capture_output=True)
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
check("the hook is registered on Stop, and only there", list(registered) == ["Stop"], str(registered))
# Registering the event is half the wiring; pointing it at this script is the other half,
# and a move that updates one without the other would otherwise pass silently.
command = registered["Stop"][0]["hooks"][0]["command"]
check("the registered command runs this script, from the plugin root",
      os.path.basename(HOOK) in command and "${CLAUDE_PLUGIN_ROOT}" in command, command)
check("the hook is executable", os.access(HOOK, os.X_OK), HOOK)

print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
