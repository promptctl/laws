#!/usr/bin/env bash
# The comparison: run the IDENTICAL task under two or more configurations, collect the
# ground-truth outcomes, and report a per-arm table plus which arm did better by the task's own
# criterion. This is the epic's payoff made runnable in one step - B vs A vs no-skill on the same
# task, decided by ground truth, never by how well output matches the skill.
#
# [LAW:decomposition] this layer only orchestrates run_scored across arms and tabulates; it adds
#   no scoring of its own.
# [LAW:no-silent-failure] an arm whose run aborts is reported as FAILED - never dropped and never
#   given a fabricated score - and any FAILED arm makes the overall exit nonzero. A run that
#   completes with a real "fail" verdict is a valid outcome, not an abort.
# [LAW:one-source-of-truth] "which did better" is computed only from the criterion's verdicts.

set -o pipefail
CMP_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../run/lib.sh
source "$CMP_HERE/../run/lib.sh"

cmp_die() { printf 'ERROR [compare]: %s\n' "$*" >&2; exit 1; }

# Best-effort skill ref for an arm, for labelling even when its run aborts: the config's git ref,
# or "none" for control, or "?" if the config itself does not parse.
cmp_arm_ref() {
  local config="$1" f skill ref
  f="$(cfg_fields "$config" 2>/dev/null)" || { printf '?\n'; return 0; }
  skill="$(printf '%s' "$f" | sed -n '1p')"; ref="$(printf '%s' "$f" | sed -n '2p')"
  [ -n "$skill" ] && printf '%s\n' "$ref" || printf 'none\n'
}

# ── Compare one task across N configurations ────────────────────────────────────────────
# Usage: compare_task <task_dir> <out_dir> <config_dir> <config_dir> [<config_dir> ...]
#   Writes <out_dir>/<arm>/ per arm (outcome + transcript + run log) and prints the table and the
#   which-arm-did-better line. Returns nonzero iff any arm's run aborted (a FAILED row).
compare_task() {
  local task="$1" out="$2"; shift 2
  [ -n "$task" ] && [ -n "$out" ] || cmp_die "usage: compare_task <task_dir> <out_dir> <config...>"
  [ "$#" -ge 2 ] || cmp_die "a comparison needs at least two configurations (got $#)"
  task_validate "$task" >/dev/null || exit $?
  [ ! -e "$out" ] || cmp_die "out dir already exists: $out (refusing to overwrite)"
  mkdir -p "$out" || cmp_die "could not create out dir: $out"

  local -a names refs verdicts
  local config name armout ref verdict rc
  for config in "$@"; do
    name="$(basename "$config")"
    armout="$out/$name"
    ref="$(cmp_arm_ref "$config")"
    printf '[compare] running arm: %s (skill_ref=%s)\n' "$name" "$ref" >&2
    # Contain the run in a subshell so an aborting arm (run_die exits) is caught here and reported
    # as FAILED, not propagated to kill the whole comparison. [LAW:no-silent-failure]
    if ( run_scored "$task" "$config" "$armout" ) >"$out/$name.runlog" 2>&1 && [ -f "$armout/outcome.json" ]; then
      verdict="$(grep -o '"verdict": *"[^"]*"' "$armout/outcome.json" | sed 's/.*"\([^"]*\)"$/\1/')"
      [ -n "$verdict" ] || verdict="FAILED"
    else
      verdict="FAILED"
    fi
    names+=("$name"); refs+=("$ref"); verdicts+=("$verdict")
  done

  cmp_report names refs verdicts
}

# Print the table and the which-arm-did-better line from parallel arrays (by name reference), and
# return nonzero iff any arm FAILED. "Better" ranks pass(2) > fail(1) > FAILED(0); the winners are
# the arms holding the best rank.
cmp_report() {
  local -n _names="$1" _refs="$2" _verdicts="$3"
  local i n rank best=-1
  printf '\n%-22s %-12s %s\n' "CONFIGURATION" "SKILL_REF" "VERDICT" >&2
  printf '%-22s %-12s %s\n' "----------------------" "------------" "-------" >&2
  n="${#_names[@]}"
  local any_failed=0
  for ((i = 0; i < n; i++)); do
    printf '%-22s %-12s %s\n' "${_names[$i]}" "${_refs[$i]}" "${_verdicts[$i]}" >&2
    case "${_verdicts[$i]}" in pass) rank=2 ;; fail) rank=1 ;; *) rank=0; any_failed=1 ;; esac
    [ "$rank" -gt "$best" ] && best="$rank"
  done

  # Winners = arms at the best rank.
  local -a winners=()
  for ((i = 0; i < n; i++)); do
    case "${_verdicts[$i]}" in pass) rank=2 ;; fail) rank=1 ;; *) rank=0 ;; esac
    [ "$rank" -eq "$best" ] && winners+=("${_names[$i]} (${_refs[$i]})")
  done

  local joined; printf -v joined '%s, ' "${winners[@]}"; joined="${joined%, }"
  printf '\n' >&2
  case "$best" in
    2) if [ "${#winners[@]}" -eq 1 ]; then printf 'Better by the criterion: %s passed.\n' "${winners[0]}" >&2
       else printf 'Better by the criterion: tie - these arms passed: %s\n' "$joined" >&2; fi ;;
    1) printf 'Better by the criterion: no arm passed; least-bad (completed but failed): %s\n' "$joined" >&2 ;;
    *) printf 'Better by the criterion: no arm completed a run.\n' >&2 ;;
  esac

  [ "$any_failed" -eq 0 ]
}
