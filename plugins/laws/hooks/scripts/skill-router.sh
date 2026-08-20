#!/bin/bash
# Session hooks for the laws plugin.
#
#   session-start  - fires at session start, including after /compact (SessionStart):
#                    the initial routing load before the first message. Also resets the
#                    engaged-craft set when the session is genuinely fresh (see guard, below).
#   engage         - fires on every user message (UserPromptSubmit): re-assert routing
#                    AND re-activate the laws for that specific request.
#   guard          - fires before every Skill load (PreToolUse, matcher Skill): the one
#                    checkpoint that enforces craft compatibility. Routing only ASKS the
#                    agent which craft to load; nothing before this observed the actual
#                    load. Compatible crafts may coexist in one session - code plus its
#                    ticket plus its docs is normal, complementary work - so what this
#                    refuses is not a second craft but an INCOMPATIBLE one: two standards
#                    that corrupt each other stacked. The one such pair today is laws:code
#                    with laws:prompt. This turns "what is loaded" from luck into owned
#                    state and refuses a conflicting addition, naming the craft it clashes.
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
Before substantive work, identify the medium of your primary deliverable and load the skill that matches: Skill(laws:code); Skill(laws:prompt); Skill(laws:prose). Compatible crafts may share a session, but laws:code and laws:prompt corrupt each other's work when stacked and cannot both be loaded - the guard refuses the conflicting second.
EOT

# The incompatibility policy is DATA, and it lives in one file read by BOTH enforcers -
# this guard AND the runtime gate (laws-excise.js) - so the rule has a single home
# ([LAW:one-source-of-truth], the divergence the two used to risk). This script hard-codes
# no craft name; changing the policy is editing incompatible-crafts.txt. Comments (#) and
# blank lines are stripped HERE, so crafts_incompatible below sees only "a b" pair lines,
# exactly the shape the former inline heredoc handed it - the read is re-derived every
# process launch, so the file is the source and this variable is just its cache, never a
# second copy that can drift.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/incompatible-crafts.txt"
if [ -r "$POLICY_FILE" ]; then
  INCOMPATIBLE="$(sed -E 's/#.*$//' "$POLICY_FILE" | grep -E '[^[:space:]]')"
else
  # Loud degrade, matching this script's ethos elsewhere (empty session_id, unwritable
  # store): a missing policy must never BLOCK skill loading, but it must not silently pass
  # as "everything coexists" either - announce it. [LAW:no-silent-failure]
  echo "laws skill-router guard: policy file not readable ($POLICY_FILE); craft compatibility enforcement disabled this session" >&2
  INCOMPATIBLE=""
fi

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

# --- the craft lock (the engaged set) -------------------------------------------------
# The record of "which crafts are engaged" is a DIRECTORY per (sub)session holding one
# empty marker file per engaged craft - a set, not a single value, because compatible
# crafts coexist. Keyed by session_id AND agent_id, because a dispatched subagent shares
# the parent's session_id (verified) and is distinguished only by its agent_id - so keying
# on session_id alone would make the subagent inherit the parent's set and break the
# sanctioned escape hatch (do an incompatible craft's work in a subagent). The main session
# has no agent_id, so it lands in the "main" slot.
LOCK_ROOT="${TMPDIR:-/tmp}/laws-craft-lock"

lock_dir_for() {
  printf '%s/%s' "$LOCK_ROOT" "$(sanitize "$1")"
}

# The slot directory for one (sub)session: its engaged-craft markers live inside it.
slot_dir_for() {
  local sid=$1 aid=$2 slot=main
  [ -n "$aid" ] && slot=$(sanitize "$aid")
  printf '%s/%s' "$(lock_dir_for "$sid")" "$slot"
}

