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

That same real-process-tree honesty extends to the detached-transport cases:
every "no pane found" case now falls to the detached transport rather than
declining, because `_find_claude_pid` walks the REAL ancestry above this test
runner and finds whatever real `claude` process is actually running it. That is
realistic for how this suite is actually run (inside Claude Code), but it is a
genuine environmental coupling, not a fixture - a runner with no claude-named
ancestor at all would see those cases decline instead, for a true reason
(nothing to relaunch as) this suite does not separately distinguish from "no
transport at all."

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
    # Real tmux does NOT validate -t here: for a pane no server owns it exits 0
    # with every field empty, so the launcher's format renders as the bare ":."
    # - non-empty, and a live tmux address for the CURRENT pane at that. Modelling
    # this as a failure would be the comfortable lie; it is what let a stale
    # $TMUX_PANE retarget the handoff unnoticed. Known panes echo their id and a
    # target naming them, so an assertion can see which pane won.
    pane=""; fmt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) pane="${2:-}"; shift 2 ;;
        -p) shift ;;
        *)  fmt="$1"; shift ;;
      esac
    done
    # ':.' is not a pane id but a target expression meaning current-session:
    # current-window.current-pane, and tmux resolves it to a REAL pane - which is
    # why an unresolvable id rendering into ':.' was dangerous rather than merely
    # wrong. The first live record stands in for "current" here.
    known=""; pane_dead=""; resolved=""
    while read -r id pid dead; do
      [ -n "$id" ] || continue
      [ "$id" = "$pane" ] && { known=yes; pane_dead="$dead"; resolved="$id"; }
      [ "$pane" = ":." ] && [ "$dead" = 0 ] && [ -z "$resolved" ] \
        && { known=yes; pane_dead="$dead"; resolved="$id"; }
    done <<< "${FIXTURE_PANES:-}"
    pane="$resolved"
    if [ -n "$known" ]; then
      line="${fmt//\#\{pane_id\}/$pane}"
      line="${line//\#\{pane_dead\}/$pane_dead}"
      line="${line//\#\{session_name\}/target-for-$pane}"
      line="${line//\#\{window_index\}/0}"
      line="${line//\#\{pane_index\}/0}"
    else
      # Every field empty, exit 0 - tmux's actual answer for a pane it does not
      # own, and the reason ":." reaches the launcher looking like a target.
      line="${fmt//\#\{pane_id\}/}"
      line="${line//\#\{pane_dead\}/}"
      line="${line//\#\{session_name\}/}"
      line="${line//\#\{window_index\}/}"
      line="${line//\#\{pane_index\}/}"
    fi
    case "$line" in
      *'#{'*) echo "fixture tmux: cannot expand '$fmt'" >&2; exit 2 ;;
    esac
    printf '%s\n' "$line"
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
# The real process table with one ancestor's elapsed time rewritten to
# $FIXTURE_FORGE_AGE - a pid younger than the descendant claiming it is the
# signature of a recycled pid, and the one thing no live machine will produce on
# cue.
#
# The age is a parameter rather than a constant so the same wrapper can also
# forge an age that is OLDER, which the walk must still accept. That pairing is
# the control: both runs drive this identical rewrite of $3 for the identical
# pid and differ only in the value written, so a wrapper that mangled `ps -eo`
# into an unparseable table would fail the accepting run instead of quietly
# handing the refusing one a pass it did not earn. A control that skips this
# wrapper entirely - as the first version did - cannot see that failure mode at
# all, because it never runs the thing it is controlling for.
#
# Only the whole-table form is forged. A per-pid query carries no pid column to
# key on, so rewriting its fields would corrupt the launcher's answer instead of
# forging an age. Anything else passes straight through.
set -uo pipefail
out=$(/bin/ps "$@") || exit $?
case "${1:-}" in
  -e*) printf '%s\n' "$out" \
         | /usr/bin/awk -v forge="$(cat "$FIXTURE_ROOT_PID")" \
                        -v age="$FIXTURE_FORGE_AGE" \
             '$1 == forge { $3 = age } { print }' ;;
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

