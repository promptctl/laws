#!/usr/bin/env bash
# Establish the STARTING state: inject three regressions in three separate areas of the library
# (conversions, lists, strings). Runs with CWD = the repo checkout. Each mutation was verified
# against the pinned commit to be caught by the repo's own test suite - a defect the criterion
# cannot see would silently invalidate the task.
# [LAW:no-silent-failure] Verify every mutation actually landed; a regression that did not apply
# would leave the "defect" state passing.
set -euo pipefail

# atoi: drop '-' from the accepted-sign class, so negative integers parse to 0.
target="src/sprig/conversions/atoi.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
perl -0pi -e 's/\^\[\+-\]\?/^[+]?/' "$target"
grep -q '\^\[+\]?' "$target" || { echo "setup: regression did not apply to $target" >&2; exit 2; }

# chunk: shorten every chunk by one element.
target="src/sprig/lists/chunk.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
perl -0pi -e 's/list\.slice\(i, i \+ n\)/list.slice(i, i + n - 1)/' "$target"
grep -q 'i + n - 1' "$target" || { echo "setup: regression did not apply to $target" >&2; exit 2; }

# trunc: negative N takes the FIRST |N| chars instead of the last |N|.
target="src/sprig/strings/trunc.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
perl -0pi -e 's/return k >= s\.length \? s : s\.slice\(s\.length - k\);/return k >= s.length ? s : s.slice(0, k);/' "$target"
grep -q 's\.slice(0, k)' "$target" || { echo "setup: regression did not apply to $target" >&2; exit 2; }

echo "setup: injected three regressions (atoi sign, chunk size, trunc negative-N)"
