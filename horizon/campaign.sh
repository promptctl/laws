#!/usr/bin/env bash
# Run a campaign: N runs of one configuration, serially, every controlled variable
# resolved ONCE and handed to every run as a value. (promptctl-horizon-7ry.5)
#
# WHY: a single run's result means nothing on its own. The baseline configuration is run
# several times so that its natural spread is on the record, and a comparison arm is read
# against that spread rather than against one run. The spread is only readable if the
# runs differ in nothing but the agent's own choices, which is what this script exists to
# hold still: run-loop.sh pins an instrument PER RUN, and left to its defaults each run
# resolves memento's default branch, lit's default branch, the reviewer's moving `v1`
# tag and this checkout's HEAD live - so two runs hours apart can legitimately disagree,
# and the manifest would record each one as pinned. [LAW:no-ambient-temporal-coupling]
#
# Usage:
#   horizon/campaign.sh <campaign-dir> [runs] [seed-dir]
#
# <campaign-dir>  where the campaign lives. Created on the first invocation and RESUMED
#                 on every later one: the pins are read back from its campaign.json, the
#                 next run number follows the last run-N/ present, and the loop stops once
#                 [runs] runs exist. A campaign spans many hours and the process driving it
#                 will not always survive that; resuming from the record is what keeps a
#                 restarted campaign the SAME campaign rather than a second one with fresh
#                 pins.
# [runs]          how many runs the campaign wants in total. Defaults to 5.
# [seed-dir]      the seed bundle every run starts from. Defaults to run-loop.sh's default
#                 (the macklebox reference seed). Recorded on the first invocation; a resume
#                 that names a different seed is refused.
#
# What is held constant, and how:
#   memento, lit's plugin, the reviewer, the /goal wording - resolved to shas here on the
#     first invocation, recorded in campaign.json, passed to run-loop.sh on every run.
#   the `lit` binary - its sha256 is taken from PATH at run time and is NOT a function of
#     any ref, so the binary on PATH at the first invocation is COPIED into <campaign>/bin
#     and every run is started with that directory first on PATH. An upgrade landing on the
#     machine mid-campaign cannot reach a run; a resume whose copy no longer matches the
#     recorded hash is refused.
#   Claude Code's version - the version resolved at the first invocation becomes the
#     campaign's HORIZON_CLAUDE_VERSION_PIN, the gate run-loop.sh applies before it creates
#     anything (see lib.sh, horizon_assert_claude_version).
#   the model - HORIZON_CLAUDE_MODEL as it stood at the first invocation, handed to every
#     run so a resume from a different shell cannot move it.
#   the budget - HORIZON_MAX_MINUTES and HORIZON_TARGET_SESSIONS, recorded once so every
#     run has the same ceiling. The defaults here are the campaign's, set against the .3
#     acceptance attempts (one ticket carried to a merged PR in ~22 minutes on the
#     reference seed, whose backlog is 4 epics and 15 tickets): 600 minutes of wall clock, and a session
#     target past what the backlog can produce, so that the run ends when the backlog is
#     complete (horizon_observe's natural end) rather than at a session count.
#
# What is NOT held constant, and is recorded instead: the driver itself. run-loop.sh and
# lib.sh run from this working tree, and campaign.json records the tree's commit and
# whether it was dirty, per run, so a reader can see whether the driver moved. Drive a
# campaign from a checkout nothing else is switching.
#
# Each run's bundle is moved from HORIZON_WORK_DIR into <campaign>/run-N/ the moment its
# driver exits, whatever the exit was - a run the driver refused before it created a work
# dir leaves no bundle, and that ends the campaign rather than looping on a refusal. The
# driver's own log and exit status go beside the bundle, in run-N.log and
# run-N.outcome.json, outside the bundle so its declared layout stays exactly what
# verify-bundle.sh checks. campaign-index.py renders every run into index.json and
# index.md: a DESCRIPTIVE index, never a verdict. [LAW:no-silent-failure]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${HORIZON_MAX_MINUTES:=600}"
: "${HORIZON_TARGET_SESSIONS:=40}"

# campaign.json is read through horizon_manifest_field, the one JSON field reader in
# horizon/: every value it holds sits under a section (seed, pins, budget) for exactly
# that reason, so a second reader with its own idea of an absent value never exists.
# [LAW:one-source-of-truth]
CAMPAIGN_RECORD="campaign.json"

