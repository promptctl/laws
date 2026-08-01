#!/usr/bin/env bash
# Prove the optional judge tier. All mechanical (no live session): the tier is about STRUCTURE -
# scoring against a reference, tagging validated/unvalidated, calibrating against human labels, and
# never deciding the comparison until validated (and never scoring against the skill).
# Exits 0 iff every check holds.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

JUDGE="$HERE/../judges/output-matches-reference"

# 1) the judge scores an artifact against the reference (produces a verdict)
[ "$(judge_score "$JUDGE" "$JUDGE/cases/case-1")" = "pass" ] && pass "judge scores a matching artifact as pass" || fail "case-1 not scored pass"
[ "$(judge_score "$JUDGE" "$JUDGE/cases/case-2")" = "fail" ] && pass "judge scores a non-matching artifact as fail" || fail "case-2 not scored fail"

# 2) before a validation set: the judge verdict is tagged unvalidated and does NOT decide.
nolabels="$WORK/nolabels-judge"; mkdir -p "$nolabels"
cp "$JUDGE/judge.sh" "$nolabels/"; cp "$JUDGE/reference" "$nolabels/"        # a judge with NO labels.tsv
rep="$(judge_report "$nolabels" "$JUDGE/cases/case-1" "pass" 2>&1)"
printf '%s\n' "$rep" | grep -q 'Primary (programmatic) verdict: pass   \[this decides the comparison\]' \
  && pass "primary programmatic verdict is what decides the comparison" || fail "primary verdict not marked as deciding"
printf '%s\n' "$rep" | grep -q 'unvalidated (no human-label validation set supplied)' \
  && printf '%s\n' "$rep" | grep -q 'does NOT decide the comparison' \
  && pass "without human labels the judge is unvalidated and does not decide" || fail "no-labels judge not tagged unvalidated/non-deciding"

# 3) with human labels: agreement rate is reported and gated by the bar.
if JUDGE_AGREEMENT_BAR=80 judge_validate "$JUDGE" 2>"$WORK/v80.txt"; then
  grep -q '4/5 = 80%' "$WORK/v80.txt" && pass "agreement with human labels reported (4/5 = 80%)" || fail "agreement rate not reported as 4/5=80%"
  pass "a judge meeting the 80% bar validates (may contribute to a verdict)"
else
  fail "judge at 80% agreement should validate against an 80% bar"
fi
if JUDGE_AGREEMENT_BAR=90 judge_validate "$JUDGE" >/dev/null 2>&1; then
  fail "judge at 80% agreement should NOT validate against a 90% bar"
else
  pass "a judge below the bar (80% < 90%) stays unvalidated and cannot contribute"
fi

# 4) a validated judge's report is tagged validated and still marks the programmatic as deciding.
rep2="$(JUDGE_AGREEMENT_BAR=80 judge_report "$JUDGE" "$JUDGE/cases/case-4" "fail" 2>&1)"
printf '%s\n' "$rep2" | grep -q 'validated (agreement 80% >= bar 80%)' && pass "a validated judge is tagged validated with its agreement" || fail "validated judge not tagged"
# case-4: the judge says pass, but a human labelled it fail - the judge is fallible, which is why
# it is secondary. The report must still show the programmatic verdict as the decider.
printf '%s\n' "$rep2" | grep -q 'Secondary (judge) verdict:      pass' && pass "judge's own (fallible) verdict shown as secondary" || fail "judge verdict not shown as secondary"

# 5) the judge never scores against the skill under test - structural. The scorer's CODE (comments
# stripped) must pull in no third argument and no skill/treatment input - it uses only $1 (artifact)
# and $2 (reference).
if grep -vE '^[[:space:]]*#' "$JUDGE/judge.sh" | grep -qiE '\$\{?3|SKILL|--append-system-prompt|--settings|CONFIG_|cfg_'; then
  fail "judge.sh's code pulls in a third input / the skill (must be blind to the treatment)"
else
  pass "judge.sh's code uses only the artifact and reference (blind to the skill/treatment)"
fi
grep -q 'judge.sh" "\$artifact" "\$abs/reference"' "$HERE/lib.sh" \
  && pass "judge_score hands the scorer ONLY the artifact and reference, never the skill" \
  || fail "judge_score invocation does not clearly pass only artifact+reference"

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'JUDGE OK - the tier scores against a reference, tags validated/unvalidated by human agreement, never decides until validated, and never sees the skill\n' >&2
  exit 0
fi
printf 'JUDGE FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
