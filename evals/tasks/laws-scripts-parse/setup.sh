#!/usr/bin/env bash
# Establish the STARTING state: inject a syntax error into one eval script so it no longer parses.
# Runs with CWD = the repo checkout. Append an unterminated `if` - enough to make `bash -n` fail -
# to a script that is not itself the criterion's own target ambiguity.
# [LAW:no-silent-failure] verify the breakage actually took, or the "defect" state would parse
# fine and silently invalidate the task.
set -euo pipefail

target="evals/driver/drive.sh"
[ -f "$target" ] || { echo "setup: expected script not found: $target" >&2; exit 1; }

printf '\nif then\n' >> "$target"   # a syntactically broken fragment: `if` with no condition

! bash -n "$target" 2>/dev/null || { echo "setup: injected fragment did not break parsing of $target" >&2; exit 1; }
echo "setup: injected a syntax error into $target"
