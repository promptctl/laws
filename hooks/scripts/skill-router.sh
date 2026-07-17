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
Before substantive work, identify the medium of your primary deliverable and load the ONE skill that matches: code — source, tests, schemas, configs, scripts, infrastructure — Skill(laws:code); text another LLM will consume — task prompts, subagent instructions, guidance documents, skill bodies, hook text — Skill(laws:prompt); prose for humans — docs, READMEs, reports, messages — Skill(laws:prose). Load one, not two: each carries a different standard, and stacking them lets one medium's rules corrupt another's work. Switch skills only if the medium itself changes.

Then, for the rest of the session, consider the craft you've loaded and how any work you create will achieve its highest-quality expression through it. Express that reasoning directly in the chat, citing its principles at the point of use — engaging with it is a must. Although it may seem tedious and repetitive to repeatedly derive the concrete from the abstract, that engagement is critical to applying the craft correctly at every stage of the work. This is not a checklist to satisfy; it is a philosophy to inhabit.
EOT

# Pure reinforcement — deepens engagement with whatever is already loaded. It does NOT
# re-route or second-guess the medium; the point of a recurring ping is to reinforce the
# current commitment, not to ask "sure you don't want to switch?" every message. This is
# the closest descendant of the original universal-laws reminder, which was itself pure
# engagement (the laws were always loaded, so it never needed to route).
read -r -d '' ENGAGE_TEXT <<'EOT'
For this request, consider the craft you've loaded and how the work you create will achieve its highest-quality expression through it. Express that reasoning directly in the chat, citing its principles at the point of use — engaging with it is a must. It may feel tedious and repetitive to keep deriving the concrete from the abstract, but that derivation IS the application, at every stage. This is not a checklist to satisfy; it is a philosophy to inhabit.
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
