#!/usr/bin/env bash
# Run EVERY task in a suite across the given arms with repeats, then print a suite-level grid
# (task x arm pass rates) derived from the outcome records. This is the per-skill eval made
# runnable in one command: same repeated comparison per task, no scoring of its own.
#
# Usage: run-suite.sh <suite_dir> <out_dir> <reps> <config_dir> <config_dir> [...]
#
# [LAW:decomposition] this layer only sequences compare_repeated over the suite's tasks and
#   summarizes; every verdict comes from the task's own criterion via the run machinery.
# [LAW:one-source-of-truth] the grid is DERIVED from the per-repetition outcome records on disk -
#   the same records the per-task tables were printed from - never a second tally kept alongside.
# [LAW:no-silent-failure] a task whose comparison had any aborted repetition marks the suite run
#   failed (nonzero exit) and its cell with '!', but the remaining tasks still run: one broken
#   task must not silently discard the datapoints of the others, and must never pass unnoticed.
# `set -e` is intentionally omitted (as in the sibling verify scripts): a failing comparison must
# be recorded and the loop continue, not abort the suite.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../compare/lib.sh
source "$HERE/../compare/lib.sh"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -ge 4 ] || suite_die "usage: run-suite.sh <suite_dir> <out_dir> <reps> <config_dir> <config_dir> [...]"
suite="$1"; out="$2"; reps="$3"; shift 3
# Reject a garbage reps NOW, through the one definition of the rule, before any dirs or runs
# exist - otherwise every task's comparison would die on it one by one and the grid loop would
# render a misleading 0/<garbage> table. [LAW:no-silent-failure]
cmp_reps_validate "$reps"

# Capture, then split: mapfile over a process substitution would discard suite_validate's exit
# status, letting a malformed suite fall through to a misleading secondary error.
# [LAW:no-silent-failure]
resolved="$(suite_validate "$suite")" || exit $?
mapfile -t TASKS <<< "$resolved"
[ "${#TASKS[@]}" -gt 0 ] || suite_die "suite resolved to no tasks: $suite"
[ ! -e "$out" ] || suite_die "out dir already exists: $out (refusing to overwrite)"
mkdir -p "$out" || suite_die "could not create out dir: $out"
suite_log "suite $(basename "$suite"): ${#TASKS[@]} task(s), $reps repetition(s), $# arm(s)"

suite_failed=0
for task in "${TASKS[@]}"; do
  name="$(basename "$task")"
  printf '\n==== suite task: %s ====\n' "$name" >&2
  # Contain each task's comparison in a subshell so an aborting comparison (cmp_die exits) is
  # recorded here and the suite continues to the next task. compare_repeated itself already
  # surfaces per-repetition aborts and returns nonzero on any.
  ( compare_repeated "$task" "$out/$name" "$reps" "$@" ) || suite_failed=1
done

# ── The suite grid, derived from the outcome records ────────────────────────────────────
# One row per task, one column per arm; each cell is k/N passed, with '!' when any repetition of
# that cell aborted (its record is missing or garbled - counted, never dropped).
printf '\n===== SUITE SUMMARY: %s =====\n' "$(basename "$suite")" >&2
{
  printf '%-28s' "TASK"
  for config in "$@"; do printf ' %-18s' "$(basename "$config")"; done
  printf '\n%-28s' "----------------------------"
  for config in "$@"; do printf ' %-18s' "------------------"; done
  printf '\n'
  for task in "${TASKS[@]}"; do
    name="$(basename "$task")"
    printf '%-28s' "$name"
    for config in "$@"; do
      arm="$(basename "$config")"
      passed=0; aborted=0
      for ((i = 1; i <= reps; i++)); do
        rec="$out/$name/$arm/rep-$(printf '%02d' "$i")/outcome.json"
        if [ -f "$rec" ]; then
          case "$(cmp_verdict_of "$rec")" in
            pass) passed=$((passed + 1)) ;;
            fail) : ;;
            *) aborted=$((aborted + 1)) ;;
          esac
        else
          aborted=$((aborted + 1))
        fi
      done
      printf ' %-18s' "$passed/$reps$([ "$aborted" -gt 0 ] && printf ' (%d!)' "$aborted")"
    done
    printf '\n'
  done
} >&2
printf '\nRead a cross-arm difference as real only if it exceeds an arm'\''s own run-to-run spread over these %s repetitions.\n' "$reps" >&2

if [ "$suite_failed" -ne 0 ]; then
  printf 'SUITE RUN FAILED - at least one repetition aborted (cells marked !); records under %s\n' "$out" >&2
  exit 1
fi
printf 'SUITE RUN OK - records under %s\n' "$out" >&2
