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
#   horizon/run-loop.sh [seed-dir] [memento-ref]
#
# [seed-dir]     the seed bundle to start from. Defaults to horizon/seeds/macklebox,
#                the reference seed.
# [memento-ref]  git ref to pin memento at, resolved against the repository that OWNS
#                memento (promptctl/memento) and passed straight to pin-instrument.sh.
#                Defaults to that repo's default branch; a campaign pins it explicitly
#                on every run. The /goal wording is pinned at this checkout's HEAD.
#
# THE CONFIG DIR IS AT A FIXED PATH AND THE WORK DIR IS NOT INSIDE IT. Claude Code keys
# its stored credential to the config directory's PATH, so the config dir has to be the
# same one login.sh authenticated - while the work dir has to be EMPTY, so this run's
# record can never be confused with the last one's. Those two lifetimes cannot share a
# tree; lib.sh defines both paths and explains the split.
#
# Produces, under the work dir:
#   instrument/   pin-instrument.sh's output (pinned/, manifest.json)
#   seed/         seed-run.sh's output (the project, backlog-shape.json, seed-manifest.json)
#   goal.md       the /goal wording this run issued, as read from the pinned commit
#   loop.json     what this run observed: sessions, their commits, and how it ended
#   transcripts/  the session transcripts, moved out of the config dir - which is a fixed
#                 path the NEXT run wipes, so this is the only copy that outlives the run
#
# The two halves get their own subdirectories because pin-instrument.sh and seed-run.sh
# each refuse a run-dir that already exists - a guard worth keeping, so they are given
# one directory each rather than being loosened to share.

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

# Usage: end_run <config_dir> <work_dir>  - the ONE exit handler
#
# Every exit path - success, a failed assertion, a dead session, the wall-clock ceiling -
# leaves the same state behind: the session ended, so the agent cannot keep working after
# loop.json is the final record, and then the transcripts moved out of the config dir.
# The status is the one the script was exiting with; a capture that fails replaces it
# with failure on purpose, because the transcripts are the record and a run whose record
# did not land is not a success. [LAW:no-silent-failure]
end_run() {
  local status=$? config_dir="$1" work_dir="$2"
  # Each in a subshell, so a die in one cannot end the handler before the other runs;
  # either failing is a failed run.
  ( horizon_release_run_lock ) || status=1
  ( horizon_capture_transcripts "$config_dir" "$work_dir" ) || status=1
  exit "$status"
}

main() {
  local seed_dir="${1:-$SCRIPT_DIR/seeds/macklebox}" memento_ref="${2:-}"

  horizon_need_base
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
  printf -v trap_cmd 'end_run %q %q' "$config_dir" "$HORIZON_WORK_DIR"
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
  "$SCRIPT_DIR/pin-instrument.sh" "$instrument_dir" ${memento_ref:+"$memento_ref"} \
    || horizon_die "pin-instrument.sh failed"

  # Here, under the lock, and not inside the pin: this is the one shared thing the pin
  # would otherwise touch, and the lock is what makes wiping it safe. [LAW:single-enforcer]
  horizon_log "rebuilding the config dir from the pinned snapshot"
  horizon_provision_config_dir "$config_dir" "$instrument_dir/pinned"

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

  horizon_log "recording unattended boot state"
  horizon_write_boot_state "$config_dir" "$project_dir"

  horizon_log "launching session one"
  horizon_launch_session "$config_dir" "$project_dir"
  horizon_wait_ready
  # The isolation guarantee, checked rather than assumed - see horizon_assert_transport.
  horizon_assert_transport
  horizon_log "handoff transport verified: in-place reset, config dir preserved"

  # The pinned wording is RE-ISSUED FROM THE COMMIT THE MANIFEST NAMES, never retyped
  # here and never read from the working tree. manifest.json records goal_wording.sha256
  # at that commit; taking the bytes from anywhere else would let a run report a
  # controlled variable it did not actually use. [LAW:one-source-of-truth]
  local repo_root goal_sha
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  goal_sha="$(horizon_manifest_field "$instrument_dir/manifest.json" goal_wording ref)"
  horizon_goal_wording_file "$repo_root" "$goal_sha" "$goal_file"

  horizon_log "issuing the pinned /goal wording"
  horizon_send "/goal $(<"$goal_file")"

  horizon_log "run is live; observing until ${HORIZON_TARGET_SESSIONS} sessions of committed work"
  horizon_observe "$config_dir" "$project_dir" "$goal_file" \
    "$HORIZON_TARGET_SESSIONS" "$HORIZON_MAX_MINUTES" \
    > "$HORIZON_WORK_DIR/loop.json"

  horizon_log "run recorded: $HORIZON_WORK_DIR/loop.json"
}

main "$@"
