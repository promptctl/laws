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
# [memento-ref]  git ref to pin memento and the /goal wording at, passed straight to
#                pin-instrument.sh. Defaults to HORIZON_MEMENTO_DEFAULT_REF, a fixed
#                commit rather than HEAD - lib.sh says why. A campaign pins it
#                explicitly on every run.
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
#   loop.json     what this run observed: sessions, their commits, and how it ended
#   transcripts/  the session transcripts, copied out of the config dir - which is a fixed
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

main() {
  local seed_dir="${1:-$SCRIPT_DIR/seeds/macklebox}" memento_ref="${2:-}"

  horizon_need_base
  horizon_need git
  horizon_need lit
  horizon_need python3
  horizon_need claude
  # Reached only from the loop primitives in lib.sh, so declared here rather than in
  # HORIZON_BASE_TOOLS: seeding and pinning do not drive a terminal, and making them
  # require tmux would fail those scripts on a machine that never needed it.
  horizon_need tmux
  horizon_need ps
  horizon_need grep
  horizon_need basename
  # Reached from horizon_bind_remote.
  horizon_need gh

  [ -d "$seed_dir" ] || horizon_die "no such seed bundle: $seed_dir"
  seed_dir="$(cd "$seed_dir" && pwd)"

  # A stale run is refused rather than merged into or silently cleared: its transcripts
  # and commits are the only record of whatever happened last time, and this script
  # cannot know whether they have been archived yet.
  [ -e "$HORIZON_WORK_DIR" ] \
    && horizon_die "work dir already holds a run: $HORIZON_WORK_DIR
Archive it (copy it wherever you are keeping runs) and remove it, then start this one."

  mkdir -p "$HORIZON_WORK_DIR" || horizon_die "could not create work dir: $HORIZON_WORK_DIR"
  HORIZON_WORK_DIR="$(cd "$HORIZON_WORK_DIR" && pwd)"

  local instrument_dir="$HORIZON_WORK_DIR/instrument"
  local seed_out_dir="$HORIZON_WORK_DIR/seed"
  local config_dir="$HORIZON_CONFIG_DIR"

  # ONE exit handler, installed the moment there is a work dir to write into, because
  # every later exit path - success, a failed assertion, a dead session, the wall-clock
  # ceiling - has to leave the same record behind. Registering it here rather than at the
  # end is the difference between "the run's transcripts are kept" and "the transcripts of
  # runs that happened to finish are kept". The temp files are retired by the same handler
  # so there is only ever one EXIT trap to reason about; a second `trap ... EXIT` anywhere
  # below would silently replace this one rather than adding to it.
  # shellcheck disable=SC2064
  trap "horizon_capture_transcripts '$config_dir' '$HORIZON_WORK_DIR'
        rm -f \"\$HORIZON_GOAL_FILE\" \"\$HORIZON_ISSUE_FILE\"" EXIT

  horizon_log "pinning the instrument"
  "$SCRIPT_DIR/pin-instrument.sh" "$instrument_dir" ${memento_ref:+"$memento_ref"} \
    || horizon_die "pin-instrument.sh failed"

  horizon_log "seeding time zero from $(basename "$seed_dir")"
  "$SCRIPT_DIR/seed-run.sh" "$seed_out_dir" "$seed_dir" \
    || horizon_die "seed-run.sh failed"

  local project_dir
  project_dir="$seed_out_dir/$(basename "$seed_dir")"
  [ -d "$project_dir" ] || horizon_die "seeding produced no project at $project_dir"

  # After seeding, because `lit init` adopts a backlog from any remote it finds - a
  # project that already had an origin would start from that remote's backlog instead of
  # the seed's. seed-run.sh attaches no remotes, so that ordering holds by construction
  # rather than by this line staying where it is.
  horizon_log "binding the run to $HORIZON_RUN_REPO"
  horizon_bind_remote "$project_dir"

  # Asserted before the session exists, not after it hangs: an unauthenticated config dir
  # boots to a login prompt, which in an unattended run is indistinguishable from an
  # agent thinking hard.
  horizon_log "checking the pinned config dir can authenticate"
  horizon_assert_authenticated "$config_dir"

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
  # Globals, not locals, and no trap of their own: the single EXIT handler installed above
  # retires them, and a handler cannot read a function-scoped variable at exit time.
  local repo_root memento_sha
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  memento_sha="$(horizon_manifest_memento_ref "$instrument_dir/manifest.json")"
  HORIZON_GOAL_FILE="$(mktemp)" || horizon_die "could not create a temp file for the goal wording"
  HORIZON_ISSUE_FILE="$(mktemp)" || horizon_die "could not create a temp file for the goal"
  horizon_goal_wording_file "$repo_root" "$memento_sha" "$HORIZON_GOAL_FILE"
  { printf '/goal '; cat "$HORIZON_GOAL_FILE"; } > "$HORIZON_ISSUE_FILE" \
    || horizon_die "could not assemble the goal to issue"

  horizon_log "issuing the pinned /goal wording"
  horizon_send "$HORIZON_ISSUE_FILE"

  horizon_log "run is live; observing until ${HORIZON_TARGET_SESSIONS} sessions of committed work"
  horizon_observe "$config_dir" "$project_dir" "$HORIZON_GOAL_FILE" \
    "$HORIZON_TARGET_SESSIONS" "$HORIZON_MAX_MINUTES" \
    > "$HORIZON_WORK_DIR/loop.json"

  horizon_log "run recorded: $HORIZON_WORK_DIR/loop.json"
}

main "$@"
