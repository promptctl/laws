#!/usr/bin/env python3
"""Tests for finalize-session's tmux pane discovery.

These drive the launcher exactly as an agent does - argv in, `--dry-run` report
out - and assert which transport and which pane it selected.
[LAW:behavior-not-structure] nothing here reaches inside _discover_tmux_pane, so
the walk can be rewritten freely as long as the pane it picks stays right.

The process tree is REAL. `nest` builds a chain of genuine processes above the
launcher, so the walk runs against the real ps, real pids, and real elapsed
times; a synthetic process table would only test the parser against this file's
own fiction, and could not notice `ps -eo` failing on some platform. tmux is the
one fixture, because a pane's dead-but-still-listed state cannot be conjured on
demand, and the forging ps in the pid-reuse case wraps the real one rather than
replacing it.

Run: python3 finalize-session.test.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.join(HERE, "finalize-session")
REAL_DIRS = "/usr/bin:/bin:/usr/sbin:/sbin"
failures = []


def check(name, condition, detail=""):
    print(f"ok   - {name}" if condition else f"FAIL - {name}: {detail}")
    if not condition:
        failures.append(name)


# --- fixtures -------------------------------------------------------------
# A pane record is `id pid dead`. ROOTPID in the pid column stands for the pid
# `nest` published: the process at the top of the chain, and therefore a genuine
# ancestor of the launcher.

TMUX = r"""#!/bin/bash
# Fixture tmux. $FIXTURE_PANES holds one `id pid dead` record per line - panes as
# data - and list-panes EXPANDS whatever -F format it is handed, the way real
# tmux does, so these tests do not care which fields the launcher asks for. An
# unexpanded #{...} left over means the launcher asked for something this fixture
# cannot answer; that exits loudly rather than handing back a line the launcher
# would parse into a plausible wrong pane.
# $FIXTURE_PANES unset stands for no server, which real tmux reports by exiting 1.
# display-message echoes a target naming the pane it was asked about, so an
# assertion can see which pane won.
set -uo pipefail
case "${1:-}" in
  list-panes)
    [ -n "${FIXTURE_PANES+set}" ] || { echo "no server running" >&2; exit 1; }
    [ -n "$FIXTURE_PANES" ] || exit 0
    fmt=""
    while [ $# -gt 0 ]; do
      case "$1" in -F) fmt="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    [ -n "$fmt" ] || { echo "fixture tmux: list-panes without -F" >&2; exit 2; }
    root=$(cat "$FIXTURE_ROOT_PID")
    while read -r id pid dead; do
      [ -n "$id" ] || continue
      line="${fmt//\#\{pane_id\}/$id}"
      line="${line//\#\{pane_pid\}/${pid//ROOTPID/$root}}"
      line="${line//\#\{pane_dead\}/$dead}"
      case "$line" in
        *'#{'*) echo "fixture tmux: cannot expand '$fmt'" >&2; exit 2 ;;
      esac
      printf '%s\n' "$line"
    done <<< "$FIXTURE_PANES"
    ;;
  display-message)
    pane=""
    while [ $# -gt 0 ]; do
      case "$1" in -t) pane="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    [ -n "$pane" ] || exit 1
    printf '%s\n' "target-for-$pane"
    ;;
  *) echo "fixture tmux: unexpected subcommand ${1:-}" >&2; exit 2 ;;
esac
"""

NEST = r"""#!/bin/bash
# nest DEPTH CMD... - put DEPTH+1 real processes above CMD, so CMD sits at
# ancestry distance DEPTH+1 from the first one. That first process publishes its
# pid to $NEST_PUBLISH_PID; the pane fixtures are written against it.
set -uo pipefail
depth="$1"; shift
if [ -n "${NEST_PUBLISH_PID:-}" ]; then
  printf '%s' "$$" > "$NEST_PUBLISH_PID"
  unset NEST_PUBLISH_PID
fi
if [ "$depth" -gt 0 ]; then
  if [ "${NEST_REHOST_AT:-}" = "$depth" ]; then
    unset NEST_REHOST_AT
    claude daemon run --bg-pty-host -- "$0" $((depth - 1)) "$@"
    exit $?
  fi
  "$0" $((depth - 1)) "$@"
  exit $?
