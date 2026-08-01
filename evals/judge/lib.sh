#!/usr/bin/env bash
# The optional, secondary judge tier. For a task whose quality is genuinely not fully mechanically
# checkable, a run MAY attach a judge that scores the produced artifact against a supplied
# REFERENCE / ground truth. Its verdicts are NOT trusted until they are shown to agree with human
# labels on a held set; until then they are reported as unvalidated and never decide the
# comparison. The primary verdict is always the programmatic / ground-truth criterion.
#
# THE JUDGE FORMAT. A judge is a directory:
#   <judge>/judge.sh   - the scorer: `judge.sh <artifact_dir> <reference_path>`, exit 0 = judge-pass,
#                        1 = judge-fail, 2 = could-not-run. It is handed ONLY the artifact and the
#                        reference - never the skill under test, the laws, or any skill-derived
#                        rubric. That the skill is unreachable is structural: this tier never passes
#                        it in.
#   <judge>/reference  - the ground truth the artifact is scored against.
#   <judge>/labels.tsv - OPTIONAL held validation set: rows of `<case_artifact_dir>\t<pass|fail>`,
#                        each a human's label for that artifact. Used only to CALIBRATE the judge;
#                        never seen by judge.sh at scoring time.
#
# [LAW:no-silent-failure] a judge that cannot run (exit >=2) aborts, never a fabricated verdict.
# [LAW:one-source-of-truth] the judge scores against the reference, the single ground truth; it
#   has no access to the treatment (the skill), so it cannot grade output against the treatment.

set -o pipefail
JUDGE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUDGE_AGREEMENT_BAR="${JUDGE_AGREEMENT_BAR:-80}"   # percent agreement with humans required to trust

# exit 2 = a harness/infra error (never a verdict), distinct from judge_validate's "below bar" (1).
judge_die() { printf 'ERROR [judge]: %s\n' "$*" >&2; exit 2; }
judge_log() { printf '[judge] %s\n' "$*" >&2; }

# Score one artifact against the judge's reference. Prints "pass" / "fail"; aborts if the judge
# could not run (exit >=2) - never a fabricated verdict.
# Usage: judge_score <judge_dir> <artifact_dir>
judge_score() {
  local judge="$1" artifact="$2"
  [ -n "$judge" ] && [ -n "$artifact" ] || judge_die "judge_score: need <judge_dir> <artifact_dir>"
  [ -x "$judge/judge.sh" ] || judge_die "judge_score: no executable judge.sh in $judge"
  [ -f "$judge/reference" ] || judge_die "judge_score: no reference in $judge"
  local abs; abs="$(cd "$judge" && pwd)"
  # The scorer is handed ONLY the artifact and the reference - never a path to the skill.
  "$abs/judge.sh" "$artifact" "$abs/reference" >/dev/null 2>&1
  case "$?" in
    0) printf 'pass\n' ;;
    1) printf 'fail\n' ;;
    *) judge_die "judge_score: judge.sh could not run against $artifact (exit >=2) - not a verdict" ;;
  esac
}

# Calibrate the judge against human labels: score every held case, compare to its human label, and
# print the agreement rate. Returns 0 iff agreement >= JUDGE_AGREEMENT_BAR (percent). The labels
# file rows are `<case_artifact_dir>\t<pass|fail>`; a relative case dir is resolved against the
# judge dir. [LAW:verifiable-goals] the bar is a machine-checked threshold.
# Usage: judge_validate <judge_dir>   -> prints agreement; return 0 if it meets the bar
judge_validate() {
  local judge="$1"
  [ -n "$judge" ] || judge_die "judge_validate: need <judge_dir>"
  local labels="$judge/labels.tsv"
  [ -f "$labels" ] || judge_die "judge_validate: no labels.tsv (held validation set) in $judge"
  local abs; abs="$(cd "$judge" && pwd)"

  local total=0 agreed=0 casedir human verdict
  while IFS=$'\t' read -r casedir human; do
    [ -n "$casedir" ] || continue
    case "$casedir" in \#*) continue ;; esac                 # allow comment rows
    case "$human" in pass|fail) : ;; *) judge_die "judge_validate: bad human label '$human' for $casedir" ;; esac
    case "$casedir" in /*) : ;; *) casedir="$abs/$casedir" ;; esac
    verdict="$(judge_score "$judge" "$casedir")" || exit $?
    total=$((total + 1))
    [ "$verdict" = "$human" ] && agreed=$((agreed + 1))
  done < "$labels"

  [ "$total" -gt 0 ] || judge_die "judge_validate: labels.tsv held set is empty"
  local pct=$((agreed * 100 / total))
  judge_log "agreement with human labels: $agreed/$total = ${pct}% (bar ${JUDGE_AGREEMENT_BAR}%)"
  [ "$pct" -ge "$JUDGE_AGREEMENT_BAR" ]
}

# Report the two-tier outcome for one artifact: the PRIMARY programmatic verdict (which alone
# decides the comparison) and the SECONDARY judge verdict, tagged with whether the judge has been
# validated against human labels. Until validated, the judge verdict is marked unvalidated and is
# explicitly excluded from the decision. Returns nonzero only if the judge could not run.
# Usage: judge_report <judge_dir> <artifact_dir> <programmatic_verdict>
judge_report() {
  local judge="$1" artifact="$2" prog="$3"
  [ -n "$judge" ] && [ -n "$artifact" ] && [ -n "$prog" ] || judge_die "usage: judge_report <judge_dir> <artifact_dir> <programmatic_verdict>"

  printf 'Primary (programmatic) verdict: %s   [this decides the comparison]\n' "$prog" >&2

  local jverdict tag
  jverdict="$(judge_score "$judge" "$artifact")" || exit $?
  if [ -f "$judge/labels.tsv" ]; then
    # ONE calibration call: capture its log and its exit status together (0 = meets bar, 1 = below,
    # >=2 = could not run), and read the agreement percentage from that same output.
    local vout vrc pct
    vout="$(judge_validate "$judge" 2>&1)"; vrc=$?
    [ "$vrc" -le 1 ] || judge_die "judge_report: judge validation could not run: $vout"
    pct="$(printf '%s' "$vout" | grep -oE '[0-9]+%' | head -1)"; pct="${pct:-?}"
    if [ "$vrc" -eq 0 ]; then
      tag="validated (agreement ${pct} >= bar ${JUDGE_AGREEMENT_BAR}%) - may contribute to a verdict"
    else
      tag="unvalidated (agreement ${pct} below bar ${JUDGE_AGREEMENT_BAR}%) - does NOT decide the comparison"
    fi
  else
    tag="unvalidated (no human-label validation set supplied) - does NOT decide the comparison"
  fi
  printf 'Secondary (judge) verdict:      %s   [%s]\n' "$jverdict" "$tag" >&2
}
