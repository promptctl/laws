#!/usr/bin/env bash
# Prove the suite format and every suite in it - statically, no LLM runs. For EACH suite
# directory (any dir here holding a manifest.sh): it validates, resolves to at least one task,
# and every resolved member is itself a valid task spec (suite_validate already refuses
# otherwise). Then prove the failure arms with fabricated suites: a missing member, an empty
# task list, a duplicate member, and a smuggled arm field each abort nonzero - a malformed suite
# can never yield a silently shorter or doubled run.
#
# [LAW:dataflow-not-control-flow] one loop over discovered suites; the failure arms are a
#   data-driven table of (name, manifest text) cases, one assertion body.
# [LAW:no-silent-failure] every unexpected outcome is a recorded FAIL, and the script exits
#   nonzero if any check failed.
# `set -e` intentionally omitted (as in the sibling verifiers): a failing check must be recorded
# and the remaining checks continue.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

# ── Every real suite validates and resolves ─────────────────────────────────────────────
found="$(find "$HERE" -mindepth 2 -maxdepth 2 -name manifest.sh -print)" \
  || suite_die "suite discovery (find) failed under $HERE"
[ -n "$found" ] || suite_die "no suite directories found under $HERE"
mapfile -t SUITES < <(printf '%s\n' "$found" | sed 's#/manifest.sh$##' | sort)
suite_log "found ${#SUITES[@]} suite(s)"

for suitedir in "${SUITES[@]}"; do
  name="$(basename "$suitedir")"
  printf '\n== suite: %s ==\n' "$name" >&2
  if resolved="$( (suite_validate "$suitedir") 2>"$WORK/verr" )"; then
    count="$(printf '%s\n' "$resolved" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "$count" -ge 1 ]; then
      pass "$name: validates and resolves to $count task(s)"
    else
      fail "$name: validated but resolved to no tasks"
    fi
  else
    fail "$name: does not validate — $(head -1 "$WORK/verr")"
  fi
done

# ── The failure arms (fabricated suites, each must abort with ITS OWN violation) ────────
# The arms run against a fabricated tasks root with a hermetic dummy task, never the real task
# inventory - so removing or renaming a real task cannot silently shift which error path a case
# exercises. And each case asserts the SPECIFIC violation message, not merely "something
# aborted": without that, the duplicate case degrading into a missing-member abort would still
# look green while the duplicate-detection path went untested. [LAW:locality-or-seam]
printf '\n== failure arms ==\n' >&2

# The dummy task must pass task_validate, whose reachability probe hits TASK_REPO - so back it
# with a local file:// git repo and the checks stay offline-stable.
dummy_repo="$WORK/dummy-repo"
git init --quiet "$dummy_repo" \
  && git -C "$dummy_repo" -c user.email=v@v -c user.name=v commit --quiet --allow-empty -m init \
  || suite_die "could not fabricate the dummy git repo"
FAKE_ROOT="$WORK/fake-tasks"
mkdir -p "$FAKE_ROOT/dummy-task"
printf 'TASK_REPO="file://%s"\nTASK_COMMIT="HEAD"\nTASK_SUMMARY="dummy"\n' "$dummy_repo" \
  > "$FAKE_ROOT/dummy-task/manifest.sh"
printf 'dummy prompt\n' > "$FAKE_ROOT/dummy-task/prompt.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ROOT/dummy-task/check.sh"
chmod +x "$FAKE_ROOT/dummy-task/check.sh"

declare -A BAD_MANIFESTS=(
  [missing-member]='SUITE_SUMMARY="bad"
SUITE_TASKS="no-such-task-anywhere"'
  [empty-tasks]='SUITE_SUMMARY="bad"
SUITE_TASKS=""'
  [duplicate-member]='SUITE_SUMMARY="bad"
SUITE_TASKS="dummy-task dummy-task"'
  [smuggled-arm]='SUITE_SUMMARY="bad"
SUITE_TASKS="dummy-task"
CONFIG_REF="deadbeef"'
)
declare -A EXPECTED_ERROR=(
  [missing-member]='does not exist under'
  [empty-tasks]='sets no SUITE_TASKS'
  [duplicate-member]='duplicate suite member'
  [smuggled-arm]='configuration/arm field'
)
for case in missing-member empty-tasks duplicate-member smuggled-arm; do
  dir="$WORK/$case"
  mkdir -p "$dir"
  printf '%s\n' "${BAD_MANIFESTS[$case]}" > "$dir/manifest.sh"
  if ( SUITE_TASKS_ROOT="$FAKE_ROOT" suite_validate "$dir" ) >/dev/null 2>"$WORK/err-$case"; then
    fail "failure arm '$case' was accepted (it must abort)"
  elif grep -q "${EXPECTED_ERROR[$case]}" "$WORK/err-$case"; then
    pass "failure arm '$case' aborts with its own violation: $(head -1 "$WORK/err-$case")"
  else
    fail "failure arm '$case' aborted with the WRONG violation (expected '${EXPECTED_ERROR[$case]}'): $(head -1 "$WORK/err-$case")"
  fi
done

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'SUITES OK - %d suite(s) validate; all failure arms abort\n' "${#SUITES[@]}" >&2
  exit 0
fi
printf 'SUITES FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
