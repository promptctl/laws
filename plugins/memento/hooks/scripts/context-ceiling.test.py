#!/usr/bin/env python3
"""Unit tests for the context-ceiling hook.

Each case feeds a synthetic transcript and the payload Claude Code actually delivers, to
the hook as a subprocess, and asserts the JSON it emits. [LAW:behavior-not-structure] it is
driven the way the harness drives it, so a rewrite of the internals cannot break these.

Run: python3 context-ceiling.test.py
"""

import atexit
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# One scratch root for every mkdtemp() below, removed on exit - each call still gets its own
# subdirectory, but the suite no longer abandons one per case in the system temp dir.
SCRATCH = tempfile.mkdtemp(prefix="context-ceiling-test-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)


def scratch_dir():
    return tempfile.mkdtemp(dir=SCRATCH)


HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "context-ceiling.py")
LAUNCHER = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                        "skills", "message-in-a-bottle", "bin", "finalize-session")
# [LAW:one-source-of-truth] every case drives the threshold explicitly, so the shipped
# default lives in the hook alone and retuning it cannot break these. A fixture magnitude,
# not a second copy of that number.
TEST_CEILING = 100_000
OVER, UNDER = TEST_CEILING + 20_000, TEST_CEILING - 60_000
failures = []


def check(name, condition, detail=""):
    print(f"ok   - {name}" if condition else f"FAIL - {name}: {detail}")
    if not condition:
        failures.append(name)


def assistant(tokens, sidechain=False):
    return {"type": "assistant", "isSidechain": sidechain, "message": {"usage": {
        "input_tokens": 2, "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": tokens - 2, "output_tokens": 0}}}


def tool_use(name, tool_input, call_id="t-1", sidechain=False):
    return {"type": "assistant", "isSidechain": sidechain, "message": {"content": [
        {"type": "tool_use", "id": call_id, "name": name, "input": tool_input}]}}


def tool_result(call_id="t-1", is_error=False):
    block = {"type": "tool_result", "tool_use_id": call_id, "content": "out"}
    if is_error:
        block["is_error"] = True
    return {"type": "user", "isSidechain": False, "message": {"content": [block]}}


user = {"type": "user", "isSidechain": False, "message": {"content": "hi"}}


def run(records, event="Stop", tool_name=None, tool_input=None, stop_hook_active=False,
        ceiling=TEST_CEILING, hook=HOOK, ceiling_file=None, log_seed="", extra_env=None):
    """Invoke the hook as Claude Code does. Returns (exit code, parsed stdout, stderr).

    ceiling=None leaves MEMENTO_CONTEXT_CEILING unset, which is how a case reaches the file
    or the shipped default."""
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    handle.write("".join(json.dumps(r) + "\n" for r in records))
    handle.close()
    log = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
    log.write(log_seed)
    log.close()
    env = {k: v for k, v in os.environ.items() if k != "MEMENTO_CONTEXT_CEILING"}
    env["MEMENTO_CEILING_LOG"] = log.name
    # Never the real ~/.claude file: a developer's own ceiling must not decide a test.
    env["MEMENTO_CEILING_FILE"] = ceiling_file or os.path.join(scratch_dir(), "absent")
    if ceiling is not None:
        env["MEMENTO_CONTEXT_CEILING"] = str(ceiling)
    env.update(extra_env or {})
    payload = {"session_id": "s-1", "hook_event_name": event,
               "transcript_path": handle.name, "stop_hook_active": stop_hook_active}
    if tool_name is not None:
        payload["tool_name"] = tool_name
        payload["tool_input"] = tool_input or {}
    try:
        done = subprocess.run([sys.executable, hook], text=True, capture_output=True,
                              env=env, input=json.dumps(payload))
    finally:
        os.unlink(handle.name)
    out = json.loads(done.stdout) if done.stdout.strip() else None
    run.log = open(log.name).read()
    os.unlink(log.name)
    return done.returncode, out, done.stderr


