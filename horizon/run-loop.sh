#!/usr/bin/env bash
# Start a horizon run and let it drive itself across session boundaries.
#
# WHY: the session boundary is the phenomenon this eval exists to observe. The reference
# run crossed it by hand; the instrument has to cross it alone, many times, with nobody
# watching. This script builds time zero, issues the pinned /goal wording once, and then
# gets out of the way - every later session is produced by memento's own relaunch.
#
# THE DRIVER OBSERVES; IT DOES NOT REPAIR. memento's goal-carry is a CONTROLLED VARIABLE
# of this experiment, not a service this script provides. A driver that re-issued the
# goal when the carry failed, or restarted a session that died, would be measuring
# itself - the run would look healthy precisely where the instrument is broken. So a
# lost carry is reported, loudly, and the run stops. [LAW:no-silent-failure]
#
# Usage:
#   horizon/run-loop.sh [seed-dir] [memento-ref] [lit-ref]
#
# [seed-dir]     the seed bundle to start from. Defaults to horizon/seeds/macklebox,
#                the reference seed.
# [memento-ref]  git ref to pin memento at, resolved against the repository that OWNS
#                memento (promptctl/memento) and passed straight to pin-instrument.sh.
#                Defaults to that repo's default branch; a campaign pins it explicitly
#                on every run. The /goal wording is pinned at this checkout's HEAD.
# [lit-ref]      git ref to pin lit's Claude plugin (the /next skill) at, resolved
#                against lit's repository (promptctl/links-issue-tracker) the same way.
#
# THE CONFIG DIR IS AT A FIXED PATH AND THE WORK DIR IS NOT INSIDE IT. Claude Code keys
# its stored credential to the config directory's PATH, so the config dir has to be the
# same one login.sh authenticated - while the work dir has to be EMPTY, so this run's
# record can never be confused with the last one's. Those two lifetimes cannot share a
# tree; lib.sh defines both paths and explains the split.
#
# The work dir IS the run bundle - the eval's actual output, since nothing here renders a
# verdict and a human reads the bundle instead. horizon_capture_bundle owns its shape;
# HORIZON_BUNDLE_LAYOUT in lib.sh declares every path it holds, and the bundle's own
# README.md renders that declaration for whoever opens it. Not restated here, because a
# second listing of the layout is a second thing to keep true. [LAW:one-source-of-truth]
#
# instrument/ and seed/ get their own subdirectories because pin-instrument.sh and
# seed-run.sh each refuse a run-dir that already exists - a guard worth keeping, so they
# are given one directory each rather than being loosened to share.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

# How many consecutive sessions of committed work the run is watched for. The ticket's
# acceptance is three; a campaign that wants the whole backlog raises it.
: "${HORIZON_TARGET_SESSIONS:=3}"
# Wall-clock ceiling. A run that stops making progress must end as a reported stall
# rather than as a process nobody remembers starting. [LAW:no-silent-failure]
: "${HORIZON_MAX_MINUTES:=480}"

# Usage: end_run <config_dir> <work_dir> <started_iso>  - the ONE exit handler
#
# Every exit path - success, a failed assertion, a dead session, the wall-clock ceiling -
# leaves the same state behind: the session ended, so the agent cannot keep working after
# the record is taken, and then the whole bundle is captured. The status is the one the
# script was exiting with; a capture that fails replaces it with failure on purpose,
# because the bundle IS the run's product and a run whose product did not land is not a
# success. [LAW:no-silent-failure]
end_run() {
  local status=$? config_dir="$1" work_dir="$2" started="$3"
  # Each in a subshell, so a die in one cannot end the handler before the other runs;
  # either failing is a failed run.
  ( horizon_release_run_lock ) || status=1
  ( horizon_capture_bundle "$config_dir" "$work_dir" "$started" ) || status=1
  exit "$status"
}