# True (exit 0) iff crafts $1 and $2 are an incompatible pair per the INCOMPATIBLE policy.
# Symmetric: it matches a line in either order. It reads the policy data and hard-codes no
# craft name, so changing the rule is editing INCOMPATIBLE, never this function.
crafts_incompatible() {
  local a=$1 b=$2 x y
  while read -r x y; do
    [ -n "$x" ] || continue
    if { [ "$x" = "$a" ] && [ "$y" = "$b" ]; } || { [ "$x" = "$b" ] && [ "$y" = "$a" ]; }; then
      return 0
    fi
  done <<EOF
$INCOMPATIBLE
EOF
  return 1
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
    # A fresh session starts with no craft engaged. startup/clear/fork are the sources
    # that begin a new logical context (startup and fork also carry a new session_id, so
    # the removal is a no-op there; clear can reuse the id, which is the case that needs
    # it). resume and compact continue the same session, so the engaged set must survive
    # them - exactly as the routing text itself is built to survive compaction.
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
    # The one checkpoint for craft compatibility. A craft is any laws:<x> skill; the colon
    # is the whole discriminator, so the craft set is derived from the namespace rather than
    # enumerated here - a new craft is covered the day it is added, and the meta-skill "laws"
    # (no colon) is excluded for free. Everything that is not a laws: craft - "next",
    # "address-pr-reviews", plain "laws" - flows straight through.
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
    craft=${skill#laws:}

    sid=$(json_field session_id)
    aid=$(json_field agent_id)
    if [ -z "$sid" ]; then
      # No session id means no way to key the engaged set. Let the load through so skill
      # loading never breaks, but say so loudly (PreToolUse stderr surfaces in hook debug)
      # rather than pretend the guard ran - a silent pass here would be the original hole back.
      echo "laws skill-router guard: empty session_id, craft lock skipped for $skill" >&2
      exit 0
    fi

    slot=$(slot_dir_for "$sid" "$aid")
    marker="$slot/$(sanitize "$craft")"

    # Re-loading a craft already engaged is idempotent (e.g. re-routing to it after a
    # compaction): its marker is already present, nothing to add or refuse.
    [ -f "$marker" ] && exit 0

    # Claim this craft's marker FIRST, then check compatibility - the same compare-and-swap
    # discipline the single-lock guard used, generalized to a set. noclobber makes the create
    # atomic: the winner proceeds to the check; a loser either finds the marker already there
    # (a parallel duplicate of the same craft - allow) or hit an unwritable store (degrade to
    # a loud allow, the same non-blocking tradeoff as the empty-session_id branch - broken
    # enforcement must never break skill loading).
    mkdir -p "$slot" 2>/dev/null
    if ! ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
      [ -f "$marker" ] && exit 0
      echo "laws skill-router guard: could not write craft lock for $skill; compatibility enforcement degraded this session" >&2
      exit 0
    fi

    # Marker claimed. Refuse only if it is incompatible with a craft ALREADY engaged; scan the
    # set, skipping our own just-written marker. On a conflict, release our claim (so a denied
    # load leaves no phantom engagement) and deny, naming the craft it clashes with. Two racing
    # incompatible loads each claim, each see the other, and each release+deny - neither ends up
    # engaged, an over-refusal the agent recovers from by retrying one. That is the safe
    # direction: never silently co-engage an incompatible pair.
    for other in "$slot"/*; do
      [ -e "$other" ] || continue
      other=${other##*/}
      [ "$other" = "$(sanitize "$craft")" ] && continue
      if crafts_incompatible "$craft" "$other"; then
        rm -f "$marker"
        # The switch is an extra ROUTE OUT of the deny, offered only when the session was started
        # by claude-laws (it is the launcher that can relaunch and enact the choice). Built as a
        # VALUE - empty when unavailable - and always appended, so the deny path itself is the
        # same code every time. [LAW:dataflow-not-control-flow]
        switch_offer=""
        if [ -n "${LAWS_SWITCH_DIR:-}" ] && [ -d "${LAWS_SWITCH_DIR:-}" ]; then
          transcript=$(json_field transcript_path)
          if [ -n "$transcript" ]; then
            printf '{"sessionId":"%s","transcript":"%s","current":"%s","incomingMedium":"%s"}\n' \
              "$sid" "$transcript" "$other" "$craft" > "$LAWS_SWITCH_DIR/pending.json" || true
            switch_offer=" OR SWITCH: this session can move to laws:$craft by retiring laws:$other, keeping your work on disk either way. Run 'laws-switch <option>': reject (stay in laws:$other, change nothing); tombstone (keep the whole conversation, retire the laws:$other guidance in place - cheapest to reason about, most expensive when the session is deep); rewind_summarize --summary '<what you did since laws:$other loaded>' (rewind to that point and carry your work forward as a summary you write now, because after the rewind only you know it); rewind_discard (rewind to just before laws:$other loaded and drop the conversation since). Files you have written are never reverted by any option. Ask the user which they want unless they have already said."
          fi
        fi
        deny "Craft already engaged this session: laws:$other. It and laws:$craft corrupt each other's work when stacked, so they cannot both be loaded in one session - the compatibility rule this plugin enforces (design-docs/working-with-skills.md). Compatible crafts may coexist, but this pair may not. To do laws:$craft work, dispatch a fresh subagent seeded with only that skill and keep just its answer; do not load it here. If this whole session's job has genuinely become laws:$craft, run /clear first, then load it clean.$switch_offer"
        exit 0
      fi
    done
    exit 0
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