def bash(command, records=None, **kw):
    """A PreToolUse decision on one Bash command above the ceiling."""
    return run(records or [user, assistant(OVER)], event="PreToolUse",
               tool_name="Bash", tool_input={"command": command}, **kw)


def denied(out):
    return (out or {}).get("hookSpecificOutput", {}).get("permissionDecision") == "deny"


# --- Stop -------------------------------------------------------------------------------

code, out, _ = run([user, assistant(UNDER)])
check("under the ceiling, the stop is allowed", code == 0 and out is None, f"{code} {out}")

code, out, _ = run([user, assistant(OVER)])
check("over the ceiling, the stop is blocked", out and out.get("decision") == "block", f"{code} {out}")
check("the reason names the launcher, the count and the ceiling",
      out and LAUNCHER in out["reason"] and f"{OVER:,}" in out["reason"]
      and f"{TEST_CEILING:,}" in out["reason"], str(out))

code, out, _ = run([user, assistant(OVER)], stop_hook_active=True)
check("a stop already blocked once is not blocked again",
      code == 0 and out and "decision" not in out, f"{code} {out}")
check("giving up is loud rather than silent",
      out and "context ceiling breached" in out.get("systemMessage", ""), str(out))
check("giving up does not claim the close-out failed",
      out and "If the close-out did not run" in out.get("systemMessage", "")
      and "was NOT closed out" not in out.get("systemMessage", ""), str(out))

ran_closeout = [user, assistant(OVER),
                tool_use("Bash", {"command": f"{LAUNCHER} 'bye'"}), tool_result()]
code, out, _ = run(ran_closeout)
check("a stop right after the close-out ran is allowed",
      code == 0 and out and "decision" not in out
      and "the close-out ran" in out.get("systemMessage", ""), str(out))
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": f"{LAUNCHER} 'bye'"}),
                    tool_result(is_error=True)])
check("a close-out that was refused does not count as having run",
      out and out.get("decision") == "block", str(out))
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": "git status"}), tool_result()])
check("a permitted call that is not the launcher does not count as the close-out",
      out and out.get("decision") == "block", str(out))
# finalize-session's own contract allows backticks/$ outside the ceiling's single-quote-only
# rule; a real, successful close-out invoked that way must still be credited at Stop.
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": f'{LAUNCHER} "See `git rev-parse HEAD`"'}),
                    tool_result()])
check("a close-out statements() cannot parse is still credited if it ran",
      code == 0 and out and "decision" not in out
      and "the close-out ran" in out.get("systemMessage", ""), str(out))
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": f"{LAUNCHER} 'bye'"}, call_id="a"),
                    tool_result("a"),
                    tool_use("Bash", {"command": "git push"}, call_id="b"),
                    tool_result("b")])
check("a confirming git call after the close-out does not undo it",
      code == 0 and out and "decision" not in out
      and "the close-out ran" in out.get("systemMessage", ""), str(out))
# The tmux transport compacts in place, so the transcript keeps growing past a close-out.
# Crediting that one forever would wave through every later breach in the same file.
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": f"{LAUNCHER} 'bye'"}), tool_result(),
                    user, assistant(OVER)])
check("a close-out from an earlier turn does not excuse a later breach",
      out and out.get("decision") == "block", str(out))

# --- PreToolUse: what the close-out is allowed to do -------------------------------------

code, out, _ = run([user, assistant(UNDER)], event="PreToolUse",
                   tool_name="Bash", tool_input={"command": "rm -rf /"})
check("under the ceiling, PreToolUse permits anything", code == 0 and out is None, f"{code} {out}")

_, out, _ = bash(f"{LAUNCHER} 'a message with an apostrophe: it'\\''s fine'")
check("the launcher itself is permitted", out is None, str(out))
_, out, _ = bash("git status")
check("git status is permitted", out is None, str(out))
_, out, _ = bash("git add -A && git commit -m 'wip' && git push")
check("the read-and-commit half of git is permitted, chained", out is None, str(out))
_, out, _ = bash("/usr/bin/git status")
check("a fully-qualified git is permitted", out is None, str(out))

