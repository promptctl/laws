#!/usr/bin/env bash
# Prove the configuration format and its arms. For every configuration directory: validate it,
# then resolve it and assert the resolved body is EXACTLY what git holds at that ref
# (`git show <ref>:<path>`), with the control arm resolving to no body. Then prove the failure
# arms: a bad ref, a bad skill/path, and a smuggled task field each abort nonzero rather than
# yielding an empty or stale body. Exit 0 iff every assertion holds.
#
# [LAW:dataflow-not-control-flow] one loop over the discovered configs; no per-config code.
# [LAW:no-silent-failure] a lookup that should fail but "succeeds" empty is a hard failure here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
ROOT="$(cfg_laws_root)"
fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

# Independently derive the expected body the way the done-claim describes - straight from
# git show <ref>:<path> - and compare the resolver's output to it byte for byte.
expected_body() {
  local ref="$1" skill="$2"
  local craft="skills/$skill/references/craft.md" main="skills/$skill/SKILL.md"
  if git -C "$ROOT" cat-file -e "$ref:$craft" 2>/dev/null; then git -C "$ROOT" show "$ref:$craft"; else git -C "$ROOT" show "$ref:$main"; fi
}

found="$(find "$HERE" -mindepth 2 -maxdepth 2 -name manifest.sh -print)" || cfg_die "config discovery failed"
[ -n "$found" ] || cfg_die "no configuration directories found under $HERE"
mapfile -t CONFIGS < <(printf '%s\n' "$found" | sed 's#/manifest.sh$##' | sort)

for cfg in "${CONFIGS[@]}"; do
  name="$(basename "$cfg")"
  printf '\n== config: %s ==\n' "$name" >&2

  if ( cfg_validate "$cfg" ) 2>"$WORK/verr"; then
    pass "$name: validates against the format"
  else
    fail "$name: does not validate — $(head -1 "$WORK/verr")"; continue
  fi

  # Check both exit codes explicitly: an empty result from a FAILED call must not fall through to
  # the control-arm branch and read as a pass. [LAW:no-silent-failure]
  f="$(cfg_fields "$cfg")" || { fail "$name: cfg_fields failed after validation"; continue; }
  skill="$(printf '%s' "$f" | sed -n '1p')"; ref="$(printf '%s' "$f" | sed -n '2p')"
  if ! body="$(cfg_resolve "$cfg" 2>"$WORK/rerr")"; then
    fail "$name: resolve aborted — $(head -1 "$WORK/rerr")"; continue
  fi
  if [ -z "$skill" ]; then
    if [ -z "$body" ]; then pass "$name: control arm resolves to NO body"; else fail "$name: control arm resolved a non-empty body"; fi
  else
    if [ "$body" = "$(expected_body "$ref" "$skill")" ] && [ -n "$body" ]; then
      pass "$name: resolves to EXACTLY git's body at $ref:skills/$skill (bytes: ${#body})"
    else
      fail "$name: resolved body does not match git show $ref:skills/$skill/…"
    fi
  fi
done

# ── Failure arms (each must abort nonzero, not yield an empty/stale body) ────────────────
printf '\n== failure arms ==\n' >&2
mk() { mkdir -p "$WORK/$1"; printf '%s\n' "$2" > "$WORK/$1/manifest.sh"; printf '%s\n' "$WORK/$1"; }

badref="$(mk badref 'CONFIG_SKILL="code"
CONFIG_REF="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
CONFIG_SUMMARY="bad ref"')"
if ( cfg_resolve "$badref" ) >/dev/null 2>&1; then fail "bad ref: resolve should abort but succeeded"; else pass "bad ref: resolve aborts nonzero (no empty/stale body)"; fi

badskill="$(mk badskill 'CONFIG_SKILL="nosuchskill"
CONFIG_REF="8f6d15b"
CONFIG_SUMMARY="bad skill/path"')"
if ( cfg_resolve "$badskill" ) >/dev/null 2>&1; then fail "bad skill: resolve should abort but succeeded"; else pass "bad skill/path: resolve aborts nonzero"; fi

taskfield="$(mk taskfield 'CONFIG_SKILL="code"
CONFIG_REF="8f6d15b"
CONFIG_SUMMARY="smuggles a task field"
TASK_REPO="https://example.com/x"')"
if ( cfg_validate "$taskfield" ) >/dev/null 2>&1; then fail "task field: validate should reject a config that names a task"; else pass "task field: rejected (config stays orthogonal to task)"; fi

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'CONFIGS OK - %d config(s) resolve exactly, control is empty, failure arms abort\n' "${#CONFIGS[@]}" >&2
  exit 0
fi
printf 'CONFIGS FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