# Usage: campaign_driver_commit  -> "<sha> <clean|dirty>" for the tree the driver runs from
campaign_driver_commit() {
  local repo_root sha state
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  sha="$(git -C "$repo_root" rev-parse --verify HEAD)" \
    || horizon_die "could not read the driver checkout's HEAD"
  if [ -z "$(git -C "$repo_root" status --porcelain -- horizon)" ]; then
    state=clean
  else
    state=dirty
  fi
  printf '%s %s\n' "$sha" "$state"
}

# Usage: campaign_next_run_number <campaign_dir>  -> 1 + the highest run-N present
campaign_next_run_number() {
  local dir="$1" highest=0 entry n
  for entry in "$dir"/run-*; do
    [ -e "$entry" ] || continue
    n="${entry##*/run-}"
    case "$n" in
      *[!0-9]*) continue ;;
    esac
    [ "$n" -gt "$highest" ] && highest="$n"
  done
  printf '%s\n' $((highest + 1))
}

# Usage: campaign_create <campaign_dir> <seed_dir>  - resolve every pin once and record it
campaign_create() {
  local dir="$1" seed_dir="$2"
  local refs memento_sha lit_sha reviewer_sha goal_ref lit_path lit_sha256 claude_path claude_version

  # Every pin is resolved and every hash taken BEFORE $dir is touched: a fetch or a gh
  # call that fails part-way would otherwise leave a directory with bin/ and no
  # campaign.json, which the next invocation refuses as neither new nor resumable.
  # [LAW:no-silent-failure]
  refs="$(mktemp -d)" || horizon_die "could not create a scratch dir for ref resolution"
  trap 'rm -rf "$refs"' RETURN

  horizon_log "resolving memento once: ${HORIZON_MEMENTO_REPO_URL}@${HORIZON_MEMENTO_DEFAULT_REF}"
  memento_sha="$(horizon_git_fetch "$HORIZON_MEMENTO_REPO_URL" "$refs/memento.git" "$HORIZON_MEMENTO_DEFAULT_REF")"
  horizon_log "resolving lit's plugin once: ${HORIZON_LIT_REPO_URL}@${HORIZON_LIT_DEFAULT_REF}"
  lit_sha="$(horizon_git_fetch "$HORIZON_LIT_REPO_URL" "$refs/lit.git" "$HORIZON_LIT_DEFAULT_REF")"
  horizon_log "resolving the reviewer once: ${REVIEWER_REPO}@${REVIEWER_TAG}"
  reviewer_sha="$(horizon_reviewer_sha)"
  goal_ref="$(horizon_resolve_commit "$(horizon_repo_root "$SCRIPT_DIR")" "HEAD")"
  lit_path="$(horizon_lit_path)"
  lit_sha256="$(horizon_sha256_file "$lit_path")"
  claude_path="$(horizon_claude_path)"
  claude_version="$(horizon_claude_version "$claude_path")"
  horizon_log "Claude Code pinned at $claude_version for the whole campaign"

  # The lit binary, frozen by copying. `cp` rather than a symlink: a symlink would follow
  # the machine's lit through every upgrade, which is the drift this exists to stop. The
  # copy is hashed again rather than trusted: the record names the bytes every run will
  # execute, not the bytes that were on PATH a moment earlier.
  mkdir -p "$dir/bin" || horizon_die "could not create $dir"
  cp "$lit_path" "$dir/bin/lit" || horizon_die "could not copy $lit_path into $dir/bin"
  chmod +x "$dir/bin/lit"
  [ "$(horizon_sha256_file "$dir/bin/lit")" = "$lit_sha256" ] \
    || horizon_die "the copy of lit at $dir/bin/lit does not hash to the binary it was copied from"
  horizon_log "lit frozen at $dir/bin/lit ($lit_sha256)"

  python3 - "$dir/$CAMPAIGN_RECORD" "$seed_dir" "$memento_sha" "$lit_sha" "$reviewer_sha" \
    "$goal_ref" "$lit_sha256" "$claude_version" "$HORIZON_CLAUDE_MODEL" \
    "$HORIZON_MAX_MINUTES" "$HORIZON_TARGET_SESSIONS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'EOF'
import json, sys
(path, seed_dir, memento_sha, lit_sha, reviewer_sha, goal_ref, lit_sha256,
 claude_version, model, max_minutes, target_sessions, created) = sys.argv[1:]
doc = {
    "schema_version": 1,
    "created": created,
    "seed": {"dir": seed_dir},
    "pins": {
        "memento_ref": memento_sha,
        "lit_plugin_ref": lit_sha,
        "reviewer_sha": reviewer_sha,
        "goal_ref": goal_ref,
        "lit_binary_sha256": lit_sha256,
        "claude_version": claude_version,
        "claude_model": model,
    },
    "budget": {
        "max_minutes": int(max_minutes),
        "target_sessions": int(target_sessions),
    },
}
with open(path, "w") as handle:
    json.dump(doc, handle, indent=2, sort_keys=True)
    handle.write("\n")
EOF
  horizon_log "campaign recorded at $dir/$CAMPAIGN_RECORD"
}

