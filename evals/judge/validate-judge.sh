#!/usr/bin/env bash
# Calibrate a judge against its human-labelled held set and report the agreement rate.
# [LAW:cli] 0 = agreement meets the bar (the judge may be trusted), nonzero = below the bar
# (unvalidated) or the judge could not run.
# Usage: validate-judge.sh <judge_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
[ "$#" -eq 1 ] || judge_die "usage: validate-judge.sh <judge_dir>"
if judge_validate "$1"; then echo "VALIDATED: agreement meets the ${JUDGE_AGREEMENT_BAR}% bar"; else
  echo "UNVALIDATED: agreement below the ${JUDGE_AGREEMENT_BAR}% bar"; exit 1; fi