# A PATH holding everything the launcher needs and provably no tmux. The absence
# has to be BUILT, not observed: tmux lives in /usr/bin on every mainstream Linux
# package, so "the real directories happen to have no tmux" is a fact about this
# machine - true where Homebrew keeps tmux in /opt, false on the platforms whose
# `ps` the real process tree exists to exercise. Asserting it would fail the
# whole suite on a correct implementation.
#
# The hazard is confined to the tmux-absent case, which runs with FIXTURES off
# PATH. Everywhere else FIXTURES comes first and the fixture tmux shadows any
# real one, wherever the host keeps it.
# It mirrors REAL_DIRS entry for entry rather than listing what the launcher
# needs. A hand-kept list rots the moment the launcher grows a call, and it fails
# as rc 127 inside a case about something else - which is exactly what the first
# version of this did, having omitted `dirname` and `basename`. Subtracting one
# name from the real environment cannot drift that way.
NO_TMUX_BIN = os.path.join(FIXTURES, "notmux")
os.mkdir(NO_TMUX_BIN)
for directory in REAL_DIRS.split(":"):
    for entry in sorted(os.listdir(directory)):
        link = os.path.join(NO_TMUX_BIN, entry)
        # Skipping an existing link keeps REAL_DIRS' own precedence, the way a
        # PATH search would resolve it.
        if entry != "tmux" and not os.path.lexists(link):
            os.symlink(os.path.join(directory, entry), link)