# Usage: campaign_assert_resumable <campaign_dir> <seed_dir>  - the machine still matches the record
campaign_assert_resumable() {
  local dir="$1" seed_dir="$2" recorded observed
  recorded="$(horizon_manifest_field "$dir/$CAMPAIGN_RECORD" seed dir)" \
    || horizon_die "could not read the campaign's seed from $dir/$CAMPAIGN_RECORD"
  [ "$recorded" = "$seed_dir" ] \
    || horizon_die "this campaign was seeded from $recorded, not $seed_dir; start a new campaign dir for a different seed"
  [ -x "$dir/bin/lit" ] || horizon_die "the campaign's frozen lit is missing at $dir/bin/lit"
  recorded="$(horizon_manifest_field "$dir/$CAMPAIGN_RECORD" pins lit_binary_sha256)" \
    || horizon_die "could not read the campaign's lit hash from $dir/$CAMPAIGN_RECORD"
  observed="$(horizon_sha256_file "$dir/bin/lit")"
  [ "$recorded" = "$observed" ] \
    || horizon_die "the frozen lit at $dir/bin/lit no longer matches the campaign record ($observed vs $recorded)"
}

# Usage: campaign_run_one <campaign_dir> <number> <seed_dir>  -> the driver's exit status
#
# The driver's stdout and stderr both go to the run log; the bundle is moved into the
# campaign the moment the driver exits, on every exit status, so nothing from this run
# can be mistaken for the next one's.
campaign_run_one() {
  local dir="$1" number="$2" seed_dir="$3"
  local run_dir="$dir/run-$number" log="$dir/run-$number.log" outcome="$dir/run-$number.outcome.json"
  local status=0 started ended driver
  local memento_sha lit_sha reviewer_sha goal_ref version_pin model max_minutes target_sessions

  [ ! -e "$run_dir" ] || horizon_die "run $number already exists at $run_dir"
  # A run the driver REFUSED left a log and an outcome but no bundle, so its number is
  # the next one again on resume - and starting it would truncate the only record of why
  # the campaign stopped. The operator moves those two files aside once they are read.
  [ ! -e "$outcome" ] && [ ! -e "$log" ] \
    || horizon_die "run $number already has a record ($log, $outcome) but no bundle: a refused run. Read it, move it aside, and resume"
  [ ! -e "$HORIZON_WORK_DIR" ] \
    || horizon_die "work dir already holds a run: $HORIZON_WORK_DIR - archive it and remove it first"

  # Each read checked on its own line: a die inside a command substitution exits only the
  # subshell, and an empty value in an env assignment below would be replaced by
  # run-loop.sh's own default without a word. [LAW:no-silent-failure]
  local record="$dir/$CAMPAIGN_RECORD"
  memento_sha="$(horizon_manifest_field "$record" pins memento_ref)" || horizon_die "unreadable pin: memento_ref"
  lit_sha="$(horizon_manifest_field "$record" pins lit_plugin_ref)" || horizon_die "unreadable pin: lit_plugin_ref"
  reviewer_sha="$(horizon_manifest_field "$record" pins reviewer_sha)" || horizon_die "unreadable pin: reviewer_sha"
  goal_ref="$(horizon_manifest_field "$record" pins goal_ref)" || horizon_die "unreadable pin: goal_ref"
  version_pin="$(horizon_manifest_field "$record" pins claude_version)" || horizon_die "unreadable pin: claude_version"
  model="$(horizon_manifest_field "$record" pins claude_model)" || horizon_die "unreadable pin: claude_model"
  max_minutes="$(horizon_manifest_field "$record" budget max_minutes)" || horizon_die "unreadable budget: max_minutes"
  target_sessions="$(horizon_manifest_field "$record" budget target_sessions)" || horizon_die "unreadable budget: target_sessions"
  driver="$(campaign_driver_commit)" || horizon_die "could not read the driver's commit"

  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || horizon_die "could not read the clock"
  horizon_log "run $number starting at $started (driver at $driver)"
  PATH="$dir/bin:$PATH" \
  HORIZON_CLAUDE_VERSION_PIN="$version_pin" \
  HORIZON_CLAUDE_MODEL="$model" \
  HORIZON_MAX_MINUTES="$max_minutes" \
  HORIZON_TARGET_SESSIONS="$target_sessions" \
    "$SCRIPT_DIR/run-loop.sh" "$seed_dir" "$memento_sha" "$lit_sha" "$reviewer_sha" "$goal_ref" \
    >"$log" 2>&1 || status=$?
  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || horizon_die "could not read the clock"
  horizon_log "run $number: driver exited $status at $ended"

  if [ -e "$HORIZON_WORK_DIR" ]; then
    mv "$HORIZON_WORK_DIR" "$run_dir" \
      || horizon_die "could not move $HORIZON_WORK_DIR to $run_dir - the run's bundle is still in the work dir"
  fi

  python3 - "$outcome" "$number" "$status" "$started" "$ended" "$driver" "$log" "$run_dir" <<'EOF'
import json, os, sys
path, number, status, started, ended, driver, log, run_dir = sys.argv[1:]
sha, state = driver.split(" ", 1)
last = None
with open(log, "rb") as handle:
    lines = [l.decode("utf-8", "replace").rstrip("\n") for l in handle if l.strip()]
    last = lines[-1] if lines else None
doc = {
    "run": int(number),
    "driver_exit_status": int(status),
    "started": started,
    "ended": ended,
    "driver": {"commit": sha, "tree": state},
    "bundle_present": os.path.isdir(run_dir),
    "log": os.path.basename(log),
    "last_log_line": last,
}
with open(path, "w") as handle:
    json.dump(doc, handle, indent=2, sort_keys=True)
    handle.write("\n")
EOF
  return "$status"
}

