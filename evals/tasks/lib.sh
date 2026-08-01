#!/usr/bin/env bash
# The task-spec format and the machinery that runs a task's success criterion against a real
# repository. A task knows NOTHING about which skill version or arm it runs under - it names a
# real repo, a commit to begin at, the task text handed to the agent, and a programmatic
# criterion a machine evaluates against the real repo. That orthogonality is what lets one task
# run honestly across arms; if the task knew the arm, the two would tangle.
#
# THE FORMAT. A task is a directory:
#   <task>/manifest.sh  - sourced; sets TASK_REPO, TASK_COMMIT, TASK_SUMMARY. Data only, no logic.
#   <task>/prompt.md    - the task text handed to the agent (multi-line).
#   <task>/check.sh     - THE CRITERION. Runs with CWD = the repo checkout. Exit 0 = the task
#                         succeeded, nonzero = it did not. This one shape - a command that exits
#                         0/nonzero - expresses a test suite passing, a mechanical defect
#                         detector, or an assertion on a produced artifact alike, so a new
#                         criterion type is a new check.sh, never a change to this format.
#   <task>/setup.sh     - OPTIONAL. Runs with CWD = the checkout to establish the STARTING state
#                         the agent begins from (e.g. apply the regression the agent must fix).
#                         The starting state is where check.sh is expected to FAIL; a correct
#                         agent moves it to where check.sh passes.
#
# The criterion must be ground-truth / programmatic - the repo's own tests, a mechanical detector,
# an assertion on the artifact - and must NOT grade the output against any skill, law, or rubric
# derived from the guidance under test. Success is decided independent of the guidance's vocabulary.
#
# [LAW:dataflow-not-control-flow] The criterion is a value (a command), not one of a fixed set of
#   modes. Variability in "what counts as success" flows as check.sh, not as branches here.
# [LAW:no-silent-failure] The machinery's OWN failures (missing repo, unresolvable commit, absent
#   check.sh) abort loudly and are never confused with the criterion's verdict. The criterion's
#   nonzero is a real FAIL verdict; the machinery aborting is an infra error - two different things.
# [LAW:effects-at-boundaries] git clone/checkout and running the task's scripts are gathered here.

set -o pipefail

task_die() { printf 'ERROR [task]: %s\n' "$*" >&2; exit 1; }
task_log() { printf '[task] %s\n' "$*" >&2; }

# ── Validate a task against the format (parse, don't validate) ───────────────────────────
# Returns 0 and echoes the resolved TASK_REPO/TASK_COMMIT/TASK_SUMMARY on success; aborts with a
# located message on the first violation. After this passes, every consumer can rely on the
# fields and files existing. [LAW:parse-dont-validate]
# Usage: task_validate <task_dir>
task_validate() {
  local dir="$1"
  [ -n "$dir" ] || task_die "task_validate: no task dir given"
  [ -d "$dir" ] || task_die "task_validate: not a directory: $dir"
  local man="$dir/manifest.sh"
  [ -f "$man" ] || task_die "task_validate: missing manifest.sh in $dir"
  [ -f "$dir/prompt.md" ] || task_die "task_validate: missing prompt.md in $dir"
  [ -s "$dir/prompt.md" ] || task_die "task_validate: prompt.md is empty in $dir"
  [ -f "$dir/check.sh" ] || task_die "task_validate: missing check.sh (the criterion) in $dir"
  [ -x "$dir/check.sh" ] || task_die "task_validate: check.sh is not executable in $dir"
  [ ! -e "$dir/setup.sh" ] || [ -x "$dir/setup.sh" ] || task_die "task_validate: setup.sh present but not executable in $dir"

  # Source the manifest in a subshell so its assignments cannot leak into the caller, and read
  # back only the three fields. A manifest that sets none of them, or adds logic that fails, is
  # caught here.
  local vars
  vars="$(set -e; TASK_REPO=""; TASK_COMMIT=""; TASK_SUMMARY=""
          # shellcheck disable=SC1090
          . "$man" >/dev/null 2>&1
          printf '%s\n%s\n%s\n' "$TASK_REPO" "$TASK_COMMIT" "$TASK_SUMMARY")" \
    || task_die "task_validate: manifest.sh failed to source cleanly: $man"
  local repo commit summary
  repo="$(printf '%s' "$vars" | sed -n '1p')"
  commit="$(printf '%s' "$vars" | sed -n '2p')"
  summary="$(printf '%s' "$vars" | sed -n '3p')"
  [ -n "$repo" ] || task_die "task_validate: manifest sets no TASK_REPO in $man"
  [ -n "$commit" ] || task_die "task_validate: manifest sets no TASK_COMMIT in $man"
  [ -n "$summary" ] || task_die "task_validate: manifest sets no TASK_SUMMARY in $man"

  # Orthogonality to configuration is structural, not grepped: the format has NO field for a
  # skill, a skill version, or an arm, and no consumer of a task ever reads one - the arm is
  # supplied entirely separately (by the configuration format). The one way a manifest could try
  # to smuggle an arm in is by setting an arm-shaped variable, which would be dead (nothing reads
  # it) but is a code smell that the author confused the two concerns; reject it so the confusion
  # is caught, not silently ignored. [LAW:types-are-the-program] the illegal field is unrepresentable.
  local smuggled
  smuggled="$(grep -nE '^[[:space:]]*(TASK_SKILL|TASK_ARM|TASK_SKILL_REF|TASK_CONFIG|SKILL_REF|ARM)[[:space:]]*=' "$man" | head -1)"
  [ -z "$smuggled" ] || task_die "task_validate: manifest sets a configuration/arm field (a task must be orthogonal to the arm): $smuggled"

  # The repo must be reachable, so a typo'd URL fails now, not deep in a run.
  git ls-remote "$repo" >/dev/null 2>&1 \
    || task_die "task_validate: TASK_REPO is not reachable: $repo"

  printf '%s\n%s\n%s\n' "$repo" "$commit" "$summary"
}

