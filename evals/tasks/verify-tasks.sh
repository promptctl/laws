#!/usr/bin/env bash
# Prove the task-spec format and every task in it. For EACH task directory (any dir holding a
# manifest.sh), assert three things:
#   1. it validates against the format;
#   2. its criterion PASSES against the clean pinned state (known-good reference);
#   3. its criterion FAILS against the state with the task's defect established (setup.sh).
# Exit 0 iff all three hold for every task. Because the loop is data-driven over whatever task
# dirs exist, a second, differently-shaped task validates here with no edit to this script - which
# is itself the proof that the format is not shaped around one task.
#
# [LAW:dataflow-not-control-flow] one loop over the discovered task list; no per-task code.
# [LAW:no-silent-failure] a task that cannot even be prepared aborts loudly; a criterion that
#   passes where it must fail (or vice-versa) is a hard failure, never glossed.
# `set -e` is intentionally omitted (as in the sibling verify-driver.sh): a failing check must be
# recorded and the suite continue, not abort. Discovery is guarded explicitly below instead.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

# Discover tasks: every directory under here that holds a manifest.sh. Capture find's own exit so
# a discovery error (an unreadable dir) aborts loudly rather than silently yielding a short list
# that would report success for only the tasks that happened to be readable. [LAW:no-silent-failure]
found="$(find "$HERE" -mindepth 2 -maxdepth 2 -name manifest.sh -print)" \
  || task_die "task discovery (find) failed under $HERE"
# Guard on empty BEFORE splitting: an empty $found would otherwise become one empty mapfile
# element that slips past the count check below and drives the loop with a blank task dir.
[ -n "$found" ] || task_die "no task directories found under $HERE"
mapfile -t TASKS < <(printf '%s\n' "$found" | sed 's#/manifest.sh$##' | sort)
[ "${#TASKS[@]}" -gt 0 ] || task_die "no task directories found under $HERE"
task_log "found ${#TASKS[@]} task(s)"

for task in "${TASKS[@]}"; do
  name="$(basename "$task")"
  printf '\n== task: %s ==\n' "$name" >&2

  # 1) validates against the format
  if ( task_validate "$task" ) >/dev/null 2>"$WORK/verr"; then
    pass "$name: validates against the format"
  else
    fail "$name: does not validate — $(head -1 "$WORK/verr")"
    continue
  fi

  # 2) criterion PASSES on the clean pinned state. Capture the (often verbose) criterion output
  # to a log and surface it only when the outcome is NOT what we require, so a green run stays
  # readable but a surprise is never swallowed. [LAW:no-silent-failure]
  good="$WORK/$name-good"
  task_prepare "$task" "$good"
  if task_check "$task" "$good" >"$WORK/good.log" 2>&1; then
    pass "$name: criterion PASSES on the known-good reference state"
  else
    fail "$name: criterion should PASS on the clean pinned state but did not"
    sed 's/^/    | /' "$WORK/good.log" >&2
  fi

  # 3) criterion FAILS on the state with the defect established
  bad="$WORK/$name-defect"
  task_prepare "$task" "$bad"
  task_setup "$task" "$bad"
  if task_check "$task" "$bad" >"$WORK/bad.log" 2>&1; then
    fail "$name: criterion should FAIL on the defect state but PASSED (the criterion does not discriminate)"
    sed 's/^/    | /' "$WORK/bad.log" >&2
  else
    pass "$name: criterion FAILS on the state that contains the defect"
  fi
done

echo "" >&2
if [ "$fails" -eq 0 ]; then
  printf 'TASKS OK - %d task(s), all validate and their criteria discriminate good from defect\n' "${#TASKS[@]}" >&2
  exit 0
fi
printf 'TASKS FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
