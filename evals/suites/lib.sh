#!/usr/bin/env bash
# The suite format: a NAMED SET of task specs, so "run the laws:code eval" is one command over
# one piece of data instead of a hand-maintained list of task invocations. A suite is DATA - a
# manifest naming task directories under evals/tasks - and it inherits its tasks' orthogonality:
# a suite knows nothing about which skill version or arm it runs under, and the manifest has no
# field to say so.
#
# THE FORMAT. A suite is a directory:
#   <suite>/manifest.sh  - sourced; sets SUITE_SUMMARY (one line) and SUITE_TASKS (whitespace-
#                          separated names of task directories under evals/tasks). Data only.
#
# [LAW:types-are-the-program] a suite member is a NAME resolved under the tasks root - not a free
#   path - so a suite cannot reach outside the task set, and every member is a validated task
#   spec by the time a consumer sees it (parse, don't validate).
# [LAW:one-source-of-truth] the suite stores task names only; everything else about a task
#   (repo, commit, criterion) lives in the task spec it names.
# [LAW:no-silent-failure] a suite naming a missing task, an empty suite, or a duplicate member
#   aborts loudly at validation - never a silently shorter run.

set -o pipefail
SUITE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../tasks/lib.sh
source "$SUITE_HERE/../tasks/lib.sh"

# Where suite member names resolve. Overridable so the verifier can prove failure arms against a
# fabricated root without touching the real tasks.
SUITE_TASKS_ROOT="${SUITE_TASKS_ROOT:-$SUITE_HERE/../tasks}"

# Exit 2, like task_die: a malformed suite is a harness/spec error, kept distinct from any
# criterion's FAIL verdict (exit 1) by the harness-wide exit-code contract.
suite_die() { printf 'ERROR [suite]: %s\n' "$*" >&2; exit 2; }
suite_log() { printf '[suite] %s\n' "$*" >&2; }

# ── Validate a suite against the format (parse, don't validate) ─────────────────────────
# Echoes the resolved, validated task directories (one absolute path per line, in manifest
# order) on success; aborts with a located message on the first violation. After this passes, a
# consumer can hand every line straight to the task machinery. [LAW:parse-dont-validate]
# Usage: suite_validate <suite_dir>
suite_validate() {
  local dir="$1"
  [ -n "$dir" ] || suite_die "suite_validate: no suite dir given"
  [ -d "$dir" ] || suite_die "suite_validate: not a directory: $dir"
  local man="$dir/manifest.sh"
  [ -f "$man" ] || suite_die "suite_validate: missing manifest.sh in $dir"

  # Source the manifest in a subshell so its assignments cannot leak, and read back the two
  # fields. The separator line keeps the (single-line) summary and the (multi-line) task list
  # unambiguous in one stream.
  local vars
  vars="$(set -e; SUITE_SUMMARY=""; SUITE_TASKS=""
          # shellcheck disable=SC1090
          . "$man" >/dev/null
          printf '%s\n--SUITE-FIELD-SEP--\n%s\n' "$SUITE_SUMMARY" "$SUITE_TASKS")" \
    || suite_die "suite_validate: manifest.sh failed to source cleanly: $man"
  local summary names
  summary="$(printf '%s\n' "$vars" | sed -n '1p')"
  names="$(printf '%s\n' "$vars" | sed -n '/^--SUITE-FIELD-SEP--$/,$p' | sed 1d | tr ' \t' '\n\n' | sed '/^$/d')"
  [ -n "$summary" ] || suite_die "suite_validate: manifest sets no SUITE_SUMMARY in $man"
  [ -n "$names" ] || suite_die "suite_validate: manifest sets no SUITE_TASKS in $man"

  # A suite must stay orthogonal to configuration, exactly as its tasks are: reject an arm-shaped
  # variable in the manifest as the smell that the two concerns got confused - same rule the task
  # format enforces. [LAW:types-are-the-program] the illegal field is unrepresentable.
  local smuggled
  smuggled="$(grep -nE '^[[:space:]]*(SUITE_SKILL|SUITE_ARM|SUITE_CONFIG|CONFIG_SKILL|CONFIG_REF|SKILL_REF|ARM)[[:space:]]*=' "$man" | head -1)"
  [ -z "$smuggled" ] || suite_die "suite_validate: manifest sets a configuration/arm field (a suite must be orthogonal to the arm): $smuggled"

  local root; root="$(cd "$SUITE_TASKS_ROOT" 2>/dev/null && pwd)" \
    || suite_die "suite_validate: tasks root does not exist: $SUITE_TASKS_ROOT"

  # Resolve and validate every member; refuse duplicates (one member, one set of repetitions -
  # a duplicate would silently double-count an arm's outcomes in any summary).
  local -a seen=()
  local name s
  while IFS= read -r name; do
    case "$name" in
      */*|.|..) suite_die "suite_validate: suite members are task NAMES under the tasks root, not paths: $name" ;;
    esac
    for s in ${seen[@]+"${seen[@]}"}; do
      [ "$s" = "$name" ] && suite_die "suite_validate: duplicate suite member: $name"
    done
    seen+=("$name")
    [ -d "$root/$name" ] || suite_die "suite_validate: suite names a task that does not exist under $root: $name"
    ( task_validate "$root/$name" ) >/dev/null || exit $?   # preserve the harness-error code (2)
    printf '%s\n' "$root/$name"
  done <<< "$names"
}
