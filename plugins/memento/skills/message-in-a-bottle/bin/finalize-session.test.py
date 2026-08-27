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

The detached-transport cases have a claude process of their own, planted in the
chain: `nest` re-execs itself under the name `claude` at the top hop, so
`_find_claude_pid` finds a process this suite owns and can name. It is a real
process in the real ancestry, matched by the real walk - the fixture is the NAME
and nothing else. Before that, those cases passed only because the walk climbed
past the chain into whatever real `claude` was running the suite, so a plain CI
runner with no claude-named ancestor saw them DECLINE instead of DETACH and the
suite failed for a reason having nothing to do with the code under test.

Run: python3 finalize-session.test.py
"""

import concurrent.futures
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
  new-session|has-session|capture-pane|load-buffer|paste-buffer|send-keys|kill-session)
    # The detached WORKER's half of the fixture. It needs almost no state: the
    # worker only ever asks whether the new session is up and whether its banner
    # is drawn, so a session that is always up plus one value for what its pane
    # shows is the whole model.
    # $FIXTURE_TMUX_FAIL names one subcommand to fail instead, which is how a
    # goal delivery that dies mid-way - or a session that cannot be created at all
    # - is staged. $FIXTURE_TMUX_PANE_TEXT is what capture-pane shows: a session
    # that never finishes booting is that same always-up session with a different
    # value in this one field, not a second mode.
    # Every subcommand appends its whole argv to $FIXTURE_TMUX_LOG, which is how a
    # case can see that a teardown the worker owes actually happened - a log line
    # from the worker only says it meant to.
    sub="$1"
    if [ "${FIXTURE_TMUX_FAIL:-}" = "$sub" ]; then
      echo "fixture tmux: failing '$sub' on request" >&2
      exit 1
    fi
    printf '%s\n' "$*" >> "${FIXTURE_TMUX_LOG:-/dev/null}"
    [ "$sub" = capture-pane ] && printf '%s\n' "${FIXTURE_TMUX_PANE_TEXT:-Claude Code v1.2.3}"
    exit 0
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
self="${NEST_SELF:-$0}"
if [ -n "${NEST_PUBLISH_PID:-}" ]; then
  printf '%s' "$$" > "$NEST_PUBLISH_PID"
  unset NEST_PUBLISH_PID
fi
# The hop named `claude`, planted so the launcher's ancestry walk has a claude
# process of this fixture's own making to find. Re-exec rather than fork: the pid
# is unchanged, so the pid already published above IS this claude - which is what
# lets an assertion name the exact process the launcher was supposed to find. The
# name is the whole of the fixture, because the launcher matches on program name;
# everything below this hop proceeds as ordinary nest.
if [ "${NEST_CLAUDE_AT:-}" = "$depth" ]; then
  unset NEST_CLAUDE_AT
  export NEST_SELF="$self"
  exec "$NEST_AS_CLAUDE" "$depth" "$@"
fi
if [ "$depth" -gt 0 ]; then
  if [ "${NEST_REHOST_AT:-}" = "$depth" ]; then
    unset NEST_REHOST_AT
    claude daemon run --bg-pty-host -- "$self" $((depth - 1)) "$@"
    exit $?
  fi
  "$self" $((depth - 1)) "$@"
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


PS_MUTE_IDENTITY = r"""#!/bin/bash
# The real ps everywhere except the one query that asks what a pid is HOLDING:
# `ps -o lstart=,command= -p <pid>` exits 0 and prints nothing, which is what a
# pid whose holder exited between the lookup and the query actually reports. It
# is the one answer a bare exit-code check cannot see — success, with no identity
# in it — and the launcher must read it as "I could not identify this process",
# never as an identity of its own.
#
# Selectivity is keyed on the field list, not on the subcommand shape, because
# `-o command=` and `-o ppid=` (the ancestry hops) and `-eo pid=,ppid=,etime=`
# (the whole-table walk) are the same `-p`/`-o` grammar and must all pass
# through untouched. Muting them instead would collapse discovery for a reason
# having nothing to do with the identity read, and the case would pass on the
# wrong evidence. The control below runs under this same wrapper and still
# resolves a pane, which is what proves the pass-through is real.
set -uo pipefail
for arg in "$@"; do
  [ "$arg" = "lstart=,command=" ] && exit 0
