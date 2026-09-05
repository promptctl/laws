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
#                    in incompatible-crafts.txt and nothing here hard-codes them; today that
#                    file holds laws:code THEN laws:prompt. Every edge runs ONE WAY - loading
#                    laws:code after laws:prompt is allowed - so the guard must be read as
#                    a directed rule, never a mutual incompatibility. This turns "what is
#                    loaded" from luck into owned state and refuses a conflicting addition,
#                    naming the craft it clashes with.
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
#
# transcript_path is the one field that is NOT such a token: it is an absolute filesystem
# path, and a quote or backslash in it truncates json_field's "[^"]*" grammar mid-value.
# The read is therefore treated as untrusted rather than assumed exact - the guard requires
# the extracted path to name an existing file before it will act on it, so a mangled read
# withholds the switch offer instead of writing a corrupt one. See the guard branch below.

HOOK_TYPE="$1"

# The engagement text - injected fresh on every user message so each request re-enters
# the philosophy rather than coasting on a stale session-start reminder. Closest
# descendant of the original universal-laws reminder, which was itself pure engagement.
# Keep it single-line, with straight quotes and no backslashes, so it needs no JSON
# escaping when emitted.
read -r -d '' ENGAGE_TEXT <<'EOT'
For the following request, please consider the laws and devices of your craft and directly consider how you will apply them to achieve the highest quality expression of your work.  You can improve your results substantially by expressing this directly in the chat.  Engaging with the laws and devices is a must.  Although it may seem tedious to repeatedly derive these concrete details from the abstract concepts, that engagement is absolutely critical for achieving your highest quality expression.  This is not a checklist to satisfy; this is a philosophy for maximizing successful achievement of your goals.
EOT

# The incompatibility policy is DATA, and it lives in one file read by BOTH enforcers -
# this guard AND the runtime gate (laws-excise.js) - so the rule has a single home
# ([LAW:one-source-of-truth], the divergence the two used to risk). This script hard-codes
# no craft name; changing the policy is editing incompatible-crafts.txt. Comments (#) and
# blank lines are stripped HERE, so conflicts_with below sees only "a b" pair lines,
# exactly the shape the former inline heredoc handed it - the read is re-derived every
# process launch, so the file is the source and this variable is just its cache, never a
# second copy that can drift.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/incompatible-crafts.txt"
INCOMPATIBLE=""
[ -r "$POLICY_FILE" ] && INCOMPATIBLE="$(sed -E 's/#.*$//' "$POLICY_FILE" | grep -E '[^[:space:]]')"
# One condition for both ways the policy can fail to arrive, because they have identical
# consequences: no edges means conflicts_with answers false for everything and the guard
# is off. Unreadable and readable-but-pairless are the same degraded state, so they get the
# same warning rather than one being announced and the other passing as "everything coexists"
# - which is what an unchecked `grep` exit status used to do to a comment-only policy file.
# A lost policy must never BLOCK skill loading, but it must never be silent either.
# [LAW:no-silent-failure] [LAW:dataflow-not-control-flow] the degrade is one path, not two.
if [ -z "$INCOMPATIBLE" ]; then
  echo "laws skill-router guard: no craft pairs readable from $POLICY_FILE; craft compatibility enforcement disabled this session" >&2
fi

# THE policy parser for this script - run once, at launch, so every consumer downstream reads
# the same normalized edge list instead of re-reading the raw file with a parser of its own.
# Emits one "engaged refused" line per WELL-FORMED edge and drops the rest loudly.
#
# EXACTLY TWO TOKENS, or the line is not an edge and the operator is told. `read -r from to`
# alone silently swallows a third word INTO $to ("code prompt extra-note" -> to="prompt
# extra-note"), which can never equal an incoming craft name - so the edge quietly became a
# permanent no-op here while parsePolicy in laws-excise.js truncated the same line to a live
# code->prompt edge and enforced it. Two enforcers, one file, opposite rules, no symptom. The
# third field exists solely to catch what a two-field read would otherwise hide.
# [LAW:single-enforcer] [LAW:no-silent-failure]
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

# The conflict clause of the routing text, RENDERED FROM THE POLICY rather than written out.
# The routing text is injected at the moment an agent picks a craft, and an agent will not open
# a file at that moment - so the clause has to name the actual edges. Naming them in prose made
# the routing text a second copy of the policy that no one would notice going stale the day a
# second edge was added. Rendering it from EDGES keeps the concrete wording AND leaves the file
# the only place an edge is declared. [LAW:one-source-of-truth]
#
# The empty case drops the trailing sentence rather than emitting "These orderings are refused: ."
# - a list-shaped opening with no list is an answer-shaped void, and the sentence explaining why
# an ordering is listed has nothing to explain when nothing is. [LAW:parse-dont-validate]
render_conflict_clause() {
  local from to clauses=""
  while read -r from to; do
    [ -n "$from" ] || continue
    clauses="${clauses:+$clauses; }once laws:$from is engaged, laws:$to is refused"
  done <<EOF
$EDGES
EOF
  if [ -z "$clauses" ]; then
    printf '%s' "No craft ordering is currently refused."
    return
  fi
  printf '%s' "These orderings are refused: $clauses. An ordering is listed only because it was shown to corrupt real work - the engaged craft's standard degrades what you would write next in the refused one."
}
CONFLICT_CLAUSE="$(render_conflict_clause)"

