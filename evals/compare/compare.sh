#!/usr/bin/env bash
# One command: run the identical task across two or more configurations and report which arm did
# better by the task's own criterion.
# [LAW:cli] exit code is the contract: 0 = every arm produced a real outcome, nonzero = at least
# one arm's run aborted (shown as FAILED in the table) - never a fabricated score for it.
# Usage: compare.sh <task_dir> <out_dir> <config_dir> <config_dir> [<config_dir> ...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -ge 3 ] || cmp_die "usage: compare.sh <task_dir> <out_dir> <config_dir> <config_dir> [...]"
task="$1"; out="$2"; shift 2
compare_task "$task" "$out" "$@"
