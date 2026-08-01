#!/usr/bin/env bash
# Validate a task directory against the format. Exit 0 iff it is a well-formed task spec.
# [LAW:cli] exit code is the contract: 0 = valid, nonzero = the first violation (named on stderr).
# Usage: validate-task.sh <task_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -eq 1 ] || task_die "usage: validate-task.sh <task_dir>"
out="$(task_validate "$1")"   # aborts nonzero on any violation
printf 'VALID: %s\n' "$1"
printf '  repo:    %s\n' "$(printf '%s' "$out" | sed -n '1p')"
printf '  commit:  %s\n' "$(printf '%s' "$out" | sed -n '2p')"
printf '  summary: %s\n' "$(printf '%s' "$out" | sed -n '3p')"
