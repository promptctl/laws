#!/usr/bin/env bash
# Establish the STARTING state: gut seven string helpers to throwing stubs, remove the shared
# case-conversion engine they were built on, and remove every visible test and fixture that
# covers them - so the only route back to green-on-the-criterion is faithful reimplementation,
# not iteration against visible coverage. Each stub keeps its file, exported signature, and the
# doc-contract altitude of the original: the docs are the fair spec surface; the corner cases
# are what the held-out corpus scores.
#
# Also severs every route by which the ORIGINAL implementation could be recovered instead of
# rewritten: the git history (removed), and the package identity (npm name, repo URLs, README)
# that would let an agent fetch the published original. The Go reference (sprig/xstrings) stays
# reachable and named in the docs - consulting the upstream spec is legitimate engineering;
# retrieving the answer verbatim is not the work being measured.
#
# [LAW:no-silent-failure] Verify every mutation actually landed; a stub or deletion that did not
# apply would leave visible coverage (or a recovery route) in place and silently invalidate the
# task's headroom.
set -euo pipefail

# ── Gut the seven helpers (stubs keep signature + doc contract) ─────────────────────────

target="src/sprig/strings/camelcase.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `camelcase s` — port of `xstrings.ToCamelCase`. Note: despite the
 * name, Go sprig's `camelcase` is **PascalCase** — the first letter
 * is uppercased, not lowercased. This is a documented Go-sprig
 * quirk and we preserve it byte-for-byte.
 *
 * Examples (matching the xstrings docstring):
 *   "some_words"      -> "SomeWords"
 *   "http_server"     -> "HttpServer"
 *   "_complex__case_" -> "_Complex_Case_"
 */
export function camelcase(s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/snakecase.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `snakecase s` — port of `xstrings.ToSnakeCase`. Inserts `_` between
 * camelCase/PascalCase word boundaries and rewrites each space, dash,
 * or underscore character to `_`. Runs of upper-case letters release
 * their last character into the next word, so `HTTPServer` becomes
 * `http_server`, not `https_erver`.
 */
export function snakecase(s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/kebabcase.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `kebabcase s` — port of `xstrings.ToKebabCase`. Identical to
 * `snakecase` except the connector is `-`.
 */
export function kebabcase(s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/wrap.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `wrap width s` — soft-wrap `s` to `width` columns at word boundaries.
 * Lines longer than width that contain no spaces are emitted as-is.
 */
export function wrap(width: number, s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/wrapWith.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/** `wrapWith width sep s` — wrap to width using `sep` instead of \n. */
export function wrapWith(width: number, sep: string, s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/abbrev.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/**
 * `abbrev width s` — truncate `s` to `width` chars, replacing the tail
 * with `...` when truncation occurs. Width must be at least 4 to fit
 * the ellipsis; smaller widths return `s` unchanged (Go sprig
 * behavior).
 */
export function abbrev(width: number, s: string): string {
  throw new Error("not implemented");
}
EOF

target="src/sprig/strings/initials.ts"
[ -f "$target" ] || { echo "setup: expected source file not found: $target" >&2; exit 2; }
cat > "$target" <<'EOF'
/** `initials s` — first letter of each whitespace-separated word, uppercased. */
export function initials(s: string): string {
  throw new Error("not implemented");
}
EOF

for f in camelcase snakecase kebabcase wrap wrapWith abbrev initials; do
  grep -q 'not implemented' "src/sprig/strings/$f.ts" \
    || { echo "setup: stub did not apply to src/sprig/strings/$f.ts" >&2; exit 2; }
done

# ── Remove the shared engine and the visible coverage of the gutted helpers ─────────────
# caseUtils.ts is the ported xstrings state machine all three case helpers delegated to -
# leaving it would hand over the entire answer for the corpus's discriminating core.
rm -f src/sprig/strings/caseUtils.ts
if grep -rq 'caseUtils' src; then
  echo "setup: dangling caseUtils references remain in src/" >&2; exit 2
fi

for f in camelcase snakecase kebabcase wrap wrapWith abbrev initials; do
  rm -f "src/sprig/strings/$f.test.ts"
done

for d in sprig-kebabcase-basic sprig-snakecase-http-server sprig-snakecase-pascal \
         sprig-camelcase-pascal-surprise sprig-camelcase-leading-connector; do
  rm -rf "conformance/fixtures/$d"
done

leftover="$(grep -rlE 'camelcase|snakecase|kebabcase|wrapWith|abbrev' conformance/fixtures 2>/dev/null || true)"
[ -z "$leftover" ] || { echo "setup: visible fixtures still exercise gutted helpers: $leftover" >&2; exit 2; }
for f in src/sprig/strings/caseUtils.ts src/sprig/strings/camelcase.test.ts \
         conformance/fixtures/sprig-kebabcase-basic; do
  [ ! -e "$f" ] || { echo "setup: expected deletion did not apply: $f" >&2; exit 2; }
done

# ── Sever recovery routes to the original implementation ───────────────────────────────
# History would let `git show` recover every gutted file; the npm/GitHub identity would let a
# fetch of the published package do the same. The Go upstream named in the docs remains the
# legitimate reference.
rm -rf .git
[ ! -d .git ] || { echo "setup: .git removal did not apply" >&2; exit 2; }

command -v node >/dev/null 2>&1 || { echo "setup: node is required to scrub package.json" >&2; exit 2; }
node -e '
  const fs = require("fs");
  const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  p.name = "gotpl-conformance-port";
  for (const k of ["repository", "homepage", "bugs", "author", "publishConfig", "keywords"]) delete p[k];
  fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
'
if grep -q 'promptctl' package.json; then
  echo "setup: package.json still names the published package" >&2; exit 2
fi

rm -f AGENTS.md CLAUDE.md
cat > README.md <<'EOF'
# gotpl (conformance port)

Go template syntax + a sprig function subset in TypeScript. This library is a conformance
port: helper output matches the Go implementation byte-for-byte, except where a helper's doc
comment documents an intentional divergence — the doc comment is the binding contract.

- `pnpm test` — unit + integration + conformance fixtures
- `pnpm typecheck`
- `pnpm lint`
- `pnpm conformance:regen` — regenerate `conformance/fixtures/*/expected.txt` with the real
  Go implementation (requires a Go toolchain)
EOF

echo "setup: gutted seven string helpers, removed their visible coverage, severed recovery routes"
