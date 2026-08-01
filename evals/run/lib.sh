#!/usr/bin/env bash
# The single scored run - the atomic unit the whole comparison is built from. It binds ONE task
# and ONE configuration together only at run time: launches an isolated Opus session with the
# configuration's guidance loaded, drives the agent through the task as real multi-turn work on
# the task's repo checked out at the task's commit, then scores the produced state with the task's
# programmatic criterion, emitting exactly one outcome record - or aborting loudly with none.
#
# [LAW:decomposition] this layer only ORCHESTRATES; it reuses the driver, task, and config
#   modules and adds no capability of its own beyond binding them.
# [LAW:no-silent-failure] a failed/empty/partial driven turn, a dead session, or a criterion that
#   could not run aborts nonzero and writes NO outcome record. The record is written last, only
#   after a real verdict exists, so a partial run can never leave a record behind.
# [LAW:one-source-of-truth] scoring is the task's criterion and nothing else - never a judgment
#   against the laws or any skill-derived rubric.

set -o pipefail
RUN_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../driver/lib.sh
source "$RUN_HERE/../driver/lib.sh"
# shellcheck source=../tasks/lib.sh
source "$RUN_HERE/../tasks/lib.sh"
# shellcheck source=../configs/lib.sh
source "$RUN_HERE/../configs/lib.sh"

RUN_TURN_TIMEOUT_SECS="${RUN_TURN_TIMEOUT_SECS:-900}"   # a real coding turn can be minutes
ISO_CONFIG_DIR="${ISO_CONFIG_DIR:-$HOME/.claude-laws-eval}"

run_die() { printf 'ERROR [run]: %s\n' "$*" >&2; exit 1; }
run_log() { printf '[run] %s\n' "$*" >&2; }

# The turns that drive the task. Turn 1 is the task text; the rest push the agent to complete and
# make the run genuinely multi-turn / long-context, so the loaded guidance is observed deep into
# the session rather than right after it was read. [epic constraint: never single-turn]
run_followups() {
  printf '%s\n' \
    "Keep going until the task is fully complete. Run the project's own tests or checks and make sure they pass; fix anything still failing. Do not stop while anything is red." \
    "Confirm the task is done and the checks pass now, and briefly summarize what you changed."
}