# The routing text - injected at session start AND re-asserted on every user message
# (see the engage case), so it stays loaded with system-prompt durability and needs no
# CLAUDE.md entry. Same formatting constraints as ENGAGE_TEXT: single-line, straight
# quotes, no backslashes, so it needs no JSON escaping. The heredoc is unquoted for the one
# substitution it carries; nothing else in the text is shell-special.
read -r -d '' ROUTE_TEXT <<EOT
Before substantive work, identify the medium of your primary deliverable and load the skill that matches: Skill(laws:code); Skill(laws:prompt); Skill(laws:prose). $CONFLICT_CLAUSE Avoid stacking crafts even where allowed; each body is large and context is scarce. Do the other craft's work in a fresh subagent seeded with only that skill - never a fork or context-inheriting subagent, which brings the engaged craft along where the guard cannot see it.
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
# policy. DIRECTED: it matches a line in THAT ORDER ONLY, because the policy's edges run one way
# (code degrades prompts; prompt does not degrade code). It reads the policy data and hard-codes
# no craft name, so changing the rule is editing INCOMPATIBLE, never this function.
#
# THE ARGUMENT ORDER IS THE CONTRACT. This was symmetric once, and under symmetry the two
# enforcers could - and did - pass their arguments in opposite orders with no symptom, because
# the predicate was incapable of telling them apart. Mirrors conflictsWith(engaged, incoming) in
# laws-excise.js exactly; if these two ever disagree about the order, the guard and the gate
# enforce opposite rules. [LAW:single-enforcer] [LAW:types-are-the-program]
conflicts_with() {
  local engaged=$1 incoming=$2 from to
  # Reads EDGES, the already-parsed well-formed pairs - malformed lines were rejected once, at
  # launch, by the one parser. This used to re-parse the raw file itself, which is how a
  # three-token line came to mean one thing here and another in laws-excise.js.
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
    # returns. The gate retires EVERY conflicting craft (laws-excise decide()), so naming only the
    # first - whichever the filesystem happened to order first - would promise the user a different
    # outcome than the switch delivers. One decision, one rule, both enforcers.
    # [LAW:one-source-of-truth] [LAW:single-enforcer]
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
        # The switch is an extra ROUTE OUT of the deny, offered only when the session was started
        # by the laws launcher (only a HOSTED session can enact the choice against its own live
        # conversation). Built as a VALUE - empty when unavailable - and always appended, so the
        # deny path itself is the same code every time. [LAW:dataflow-not-control-flow]
        switch_offer=""
        # ONLY THE SESSION THE LAUNCHER STARTED MAY BE OFFERED THE SWITCH, and the test is
        # identity, not inference. The launcher pins its session id up front (claude --session-id)
        # and exports it, so this compares ids rather than guessing from context.
        #
        # Everything else that reaches this code inherits LAWS_SWITCH_DIR from the launcher's
        # environment and would otherwise look eligible:
        #   - a dispatched SUBAGENT shares the owning session_id and is told apart only by
        #     agent_id, which is why the id check alone is not enough;
        #   - a NESTED `claude` started from a Bash call is its own top-level session - own
        #     session_id, no agent_id at all - so an "am I not a subagent" test lets it straight
        #     through.
        # Either one writing pending.json overwrites the HOSTING session's offer, and the host reads
        # the offer rather than the request - so it would recompute the switch from a transcript that
        # is not its own and then apply the result to its own live conversation. The subagent escape
        # hatch this very deny recommends would rewind its own caller to a point that never existed
        # there.
        # [LAW:composability] the dependence on being the launcher's own session is checked, never
        # assumed from the ambient environment.
        if [ -n "${LAWS_SWITCH_SESSION:-}" ] && [ "$sid" = "${LAWS_SWITCH_SESSION:-}" ] \
           && [ -z "$aid" ] && [ -n "${LAWS_SWITCH_DIR:-}" ] && [ -d "${LAWS_SWITCH_DIR:-}" ]; then
          transcript=$(json_field transcript_path)
          # A transcript path is not a constrained token (see the header), so the extraction is
          # not assumed exact - it has to name a file that is really there. A path truncated at
          # an embedded quote fails this and the deny goes out with no switch, rather than
          # advertising one backed by a corrupt pending.json. [LAW:parse-dont-validate] the check
          # yields a path known to resolve, not a promise that it does.
          if [ -f "$transcript" ]; then
            # `current` carries the whole conflicting set, comma-joined - the same wire format the
            # launcher reads back from the gate. Craft names are media slugs, so ',' cannot occur
            # inside one.
            if printf '{"sessionId":"%s","transcript":"%s","current":"%s","incomingMedium":"%s"}\n' \
                 "$(json_escape "$sid")" "$(json_escape "$transcript")" \
                 "$(json_escape "$conflicts")" "$(json_escape "$craft")" \
                 > "$LAWS_SWITCH_DIR/pending.json"; then
              switch_offer=" OR SWITCH: this session can move to laws:$craft by retiring $conflicts_pretty, keeping your work on disk either way. Run 'laws-switch <option>': reject (stay in $conflicts_pretty, change nothing); tombstone (keep the whole conversation, retire the $conflicts_pretty guidance in place - cheapest to reason about, most expensive when the session is deep); rewind_summarize --summary '<what you did since $conflicts_pretty loaded>' (rewind to that point and carry your work forward as a summary you write now, because after the rewind only you know it - summarize YOUR WORK ONLY and carry none of $conflicts_pretty's guidance into it, or you re-inject the guidance this switch exists to retire); rewind_discard (rewind to just before $conflicts_pretty loaded and drop the conversation since). Files you have written are never reverted by any option. Ask the user which they want unless they have already said."
            else
              # The offer is only made when the decision it depends on was actually recorded.
              # Advertising it after a failed write would send the agent to laws-switch to be told
              # "no pending craft switch" - which contradicts the deny it is holding and points it
              # at the wrong diagnosis. Withhold the offer and say why, matching the empty-session_id
              # and unwritable-lock branches above. [LAW:no-silent-failure]
              echo "laws skill-router guard: could not record the pending craft switch in $LAWS_SWITCH_DIR; denying without a switch offer" >&2
            fi
          else
            # A withheld offer has two very different causes that look identical from outside: the
            # launcher legitimately not offering one (subagent, nested claude, unpinned session),
            # and THIS - a transcript_path that did not survive extraction, which the header's own
            # example of a path truncated at an embedded quote produces. Falling through silently
            # collapses a parsing failure onto the shape of a deliberate decision, so the reader
            # cannot tell a broken hook from a working one. Say which it was, matching the
            # write-failure branch above. [LAW:no-silent-failure]
            echo "laws skill-router guard: transcript_path did not resolve to a readable file (got '$transcript'); denying without a switch offer" >&2
          fi
        fi
        deny "Craft already engaged this session: $conflicts_pretty. Loading laws:$craft on top of it would corrupt your laws:$craft work - the damage runs THIS WAY ONLY, so it is this ordering that is refused, not the pairing (design-docs/working-with-skills.md). To do laws:$craft work now, dispatch a fresh subagent seeded with only that skill, and keep only its answer. Not a fork, and not any subagent that inherits this conversation: it starts with the engaged craft already in its context, so it reproduces exactly this corruption - and the guard cannot catch that, because the craft lock is per-agent and records loads, not inherited context. If this session's whole job has become laws:$craft, run /clear, then load it clean.$switch_offer"
        exit 0
    fi
    exit 0
    ;;

  retire-craft)
    # The launcher's half of retiring a craft, and the reason a switch takes effect at all.
    #
    # Retiring a craft is ONE job with two halves: the transcript surgery removes the craft's
    # guidance, and this releases the engagement marker. Ship only the first and the resumed
    # session refuses the very load the switch existed to permit - the transcript says the craft
    # is gone while the lock still says it is engaged. A --resume keeps the same session_id
    # (measured, 2.1.226), so the lock is the SAME slot the guard already refused from, and
    # session-start deliberately preserves the set across resume. Both halves or neither.
    # [LAW:composability] one complete job, no hidden strings - the same lesson rewindTo records.
    #
    # The lock layout (LOCK_ROOT, sanitize, slot_dir_for) lives in this file and only here, so
    # the launcher asks for the release instead of rebuilding the path and drifting from it.
    # [LAW:one-source-of-truth]
    #
    # It releases only; it never pre-claims the incoming craft. A marker means "this craft
    # actually loaded", and the guard writes it when the load really happens - pre-claiming
    # would make the marker mean something weaker and lie whenever the load never came.
    sid=$(json_field session_id)
    aid=$(json_field agent_id)
    craft=$(json_field craft)
    if [ -z "$sid" ] || [ -z "$craft" ]; then
      echo "laws skill-router retire-craft: need both session_id and craft" >&2
      exit 2
    fi
    marker="$(slot_dir_for "$sid" "$aid")/$(sanitize "$craft")"
    # Two different facts, kept apart rather than collapsed into one exit code. An absent marker
    # means the postcondition already holds (the store was cleared, or the guard degraded and
    # never wrote one) - note it and succeed. A marker that will not delete means the guard will
    # still refuse the incoming craft, so the switch silently did nothing: that is a failure and
    # it exits loudly. [LAW:no-silent-failure]
    if [ ! -e "$marker" ]; then
      echo "laws skill-router retire-craft: laws:$craft was not engaged; nothing to release" >&2
      exit 0
    fi
    if ! rm -f "$marker"; then
      echo "laws skill-router retire-craft: could not release laws:$craft ($marker)" >&2
      exit 1
    fi
    ;;

  *)
    # Unknown hook type, do nothing
    ;;
esac
