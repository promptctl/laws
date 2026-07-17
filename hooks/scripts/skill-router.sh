#!/bin/bash
# Session hook for the laws plugin.
#
#   session-start  — fires once per session (wired in hooks.json): route to the ONE
#                    medium-matched skill, then engage it actively for the whole session.
#   engage         — re-activation ping (cooldown-gated). NOT wired by default; add it
#                    to a UserPromptSubmit hook to test whether per-prompt re-engagement
#                    improves behavior enough to justify the injection. See README.
#
# No external dependencies — pure bash (3.2+), so it runs anywhere Claude Code does.

HOOK_TYPE="$1"
STATE_FILE="$HOME/.claude/.last_laws_engage"
COOLDOWN_SECONDS=300  # 5 minutes

# The engagement text — the one source of truth, injected by both hooks. session-start
# prepends the routing line; the engage ping (unwired) uses it alone as pure
# reinforcement. It does NOT re-route or second-guess the medium: the point of a
# recurring ping is to reinforce the current commitment, not to ask "sure you don't want
# to switch?" every message. Closest descendant of the original universal-laws reminder,
# which was itself pure engagement — the laws were always loaded, so it never routed.
read -r -d '' ENGAGE_TEXT <<'EOT'
For the following request, please consider the laws and devices of your craft and directly consider how you will apply them to achieve the highest quality expression of your work.  You can improve your results substantially by expressing this directly in the chat.  Engaging with the laws and devices is a must.  Although it may seem tedious to repeatedly derive these concrete details from the abstract concepts, that engagement is absolutely critical for achieving your highest quality expression.  This is not a checklist to satisfy; this is a philosophy for maximizing successful achievement of your goals.
EOT

# Keep this text single-line, with straight quotes and no backslashes, so it needs no
# JSON escaping when emitted.
read -r -d '' ROUTE_TEXT <<'EOT'
Before substantive work, identify the medium of your primary deliverable and load the ONE skill that matches: code - source, tests, schemas, configs, scripts, infrastructure - Skill(laws:code); text another LLM will consume - task prompts, subagent instructions, guidance documents, skill bodies, hook text - Skill(laws:prompt); prose for humans - docs, READMEs, reports, messages - Skill(laws:prose). Load one, not two: each carries a different standard, and stacking them lets one medium's rules corrupt another's work. Switch skills only if the medium itself changes.
EOT

SESSION_TEXT="${ROUTE_TEXT}  ${ENGAGE_TEXT}"

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

# The two substitutions are defensive: the text as written needs no escaping, but a later
# edit could reintroduce a backslash or newline, and either would silently break the
# emitted JSON. Escaping them here keeps that guarantee off the editor's memory.
emit() {
  local ctx=$2
  ctx=${ctx//\\/\\\\}
  ctx=${ctx//$'\n'/ }
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$ctx"
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