fi
# $NEST_SLEEP holds the bottom of the chain still long enough that ps reports a
# non-zero elapsed time for it. Without that the whole chain is born inside one
# second, every age reads 00:00, and no forged age can be younger than its own
# descendant - so the age check would have nothing to catch.
[ -n "${NEST_SLEEP:-}" ] && sleep "$NEST_SLEEP"
"$@"
exit $?
"""

CLAUDE = r"""#!/bin/bash
# Stands in for `claude daemon run --bg-pty-host`: the re-hosting hop this whole
# mechanism exists for. The session is spawned by the daemon rather than by the
# pane's shell, so it inherits none of tmux's environment - stripped here for
# real, not simulated.
set -uo pipefail
while [ "${1:-}" != "--" ]; do
  [ $# -gt 0 ] || { echo "claude shim: no -- separator" >&2; exit 2; }
  shift
done
shift
env -u TMUX -u TMUX_PANE "$@"
exit $?
"""

PS_FORGING = r"""#!/bin/bash
# The real process table with one ancestor's elapsed time forged young - the
# signature a recycled pid leaves, and the one thing no live machine will
# produce on cue.
#
# Only the whole-table form is forged. A per-pid query carries no pid column to
# key on, so rewriting its fields would corrupt the launcher's answer instead of
# forging an age - and a fixture that breaks the subject reports a pass it did
# not earn. Anything else passes straight through.
set -uo pipefail
out=$(/bin/ps "$@") || exit $?
case "${1:-}" in
  -e*) printf '%s\n' "$out" \
         | /usr/bin/awk -v forge="$(cat "$FIXTURE_ROOT_PID")" \
             '$1 == forge { $3 = "00:00" } { print }' ;;
  *)   printf '%s\n' "$out" ;;