# ── Prepare the repo state (clone + checkout the pinned commit) ──────────────────────────
# Clone TASK_REPO into <dest> and check out TASK_COMMIT. Does NOT run setup.sh - preparing the
# clean pinned state and establishing the task's starting state are separate steps a caller
# composes. Aborts loudly if the repo won't clone or the commit won't resolve.
# Usage: task_prepare <task_dir> <dest_dir>
task_prepare() {
  local dir="$1" dest="$2"
  [ -n "$dir" ] && [ -n "$dest" ] || task_die "task_prepare: need <task_dir> <dest_dir>"
  local out; out="$(task_validate "$dir")" || exit 1
  local repo commit
  repo="$(printf '%s' "$out" | sed -n '1p')"
  commit="$(printf '%s' "$out" | sed -n '2p')"

  [ ! -e "$dest" ] || task_die "task_prepare: dest already exists: $dest (refusing to overwrite)"
  git clone --quiet "$repo" "$dest" 2>/dev/null || task_die "task_prepare: git clone failed: $repo"
  git -C "$dest" checkout --quiet "$commit" 2>/dev/null \
    || task_die "task_prepare: TASK_COMMIT does not resolve in $repo: $commit"
  task_log "prepared $repo @ $commit -> $dest"
}

# ── Establish the starting state (optional setup.sh) ────────────────────────────────────
# Run the task's setup.sh in the checkout, if it has one. This is what makes the starting state
# the agent begins from - typically the state where check.sh fails.
# Usage: task_setup <task_dir> <state_dir>
task_setup() {
  local dir="$1" state="$2"
  [ -n "$dir" ] && [ -n "$state" ] || task_die "task_setup: need <task_dir> <state_dir>"
  [ -d "$state" ] || task_die "task_setup: state dir does not exist: $state"
  [ -e "$dir/setup.sh" ] || { task_log "no setup.sh for $dir (nothing to establish)"; return 0; }
  local abs; abs="$(cd "$dir" && pwd)"
  ( cd "$state" && exec "$abs/setup.sh" ) 2>&1 | sed 's/^/[setup] /' >&2
  local rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] || task_die "task_setup: setup.sh failed (rc=$rc) for $dir"
}

# ── Run the criterion against a prepared state ──────────────────────────────────────────
# Run check.sh with CWD = <state_dir> and return its verdict: 0 = pass, nonzero = fail. The
# machinery aborts (nonzero, via task_die) only on ITS OWN errors - an absent check.sh or a
# missing state dir - so a genuine FAIL verdict is never confused with a broken harness.
# Usage: task_check <task_dir> <state_dir>   -> exit 0 (pass) / 1 (fail); prints PASS/FAIL to stderr
task_check() {
  local dir="$1" state="$2"
  [ -n "$dir" ] && [ -n "$state" ] || task_die "task_check: need <task_dir> <state_dir>"
  [ -x "$dir/check.sh" ] || task_die "task_check: no executable check.sh in $dir"
  [ -d "$state" ] || task_die "task_check: state dir does not exist: $state"
  local abs; abs="$(cd "$dir" && pwd)"
  if ( cd "$state" && exec "$abs/check.sh" ) >&2; then
    task_log "criterion PASS for $(basename "$dir") against $state"
    return 0
  else
    task_log "criterion FAIL for $(basename "$dir") against $state"
    return 1
  fi
}
