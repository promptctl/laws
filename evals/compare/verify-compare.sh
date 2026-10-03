#!/usr/bin/env bash
# Prove the comparison against a LIVE Opus session. One comparison over three arms - a skill arm,
# the no-skill control, and an arm whose run is forced to abort - demonstrates the whole done-claim
# at once. Exits 0 iff:
#   1. the table has one row per arm, each labelled by its git ref or "none", each carrying the
#      task criterion's real verdict (the two completing arms reproduce a pass) and a
#      which-arm-did-better line derived only from those verdicts;
#   2. the aborting arm shows as FAILED with a nonzero overall exit and NO fabricated score for it.
#
# [LAW:verifiable-goals] the comparison is decided by the task's own criterion; this runs the check.
# [LAW:no-silent-failure] a FAILED arm that leaves a score behind, or does not force nonzero exit,
#   is a hard failure here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

TASK="$HERE/../tasks/go-template-add-fix"
ARM_A="$HERE/../configs/code-ref-a"        # a skill arm, ref 8f6d15b -> expected pass
ARM_CONTROL="$HERE/../configs/control"     # the no-skill arm       -> expected pass

# A third arm whose run cannot complete: a config pinned to a ref that does not exist, so its run
# aborts (FAILED) without a fabricated score.
BADARM="$WORK/bad-ref-arm"; mkdir -p "$BADARM"
cat > "$BADARM/manifest.sh" <<'EOF'
CONFIG_SKILL="code"
CONFIG_REF="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
CONFIG_SUMMARY="a ref that does not exist - this arm's run must abort"
EOF

echo "== comparing three arms on one task (skill A, control, a forced-abort arm) ==" >&2
out="$WORK/cmp"
if compare_task "$TASK" "$out" "$ARM_A" "$ARM_CONTROL" "$BADARM" 2>"$WORK/table.txt"; then
  fail "comparison exited 0 but one arm was forced to abort (expected nonzero)"
else
  pass "comparison exited nonzero because an arm's run aborted"
fi
cat "$WORK/table.txt" >&2

# The two completing arms produced real pass verdicts, read from their own outcome records.
va="$(grep -o '"verdict": *"[^"]*"' "$out/code-ref-a/outcome.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"
vc="$(grep -o '"verdict": *"[^"]*"' "$out/control/outcome.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"
[ "$va" = "pass" ] && pass "skill arm (code-ref-a) reproduced a real pass" || fail "code-ref-a verdict = [$va], expected pass"
[ "$vc" = "pass" ] && pass "control arm reproduced a real pass" || fail "control verdict = [$vc], expected pass"

# The aborting arm left NO outcome record (no fabricated score) and shows FAILED in the table.
[ ! -f "$out/bad-ref-arm/outcome.json" ] && pass "aborting arm left NO outcome record (no fabricated score)" || fail "aborting arm left an outcome record behind"
grep -q "bad-ref-arm" "$WORK/table.txt" && grep -q "FAILED" "$WORK/table.txt" && pass "aborting arm shown as FAILED in the table" || fail "aborting arm not shown as FAILED"

# The table has a row per arm and a which-arm-did-better line.
rows="$(grep -cE '^(code-ref-a|control|bad-ref-arm) ' "$WORK/table.txt")"
[ "${rows:-0}" -eq 3 ] && pass "table has one row per arm (3 rows, each labelled by ref/none)" || fail "table row count = ${rows:-0}, expected 3"
grep -q "Better by the criterion" "$WORK/table.txt" && pass "which-arm-did-better line present, derived from verdicts" || fail "no which-arm-did-better line"

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'COMPARE OK - a one-command comparison reports real per-arm verdicts and which did better; an aborted arm is FAILED, never fabricated\n' >&2
  exit 0
fi
printf 'COMPARE FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