done
exec /bin/ps "$@"
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
# `nest` under the one name the launcher's ancestry walk looks for. A symlink and
# not a copy: there is one nest program, and a second copy of it that could drift
# from the first is a bug waiting for someone to edit only one of them.
AS_CLAUDE_DIR = os.path.join(FIXTURES, "as-claude")
os.mkdir(AS_CLAUDE_DIR)
NEST_AS_CLAUDE = os.path.join(AS_CLAUDE_DIR, "claude")
os.symlink(NEST_BIN, NEST_AS_CLAUDE)
FORGE_DIR = os.path.join(FIXTURES, "forge")
os.mkdir(FORGE_DIR)
install(FORGE_DIR, "ps", PS_FORGING)
MUTE_DIR = os.path.join(FIXTURES, "mute")
os.mkdir(MUTE_DIR)
install(MUTE_DIR, "ps", PS_MUTE_IDENTITY)

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
        rehost_at=None, tmux_pane=None, sleep=None, mute_identity=False,
        message="handoff"):
    """Launch finalize-session under a real `nest` chain and return its dry-run report."""
    workdir = tempfile.mkdtemp(prefix="finalize-case.")
    pidfile = os.path.join(workdir, "root.pid")
    # The two PATHs are different shapes rather than one with an entry dropped:
    # the tmux-absent case must not carry REAL_DIRS at all, because that is
    # precisely where a packaged tmux lives.
    path = [FIXTURES, REAL_DIRS] if tmux_on_path else [NO_TMUX_BIN]
    if forge_age is not None:
        path.insert(0, FORGE_DIR)
    if mute_identity:
        path.insert(0, MUTE_DIR)
    env = {
        "PATH": ":".join(path),
        "HOME": os.environ.get("HOME", workdir),
        "TMPDIR": workdir,
        "FINALIZE_DRY_RUN": "1",
        "NEST_PUBLISH_PID": pidfile,
        "FIXTURE_ROOT_PID": pidfile,
        # The claude process the detached transport relaunches as is planted at the
        # top of this chain, so the ancestry walk finds a process this fixture owns
        # rather than whatever real claude happens to be running the suite. Every
        # case gets one, unconditionally: a claude hop the walk cannot reach (the
        # over-the-bound chains) is refused for the same reason a claude hop that
        # was never planted would be, so nothing has to decide which cases need it.
        "NEST_CLAUDE_AT": str(depth),
        "NEST_AS_CLAUDE": NEST_AS_CLAUDE,
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
        done = subprocess.run([NEST_BIN, str(depth), LAUNCHER, message],
                              text=True, capture_output=True, env=env, timeout=120)
        # The chain's top pid, read before the workdir goes away. It names both the
        # pane fixtures' ROOTPID and the planted claude - they are one process - so
        # an assertion can say which process the launcher picked, not merely that it
        # picked one.
        with open(pidfile) as handle:
            done.root_pid = handle.read().strip()
        return done
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
# transport whenever a claude process is findable to relaunch. Every chain here
# plants one at its top hop, so that process is always findable; DECLINED survives
# only where tmux itself is unreachable to spawn a fresh window with.

done = run(panes=None)
check("no tmux server: falls to the detached transport", picked(done) == DETACHED, picked(done))
# Which claude, exactly. DETACHED alone cannot tell the planted process from an
# ambient one four levels above the test runner, and that is precisely the
# distinction that decides whether these cases pass on a machine that is not
# already inside a Claude Code session. Naming the pid closes it.
check("the detached transport relaunches as the planted claude, not an ambient one",
      f"claude_pid={done.root_pid} " in done.stdout,
      f"root_pid={done.root_pid} out={done.stdout!r} err={done.stderr!r}")
# A pid alone cannot license a kill 40 seconds later, so the launcher captures what
# the pid is HOLDING and hands that down to the worker to re-check. The captured
# text has to describe the process actually found - a constant, or the pid restated,
# would satisfy "non-empty" and prove nothing.
check("the launcher captures the old process's identity, not just its pid",
      any(line.startswith("[dry-run] old-process identity: ") and NEST_AS_CLAUDE in line
          for line in done.stdout.splitlines()),
      f"out={done.stdout!r}")

# An identity read that SUCCEEDS and says nothing. `ps` exits 0 with empty output
# for a pid whose holder exited between the ancestry lookup and the query, so the
# exit code alone reports "fine" over an answer that identifies nobody. Read as an
# identity, that emptiness is fatal at exactly one remove: the launcher would hand
# "" to the worker, the worker's own re-read of a since-reissued pid would also
# come back "", the two would compare EQUAL, and the worker would send TERM/KILL to
# whatever stranger now holds that pid. So the launcher refuses here, and the
# assertion names the refusal - exit code and reason - rather than merely nonzero,
# because a chain that never found a claude at all also exits 2.
#
# This has to be pinned at the LAUNCHER. At the worker the same guard is a genuine
# no-op: `IDENT_NOW=$(_process_identity "$PID") || IDENT_NOW=""` yields the same
# empty string whether the function returns 1 or returns 0 holding nothing, so no
# worker case can tell the two apart. Only a caller that treats failure as a hard
# stop can.
done = run(panes=None, mute_identity=True)
check("an identity read that succeeds but names nobody is a refusal, not an empty identity",
      done.returncode == NO_TRANSPORT_RC
      and "cannot read the identity of claude process" in done.stderr,
      f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
# The control, under the same wrapper: everything ps answers apart from that one
# field list still answers truthfully, so the ancestry hops and the whole-table
# `ps -eo` walk resolve the pane exactly as they do without it. Without this, a
# wrapper that broke ps outright would produce the refusal above for a reason
# having nothing to do with the identity read.
check("the identity-muting ps leaves the ancestry walk intact",
      picked(run(depth=2, mute_identity=True)) == "%99",
      "without this the mute wrapper, not the identity guard, could be doing the work")

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

# The same two panes in the other order, and the reversal is the entire point.
# Liveness is checked twice on two different paths - the walk screens what enters
# discovery, `_pane_target` screens the inherited $TMUX_PANE - and every dead-pane
# case above is decided by the SECOND one: the walk hands its answer straight to
# `_pane_target`, so a dead pane the walk wrongly admitted is refused downstream
# before any assertion here can see it, and all those cases read DETACHED either
# way. Deleting the walk's liveness whitelist left the suite fully green (verified
# by mutation), which would have let a later reader delete `_pane_target`'s check
# too, believing the walk covered it, with neither guard live and nothing red.
#
# Order breaks the tie because the walk keeps ONE pane per pid, last row winning.
# Listed live-then-dead, a walk that screens for liveness keeps %98 and resolves;
# one that does not lets the dead %99 overwrite it, and the answer collapses to
# DETACHED. Only the walk's own check can produce %98 here.
done = run(depth=2, panes="%98 ROOTPID 0\n%99 ROOTPID 1")
check("a dead pane listed after a live one does not displace it in the walk",
      picked(done) == "%98", f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

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

# --- the reset mode inferred from the message ------------------------------
# The only inference in the script: with no --reset flag, the handoff's own prose
# decides /clear vs /compact. It is deliberately biased toward clear because the
# two errors cost different amounts, and it already has a production incident in
# its own comments - on 2026-08-16 a message reading "Do NOT use /compact" compacted,
# because a word-boundary match cannot see a negation, so the more emphatically an
# author forbade compaction the surer it was to happen. Nothing in the repo pinned
# that, which left the negation list and the mention pattern free to regress in
# silence.
#
# These read the launcher's own dry-run report rather than calling the shell
# function, so the whole path - argv, sentence split, negation screen, default -
# is what is under test. [LAW:behavior-not-structure]


def chose_reset(done):
    """The reset mode the launcher settled on, per its dry-run report."""
    for line in done.stdout.splitlines():
        if line.startswith("[dry-run] transport=tmux "):
            for field in line.split():
                if field.startswith("reset=/"):
                    return field.split("/", 1)[1]
    return f"<no reset: rc={done.returncode} out={done.stdout!r} err={done.stderr!r}>"


done = run(message="Pick up where I left off. Use /compact so the context survives.")
check("an affirmative /compact mention infers compact", chose_reset(done) == "compact",
      chose_reset(done))

# The incident itself. A message that forbids compaction must not compact - and
# under a matcher blind to negation, this is the case that inverts.
done = run(message="Do NOT use /compact here, a blank slate is required.")
check("a negated /compact mention infers clear, not compact", chose_reset(done) == "clear",
      chose_reset(done))

# Negation screens the SENTENCE, not the message: skipping one ambiguous sentence
# must still leave a later affirmative one able to decide. Without this case, a
# regression that gave up at the first negated mention - refusing compact for the
# rest of the message - would read exactly like the fix above.
done = run(message="Do NOT use /compact blindly. Use /compact for this handoff.")
check("a negated sentence does not veto a later affirmative one",
      chose_reset(done) == "compact", chose_reset(done))

# The default, and the reason the bias points where it does: no mention at all is
# not an absence of evidence to guess around, it is the answer.
done = run(message="Pick up the next ticket and keep going.")
check("a message that never mentions compaction infers clear",
      chose_reset(done) == "clear", chose_reset(done))

# --- the detached worker: what it retires, and in what order ----------------
# Everything above drives the LAUNCHER in dry-run, so the promise the detached
# transport makes at the other end - after the handoff, exactly one live agent -
# had no coverage at all. These cases run the real worker against the fixture tmux
# and a real victim process, and each is decided by whether a process is alive or
# dead when it finishes, never by a log line claiming one or the other.


# A victim that refuses SIGTERM, so retirement has to escalate. The default `sleep 600`
# dies on the first signal and therefore never reaches the KILL branch at all, which is
# how that branch went uncovered.
#
# ITS `ps` COMMAND STRING MUST BE STABLE FROM BIRTH, which is the whole reason this is not
# a python victim. `sys.executable` was tried and is flaky by nature, not by timing: the
# interpreter REWRITES its own command string during startup, so a reading taken at launch
# (".../bin/python3.14 -c ...") stops matching the reading taken seconds later
# (".../Python.app/Contents/MacOS/Python -c ..."). The retirement code then correctly
# refuses to signal what looks like a different process, and the case fails - about one run
# in three. A fixture whose identity mutates cannot be used to test a mechanism whose whole
# job is proving identity has NOT changed.
#
# The trailing `sleep 1` loop keeps the shell blocked without a long-lived child: when KILL
# lands on the shell, the one sleep in flight is orphaned for at most a second and reaps
# itself, so the case leaves nothing behind.
IGNORES_TERM = ["/bin/bash", "-c", 'trap "" TERM; while :; do sleep 1; done']


def worker_case(identity, goal="", fail_on=None, pane_text=None, victim=("sleep", "600")):
    """Run one detached worker over a real process standing in for the old claude.

    Returns (retired, done): whether the victim was actually signalled, and the
    worker's own result, carrying `done.tmux_log` - every tmux argv the worker
    issued. The identity handed to the worker is read with the same `ps` fields
    the launcher captures, so `identity="match"` passes the genuine article
    rather than something shaped like it; `identity="reused"` keeps that reading
    and swaps the command out, which is what the pid holds after the OS reissues
    it to a stranger. `pane_text` is what the new session's pane shows, so a
    session that never finishes booting is expressed as a value, not a mode.
    """
    proc = subprocess.Popen(list(victim),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    read = subprocess.run(["ps", "-o", "lstart=,command=", "-p", str(proc.pid)],
                          text=True, capture_output=True)
    # `$(...)` strips trailing newlines and nothing else; matching that exactly
    # matters, because the whole check is a string comparison against it.
    real = read.stdout.rstrip("\n")
    if identity == "match":
        ident = real
    else:
        ident = real.replace(" ".join(victim), "vi Makefile")
        # A substitution that matched nothing would hand the worker the REAL identity
        # under the name "reused", and the case would assert that a matching process is
        # left alone - passing while testing the opposite of its name.
        assert ident != real, f"reused-identity fixture altered nothing: {real!r}"
    workdir = tempfile.mkdtemp(prefix="finalize-worker.")
    msgfile = os.path.join(workdir, "msg")
    goalfile = os.path.join(workdir, "goal")
    with open(msgfile, "w") as handle:
        handle.write("handoff")
    with open(goalfile, "w") as handle:
        handle.write(goal)
    tmuxlog = os.path.join(workdir, "tmux.log")
    env = {
        "PATH": ":".join([FIXTURES, REAL_DIRS]),
        "HOME": os.environ.get("HOME", workdir),
        "TMPDIR": workdir,
        "FIXTURE_TMUX_LOG": tmuxlog,
    }
    if fail_on is not None:
        env["FIXTURE_TMUX_FAIL"] = fail_on
    if pane_text is not None:
        env["FIXTURE_TMUX_PANE_TEXT"] = pane_text
    try:
        done = subprocess.run(
            [LAUNCHER, "--detached-worker", "fixture-session", workdir, msgfile,
             goalfile, "", str(proc.pid), "/bin/true", ident],
            text=True, capture_output=True, env=env, timeout=180)
        try:
            proc.wait(timeout=5)
            retired = True
        except subprocess.TimeoutExpired:
            retired = False
        done.tmux_log = open(tmuxlog).read() if os.path.exists(tmuxlog) else ""
        return retired, done
    finally:
        proc.kill()
        proc.wait()
        shutil.rmtree(workdir, ignore_errors=True)


# Each worker sleeps out the full HANDOFF_DELAY_SECONDS, so the cases run
# alongside each other rather than one after another. They share nothing: each
# owns its victim process and its own workdir.
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    same_pid = pool.submit(worker_case, "match")
    reused_pid = pool.submit(worker_case, "reused")
    # The goal delivery is staged to fail at its first tmux call, which under the
    # worker's `set -euo pipefail` aborts the script on the spot.
    goal_fails = pool.submit(worker_case, "match", goal="ship the thing",
                             fail_on="load-buffer")
    # The spawn that never happens, and the spawn that never comes up: the worker's
    # two "the successor is not there" arms. Both promise the old process is left
    # running, and until now that promise was made only in a comment.
    spawn_fails = pool.submit(worker_case, "match", fail_on="new-session")
    # A pane that shows something other than the boot banner for the whole
    # readiness window - the slow or wedged boot. This one sleeps out the full
    # CLAUDE_READY_TIMEOUT_SECONDS on top of the handoff delay, so it is the
    # longest case in the suite.
    never_ready = pool.submit(worker_case, "match", goal="ship the thing",
                              pane_text="waiting for the shell to start")
    # A victim that ignores TERM, which is the only way to reach the KILL escalation.
    # Every other case here dies on the first signal, so that branch - and the identity
    # re-check guarding it - ran in no test at all until this one.
    survives_term = pool.submit(worker_case, "match", victim=IGNORES_TERM)

retired, done = same_pid.result()
check("the worker retires the old process it was given",
      retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# The window between capturing the pid and signalling it runs to ~41s (the delay
# plus the readiness wait), which is ample room for the OS to hand that pid to
# something else. `kill -0` cannot see that happen - it answers "something is
# alive here", which is true of the stranger too.
retired, done = reused_pid.result()
check("a pid reissued to another process during the wait is not signalled",
      not retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
check("and the worker says why it left that pid alone",
      "not the process captured at launch" in done.stdout, f"out={done.stdout!r}")

# Ordering, not guarding, is what protects the single-live-agent guarantee: the
# goal delivery below the retirement is optional and fallible, and `set -e` turns
# any failure there into an immediate abort. Retirement happens first, so the
# abort finds nothing left to suppress.
retired, done = goal_fails.result()
check("a failed goal delivery cannot leave the old process alive",
      retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# A successor that could not be spawned at all. The old process is the only agent
# there is, so it must still be running when the worker gives up - and the worker
# must say it failed rather than exiting 0 over a handoff that never landed.
retired, done = spawn_fails.result()
check("a session that cannot be created leaves the old process running",
      not retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
check("and the failed spawn is reported as a failure, not a quiet no-op",
      done.returncode == 1 and "could not create detached tmux session" in done.stdout,
      f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
# Nothing was created, so nothing is torn down. This is the counterpart that keeps
# the teardown assertion below honest: a worker that killed the session on every
# failure path would satisfy that one while being wrong here.
check("a spawn that never happened tears nothing down",
      "kill-session" not in done.tmux_log, f"tmux_log={done.tmux_log!r}")

# The dangerous one. The handoff message rides in the `tmux new-session` argv, so a
# readiness timeout does not mean the successor got nothing - it usually means the
# successor is still booting. Left alone, a boot finishing one second past the
# deadline yields two live agents: the old one never retired, the new one already
# working the handoff. The worker collapses that back to one by tearing the new
# session down, and only the tmux log can show it happened; the worker's own log
# line would say so either way.
retired, done = never_ready.result()
check("a successor that never becomes ready is torn down, not left racing the old process",
      "kill-session -t fixture-session" in done.tmux_log,
      f"rc={done.returncode} out={done.stdout!r} tmux_log={done.tmux_log!r}")
check("and the old process survives the timeout - a spawn that never came up kills nobody",
      not retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
check("and the timeout is reported as a failure, with the undelivered goal named",
      done.returncode == 1 and "did not become ready" in done.stdout
      and "carried goal NOT delivered" in done.stdout,
      f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")

# Retirement escalates when TERM is refused. Worth its own case because the branch
# decides to send SIGKILL, and until now nothing in the suite reached it - every other
# victim dies on the first signal, so the escalation and the identity check standing in
# front of it were both unexecuted code.
retired, done = survives_term.result()
check("a process that refuses TERM is still retired, by escalation to KILL",
      retired, f"rc={done.returncode} out={done.stdout!r} err={done.stderr!r}")
check("and the escalation says so, rather than the pid quietly disappearing",
      "survived TERM; sending KILL" in done.stdout,
      f"rc={done.returncode} out={done.stdout!r}")

STRANGER.terminate()
STRANGER.wait()
shutil.rmtree(FIXTURES, ignore_errors=True)
print(f"\n{len(failures)} failed")
sys.exit(1 if failures else 0)
