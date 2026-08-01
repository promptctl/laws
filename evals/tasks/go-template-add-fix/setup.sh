#!/usr/bin/env bash
# Establish the STARTING state: inject the regression the agent must fix. Runs with CWD = the
# repo checkout. The Sprig add() sums its args (`acc + v`); flip it to `acc - v` so add(1,2,3)
# returns -6 and the test suite fails. A correct fix restores the sum.
# [LAW:no-silent-failure] Verify the edit actually landed; a regression that did not apply would
# leave the "defect" state passing and silently invalidate the task.
set -euo pipefail

target="src/sprig/math/add.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 1; }

# Turn the reducer's "+ v" into "- v". Anchored to the exact reduce expression so it can only
# match the intended line.
perl -0pi -e 's/\(acc, v\) => acc \+ v/(acc, v) => acc - v/' "$target"

grep -q '=> acc - v' "$target" || { echo "setup: regression did not apply to $target" >&2; exit 1; }
echo "setup: injected regression into $target (add now subtracts)"
