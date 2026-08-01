#!/usr/bin/env bash
# Run a task across arms with N repetitions each and report each arm's pass rate over its reps, so
# the harness's own run-to-run noise is visible before a cross-arm difference is trusted.
# [LAW:cli] exit code is the contract: 0 = every repetition of every arm produced a real outcome,
# nonzero = at least one repetition aborted (a FAILED run in the count) - never a fabricated pass.
# Usage: compare-repeated.sh <task_dir> <out_dir> <reps> <config_dir> [<config_dir> ...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -ge 4 ] || cmp_die "usage: compare-repeated.sh <task_dir> <out_dir> <reps> <config_dir> [<config_dir> ...]"
task="$1"; out="$2"; reps="$3"; shift 3
compare_repeated "$task" "$out" "$reps" "$@"
