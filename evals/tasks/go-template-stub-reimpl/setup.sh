#!/usr/bin/env bash
# Establish the STARTING state: replace two helper implementations with throwing stubs, keeping
# each file's exported signature. Runs with CWD = the repo checkout. The helpers were chosen for
# their coverage - unit tests plus conformance fixtures and integration tests the reimplementer
# never sees named in the prompt - so a shallow reimplementation is caught mechanically.
# [LAW:no-silent-failure] Verify each stub actually landed; a stub that did not apply would leave
# the "defect" state passing and silently invalidate the task.
set -euo pipefail

target="src/sprig/strings/splitn.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `splitn sep n s` — split `s` on `sep` into at most `n` parts and
 * return a `{_0, _1, …}` map. Mirrors Go sprig's splitn, which is
 * built on Go's `strings.SplitN`.
 */
export function splitn(sep: string, n: number, s: string): Record<string, string> {
  throw new Error("not implemented");
}
EOF

target="src/sprig/dicts/merge.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `merge dst src1 src2 …` — copies missing keys from sources into dst,
 * leaving dst's existing keys untouched. Returns a new dict.
 */
export function merge(
  dst: Record<string, unknown>,
  ...sources: Record<string, unknown>[]
): Record<string, unknown> {
  throw new Error("not implemented");
}
EOF

grep -q 'not implemented' src/sprig/strings/splitn.ts \
  || { echo "setup: stub did not apply to src/sprig/strings/splitn.ts" >&2; exit 2; }
grep -q 'not implemented' src/sprig/dicts/merge.ts \
  || { echo "setup: stub did not apply to src/sprig/dicts/merge.ts" >&2; exit 2; }
echo "setup: gutted splitn and merge to throwing stubs"
