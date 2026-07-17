#!/bin/bash
# Session hook for the laws plugin.
#
#   session-start  — fires once per session (wired in hooks.json): route to the ONE
#                    medium-matched skill, then engage it actively for the whole session.
#   engage         — re-activation ping (cooldown-gated). NOT wired by default; add it
#                    to a UserPromptSubmit hook to test whether per-prompt re-engagement
#                    improves behavior enough to justify the injection. See README.
#
# Requires: jq

HOOK_TYPE="$1"
STATE_FILE="$HOME/.claude/.last_laws_engage"
COOLDOWN_SECONDS=300  # 5 minutes

# Without jq the hook would error on every firing; degrade to a silent no-op instead.
command -v jq >/dev/null 2>&1 || exit 0

read -r -d '' SESSION_TEXT <<'EOT'
Before substantive work, identify the medium of the primary deliverable and load the ONE skill that matches: code — source, tests, schemas, configs, scripts, infrastructure — Skill(laws:code); text another LLM will consume — task prompts, subagent instructions, guidance documents, skill bodies, hook text — Skill(laws:prompt); prose for humans — docs, READMEs, reports, messages — Skill(laws:prose). Load one, not two: these skills carry different quality standards, and stacking them in one context is how one medium's standards bleed into another's artifact. If the medium genuinely changes mid-session, switch skills at that point.

Once loaded, engage the guidance actively for every task in this session: consider how the work you produce will achieve its highest-quality expression through it, and express that reasoning directly in the chat as you go — cite its principles at the point of use. It may feel tedious and repetitive to keep deriving the concrete from the abstract; that derivation IS the application, at every stage of the work. This is not a checklist to satisfy. It is a philosophy to inhabit.
EOT

read -r -d '' ENGAGE_TEXT <<'EOT'
Re-engage the loaded guidance for this request: how does this specific piece of work achieve its highest-quality expression through it? Express the derivation in chat — abstract to concrete, again, at the point of use. If no guidance skill is loaded yet, load the one matching the deliverable's medium first. This is a philosophy to inhabit, not a checklist to satisfy.
EOT

# Time-based throttling for the engage ping
should_remind() {
  LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - LAST)) -gt $COOLDOWN_SECONDS ]; then
    echo "$NOW" > "$STATE_FILE"
    return 0
  fi
  return 1
}

emit() {
  jq -n --arg event "$1" --arg ctx "$2" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $ctx}}'
}

case "$HOOK_TYPE" in
  session-start)
    echo "$(date +%s)" > "$STATE_FILE"
    emit "SessionStart" "$SESSION_TEXT"
    ;;

  engage)
    if should_remind; then
      emit "UserPromptSubmit" "$ENGAGE_TEXT"
    fi
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
