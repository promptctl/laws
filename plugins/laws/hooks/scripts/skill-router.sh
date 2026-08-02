#!/bin/bash
# Session hooks for the laws plugin.
#
#   session-start  - fires at session start, including after /compact (SessionStart):
#                    the initial routing load before the first message. Also resets the
#                    medium lock when the session is genuinely fresh (see guard, below).
#   engage         - fires on every user message (UserPromptSubmit): re-assert routing
#                    AND re-activate the laws for that specific request.
#   guard          - fires before every Skill load (PreToolUse, matcher Skill): the one
#                    checkpoint that enforces one-craft-per-session. Routing only ASKS
#                    the agent to load a single medium; nothing before this observed the
#                    actual load, so a second medium loaded silently. This turns "which
#                    medium loaded first" from luck into owned state and refuses a second.
#
# Routing is re-injected on EVERY message, not only at session start, so it carries the
# same durability as a line in a system prompt: a long or compacted session can bury a
# single session-start injection, but a per-message re-injection is present on every
# turn. This is deliberate - the plugin owns routing end to end and needs nothing in any
# CLAUDE.md to stay loaded. Engagement rides along in the same per-message text.
#
# No external dependencies - pure bash (3.2+), so it runs anywhere Claude Code does.
# The guard parses a few string fields out of the hook's JSON stdin without jq; that is
# safe here because every field it reads (session_id, agent_id, source, tool_name, and
# tool_input.skill) is a constrained token - a UUID, a hex id, a lowercase word, or a
# skill name like "laws:code" - none of which can contain a quote, backslash, or newline
# that would need real JSON decoding.

HOOK_TYPE="$1"

# The engagement text - injected fresh on every user message so each request re-enters
# the philosophy rather than coasting on a stale session-start reminder. Closest
# descendant of the original universal-laws reminder, which was itself pure engagement.
# Keep it single-line, with straight quotes and no backslashes, so it needs no JSON
# escaping when emitted.
read -r -d '' ENGAGE_TEXT <<'EOT'
For the following request, please consider the laws and devices of your craft and directly consider how you will apply them to achieve the highest quality expression of your work.  You can improve your results substantially by expressing this directly in the chat.  Engaging with the laws and devices is a must.  Although it may seem tedious to repeatedly derive these concrete details from the abstract concepts, that engagement is absolutely critical for achieving your highest quality expression.  This is not a checklist to satisfy; this is a philosophy for maximizing successful achievement of your goals.
EOT

# The routing text - injected at session start AND re-asserted on every user message
# (see the engage case), so it stays loaded with system-prompt durability and needs no
# CLAUDE.md entry. Same formatting constraints as ENGAGE_TEXT: single-line, straight
# quotes, no backslashes, so it needs no JSON escaping.
read -r -d '' ROUTE_TEXT <<'EOT'
Before substantive work, identify the medium of your primary deliverable and load the ONE skill that matches: Skill(laws:code); Skill(laws:prompt); Skill(laws:prose). Load one, NEVER two: each carries a different standard, and stacking them lets one medium's rules corrupt another's work.
EOT

# Read the hook's JSON payload once. Every hook event delivers JSON on stdin; session-start
# and guard read fields out of it, engage ignores it. Harmless where unused. Newlines are
# stripped so field extraction is independent of whether Claude Code sends compact or
# pretty-printed JSON - a string key/value pair is intra-line either way, but collapsing
# first makes that independence explicit rather than a latent assumption.
INPUT=$(cat | tr -d '\n')

# --- pure-bash field extraction -------------------------------------------------------
# Pull the string value of a JSON key. Only used for the constrained tokens named in the
# header, whose values never contain an escaped quote - so "key" ... "value" is the whole
# grammar we need, and a real JSON parser would buy nothing but a dependency.
json_field() {
  local key=$1
  printf '%s' "$INPUT" \
    | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/'
}

# Filesystem-safe rendering of an id. UUIDs and hex agent ids pass through unchanged; the
# tr collapses anything else - notably a slash or a dot - so no id can smuggle a path
# separator or a ".." into the lock path that session-start later feeds to rm -rf.
sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'
}

# --- the medium lock ------------------------------------------------------------------
# One clock for "which medium is engaged": a file whose presence means locked and whose
# contents name the medium. Keyed by session_id AND agent_id, because a dispatched
# subagent shares the parent's session_id (verified) and is distinguished only by its
# agent_id - so keying on session_id alone would make the subagent inherit the parent's
# lock and break the sanctioned escape hatch (do a second medium's work in a subagent).
# The main session has no agent_id, so it lands in the "main" slot.
LOCK_ROOT="${TMPDIR:-/tmp}/laws-medium-lock"

lock_dir_for() {
  printf '%s/%s' "$LOCK_ROOT" "$(sanitize "$1")"
}

lock_file_for() {
  local sid=$1 aid=$2 slot=main
  [ -n "$aid" ] && slot=$(sanitize "$aid")
  printf '%s/%s' "$(lock_dir_for "$sid")" "$slot"
}

