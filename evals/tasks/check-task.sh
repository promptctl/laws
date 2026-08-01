#!/usr/bin/env bash
# Run a task's criterion against an already-prepared repo state and report the verdict.
# [LAW:cli] exit code is the contract: 0 = criterion PASSED, 1 = criterion FAILED, and any other
# nonzero (via task_die) = the harness itself could not run the check - never a fabricated verdict.
# Usage: check-task.sh <task_dir> <state_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -eq 2 ] || task_die "usage: check-task.sh <task_dir> <state_dir>"
if task_check "$1" "$2"; then
  printf 'PASS: %s against %s\n' "$1" "$2"
  exit 0
else
  printf 'FAIL: %s against %s\n' "$1" "$2"
  exit 1
fi