_, out, _ = bash("git reset --hard")
check("the destructive half of git is denied", denied(out), str(out))
# Recorded, not hidden: arguments are not inspected, so the destructive forms of a
# permitted subcommand are permitted. Every rule tried against git's argument surface
# refused more real close-out work than it prevented.
for destructive in ("git push --force", "git push origin +main:main",
                    "git push origin :topic", "git commit --amend -m rewritten"):
    _, out, _ = bash(destructive)
    check(f"{destructive!r} is permitted, by decision", out is None, str(out))
for write in ("git diff --output=/tmp/pwned", "git diff -o/tmp/pwned",
             "git log --output=/tmp/pwned", "git show --output=/tmp/pwned"):
    _, out, _ = bash(write)
    check(f"{write!r} is denied: --output writes outside the repo", denied(out), str(out))
_, out, _ = bash("git diff --output-indicator-new=X")
check("an unrelated --output-* flag is denied too - over-refusal here is free", denied(out), str(out))
_, out, _ = bash("git commit -am 'staged and messaged'")
check("bundled short flags are permitted", out is None, str(out))
_, out, _ = bash("git commit -m '-1 experiment'")
check("a commit message beginning with a dash is permitted", out is None, str(out))
_, out, _ = bash("git -C /somewhere/else status")
check("a global option before the subcommand is permitted", out is None, str(out))
_, out, _ = bash("git --no-pager log")
check("--no-pager is permitted", out is None, str(out))
# The subcommand is read by position, so a denied one cannot be laundered by mentioning a
# permitted word among its arguments.
_, out, _ = bash("git branch -D status")
check("a denied subcommand is not laundered by a permitted word", denied(out), str(out))
_, out, _ = bash("git -c core.pager=less status")
check("git -c is denied: it can define an alias that runs anything", denied(out), str(out))
_, out, _ = bash("git branch -D topic")
check("git branch is denied", denied(out), str(out))
_, out, _ = bash("cat notes.md")
check("new work is denied", denied(out), str(out))
_, out, _ = run([user, assistant(OVER)], event="PreToolUse",
                tool_name="Read", tool_input={"file_path": "/etc/hosts"})
check("reads are denied - a tool that grows context cannot respect a context limit",
      denied(out), str(out))
_, out, _ = run([user, assistant(OVER)], event="PreToolUse",
                tool_name="SomeToolInventedTomorrow", tool_input={})
check("an unrecognised tool is denied by default", denied(out), str(out))
_, out, _ = run([user, assistant(OVER)], event="PreToolUse",
                tool_name="Skill", tool_input={"skill": "memento:message-in-a-bottle"})
check("the handoff skill is permitted", out is None, str(out))
_, out, _ = run([user, assistant(OVER)], event="PreToolUse",
                tool_name="Skill", tool_input={"skill": "laws:code"})
check("another skill is denied", denied(out), str(out))
_, out, _ = bash("")
check("an empty command is denied with no case of its own", denied(out), str(out))

reason = (out or {}).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
check("the denial names the permitted git subcommands from the set that decides them",
      "commit" in reason and "push" in reason and "reset" not in reason, reason)

# --- PreToolUse: the parser refuses what it cannot prove is plain -------------------------

_, out, _ = bash("git status |& rm -rf x")
check("an operator outside the enumerated set does not smuggle a second command",
      denied(out), str(out))