# ── One scored run ──────────────────────────────────────────────────────────────────────
# Usage: run_scored <task_dir> <config_dir> <out_dir>
#   Produces <out_dir>/outcome.json (the single record) and <out_dir>/transcript.txt, or aborts
#   nonzero having written no outcome.json.
run_scored() {
  local task="$1" config="$2" out="$3"
  [ -n "$task" ] && [ -n "$config" ] && [ -n "$out" ] || run_die "usage: run_scored <task_dir> <config_dir> <out_dir>"
  task_validate "$task" >/dev/null || exit $?
  cfg_validate "$config" || exit $?
  [ ! -e "$out" ] || run_die "out dir already exists: $out (refusing to overwrite)"
  mkdir -p "$out" || run_die "could not create out dir: $out"

  # Resolve the arm: the skill ref (or "none" for control) and the body file the session loads.
  local f skillref bodyfile=""
  f="$(cfg_fields "$config")" || exit $?
  local cskill cref; cskill="$(printf '%s' "$f" | sed -n '1p')"; cref="$(printf '%s' "$f" | sed -n '2p')"
  if [ -z "$cskill" ]; then
    skillref="none"
    run_log "arm: control (no skill body loaded)"
  else
    skillref="$cref"
    bodyfile="$out/skill-body.md"
    cfg_resolve "$config" > "$bodyfile" || exit $?
    [ -s "$bodyfile" ] || run_die "resolved skill body is empty for $config"
    run_log "arm: $cskill @ $cref ($(wc -c <"$bodyfile" | tr -d ' ') bytes loaded as system prompt)"
  fi

  # Prepare the repo at the task's commit and establish the starting (defect) state.
  local checkout="$out/repo"
  task_prepare "$task" "$checkout"
  task_setup "$task" "$checkout"
  # Strip any CLAUDE.md from the checkout so the ONLY guidance in the session is the skill body
  # under test - the arm is the sole variable across runs, and this also satisfies the isolation's
  # clean-work-dir requirement. [LAW:single-enforcer] one guidance source: the arm.
  find "$checkout" -name CLAUDE.md -type f -delete 2>/dev/null || true

  # Launch the isolated Opus session in the checkout, with the arm's body loaded and permissions
  # bypassed so the agent can edit files and run tests without a human to approve prompts.
  local sess="evalrun-$$-$RANDOM"
  # shellcheck disable=SC2064
  trap "iso_teardown '$sess'" RETURN
  # A larger launch budget: the run clears the trust dialog AND the bypass-permissions warning and
  # boots with a tens-of-KB system prompt, which is slower than a bare interactive launch.
  DRV_TURN_TIMEOUT_SECS="$RUN_TURN_TIMEOUT_SECS" ISO_LAUNCH_TIMEOUT_SECS="${ISO_LAUNCH_TIMEOUT_SECS:-120}" \
    drv_launch "$sess" "$ISO_CONFIG_DIR" "$checkout" "$bodyfile" "--permission-mode bypassPermissions"

  # Drive the task: turn 1 is the prompt, then the follow-ups. Every turn goes through drive_turn,
  # which aborts nonzero on any bad/empty/partial turn - so this loop cannot emit a partial run.
  local transcript="$out/transcript.txt" nturns=0 prompt reply
  : > "$transcript"
  # A driven turn that fails aborts the run - but first tear the session down (run_die exits, which
  # would bypass the RETURN trap and leak the tmux session). [LAW:no-silent-failure]
  prompt="$(cat "$task/prompt.md")"
  { printf '===== turn 1 (task prompt) =====\n%s\n\n' "$prompt"; } >> "$transcript"
  reply="$(DRV_TURN_TIMEOUT_SECS="$RUN_TURN_TIMEOUT_SECS" drive_turn "$sess" "$prompt")" \
    || { iso_teardown "$sess"; run_die "run aborted: turn 1 failed (no outcome emitted)"; }
  { printf -- '----- reply -----\n%s\n\n' "$reply"; } >> "$transcript"
  nturns=1

  local fu
  while IFS= read -r fu; do
    nturns=$((nturns + 1))
    { printf '===== turn %d (follow-up) =====\n%s\n\n' "$nturns" "$fu"; } >> "$transcript"
    reply="$(DRV_TURN_TIMEOUT_SECS="$RUN_TURN_TIMEOUT_SECS" drive_turn "$sess" "$fu")" \
      || { iso_teardown "$sess"; run_die "run aborted: turn $nturns failed (no outcome emitted)"; }
    { printf -- '----- reply -----\n%s\n\n' "$reply"; } >> "$transcript"
  done < <(run_followups)

  iso_teardown "$sess"; trap - RETURN

  # Score the produced state with the task's own criterion. task_check returns 0 (pass) / 1 (fail);
  # a harness error (>=2) aborts inside task_check - never a fabricated verdict.
  local verdict rc=0
  task_check "$task" "$checkout" && verdict="pass" || { rc=$?; verdict="fail"; }
  [ "$rc" -le 1 ] || run_die "run aborted: criterion could not run (no outcome emitted)"

  # Emit the single outcome record LAST, now that a real verdict exists.
  run_emit_outcome "$out/outcome.json" "$(basename "$task")" "$(basename "$config")" "$skillref" "$verdict" "$nturns" "$checkout" "$transcript"
  run_log "outcome: task=$(basename "$task") arm=$(basename "$config") skill_ref=$skillref verdict=$verdict turns=$nturns"
  printf '%s\n' "$out/outcome.json"
}

# Write the outcome record as JSON. Values are shell strings with no embedded quotes/newlines
# (names, a ref, a verdict, a count, paths), so a small hand-rolled writer is safe and dep-free.
run_emit_outcome() {
  local file="$1" task="$2" config="$3" skillref="$4" verdict="$5" turns="$6" artifact="$7" transcript="$8"
  cat > "$file" <<JSON
{
  "task": "$task",
  "config": "$config",
  "skill_ref": "$skillref",
  "verdict": "$verdict",
  "turns": $turns,
  "artifact": "$artifact",
  "transcript": "$transcript"
}
JSON
}
