#!/usr/bin/env bash
# Score one artifact against a judge's reference. Prints "pass"/"fail"; aborts if the judge could
# not run. [LAW:cli] 0 = scored (pass or fail printed), nonzero = the judge could not run.
# Usage: score-judge.sh <judge_dir> <artifact_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
[ "$#" -eq 2 ] || judge_die "usage: score-judge.sh <judge_dir> <artifact_dir>"
judge_score "$1" "$2"
