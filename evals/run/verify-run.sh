#!/usr/bin/env bash
# Prove the single scored run against a LIVE Opus session. Exits 0 iff:
#   1. one real run produces exactly one outcome record whose skill_ref equals the arm's git ref,
#      whose verdict is the criterion's real pass/fail (pass, on this task+config known to pass),
#      and whose transcript shows MORE than one turn (genuinely multi-turn, not single-turn);
#   2. forcing a driven turn to fail (a 1-second turn bound) yields a nonzero exit and ZERO
#      outcome records - never a fabricated or partial one.
#
# [LAW:verifiable-goals] the run is scored by the task's own criterion; this script runs the check.
# [LAW:no-silent-failure] a failure arm that leaves a record behind is a hard failure here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

TASK="$HERE/../tasks/go-template-add-fix"
ARM="$HERE/../configs/code-ref-a"      # skill_ref 8f6d15b
EXPECT_REF="8f6d15b"

# ── 1) a real scored run ────────────────────────────────────────────────────────────────
echo "== a real scored run (go-template-add-fix x code-ref-a) ==" >&2
if run_scored "$TASK" "$ARM" "$WORK/run1" >/dev/null; then
  rec="$WORK/run1/outcome.json"
  if [ -f "$rec" ]; then
    pass "one outcome record written"
    ref="$(grep -o '"skill_ref": *"[^"]*"' "$rec" | sed 's/.*"\([^"]*\)"$/\1/')"
    verdict="$(grep -o '"verdict": *"[^"]*"' "$rec" | sed 's/.*"\([^"]*\)"$/\1/')"
    turns="$(grep -o '"turns": *[0-9]*' "$rec" | grep -o '[0-9]*')"
    [ "$ref" = "$EXPECT_REF" ] && pass "skill_ref field = the arm's git ref ($ref)" || fail "skill_ref = [$ref], expected $EXPECT_REF"
    [ "$verdict" = "pass" ] && pass "verdict = the criterion's real pass on a task+config known to pass" || fail "verdict = [$verdict], expected pass"
    [ "${turns:-0}" -gt 1 ] && pass "run consumed more than one turn (turns=$turns, genuinely multi-turn)" || fail "run was not multi-turn (turns=${turns:-0})"
    tmarks="$(grep -c '^===== turn ' "$WORK/run1/transcript.txt" 2>/dev/null || echo 0)"
    [ "${tmarks:-0}" -gt 1 ] && pass "transcript shows multiple exchanges ($tmarks turns)" || fail "transcript does not show multiple exchanges ($tmarks)"
  else
    fail "run exited 0 but wrote no outcome record"
  fi
else
  fail "a real run did not complete (exit nonzero)"
fi

# ── 2) forcing a turn to fail leaves no record ──────────────────────────────────────────
echo "== forcing a driven turn to fail (1-second bound) ==" >&2
if ( RUN_TURN_TIMEOUT_SECS=1 run_scored "$TASK" "$ARM" "$WORK/run2" ) >/dev/null 2>&1; then
  fail "a forced-failure run exited 0 (should abort)"
else
  if [ -f "$WORK/run2/outcome.json" ]; then
    fail "a forced-failure run left an outcome record behind"
  else
    pass "forced turn failure exits nonzero and writes ZERO outcome records"
  fi
fi

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'RUN OK - one scored run produces a real, multi-turn, ground-truth outcome; a failed turn leaves none\n' >&2
  exit 0
fi
printf 'RUN FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
