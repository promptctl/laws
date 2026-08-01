#!/usr/bin/env bash
# Prove the repeated comparison against a LIVE Opus session. One repeated comparison over two arms
# with N=2 repetitions each - a skill arm and an arm whose runs are forced to abort - demonstrates
# the whole done-claim. Exits 0 iff:
#   1. per arm, the outcomes of all N runs are reported plus a spread summary (k of N passed) - and
#      the skill arm's two runs form a visible same-arm spread;
#   2. an aborted repetition appears as a FAILED run in the count (never inflating the pass rate)
#      and forces a nonzero overall exit.
#
# [LAW:verifiable-goals] scored by the task's own criterion; this runs the check.
# [LAW:no-silent-failure] an aborted rep counted as a pass, or not surfaced, is a hard failure here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

TASK="$HERE/../tasks/go-template-add-fix"
ARM_A="$HERE/../configs/code-ref-a"
REPS=2

# An arm whose every repetition aborts (a ref that does not exist).
BADARM="$WORK/bad-ref-arm"; mkdir -p "$BADARM"
cat > "$BADARM/manifest.sh" <<'EOF'
CONFIG_SKILL="code"
CONFIG_REF="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
CONFIG_SUMMARY="a ref that does not exist - every repetition must abort"
EOF

echo "== repeated comparison: 2 arms x $REPS reps (skill arm, forced-abort arm) ==" >&2
out="$WORK/rep"
if compare_repeated "$TASK" "$out" "$REPS" "$ARM_A" "$BADARM" 2>"$WORK/report.txt"; then
  fail "repeated comparison exited 0 but an arm's reps were forced to abort (expected nonzero)"
else
  pass "an aborted repetition forces a nonzero overall exit"
fi
cat "$WORK/report.txt" >&2

# Skill arm: both repetitions produced real pass outcomes -> a visible same-arm spread (2/2).
va1="$(grep -o '"verdict": *"[^"]*"' "$out/code-ref-a/rep-01/outcome.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"
va2="$(grep -o '"verdict": *"[^"]*"' "$out/code-ref-a/rep-02/outcome.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"
[ "$va1" = "pass" ] && [ "$va2" = "pass" ] && pass "skill arm: both repetitions passed (same-arm spread 2/2 visible)" || fail "skill arm reps = [$va1,$va2], expected pass,pass"

# The report shows each arm's per-run outcomes and a k/N pass-rate summary.
grep -qE '^  run 01: ' "$WORK/report.txt" && grep -qE '^  run 02: ' "$WORK/report.txt" && pass "per-run outcomes reported for each repetition" || fail "per-run outcomes not reported"
grep -qE 'code-ref-a .* 2/2' "$WORK/report.txt" && pass "skill arm pass rate summarized as 2/2" || fail "skill arm pass rate not summarized as 2/2"

# Aborted arm: no outcome records, counted as 0/2 with the aborts surfaced - never inflated.
[ ! -f "$out/bad-ref-arm/rep-01/outcome.json" ] && [ ! -f "$out/bad-ref-arm/rep-02/outcome.json" ] \
  && pass "aborted arm left NO outcome records (no fabricated pass)" || fail "aborted arm left an outcome record"
grep -qE 'bad-ref-arm .* 0/2 \(2 aborted\)' "$WORK/report.txt" && pass "aborted reps counted as failures (0/2, 2 aborted), not inflated" || fail "aborted reps not counted correctly"

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'REPEATED OK - each arm reports its outcomes across N reps and a pass-rate spread; aborted reps are failures, never a fabricated pass\n' >&2
  exit 0
fi
printf 'REPEATED FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