# --- emitters -------------------------------------------------------------------------
# The two substitutions are defensive: the routing text as written needs no escaping, but
# a later edit could reintroduce a backslash or newline, and either would silently break
# the emitted JSON. Escaping them here keeps that guarantee off the editor's memory.
emit() {
  local ctx=$2
  ctx=${ctx//\\/\\\\}
  ctx=${ctx//$'\n'/ }
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$ctx"
}

# Refuse the tool call and hand the reason back to the agent. The reason is assembled
# below from a skill name, so it can carry a quote in principle; escape all three JSON
# metacharacters, not just the two emit() handles.
deny() {
  local reason=$1
  reason=${reason//\\/\\\\}
  reason=${reason//\"/\\\"}
  reason=${reason//$'\n'/ }
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
}

case "$HOOK_TYPE" in
  session-start)
    # A fresh session starts with no medium engaged. startup/clear/fork are the sources
    # that begin a new logical context (startup and fork also carry a new session_id, so
    # the removal is a no-op there; clear can reuse the id, which is the case that needs
    # it). resume and compact continue the same session, so the lock must survive them -
    # exactly as the routing text itself is built to survive compaction.
    sid=$(json_field session_id)
    source=$(json_field source)
    case "$source" in
      startup|clear|fork)
        [ -n "$sid" ] && rm -rf "$(lock_dir_for "$sid")"
        ;;
    esac
    emit "SessionStart" "$ROUTE_TEXT"
    ;;

  engage)
    # Route first (load the medium-matched skill), then engage (apply it). Emitting the
    # full routing text here - not a short reminder - is what gives it CLAUDE.md-grade
    # durability: the complete instruction is present on every turn, so even a compacted
    # context that dropped the session-start load still carries it.
    emit "UserPromptSubmit" "$ROUTE_TEXT $ENGAGE_TEXT"
    ;;

  guard)
    # The one checkpoint for one-craft-per-session. A medium is any laws:<x> craft skill;
    # the colon is the whole discriminator, so the set of media is derived from the
    # namespace rather than enumerated here - a new medium is covered the day it is added,
    # and the meta-skill "laws" (no colon) is excluded for free. Everything that is not a
    # laws: craft - "next", "address-pr-reviews", plain "laws" - flows straight through.
    tool=$(json_field tool_name)
    skill=$(json_field skill)
    case "$tool" in
      Skill) ;;
      *) exit 0 ;;
    esac
    case "$skill" in
      laws:?*) ;;
      *) exit 0 ;;
    esac

    sid=$(json_field session_id)
    aid=$(json_field agent_id)
    if [ -z "$sid" ]; then
      # No session id means no way to key the lock. Let the load through so skill loading
      # never breaks, but say so loudly (PreToolUse stderr surfaces in hook debug) rather
      # than pretend the guard ran - a silent pass here would be the original hole back.
      echo "laws skill-router guard: empty session_id, medium lock skipped for $skill" >&2
      exit 0
    fi

    lock=$(lock_file_for "$sid" "$aid")
    engaged=""
    [ -f "$lock" ] && engaged=$(cat "$lock")

    if [ -z "$engaged" ]; then
      # First medium of the (sub)session: record it, atomically. The write is the guard's
      # one external effect and its own concurrency control - noclobber makes the redirect
      # fail if a parallel guard already created the lock, turning a check-then-write race
      # into a compare-and-swap. A winner records and allows. A loser re-reads the lock and
      # falls through to the comparison below, so a racing SECOND medium is still refused,
      # never slipped through. A genuine write failure (full or unwritable TMPDIR) leaves no
      # lock: warn and still allow - degraded enforcement beats blocking every skill load,
      # the same loud-but-non-blocking tradeoff as the empty-session_id branch.
      mkdir -p "$(dirname "$lock")"
      if ( set -o noclobber; printf '%s' "$skill" > "$lock" ) 2>/dev/null; then
        exit 0
      fi
      engaged=""
      [ -f "$lock" ] && engaged=$(cat "$lock")
      if [ -z "$engaged" ]; then
        echo "laws skill-router guard: could not write medium lock for $skill; one-craft enforcement degraded this session" >&2
        exit 0
      fi
      # A concurrent guard won the create; fall through to compare against what it recorded.
    fi

    if [ "$engaged" = "$skill" ]; then
      # Re-loading the same medium (e.g. re-routing to it after a compaction) is idempotent.
      exit 0
    fi

    deny "Medium already engaged this session: $engaged. Loading $skill would put a second craft standard on duty, and two standards stacked corrupt each other's work - the one-craft-per-session rule this plugin enforces (design-docs/working-with-skills.md). To do $skill work, dispatch a fresh subagent seeded with only that skill and keep just its answer; do not load a second craft here. If this whole session's job has genuinely become $skill, run /clear first, then load it clean."
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
