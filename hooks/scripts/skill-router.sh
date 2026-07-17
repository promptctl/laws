#!/bin/bash
# Skill-router reminder hook — steers each session to load the skill that matches
# the medium of its deliverable. Quality guidance is scoped per medium; applying
# one medium's standards to another's artifact is the failure mode this plugin
# exists to prevent (see the prompt skill).
#
# Requires: jq

HOOK_TYPE="$1"
STATE_FILE="$HOME/.claude/.last_laws_router_reminder"
COOLDOWN_SECONDS=300  # 5 minutes

# Without jq the hook would error on every prompt; degrade to a silent no-op instead.
command -v jq >/dev/null 2>&1 || exit 0

read -r -d '' ROUTER_LONG <<'EOT'
Identify the medium of the deliverable for this request, then load the matching skill BEFORE doing substantive work:
- Code — source, tests, schemas, configs, scripts, infrastructure, architecture — load Skill(laws:code).
- Text another LLM will consume — task prompts, subagent instructions, agent guidance documents, skill bodies, hook text — load Skill(laws:prompt).
- Prose for humans — docs, READMEs, reports, summaries, messages — load Skill(laws:prose).
Load the skill first, then hold its bar for the whole task. If the task spans several media, load each skill at the point you switch. Applying one medium's quality standards to another medium's artifact is a known failure mode: the code laws applied to guidance prose destroy the guidance, and prose instincts applied to code hide bugs. Route by medium first.
EOT

read -r -d '' ROUTER_SHORT <<'EOT'
Reminder: your quality bar comes from the medium of the current deliverable — code → Skill(laws:code), LLM-consumed text → Skill(laws:prompt), human prose → Skill(laws:prose). If the matching skill is not loaded yet, load it before continuing.
EOT

# Time-based throttling: only fire if cooldown has elapsed
should_remind() {
  LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - LAST)) -gt $COOLDOWN_SECONDS ]; then
    echo "$NOW" > "$STATE_FILE"
    return 0
  fi
  return 1
}

# additionalContext JSON is required for the text to reach the model on tool hooks;
# plain stdout only reaches context on UserPromptSubmit.
emit() {
  jq -n --arg event "$1" --arg ctx "$2" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $ctx}}'
}

case "$HOOK_TYPE" in
  user-prompt)
    # Full routing instruction at task start; resets the cooldown timer
    echo "$(date +%s)" > "$STATE_FILE"
    emit "UserPromptSubmit" "$ROUTER_LONG"
    ;;

  read-post)
    # Time-throttled: short nudge if 5+ minutes since last reminder
    if should_remind; then
      emit "PostToolUse" "$ROUTER_SHORT"
    fi
    ;;

  task-pre)
    # Full routing instruction before spawning subagents; resets the cooldown timer
    echo "$(date +%s)" > "$STATE_FILE"
    emit "PreToolUse" "$ROUTER_LONG"
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
