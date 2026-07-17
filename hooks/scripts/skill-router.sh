#!/bin/bash
# Session hooks for the laws plugin.
#
#   session-start  — fires once per session (SessionStart): route to the ONE
#                    medium-matched skill for the work ahead.
#   engage         — fires on every user message (UserPromptSubmit): re-activate the
#                    laws for that specific request.
#
# Routing is a once-per-session concern; engagement is a per-message one, so they live
# in separate hooks with separate texts, not one blob emitted twice.
#
# No external dependencies — pure bash (3.2+), so it runs anywhere Claude Code does.

HOOK_TYPE="$1"

# The engagement text — injected fresh on every user message so each request re-enters
# the philosophy rather than coasting on a stale session-start reminder. Closest
# descendant of the original universal-laws reminder, which was itself pure engagement.
# Keep it single-line, with straight quotes and no backslashes, so it needs no JSON
# escaping when emitted.
read -r -d '' ENGAGE_TEXT <<'EOT'
For the following request, please consider the laws and devices of your craft and directly consider how you will apply them to achieve the highest quality expression of your work.  You can improve your results substantially by expressing this directly in the chat.  Engaging with the laws and devices is a must.  Although it may seem tedious to repeatedly derive these concrete details from the abstract concepts, that engagement is absolutely critical for achieving your highest quality expression.  This is not a checklist to satisfy; this is a philosophy for maximizing successful achievement of your goals.
EOT

# The routing text — injected once at session start to load the medium-matched skill.
# Same formatting constraints as ENGAGE_TEXT: single-line, straight quotes, no
# backslashes, so it needs no JSON escaping.
read -r -d '' ROUTE_TEXT <<'EOT'
Before substantive work, identify the medium of your primary deliverable and load the ONE skill that matches: code - source, tests, schemas, configs, scripts, infrastructure - Skill(laws:code); text another LLM will consume - task prompts, subagent instructions, guidance documents, skill bodies, hook text - Skill(laws:prompt); prose for humans - docs, READMEs, reports, messages - Skill(laws:prose). Load one, not two: each carries a different standard, and stacking them lets one medium's rules corrupt another's work. Switch skills only if the medium itself changes.
EOT

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
    emit "SessionStart" "$ROUTE_TEXT"
    ;;

  engage)
    emit "UserPromptSubmit" "$ENGAGE_TEXT"
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