esac
"""


def install(directory, name, body):
    path = os.path.join(directory, name)
    with open(path, "w") as handle:
        handle.write(body)
    os.chmod(path, 0o755)
    return path


FIXTURES = tempfile.mkdtemp(prefix="finalize-fixtures.")
install(FIXTURES, "tmux", TMUX)
install(FIXTURES, "claude", CLAUDE)
NEST_BIN = install(FIXTURES, "nest", NEST)
FORGE_DIR = os.path.join(FIXTURES, "forge")
os.mkdir(FORGE_DIR)
install(FORGE_DIR, "ps", PS_FORGING)


def run(depth=1, panes="%99 ROOTPID 0", tmux_on_path=True, forge=False,
        rehost_at=None, tmux_pane=None, sleep=None):
    """Launch finalize-session under a real `nest` chain and return its dry-run report."""
    workdir = tempfile.mkdtemp(prefix="finalize-case.")
    pidfile = os.path.join(workdir, "root.pid")
    path = [FIXTURES] if tmux_on_path else []
    if forge:
        path.insert(0, FORGE_DIR)
    env = {
        "PATH": ":".join(path + [REAL_DIRS]),
        "HOME": os.environ.get("HOME", workdir),
        "TMPDIR": workdir,
        "FINALIZE_DRY_RUN": "1",
        "NEST_PUBLISH_PID": pidfile,
        "FIXTURE_ROOT_PID": pidfile,
    }
    if panes is not None:
        env["FIXTURE_PANES"] = panes
    if rehost_at is not None:
        env["NEST_REHOST_AT"] = str(rehost_at)
    if tmux_pane is not None:
        env["TMUX_PANE"] = tmux_pane
    if sleep is not None:
        env["NEST_SLEEP"] = str(sleep)
    try:
        return subprocess.run([NEST_BIN, str(depth), LAUNCHER, "handoff"],
                              text=True, capture_output=True, env=env, timeout=120)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


DECLINED = "declined"
NO_TRANSPORT_RC = 2  # the launcher's own code for "no transport to deliver into"


def picked(done):
    """The pane id the launcher resolved to, or DECLINED when it found no
    transport and said so with the no-transport exit code.

    [LAW:parse-dont-validate] returning a bare None for the second case would be
    an answer-shaped void: a launcher that deliberately declined and one that
    crashed on its way to an answer would read identically, and every negative
    case below would pass on either. So the exit code is read here, once, and a
    run that is neither a pane nor a clean decline comes back as its own report -
    a value no assertion matches, carrying the evidence into the failure message.
    """
    for line in done.stdout.splitlines():
        if line.startswith("[dry-run] transport=tmux target=target-for-"):
            return line.split("target-for-", 1)[1].split(" ", 1)[0]
    if done.returncode == NO_TRANSPORT_RC:
        return DECLINED
    return f"<no decision: rc={done.returncode} out={done.stdout!r} err={done.stderr!r}>"


# --- preconditions --------------------------------------------------------
# [LAW:verifiable-goals] a suite that silently tested the wrong binary, or found
# a real tmux where it meant to find none, would pass while proving nothing.

check("the launcher under test exists and is executable", os.access(LAUNCHER, os.X_OK), LAUNCHER)
check("no real tmux leaks in through the bare PATH",
      shutil.which("tmux", path=REAL_DIRS) is None,
      "a tmux in /usr/bin or /bin would answer the fixture's cases")

# --- resolution through a real ancestry -----------------------------------

for depth in (0, 1, 5):
    done = run(depth=depth)
    check(f"resolves the pane {depth + 1} process(es) up",
          picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# The walk examines this process and 15 ancestors; `nest DEPTH` puts the
# published pid at distance DEPTH+1. These two pin that bound from both sides.
done = run(depth=14)
check("resolves a pane at the last hop inside the 16-hop bound",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

done = run(depth=15)
check("refuses a pane one hop beyond the 16-hop bound", picked(done) == DECLINED, picked(done))

done = run(depth=3, panes="%1 4 0\n%99 ROOTPID 0\n%7 5 0")
check("picks the pane that owns it, not the first pane listed",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r}")

# The case the whole mechanism exists for: a hop that re-hosts the session off
# the pane's shell, taking $TMUX and $TMUX_PANE with it.
done = run(depth=5, rehost_at=3)
check("resolves through a `claude daemon run --bg-pty-host` re-hosting hop",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# --- no pane to be had ----------------------------------------------------

done = run(panes=None)
check("no tmux server: selects no transport", picked(done) == DECLINED, picked(done))
# [LAW:single-enforcer] the exit code is the whole of the no-transport report, so
# it is pinned once, here, as its own contract. Every other decline below asserts
# DECLINED, which already carries it - re-asserting the code beside each one
# would be the same invariant enforced in six places, drifting apart on the day
# the code changes.
check("declining is reported by exit code, not by prose alone",
      done.returncode == NO_TRANSPORT_RC, f"rc={done.returncode}")

done = run(panes="")
check("a server with no panes selects no transport", picked(done) == DECLINED, picked(done))

done = run(tmux_on_path=False)
check("tmux absent from PATH: selects no transport", picked(done) == DECLINED, picked(done))

done = run(depth=2, panes="%5 1 0")
check("a pane owned by someone else is not claimed", picked(done) == DECLINED, picked(done))

# --- the two forgeries a bare pid match cannot see -------------------------

done = run(depth=2, panes="%99 ROOTPID 1")
check("a dead pane still advertising an ancestor's pid is refused",
      picked(done) == DECLINED, picked(done))

done = run(depth=2, panes="%99 ROOTPID 1\n%98 ROOTPID 0")
check("a live pane is still found past a dead one holding the same pid",
      picked(done) == "%98", f"rc={done.returncode} out={done.stdout!r}")

done = run(depth=2, sleep=2, forge=True)
check("an ancestor younger than its own descendant is refused as a recycled pid",
      picked(done) == DECLINED, picked(done))
check("the same aged chain resolves once the elapsed time is not forged",
      picked(run(depth=2, sleep=2)) == "%99",
      "without this the forging fixture, not the age check, could be doing the work")

# --- precedence -----------------------------------------------------------

done = run(depth=2, panes="%5 1 0", tmux_pane="%42")
check("an inherited $TMUX_PANE wins outright and discovery never runs",
      picked(done) == "%42", f"rc={done.returncode} out={done.stdout!r}")

shutil.rmtree(FIXTURES, ignore_errors=True)
print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