# A live process that is provably not an ancestor of the launcher: the runner is
# an ancestor of every `nest` chain, so a child of the runner is their sibling.
# Structural, unlike naming a low pid and hoping the platform has one - the same
# host-assumption the tmux directory above exists to avoid.
STRANGER = subprocess.Popen(["sleep", "600"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run(depth=1, panes="%99 ROOTPID 0", tmux_on_path=True, forge_age=None,
        rehost_at=None, tmux_pane=None, sleep=None):
    """Launch finalize-session under a real `nest` chain and return its dry-run report."""
    workdir = tempfile.mkdtemp(prefix="finalize-case.")
    pidfile = os.path.join(workdir, "root.pid")
    # The two PATHs are different shapes rather than one with an entry dropped:
    # the tmux-absent case must not carry REAL_DIRS at all, because that is
    # precisely where a packaged tmux lives.
    path = [FIXTURES, REAL_DIRS] if tmux_on_path else [NO_TMUX_BIN]
    if forge_age is not None:
        path.insert(0, FORGE_DIR)
    env = {
        "PATH": ":".join(path),
        "HOME": os.environ.get("HOME", workdir),
        "TMPDIR": workdir,
        "FINALIZE_DRY_RUN": "1",
        "NEST_PUBLISH_PID": pidfile,
        "FIXTURE_ROOT_PID": pidfile,
    }
    if forge_age is not None:
        env["FIXTURE_FORGE_AGE"] = forge_age
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
DETACHED = "detached"
NO_TRANSPORT_RC = 2  # the launcher's own code for "no transport to deliver into"


def picked(done):
    """The pane id the launcher resolved to, DETACHED when it fell all the way
    to the fresh-window transport, or DECLINED when it found no transport at
    all and said so with the no-transport exit code.

    [LAW:parse-dont-validate] returning a bare None for the no-decision case
    would be an answer-shaped void: a launcher that deliberately declined and
    one that crashed on its way to an answer would read identically, and every
    negative case below would pass on either. So the exit code is read here,
    once, and a run that is neither a pane, a detached pick, nor a clean
    decline comes back as its own report - a value no assertion matches,
    carrying the evidence into the failure message.
    """
    for line in done.stdout.splitlines():
        if line.startswith("[dry-run] transport=tmux target=target-for-"):
            # The fixture's target is `target-for-<pane>:0.0`; take the pane back
            # out of it rather than matching the whole rendered string.
            return line.split("target-for-", 1)[1].split(" ", 1)[0].split(":", 1)[0]
        if line.startswith("[dry-run] transport=detached "):
            return DETACHED
    if done.returncode == NO_TRANSPORT_RC:
        return DECLINED
    return f"<no decision: rc={done.returncode} out={done.stdout!r} err={done.stderr!r}>"


# --- preconditions --------------------------------------------------------
# [LAW:verifiable-goals] a suite that silently tested the wrong binary, or found
# a real tmux where it meant to find none, would pass while proving nothing.

check("the launcher under test exists and is executable", os.access(LAUNCHER, os.X_OK), LAUNCHER)
# This pins the constructed directory, not the host. Asking whether REAL_DIRS
# holds a tmux would answer a question about the machine and fail the entire
# suite on any Linux that packages one into /usr/bin.
check("the tmux-absent PATH contains no tmux",
      shutil.which("tmux", path=NO_TMUX_BIN) is None, NO_TMUX_BIN)
check("the tmux-absent PATH can still run the launcher",
      shutil.which("bash", path=NO_TMUX_BIN) is not None,
      "the launcher's `#!/usr/bin/env bash` resolves bash through PATH")

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

# The case the whole mechanism exists for: a hop that re-hosts the session off the
# pane's shell, taking $TMUX and $TMUX_PANE with it. $TMUX_PANE must be SET here,
# and set to a pane the ancestry does not own - otherwise the shim's `env -u` has
# nothing to strip and the case quietly degrades into another depth-6 chain,
# passing just as well with the strip deleted outright.
#
# This and the inherited-$TMUX_PANE case at the end are the two directions of one
# precedence rule - the environment wins while the chain is intact, discovery wins
# once a re-host has broken it. They look alike and are not: neither can be
# dropped as a duplicate of the other.
#
# %77 has to be a pane tmux still owns, not merely a name in the environment.
# Once the launcher learned to hand a stale $TMUX_PANE on to discovery, an
# unresolvable %77 reached %99 whether or not the strip ran, and this case went
# quiet again - the same inertness in a new disguise, introduced by making the
# launcher more forgiving. A live %77 is one discovery would never choose, so
# only the strip can decide the outcome.
done = run(depth=5, rehost_at=3, tmux_pane="%77",
           panes=f"%99 ROOTPID 0\n%77 {STRANGER.pid} 0")
check("a re-hosting hop drops the stale $TMUX_PANE and discovery wins",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# --- no pane to be had, but tmux still gives a transport --------------------
# [LAW:no-mode-explosion] owner decision 2026-08-23: every session gets the same
# capability, no subclass excluded. Refusing a PANE is still correct in every
# case below - the walk's job is unchanged - but refusing a pane no longer means
# refusing to deliver AT ALL, because the launcher falls to the detached
# transport whenever a claude process is findable to relaunch. This suite's
# `nest` chain always runs as a real descendant of the test runner's own claude
# session, so that process is always findable here; DECLINED survives only where
# tmux itself is unreachable to spawn a fresh window with.

done = run(panes=None)
check("no tmux server: falls to the detached transport", picked(done) == DETACHED, picked(done))

done = run(panes="")
check("a server with no panes falls to the detached transport", picked(done) == DETACHED, picked(done))

done = run(tmux_on_path=False)
check("tmux absent from PATH: this is the one true decline - nothing left to spawn a window with",
      picked(done) == DECLINED, picked(done))
# [LAW:single-enforcer] the exit code is the whole of the no-transport report,
# pinned once here against the sole remaining decline case, rather than
# re-asserted beside every refused-pane case below (which no longer decline).
check("declining is reported by exit code, not by prose alone",
      done.returncode == NO_TRANSPORT_RC, f"rc={done.returncode}")

# The promise in one case: a live pane, owned by a real process, that no ancestor
# accounts for - and it must be refused rather than claimed for want of anything
# better. Nothing else in the suite forces a rejection: every other pane is dead,
# out of ancestry AND out of the walk's reach, or genuinely owned. Refusing this
# pane still lands on the detached transport, not on silence.
done = run(depth=2, panes=f"%5 {STRANGER.pid} 0")
check("a live pane owned by a stranger is refused, not claimed - falls to detached",
      picked(done) == DETACHED, picked(done))

# Distinct from the case above, and easy to mistake for it: the walk exits at
# `pid + 0 <= 1` on reaching init, so a pane_pid of 1 is never even tested
# against the ancestry. This pins that termination guard, not the descent match.
done = run(depth=2, panes="%5 1 0")
check("the walk stops at init rather than climbing past it - falls to detached",
      picked(done) == DETACHED, picked(done))

# --- the two forgeries a bare pid match cannot see -------------------------

done = run(depth=2, panes="%99 ROOTPID 1")
check("a dead pane still advertising an ancestor's pid is refused - falls to detached",
      picked(done) == DETACHED, picked(done))

done = run(depth=2, panes="%99 ROOTPID 1\n%98 ROOTPID 0")
check("a live pane is still found past a dead one holding the same pid",
      picked(done) == "%98", f"rc={done.returncode} out={done.stdout!r}")

# A pane record with no dead column: the fixture's `read` leaves $dead empty, so
# #{pane_dead} expands to nothing - which is precisely what a tmux predating that
# format emits, since tmux renders an unknown field as the empty string rather
# than leaving the token literal. The row reaches awk with three fields, and a
# guard written as `$4 != 1` would read the uninitialised $4 as alive and admit
# the pane, turning the whole dead-pane check off with nothing to show for it.
# The positive cases above are this one's counterpart: they supply the column and
# resolve.
done = run(depth=2, panes="%99 ROOTPID")
check("a pane whose liveness tmux never stated is refused, not assumed - falls to detached",
      picked(done) == DETACHED, picked(done))

done = run(depth=2, sleep=2, forge_age="00:00")
check("an ancestor younger than its own descendant is refused as a recycled pid - falls to detached",
      picked(done) == DETACHED, picked(done))
# The control runs UNDER the forging ps, differing only in the value written.
# Re-running the chain without the wrapper would leave the one spurious-pass mode
# open that `picked()` cannot see: a mangled process table declining cleanly with
# the no-transport code, for a reason having nothing to do with the age check.
# Only a run that forges and still resolves proves the wrapper leaves the subject
# intact.
check("the same forged pid resolves when the age is older instead of younger",
      picked(run(depth=2, sleep=2, forge_age="99:00:00")) == "%99",
      "without this the forging fixture, not the age check, could be doing the work")

# The walk refuses an elapsed time it cannot read rather than folding it into an
# age of zero, and pinning that needs a value the format rejects which ageof()
# still reads as LARGE. Garbage that folds to zero (`abc`) proves nothing here:
# zero is younger than the descendant, so the age check refuses it and the format
# guard could be deleted with no case noticing. `1:2:3:4` has too many fields for
# [[dd-]hh:]mm:ss yet folds to ~62 hours, so it clears the age comparison and only
# the format check stands between it and a claimed pane.
done = run(depth=2, sleep=2, forge_age="1:2:3:4")
check("an elapsed time the walk cannot read refuses the pane - falls to detached",
      picked(done) == DETACHED, picked(done))

# --- precedence -----------------------------------------------------------
# Both candidates must be resolvable, or the case cannot see which one won. An
# earlier version handed discovery the unresolvable `%5 1 0` set, so $TMUX_PANE
# was the only answer available and %42 came back under either ordering - a check
# that read as pinning precedence while pinning nothing. Here discovery can reach
# %99 and the environment names %42, so the two genuinely compete.

done = run(depth=2, panes=f"%99 ROOTPID 0\n%42 {STRANGER.pid} 0", tmux_pane="%42")
check("an inherited $TMUX_PANE wins outright and discovery never runs",
      picked(done) == "%42", f"rc={done.returncode} out={done.stdout!r}")

# A $TMUX_PANE naming a pane that has since gone - the map outliving its
# territory, which is the whole reason discovery exists. It must not be able to
# consume the attempt: tmux answers display-message for an unowned pane with exit
# 0 and empty fields, so the target renders as the bare ":." - non-empty, and a
# live tmux address for whatever pane is current. Taking it would hand the session
# to whichever window the user happened to be looking at.
done = run(depth=2, tmux_pane="%4242")
check("a stale $TMUX_PANE hands the question on and discovery answers it",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r}")

# And with nothing to fall back to, the answer is still no pane - never the ":."
# that an unresolvable id renders into - though the launcher still has the
# detached transport left to try.
done = run(depth=2, panes="%5 1 0", tmux_pane="%4242")
check("a stale $TMUX_PANE with nothing to discover falls to detached rather than guessing a pane",
      picked(done) == DETACHED, picked(done))

# Owning a pane and displaying a live process are different facts, and
# remain-on-exit is what separates them: tmux keeps answering for a pane whose
# process has exited. So an inherited $TMUX_PANE can name a pane that is real,
# owned, and dead - it echoes its own id back exactly as a live one does, and an
# id-only check would take it, skip discovery, and send the handoff into a corpse.
done = run(depth=2, panes=f"%99 ROOTPID 0\n%77 {STRANGER.pid} 1", tmux_pane="%77")
check("an inherited $TMUX_PANE naming a dead pane loses to a live discovered one",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r}")

# ':.' is what an unresolvable pane id renders into, and it is not inert - tmux
# reads it as current-session:current-window.current-pane and hands back a real,
# live pane. Liveness cannot refuse it, because the pane it resolves to IS alive;
# only comparing the echoed id against the id asked for can. %77 is listed first
# so 'current' is a pane the ancestry does not own, which is what makes taking it
# a wrong answer rather than a lucky one.
done = run(depth=2, panes=f"%77 {STRANGER.pid} 0\n%99 ROOTPID 0", tmux_pane=":.")
check("a $TMUX_PANE that resolves to someone else's live pane is refused",
      picked(done) == "%99", f"rc={done.returncode} out={done.stdout!r}")

STRANGER.terminate()
STRANGER.wait()
shutil.rmtree(FIXTURES, ignore_errors=True)
print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
