#!/usr/bin/env bash
# Take one task and one configuration to a single scored, ground-truth outcome.
# [LAW:cli] exit code is the contract: 0 = one outcome record written (a real verdict), nonzero =
# the run could not be completed and NO record was written - never a partial or fabricated one.
# Usage: run.sh <task_dir> <config_dir> <out_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -eq 3 ] || run_die "usage: run.sh <task_dir> <config_dir> <out_dir>"
run_scored "$1" "$2" "$3"