main() {
  local seed_dir="${1:-$SCRIPT_DIR/seeds/macklebox}" memento_ref="${2:-}" lit_ref="${3:-}"

  horizon_need_base
  # Read at both ends of the run - the start below, and the end from the close-out - so a
  # machine without it fails here by name rather than with a bare "command not found"
  # from inside the exit trap, where the run is already over.
  horizon_need date
  horizon_need git
  horizon_need lit
  horizon_need python3
  horizon_need claude
  # Loop primitives: declared by the scripts that reach them rather than in
  # HORIZON_BASE_TOOLS, because seeding never does.
  horizon_need tmux
  horizon_need ps
  horizon_need basename
  # Reached from horizon_bind_remote.
  horizon_need gh

  [ -d "$seed_dir" ] || horizon_die "no such seed bundle: $seed_dir"
  seed_dir="$(cd "$seed_dir" && pwd)"

  # Absolute before it is baked into the exit handler; the directory does not exist yet.
  [[ "$HORIZON_WORK_DIR" = /* ]] || HORIZON_WORK_DIR="$PWD/$HORIZON_WORK_DIR"
  # A stale run is refused rather than merged into or silently cleared: its transcripts
  # and commits are the only record of whatever happened last time, and this script
  # cannot know whether they have been archived yet.
  [ ! -e "$HORIZON_WORK_DIR" ] \
    || horizon_die "work dir already holds a run: $HORIZON_WORK_DIR
Archive it (copy it wherever you are keeping runs) and remove it, then start this one."

  # The run's start, read BEFORE the lock is taken and baked into the handler below.
  # Taken at all rather than computed at the end from the earliest transcript, because the
  # time spent pinning, provisioning and seeding is the run's time too, and a start
  # derived from session one would silently omit all of it.
  #
  # BEFORE, and not one line after, because `horizon_die` exits without releasing anything
  # and the handler that releases the lock cannot be installed until there is a lock to
  # release. Anything fallible in between exits holding it: the tmux lock session stays
  # alive, and every later run is refused with "one run at a time" until somebody kills it
  # by hand. That is the exact shape this script's "a refused invocation leaves nothing
  # behind" is written to prevent, so the window stays empty of anything that can fail.
  local started
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || horizon_die "could not read the clock"

  # THE LOCK, before anything shared is touched and before anything is created: a refused
  # invocation leaves nothing behind. Everything below - the config dir wipe, the remote
  # reset, the launch - would otherwise land on top of a run that is still going, and the
  # only record of that would be the run stopping. [LAW:no-ambient-temporal-coupling]
  horizon_take_run_lock
  local config_dir="$HORIZON_CONFIG_DIR"
  # The handler is installed the moment there is a lock to release; it is the only
  # `trap ... EXIT` in this script, because a second one anywhere below would silently
  # replace it rather than add to it. Arguments are baked in now: a handler cannot read
  # a function-scoped variable at exit time. %q, not hand-placed quotes: both paths are
  # operator-overridable, and a quote inside one would break the handler itself.
  local trap_cmd
  printf -v trap_cmd 'end_run %q %q %q' "$config_dir" "$HORIZON_WORK_DIR" "$started"
  # shellcheck disable=SC2064
  trap "$trap_cmd" EXIT

  # Asserted before anything shared is touched, not after the session hangs: an
  # unauthenticated config dir boots to a login prompt, which in an unattended run is
  # indistinguishable from an agent thinking hard - and the remote must not be reset for
  # a run that cannot launch. The credential is keyed to the config dir's path, so the
  # rebuild below keeps it.
  horizon_log "checking the pinned config dir can authenticate"
  horizon_assert_authenticated "$config_dir"

  mkdir -p "$HORIZON_WORK_DIR" || horizon_die "could not create the work dir $HORIZON_WORK_DIR"
  local instrument_dir="$HORIZON_WORK_DIR/instrument"
  local seed_out_dir="$HORIZON_WORK_DIR/seed"
  local goal_file="$HORIZON_WORK_DIR/goal.md"

  horizon_log "pinning the instrument"
  # Empty refs are passed through as empty: pin-instrument.sh reads an empty argument as
  # that argument's default, and the reviewer and goal refs are always left to theirs.
  "$SCRIPT_DIR/pin-instrument.sh" "$instrument_dir" "$memento_ref" "" "" "$lit_ref" \
    || horizon_die "pin-instrument.sh failed"

  # Here, under the lock, and not inside the pin: this is the one shared thing the pin
  # would otherwise touch, and the lock is what makes wiping it safe. [LAW:single-enforcer]
  horizon_log "rebuilding the config dir from the pinned snapshot"
  horizon_provision_config_dir "$config_dir" "$instrument_dir"

  horizon_log "seeding time zero from $(basename "$seed_dir")"
  "$SCRIPT_DIR/seed-run.sh" "$seed_out_dir" "$seed_dir" \
    || horizon_die "seed-run.sh failed"

  # The name seed-run.sh recorded, not basename re-derived here. [LAW:one-source-of-truth]
  local project_dir
  project_dir="$seed_out_dir/$(horizon_manifest_field "$seed_out_dir/seed-manifest.json" project name)"
  [ -d "$project_dir" ] || horizon_die "seeding produced no project at $project_dir"

  # After seeding, because `lit init` adopts a backlog from any remote it finds - a
  # project that already had an origin would start from that remote's backlog instead of
  # the seed's. seed-run.sh attaches no remotes, so that ordering holds by construction
  # rather than by this line staying where it is.
  horizon_log "binding the run to $HORIZON_RUN_REPO"
  horizon_bind_remote "$project_dir"
  # Immediately after the reset, because this is the one moment the fact is true: the eval
  # drives ONE shared repository whose PR numbers keep climbing across runs, and afterwards
  # nothing distinguishes this run's pull requests from the last run's except that they
  # are numbered above this line. [LAW:no-ambient-temporal-coupling]
  horizon_record_remote_time_zero "$HORIZON_WORK_DIR" "$HORIZON_RUN_REPO"

  horizon_log "recording unattended boot state"
  horizon_write_boot_state "$config_dir" "$project_dir"

  # The pinned wording is RE-ISSUED FROM THE COMMIT THE MANIFEST NAMES, never retyped
  # here and never read from the working tree. manifest.json records goal_wording.sha256
  # at that commit; taking the bytes from anywhere else would let a run report a
  # controlled variable it did not actually use. [LAW:one-source-of-truth]
  local repo_root goal_sha
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  goal_sha="$(horizon_manifest_field "$instrument_dir/manifest.json" goal_wording ref)"
  horizon_goal_wording_file "$repo_root" "$goal_sha" "$goal_file"

  horizon_log "launching session one with the pinned /goal wording as its prompt"
  # The pinned binary, not the bare name: the symlink pin-instrument.sh wrote is this
  # run's handle on its harness version, and horizon_assert_transport's in-place guarantee
  # means this one process is every session the run will have. [LAW:one-source-of-truth]
  horizon_launch_session "$config_dir" "$project_dir" "$goal_file" \
    "$instrument_dir/bin/claude"
  # The pane the wait settled on, kept rather than re-fetched: the banner is on screen
  # because THIS capture is what `ready` was read out of, and by the time the manifest has
  # been opened the session has been working for a beat and tmux would hand back a pane
  # that has moved on. [LAW:no-ambient-temporal-coupling]
  # Checked rather than bare, for the reason stated at recorded_version below: horizon_die
  # inside a command substitution exits only the SUBSHELL, so the wait's own refusal
  # becomes an ordinary non-zero assignment here. Errexit would end the run on it either
  # way; what the explicit check adds is a line saying which wait failed, rather than a
  # bare exit 1 under the wait's message. [LAW:no-silent-failure]
  local booted_pane
  booted_pane="$(horizon_wait_ready)" \
    || horizon_die "session one never became ready - the wait's diagnosis is above"
  # Asked of the session rather than of the driver: manifest.json records a version read
  # from a file on disk, and this is the only reading taken from the process running it.
  #
  # Captured into a checked assignment rather than nested into the argument list: a
  # command substitution that fails inside an argument has its status discarded, so
  # horizon_manifest_field's horizon_die would be swallowed and the assert would run with
  # an empty expectation - reporting a harness divergence for what is really an unreadable
  # manifest. The same rule horizon_lit_sha256 states. [LAW:no-silent-failure]
  local recorded_version
  recorded_version="$(horizon_manifest_field "$instrument_dir/manifest.json" claude version)" \
    || horizon_die "could not read claude.version from $instrument_dir/manifest.json"
  horizon_assert_booted_version "$HORIZON_TMUX_SESSION" "$recorded_version" <<<"$booted_pane"
  # The isolation guarantee, checked rather than assumed - see horizon_assert_transport.
  horizon_assert_transport
  horizon_log "handoff transport verified: in-place reset, config dir preserved"
  horizon_wait_goal_in_force "$config_dir" "$project_dir" "$goal_file"
  horizon_log "session one's pinned /goal is in force"

  horizon_log "run is live; observing until ${HORIZON_TARGET_SESSIONS} sessions of committed work"
  # NOT redirected into loop.json any more. The close-out writes that file on every exit
  # path, and a redirect here would make this the second writer of it - the one that won
  # only when the observer got far enough to print. Acceptance attempt 1 was stopped by
  # hand four minutes in and left an empty loop.json behind, which is precisely the shape
  # of a record that exists because of how a run ENDED rather than because it ran.
  # [LAW:one-source-of-truth] The report still prints here, where it is diagnostic output
  # beside the failure that produced it.
  horizon_observe "$config_dir" "$project_dir" "$goal_file" \
    "$HORIZON_TARGET_SESSIONS" "$HORIZON_MAX_MINUTES"
}

main "$@"
