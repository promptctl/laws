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
#                pin-instrument.sh. Defaults to this repo's HEAD; a campaign pins it
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
  # Reached from horizon_create_remote and from the run's own repo naming below.
  horizon_need gh
  horizon_need date

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

  horizon_log "pinning the instrument"
  "$SCRIPT_DIR/pin-instrument.sh" "$instrument_dir" ${memento_ref:+"$memento_ref"} \
    || horizon_die "pin-instrument.sh failed"

  horizon_log "seeding time zero from $(basename "$seed_dir")"
  "$SCRIPT_DIR/seed-run.sh" "$seed_out_dir" "$seed_dir" \
    || horizon_die "seed-run.sh failed"

  local project_dir
  project_dir="$seed_out_dir/$(basename "$seed_dir")"
  [ -d "$project_dir" ] || horizon_die "seeding produced no project at $project_dir"

  # The run's own GitHub repo, created only now that seeding is finished - see
  # horizon_create_remote for why the order is not negotiable. The name carries the run's
  # start time because it is the one thing that distinguishes two runs of the same seed,
  # and reading the clock is an effect, so it happens out here at the edge rather than
  # inside the library. [LAW:effects-at-boundaries]
  local repo_name
  repo_name="horizon-run-$(date -u +%Y%m%dT%H%M%SZ)" \
    || horizon_die "could not read the clock to name the run's repo"
  horizon_log "creating the run's repo: ${HORIZON_RUN_REPO_OWNER}/${repo_name}"
  horizon_create_remote "$project_dir" "$repo_name"

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
  local repo_root memento_sha goal_file issue_file
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  memento_sha="$(horizon_manifest_memento_ref "$instrument_dir/manifest.json")"
  goal_file="$(mktemp)" || horizon_die "could not create a temp file for the goal wording"
  issue_file="$(mktemp)" || horizon_die "could not create a temp file for the goal"
  # shellcheck disable=SC2064
  trap "rm -f '$goal_file' '$issue_file'" EXIT
  horizon_goal_wording_file "$repo_root" "$memento_sha" "$goal_file"
  { printf '/goal '; cat "$goal_file"; } > "$issue_file" \
    || horizon_die "could not assemble the goal to issue"

  horizon_log "issuing the pinned /goal wording"
  horizon_send "$issue_file"

  horizon_log "run is live; observing until ${HORIZON_TARGET_SESSIONS} sessions of committed work"
  horizon_observe "$config_dir" "$project_dir" "$goal_file" \
    "$HORIZON_TARGET_SESSIONS" "$HORIZON_MAX_MINUTES" \
    > "$HORIZON_WORK_DIR/loop.json"

  horizon_log "run recorded: $HORIZON_WORK_DIR/loop.json"
}

main "$@"