main() {
  local dir="${1:-}" runs="${2:-5}" seed_dir="${3:-$SCRIPT_DIR/seeds/macklebox}"
  [ -n "$dir" ] || horizon_die "usage: campaign.sh <campaign-dir> [runs] [seed-dir]"
  case "$runs" in
    ''|*[!0-9]*|0) horizon_die "[runs] must be a positive integer, not '$runs'" ;;
  esac
  [ -d "$seed_dir" ] || horizon_die "no such seed bundle: $seed_dir"
  seed_dir="$(cd "$seed_dir" && pwd)"
  [[ "$dir" = /* ]] || dir="$PWD/$dir"

  horizon_need_base
  horizon_need git
  horizon_need lit
  horizon_need python3
  horizon_need claude
  horizon_need gh
  horizon_need cp
  horizon_need chmod
  horizon_need mv
  horizon_need date
  horizon_need ls

  if [ -e "$dir/$CAMPAIGN_RECORD" ]; then
    horizon_log "resuming the campaign at $dir"
    campaign_assert_resumable "$dir" "$seed_dir"
  else
    [ ! -e "$dir" ] || [ -z "$(ls -A "$dir")" ] \
      || horizon_die "$dir exists, is not empty, and holds no $CAMPAIGN_RECORD - not a campaign this can resume"
    campaign_create "$dir" "$seed_dir"
  fi

  local number status
  number="$(campaign_next_run_number "$dir")"
  while [ "$number" -le "$runs" ]; do
    status=0
    campaign_run_one "$dir" "$number" "$seed_dir" || status=$?
    # A run that never became live - refused before it created a work dir (an
    # unauthenticated config dir, a held lock, a missing reviewer credential), or refused
    # while pinning or seeding (a fetch that failed) - is not a run, and nothing about the
    # next one would differ, so the campaign stops here and says so rather than spending
    # the remaining slots on the same refusal. A run counts once it was seeded and its
    # close-out wrote run.json; a bundle missing either is a stopped campaign, whatever
    # the driver's exit status. [LAW:no-silent-failure]
    [ -d "$dir/run-$number/seed" ] && [ -f "$dir/run-$number/run.json" ] \
      || horizon_die "run $number never became a run (driver exit $status, no seeded project or no run.json in $dir/run-$number); see $dir/run-$number.log"
    python3 "$SCRIPT_DIR/campaign-index.py" "$dir" \
      || horizon_die "could not render the campaign index after run $number"
    number=$((number + 1))
  done
  horizon_log "campaign complete: $runs run(s) at $dir; index at $dir/index.md"
}

main "$@"