_, out, _ = bash("git status\nrm -rf x")
check("a bare newline does not smuggle a second command", denied(out), str(out))
_, out, _ = bash("git status\ngit diff")
check("a bare newline separates statements rather than refusing them", out is None, str(out))
_, out, _ = bash(f'{LAUNCHER} "$(rm -rf x)"')
check("command substitution inside double quotes is refused", denied(out), str(out))
_, out, _ = bash(f"{LAUNCHER} `rm -rf x`")
check("backticks are refused", denied(out), str(out))
_, out, _ = bash(f"echo hi; {LAUNCHER} 'bye'")
check("a permitted segment does not launder an unpermitted one", denied(out), str(out))
_, out, _ = bash(f"cat {LAUNCHER}")
check("merely mentioning the launcher is not running it", denied(out), str(out))
decoy = os.path.join(scratch_dir(), "finalize-session")
open(decoy, "w").close()
os.chmod(decoy, 0o755)
_, out, _ = bash(f"{decoy} 'bye'")
check("an impostor named finalize-session is not the close-out", denied(out), str(out))
_, out, _ = run([user, assistant(OVER), tool_use("Bash", {"command": f"{decoy} 'bye'"}),
                 tool_result()])
check("an impostor close-out does not satisfy the stop either",
      out and out.get("decision") == "block", str(out))
# On the record: git is matched by name because many real files are git, so a planted one
# passes. This gate bounds a session that would talk itself into continuing, not one
# trying to escape - and planting the file needs a tool call, itself denied up here.
planted_git = os.path.join(scratch_dir(), "git")
open(planted_git, "w").close()
os.chmod(planted_git, 0o755)
_, out, _ = bash(f"{planted_git} status")
check("an executable named git is permitted, by name and by decision", out is None, str(out))

# The launcher's internal worker entry points take a pid to kill and a binary to run, and
# need no setup at all - one Bash call to the real file reaches them.
for internal in ("--worker tmux clear /tmp/m /tmp/g",
                 "--iterm-worker uuid 4242 /tmp/m /tmp/g flags",
                 "--detached-worker s /tmp . /tmp/m /tmp/g f 1 /bin/sh id"):
    _, out, _ = bash(f"{LAUNCHER} {internal}")
    check(f"the launcher's {internal.split()[0]} entry point is denied", denied(out), str(out))
_, out, _ = run([user, assistant(OVER),
                 tool_use("Bash", {"command": f"{LAUNCHER} --detached-worker s /tmp . /tmp/m /tmp/g f 1 /bin/sh id"}),
                 tool_result()])
check("an internal worker call is not credited as the close-out",
      out and out.get("decision") == "block", str(out))
# [LAW:one-source-of-truth] every worker flag the launcher itself dispatches on, read from
# its own `case "${1:-}"` block rather than re-asserted here - a future 4th entry point is
# denied by this loop with no line of this file to update, instead of silently reachable.
dispatch = open(LAUNCHER).read().split('case "${1:-}"', 1)[1].split("esac", 1)[0]
for flag in re.findall(r'^\s*(--[\w-]+)\)', dispatch, re.MULTILINE):
    _, out, _ = bash(f"{LAUNCHER} {flag}")
    check(f"the launcher's {flag} entry point is denied", denied(out), str(out))
_, out, _ = bash(f"{LAUNCHER} --goal 'keep going' /next")
check("the documented --goal shape is permitted", out is None, str(out))
_, out, _ = bash(f"{LAUNCHER} --reset clear 'a handoff'")
check("the documented --reset shape is permitted", out is None, str(out))

# F5: the shell would find a bare name on PATH, so the gate resolves it the same way before
# checking identity.
launcher_dir = os.path.dirname(LAUNCHER)
_, out, _ = bash("finalize-session 'bye'", extra_env={"PATH": launcher_dir + os.pathsep
                                                      + os.environ.get("PATH", "")})
check("the launcher invoked by bare name on PATH is permitted", out is None, str(out))
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": "finalize-session 'bye'"}), tool_result()],
                   extra_env={"PATH": launcher_dir + os.pathsep + os.environ.get("PATH", "")})
check("a bare-name close-out is credited at the stop",
      code == 0 and out and "decision" not in out
      and "the close-out ran" in out.get("systemMessage", ""), str(out))
_, out, _ = bash("finalize-session 'bye'", extra_env={"PATH": os.path.dirname(decoy)})
check("a bare name resolving to an impostor is still not the launcher", denied(out), str(out))

