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
#                    refuses is not a second craft but a conflicting ORDERING: an engaged
#                    craft whose standard corrupts the one now being loaded. The edges live
#                    in incompatible-crafts.txt and nothing here hard-codes them. Every edge
#                    runs ONE WAY - the reverse ordering is allowed unless it has its own
#                    edge - so the guard must be read as a directed rule, never a mutual
#                    incompatibility. This turns "what is loaded" from luck into owned
#                    state and refuses a conflicting addition, naming the craft it
#                    clashes with.
#
# Routing is re-injected on EVERY message, not only at session start, so it carries the
# same durability as a line in a system prompt: a long or compacted session can bury a
# single session-start injection, but a per-message re-injection is present on every
# turn. This is deliberate - the plugin owns routing end to end and needs nothing in any
# CLAUDE.md to stay loaded. Engagement rides along in the same per-message text.
#
# No external dependencies - pure bash (3.2+), so it runs anywhere Claude Code does.
# The guard parses a few string fields out of the hook's JSON stdin without jq. That is
# sound for the CONSTRAINED tokens - session_id, agent_id, source, tool_name, and
# tool_input.skill are a UUID, a hex id, a lowercase word, or a skill name like
# "laws:code", none of which can contain a quote, backslash, or newline that would need
# real JSON decoding.

HOOK_TYPE="$1"

# The engagement text - injected fresh on every user message so each request re-enters
# the philosophy rather than coasting on a stale session-start reminder. Closest
# descendant of the original universal-laws reminder, which was itself pure engagement.
# Keep it single-line, with straight quotes and no backslashes, so it needs no JSON
# escaping when emitted.
read -r -d '' ENGAGE_TEXT <<'EOT'
For the following request, please consider the laws and devices of your craft and directly consider how you will apply them to achieve the highest quality expression of your work.  You can improve your results substantially by expressing this directly in the chat.  Engaging with the laws and devices is a must.  Although it may seem tedious to repeatedly derive these concrete details from the abstract concepts, that engagement is absolutely critical for achieving your highest quality expression.  This is not a checklist to satisfy; this is a philosophy for maximizing successful achievement of your goals.
EOT

# The incompatibility policy is DATA, and it lives in one file, incompatible-crafts.txt, so
# the rule has a single home ([LAW:one-source-of-truth]). This script hard-codes no craft
# name; changing the policy is editing that file. Comments (#) and blank lines are stripped
# HERE, so conflicts_with below sees only "a b" pair lines - the read is re-derived every
# process launch, so the file is the source and this variable is just its cache, never a
# second copy that can drift.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/incompatible-crafts.txt"
INCOMPATIBLE=""
# A carriage return is whitespace. `read` does not split on it, so a CRLF line "a b" would
# otherwise parse with to="b\r": two tokens, no warning, and an edge that never matches.
# [LAW:no-silent-failure]
[ -r "$POLICY_FILE" ] && INCOMPATIBLE="$(tr '\r' ' ' < "$POLICY_FILE" | sed -E 's/#.*$//' | grep -E '[^[:space:]]')"
# THE policy parser for this script - run once, at launch, so every consumer downstream reads
# the same normalized edge list instead of re-reading the raw file with a parser of its own.
# Emits one "engaged refused" line per WELL-FORMED edge and drops the rest loudly.
#
# EXACTLY TWO TOKENS, or the line is not an edge and the operator is told. `read -r from to`
# alone silently swallows a third word INTO $to ("a b extra-note" -> to="b
# extra-note"), which can never equal an incoming craft name - so the edge quietly becomes a
# permanent no-op. The third field exists solely to catch what a two-field read would hide.
# [LAW:no-silent-failure]
parse_edges() {
  local from to extra
  while read -r from to extra; do
    [ -n "$from" ] || continue
    if [ -z "$to" ] || [ -n "$extra" ]; then
      echo "laws policy: ignoring malformed line (expected exactly two craft names): $from${to:+ $to}${extra:+ $extra}" >&2
      continue
    fi
    printf '%s %s\n' "$from" "$to"
  done <<EOF
$INCOMPATIBLE
EOF
}
EDGES="$(parse_edges)"
# Tested on the PARSED edges, because no edges is what turns the guard off: conflicts_with then
# answers false for everything. A missing file, a comment-only file, and a file whose every line is
# malformed all arrive here, so all three get this warning instead of passing as "everything
# coexists". A lost policy must never BLOCK skill loading, but it must never be silent either.
# [LAW:no-silent-failure] [LAW:dataflow-not-control-flow] the degrade is one path, not three.
if [ -z "$EDGES" ]; then
  echo "laws skill-router guard: no craft pairs readable from $POLICY_FILE; craft compatibility enforcement disabled this session" >&2
fi


