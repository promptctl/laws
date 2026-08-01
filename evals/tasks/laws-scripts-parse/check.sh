#!/usr/bin/env bash
# THE CRITERION (mechanical-detector shape). Runs with CWD = the repo checkout. Exit 0 = every
# shell script under evals/ parses; nonzero = at least one does not. Ground truth via `bash -n`,
# not a judgment of the work against any skill, law, or rubric.
# Exit codes follow the harness contract: 0 = every script parses, 1 = at least one does not (the
# verdict), 2 = the criterion could NOT run (no evals/ tree) - a harness error, never a fabricated
# FAIL. [LAW:no-silent-failure]
set -euo pipefail

[ -d evals ] || { echo "check: no evals/ directory in the checkout" >&2; exit 2; }

failed=0
while IFS= read -r script; do
  if ! bash -n "$script" 2>/dev/null; then
    echo "check: does not parse: $script" >&2
    failed=1
  fi
done < <(find evals -name '*.sh' -type f | sort)

exit "$failed"