_, out, _ = bash(f"{LAUNCHER} \"$(cat <<'EOF'\nbye\nEOF\n)\"")
reason = (out or {}).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
check("a misquoted close-out gets the rewrite message, not the denial",
      denied(out) and "this IS the close-out" in reason, reason[:160])
_, out, _ = bash("cat $(ls)")
reason = (out or {}).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
check("unparseable new work gets the denial, not the rewrite message",
      denied(out) and "this IS the close-out" not in reason, reason[:160])

# --- the ceiling is configurable while sessions run --------------------------------------

written = tempfile.NamedTemporaryFile("w", suffix=".ceiling", delete=False)
written.write("50000\n")
written.close()
_, out, _ = run([user, assistant(60_000)], ceiling=None, ceiling_file=written.name)
check("the ceiling file is honoured when the environment is silent",
      out and out.get("decision") == "block" and "50,000" in out["reason"], str(out))
_, out, _ = run([user, assistant(60_000)], ceiling="", ceiling_file=written.name)
check("an exported-empty override is silence, not a value, and falls through to the file",
      out and out.get("decision") == "block" and "50,000" in out["reason"], str(out))
code, out, _ = run([user, assistant(60_000)], ceiling=200_000, ceiling_file=written.name)
check("the environment outranks the file", code == 0 and out is None, f"{code} {out}")

for word in ("off", "NONE", "never", "disabled"):
    open(written.name, "w").write(word + "\n")
    code, out, _ = run([user, assistant(5_000_000)], ceiling=None, ceiling_file=written.name)
    check(f"the gate can be switched off by writing {word!r}",
          code == 0 and out is None, f"{code} {out}")

open(written.name, "w").write("350k\n")
code, out, err = run([user, assistant(OVER)], ceiling=None, ceiling_file=written.name)
check("a ceiling that does not parse fails loudly and names where to fix it",
      code == 1 and "350k" in err and written.name in err, f"{code} {err}")
os.unlink(written.name)

code, out, err = run([user], ceiling="lots")
check("an unparseable override fails loudly", code == 1 and "lots" in err, f"{code} {err}")

# The shipped default, bracketed rather than named: a trivial session passes and one larger
# than any context window is caught, whatever the number happens to be.
code, out, _ = run([user, assistant(1_000)], ceiling=None)
check("with no override, a small session is allowed", code == 0 and out is None, f"{code} {out}")
_, out, _ = run([user, assistant(2_000_000)], ceiling=None)
check("with no override, a session past any window is blocked",
      out and out.get("decision") == "block", str(out))

# --- measuring the session ----------------------------------------------------------------

_, out, _ = run([user, {"type": "assistant", "isSidechain": False, "message": {"usage": {
    "input_tokens": 1_000, "cache_creation_input_tokens": 20_000,
    "cache_read_input_tokens": 70_000, "output_tokens": 12_000}}}])
check("the count sums input, cache write, cache read and output",
      out and "103,000" in out["reason"], str(out))

_, out, _ = run([user, assistant(OVER), assistant(20_000, sidechain=True)])
check("a trailing subagent record does not mask the session's count",
      out and out.get("decision") == "block", str(out))
code, out, _ = run([user, assistant(UNDER), assistant(900_000, sidechain=True)])
check("a subagent's context does not count against the session", code == 0 and out is None, str(out))
code, out, _ = run([user, assistant(OVER),
                    tool_use("Bash", {"command": f"{LAUNCHER} 'bye'"}, sidechain=True),
                    tool_result()])
check("a subagent running the launcher is not this session's close-out",
      out and out.get("decision") == "block", str(out))

code, out, _ = run([user, assistant(OVER), user, assistant(UNDER)])
check("a compacted session reads as its post-compaction size", code == 0 and out is None, str(out))

padding = [user] * 4000
code, out, _ = run(padding + [assistant(OVER)])
check("the newest record is found in a transcript spanning several chunks",
      out and out.get("decision") == "block", str(out))