# The routing text - injected at session start AND re-asserted on every user message
# (see the engage case), so it stays loaded.
#
# The heredoc is QUOTED, like ENGAGE_TEXT's. It was unquoted while it interpolated the
# rendered conflict clause; that renderer is gone, so nothing here needs substitution and
# the quoting closes the hazard the substitution used to require us to live with - a `$`,
# a backtick, or a backslash in the prose expanding at hook launch, or breaking the JSON,
# with every test still green. Keep it quoted: the prose is the kind of thing that gets
# reworded by someone thinking about wording, not about shell. [LAW:no-silent-failure]
# Same formatting constraints as ENGAGE_TEXT otherwise: single line, straight quotes, no
# backslashes, so it needs no JSON escaping.
read -r -d '' ROUTE_TEXT <<'EOT'
Before substantive work, identify the medium of your primary deliverable and load the craft skill that matches, if one does.
EOT

# Read the hook's JSON payload once. Every hook event delivers JSON on stdin.
#
# The newline strip is NOT cosmetic and is not removable: json_field matches with a single
# `grep -oE`, which is line-oriented, so a pretty-printed payload that puts a key and its
# value on separate lines would simply fail to match and the field would come back empty.
# Collapsing first makes extraction independent of whether Claude Code sends compact or
# pretty-printed JSON, rather than leaving that a latent assumption. [LAW:no-silent-failure]
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

# True (exit 0) iff an already-loaded $1 forbids loading an incoming $2, per the INCOMPATIBLE
# policy. DIRECTED: it matches a line in THAT ORDER ONLY, because the policy's edges run one way.
# It reads the policy data and hard-codes
# no craft name, so changing the rule is editing INCOMPATIBLE, never this function.
#
# THE ARGUMENT ORDER IS THE CONTRACT. This was symmetric once, and under symmetry a caller
# could pass its arguments in the wrong order with no symptom, because the predicate was
# incapable of telling them apart. [LAW:types-are-the-program]
conflicts_with() {
  local engaged=$1 incoming=$2 from to
  # Reads EDGES, the already-parsed well-formed pairs - malformed lines were rejected once, at
  # launch, by the one parser, so no consumer re-reads the raw file with a parser of its own.
  while read -r from to; do
    [ -n "$from" ] || continue
    if [ "$from" = "$engaged" ] && [ "$to" = "$incoming" ]; then
      return 0
    fi
  done <<EOF
$EDGES
EOF
  return 1
}

# --- emitters -------------------------------------------------------------------------
# Escaping a value for inclusion in a JSON string. Every emitter and every file this script
# writes goes through here, so the rule has one home instead of a copy per call site that
# can drift - the divergence [LAW:one-source-of-truth] exists to prevent. Backslash first,
# or it would re-escape the escapes the other substitutions introduce.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "${s//$'\n'/\\n}"
}

# The escaping is defensive here: the routing text as written needs none, but a later edit
# could reintroduce a backslash or newline, and either would silently break the emitted JSON.
emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$(json_escape "$2")"
}

# Refuse the tool call and hand the reason back to the agent. The reason is assembled below
# from a skill name, so it can carry a quote in principle.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
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
    # load leaves no phantom engagement) and deny, naming the crafts it clashes with. Two racing
    # incompatible loads each claim, each see the other, and each release+deny - neither ends up
    # engaged, an over-refusal the agent recovers from by retrying one. That is the safe
    # direction: never silently co-engage a conflicting ordering.
    #
    # THE WHOLE SET IS COLLECTED BEFORE DENYING, rather than denying on the first marker the glob
    # returns: the refusal names every craft the load clashes with, not whichever one the
    # filesystem happened to order first. [LAW:no-silent-failure]
    conflicts=""
    for other in "$slot"/*; do
      [ -e "$other" ] || continue
      other=${other##*/}
      [ "$other" = "$(sanitize "$craft")" ] && continue
      # (engaged, incoming) — $other is the marker already on disk, $craft is the load being
      # attempted. Passing these the other way round asks whether the INCOMING craft would
      # forbid the engaged one, which is a different question with a different answer.
      if conflicts_with "$other" "$craft"; then
        conflicts="${conflicts:+$conflicts,}$other"
      fi
    done
    if [ -n "$conflicts" ]; then
        # Rendered once, for every message below: "laws:code" or "laws:code, laws:prose".
        conflicts_pretty="laws:${conflicts//,/, laws:}"
        rm -f "$marker"
        # There is no way to move a running session from one craft to another - the refusal names
        # the one honest alternative, a fresh session. [LAW:no-mode-explosion]
        deny "Craft already engaged this session: $conflicts_pretty. Loading laws:$craft after it is refused: laws:$craft work written in this ordering comes out wrong (design-docs/working-with-skills.md). Do the laws:$craft work in a fresh subagent that loads only that skill - not a fork, not any subagent that inherits this conversation, since either carries the engaged craft where the guard cannot see it. The subagent sees only its prompt, so put in it: the requester's requirements in their own words, the exact output path, what a correct result looks like, and an instruction to read its artifact back against those before reporting. Keep only its answer. If this session's whole job has become laws:$craft, there is no in-session switch: start fresh with /clear and load it clean."
        exit 0
    fi
    exit 0
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