# Wider than one backward read, so it is read whole only if the partial head is carried.
wide = assistant(OVER)
wide["pad"] = "x" * (400 * 1024)
code, out, _ = run(padding + [wide])
check("a record straddling a chunk boundary is still read whole",
      out and out.get("decision") == "block", str(out))
code, out, _ = run([assistant(OVER)] + padding + [user, assistant(UNDER)])
check("an older record beyond the first chunk does not override the newest",
      code == 0 and out is None, str(out))

code, out, _ = run([user, assistant(TEST_CEILING)])
check("a session at exactly the ceiling is over it, not under",
      out and out.get("decision") == "block", str(out))
code, out, _ = run([user, assistant(TEST_CEILING - 1)])
check("a session one token below the ceiling is under it", code == 0 and out is None, str(out))

code, out, _ = run([user], ceiling=1)
check("a transcript with no assistant record reads as zero", code == 0 and out is None, str(out))

# --- the log is the only place "allowed" and "never ran" differ ---------------------------

run([user, assistant(UNDER)])
check("an allowed call is logged too", "allow-under" in run.log, run.log)
run([user, assistant(OVER)])
check("a block is logged", "-> block" in run.log, run.log)
bash("cat notes.md")
check("a denial is logged with the tool that was refused",
      "-> deny" in run.log and "tool=Bash" in run.log, run.log)
bash(f"{LAUNCHER} \"$(echo hi)\"")
check("a misquoted close-out is logged apart from a plain denial",
      "-> deny-misquoted" in run.log, run.log)
run([user, assistant(UNDER)], log_seed="old\n" * 600_000)
check("the log is truncated once it passes its cap",
      "[truncated at" in run.log and len(run.log) < 2_000_000, str(len(run.log)))

# --- wiring --------------------------------------------------------------------------------

isolated = {k: v for k, v in os.environ.items() if k != "MEMENTO_CONTEXT_CEILING"}
isolated["MEMENTO_CEILING_FILE"] = os.path.join(scratch_dir(), "absent")
isolated["MEMENTO_CEILING_LOG"] = os.path.join(scratch_dir(), "log")
done = subprocess.run([sys.executable, HOOK], input="{}", text=True, capture_output=True,
                      env=isolated)
check("a payload with no event fails loudly",
      done.returncode == 1 and "hook_event_name" in done.stderr, str(done)[:200])

# A plugin root can contain a space (~/Library/Application Support/...), and unquoted the
# only exit from the block fails to execute.
spaced_root = os.path.join(scratch_dir(), "ceiling test")
spaced_hook = os.path.join(spaced_root, "hooks", "scripts", os.path.basename(HOOK))
os.makedirs(os.path.dirname(spaced_hook))
shutil.copy(HOOK, spaced_hook)
spaced_launcher = os.path.join(spaced_root, "skills", "message-in-a-bottle",
                               "bin", "finalize-session")
try:
    _, out, _ = run([user, assistant(OVER)], hook=spaced_hook)
    check("a launcher path containing a space is quoted in the instruction",
          out and f"'{spaced_launcher}'" in out["reason"], str(out)[:200])
finally:
    shutil.rmtree(os.path.dirname(spaced_root))

check("the launcher the hook points at exists", os.access(LAUNCHER, os.X_OK), LAUNCHER)
registered = json.load(open(os.path.join(os.path.dirname(HERE), "hooks.json")))["hooks"]
check("the hook is registered on both events, and only those",
      sorted(registered) == ["PreToolUse", "Stop"], str(sorted(registered)))
for event in ("Stop", "PreToolUse"):
    command = registered[event][0]["hooks"][0]["command"]
    check(f"the {event} registration runs this script, from the plugin root",
          os.path.basename(HOOK) in command and "${CLAUDE_PLUGIN_ROOT}" in command, command)
check("the hook is executable", os.access(HOOK, os.X_OK), HOOK)

print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
