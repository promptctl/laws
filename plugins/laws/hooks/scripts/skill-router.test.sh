#!/bin/bash
# Unit tests for the skill-router craft-compatibility guard. Pure bash, no jq - same
# dependency stance as the script under test, so the test runs anywhere the hook does.
#
# Each case feeds a synthetic hook payload (the exact shape Claude Code delivers on
# stdin, captured from a real PreToolUse run) to skill-router.sh and asserts the visible
# contract: an allowed load emits nothing, a refused load emits a deny decision. Compatible
# crafts coexist; only an incompatible pairing (today: laws:code + laws:prompt) is refused.
# State is isolated under a throwaway TMPDIR so a run never touches a real session's lock.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROUTER="$HERE/skill-router.sh"

export TMPDIR
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Detected violations are recorded under the XDG state dir; point it into the throwaway
# TMPDIR so no test run ever appends to the real ~/.local/state log.
export XDG_STATE_HOME="$TMPDIR/state"
VLOG="$XDG_STATE_HOME/claude-laws/violations.jsonl"

pass=0
fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail+1)); }

# run <hooktype> <payload-json> -> stdout of the hook (stderr silenced; asserted separately)
run() { printf '%s' "$2" | "$ROUTER" "$1" 2>/dev/null; }

# Payload builders keep the JSON in one place so a field rename is a one-line fix.
skill_payload() { # <session_id> <skill> [agent_id]
  local sid=$1 skill=$2 aid=${3:-}
  if [ -n "$aid" ]; then
    printf '{"session_id":"%s","agent_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$sid" "$aid" "$skill"
  else
    printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$sid" "$skill"
  fi
}
start_payload() { # <session_id> <source>
  printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$2"
}

assert_allow() { # <label> <output>
  [ -z "$2" ] && ok "$1" || bad "$1 (expected allow/empty, got: $2)"
}
assert_deny() { # <label> <output> <must-contain...>
  local label=$1 out=$2; shift 2
  case "$out" in *'"permissionDecision":"deny"'*) ;; *) bad "$label (no deny in: $out)"; return;; esac
  local needle
  for needle in "$@"; do
    case "$out" in *"$needle"*) ;; *) bad "$label (deny missing '$needle')"; return;; esac
  done
  ok "$label"
}

# 1. A non-medium skill is irrelevant to the lock and passes straight through - proven
#    behaviorally: after "next", a real medium is still treated as the first (allowed),
#    which can only hold if "next" wrote no lock. No knowledge of the lock's layout.
assert_allow "non-medium skill (next) allowed" "$(run guard "$(skill_payload S1 next)")"
assert_allow "a medium after a non-medium is still the first, allowed" \
  "$(run guard "$(skill_payload S1 laws:code)")"

# 2. The first medium load is allowed. That it was recorded as laws:code is asserted
#    behaviorally by case 4, whose deny reason names laws:code - so no structural probe
#    of the lock file is needed (or wanted: it would pin the router's internal layout).
assert_allow "first medium (laws:code) allowed" "$(run guard "$(skill_payload S2 laws:code)")"

# 3. Re-loading the SAME medium is idempotent (e.g. re-routing after a compaction).
assert_allow "same medium re-load (laws:code) allowed" "$(run guard "$(skill_payload S2 laws:code)")"

# 4. An INCOMPATIBLE craft in the same session is refused, naming both crafts. laws:code and
#    laws:prompt are the one incompatible pair - THE specific case this guard exists for.
assert_deny "incompatible craft (laws:prompt after laws:code) refused" \
  "$(run guard "$(skill_payload S2 laws:prompt)")" "laws:code" "laws:prompt"

# 5. A subagent (distinct agent_id, shared session_id) gets its own engaged set - the dispatch
#    escape hatch survives. It may load laws:prompt even though the parent holds laws:code.
assert_allow "subagent isolated by agent_id, incompatible craft allowed" \
  "$(run guard "$(skill_payload S2 laws:prompt agentX)")"

# 5a. COEXISTENCE - the point of the compatibility model: a DIFFERENT but compatible craft
#     loads alongside the first, no refusal. laws:code + laws:prose + laws:ticket is normal,
#     complementary work (write code, its docs, its ticket) and must not be blocked.
assert_allow "compatible craft (laws:prose) coexists with laws:code" \
  "$(run guard "$(skill_payload S9 laws:code)")"  # engage code first
assert_allow "  ... laws:prose added" "$(run guard "$(skill_payload S9 laws:prose)")"
assert_allow "  ... laws:ticket added too" "$(run guard "$(skill_payload S9 laws:ticket)")"

# 5b. ... but an incompatible craft is still refused against a set of compatible ones, and the
#     refusal names the specific conflicting craft (laws:code), not whichever loaded last.
assert_deny "laws:prompt refused against code+prose+ticket, naming code" \
  "$(run guard "$(skill_payload S9 laws:prompt)")" "laws:code" "laws:prompt"

# 5c. DIRECTION: the conflict edge runs ONE WAY. code degrades prompts, so code-then-prompt is
#     refused (5b above) - but prompt-then-code is ordinary work and must be ALLOWED. This is the
#     guard's half of the asymmetry, and it is the direction where a wrong answer costs the most:
#     a false refusal here also offers a tombstone-or-rewind switch, so the user can spend real
#     conversation escaping a conflict that never existed.
#
#     It is also the assertion that pins the ARGUMENT ORDER at the callsite. Under the old
#     symmetric predicate the guard passed (incoming, engaged) while the gate passed
#     (engaged, incoming), and nothing could tell; reversing them now inverts this exact case.
run guard "$(skill_payload S10 laws:prompt)" >/dev/null
assert_allow "laws:code after laws:prompt is allowed (the edge runs one way)" \
  "$(run guard "$(skill_payload S10 laws:code)")"

# 5d. laws:chat is in no incompatible pair, so it coexists with everything, both directions.
run guard "$(skill_payload S11 laws:prompt)" >/dev/null
assert_allow "laws:chat coexists with laws:prompt" "$(run guard "$(skill_payload S11 laws:chat)")"
run guard "$(skill_payload S12 laws:chat)" >/dev/null
assert_allow "laws:code coexists with laws:chat" "$(run guard "$(skill_payload S12 laws:code)")"

# 6. The meta-skill "laws" (no colon) is not a medium craft.
assert_allow "meta-skill laws (no colon) allowed" "$(run guard "$(skill_payload S3 laws)")"
assert_allow "medium after meta-skill still allowed as first" "$(run guard "$(skill_payload S3 laws:code)")"

# 7. session-start on a fresh source (clear) resets the lock; the next medium is first again.
run guard "$(skill_payload S4 laws:code)" >/dev/null
run session-start "$(start_payload S4 clear)" >/dev/null
assert_allow "after /clear, a new medium is allowed as first" "$(run guard "$(skill_payload S4 laws:prompt)")"

# 8. session-start on a continuing source (compact) preserves the engaged set; an incompatible
#    craft is still refused across the compaction boundary.
run guard "$(skill_payload S5 laws:code)" >/dev/null
run session-start "$(start_payload S5 compact)" >/dev/null
assert_deny "after compaction, incompatible craft still refused" \
  "$(run guard "$(skill_payload S5 laws:prompt)")" "laws:code" "laws:prompt"

# 8b. resume - the other continuing source - preserves the engaged set just like compact.
run guard "$(skill_payload S8 laws:code)" >/dev/null
run session-start "$(start_payload S8 resume)" >/dev/null
assert_deny "after resume, incompatible craft still refused" \
  "$(run guard "$(skill_payload S8 laws:prompt)")" "laws:code" "laws:prompt"

# 9. A missing session_id cannot key a lock: allow the load but warn on stderr (loud, not silent).
nosession='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}'
out=$(printf '%s' "$nosession" | "$ROUTER" guard 2>/dev/null)
err=$(printf '%s' "$nosession" | "$ROUTER" guard 2>&1 >/dev/null)
assert_allow "empty session_id allows the load" "$out"
case "$err" in *"empty session_id"*) ok "empty session_id warns on stderr";; *) bad "empty session_id did not warn (got: $err)";; esac

# 10. A non-Skill tool is never the guard's business.
assert_allow "non-Skill tool ignored" \
  "$(run guard '{"session_id":"S6","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"x"}}')"

# 11. A lock store that cannot be written degrades loudly, not silently: the load is still
#     allowed (skill loading must never break over a full/unwritable TMPDIR) but the
#     failure is announced on stderr - otherwise a lost engaged set would let an incompatible
#     craft slip through as a first load. A read-only TMPDIR makes the marker create fail.
ro=$(mktemp -d); chmod 500 "$ro"
ro_payload=$(skill_payload S7 laws:code)
out=$(printf '%s' "$ro_payload" | TMPDIR="$ro" "$ROUTER" guard 2>/dev/null)
err=$(printf '%s' "$ro_payload" | TMPDIR="$ro" "$ROUTER" guard 2>&1 >/dev/null)
chmod 700 "$ro"; rm -rf "$ro"
assert_allow "unwritable lock store still allows the load" "$out"
case "$err" in *"could not write craft lock"*) ok "unwritable lock store warns on stderr";; *) bad "unwritable lock store did not warn (got: $err)";; esac

# 12. A missing policy file degrades loudly, not silently: the incompatible load is ALLOWED
#     (a lost policy must never block skill loading) but a warning is emitted - otherwise an
#     absent policy would silently read as "everything coexists" and the guard would go dark.
#     Run a copy of the router in a dir WITHOUT the policy file so the read fails.
nopolicy=$(mktemp -d)
cp "$ROUTER" "$nopolicy/skill-router.sh"
np_code=$(skill_payload S13 laws:code)
np_prompt=$(skill_payload S13 laws:prompt)
printf '%s' "$np_code" | "$nopolicy/skill-router.sh" guard >/dev/null 2>&1
out=$(printf '%s' "$np_prompt" | "$nopolicy/skill-router.sh" guard 2>/dev/null)
err=$(printf '%s' "$np_prompt" | "$nopolicy/skill-router.sh" guard 2>&1 >/dev/null)
rm -rf "$nopolicy"
assert_allow "missing policy file still allows the load (degraded)" "$out"
case "$err" in *"no craft pairs readable"*) ok "missing policy file warns on stderr";; *) bad "missing policy file did not warn (got: $err)";; esac

# 9. The switch offer. It is an EXTRA route out of the deny, available only when the session was
#    launched by claude-laws (only the launcher can relaunch and enact a choice). The deny itself
#    must be identical either way - the switch never weakens the refusal.
switch_payload() { # <session_id> <skill> <transcript_path>
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$3" "$2"
}

swdir=$(mktemp -d)
# The transcript must really exist: the guard now refuses to advertise a switch backed by a
# path it cannot resolve, so a fixture pointing at a nonexistent file would test the refusal
# rather than the offer.
sw1=$(mktemp "$TMPDIR/sw1.XXXXXX.jsonl")
run guard "$(skill_payload SW1 laws:code)" >/dev/null            # engage code
out=$(printf '%s' "$(switch_payload SW1 laws:prompt "$sw1")" | LAWS_SWITCH_DIR="$swdir" LAWS_SWITCH_SESSION=SW1 "$ROUTER" guard 2>/dev/null)
assert_deny "under claude-laws, the deny still refuses and also offers the switch" \
  "$out" "laws:code" "laws:prompt" "laws-switch" "rewind_summarize"
case "$out" in
  *"dispatch a fresh subagent"*) ok "  ... and keeps the subagent escape hatch";;
  *) bad "  ... lost the subagent escape hatch (got: $out)";;
esac
if [ -f "$swdir/pending.json" ]; then
  ok "  ... and records the pending decision for the launcher"
  pend=$(cat "$swdir/pending.json")
  case "$pend" in
    *'"current":"code"'*'"incomingMedium":"prompt"'*) ok "  ... naming the engaged craft and the incoming one";;
    *) bad "  ... pending.json has the wrong shape (got: $pend)";;
  esac
  case "$pend" in
    *"$sw1"*) ok "  ... and the transcript the launcher must operate on";;
    *) bad "  ... pending.json is missing the transcript path (got: $pend)";;
  esac
else
  bad "  ... but wrote no pending.json"
  bad "  ... (shape check skipped)"
  bad "  ... (transcript check skipped)"
fi
rm -rf "$swdir"

# 9b. Without the launcher there is nothing that could enact a switch, so it must not be advertised.
run guard "$(skill_payload SW2 laws:code)" >/dev/null
out=$(run guard "$(switch_payload SW2 laws:prompt /tmp/sw2.jsonl)")
assert_deny "without claude-laws, the deny is unchanged" "$out" "laws:code" "laws:prompt"
case "$out" in
  *"laws-switch"*) bad "  ... but offered a switch that cannot be enacted";;
  *) ok "  ... and offers no switch it cannot enact";;
esac

# 10. retire-craft: the launcher's half of the switch. These assert the ARC a real switch travels
#     - deny, retire, resume, load - because that arc is where the two halves meet and where each
#     half's own suite stops looking. A --resume keeps the same session_id (measured on 2.1.226),
#     so the resumed session lands in the SAME lock slot the guard just refused from.
retire_payload() { # <session_id> <craft>
  printf '{"session_id":"%s","craft":"%s"}' "$1" "$2"
}

# 10a. The whole point: after a switch, the craft that was refused must actually load.
run guard "$(skill_payload R1 laws:code)" >/dev/null
out=$(run guard "$(skill_payload R1 laws:prompt)")
assert_deny "arc: the incompatible load is refused first" "$out" "laws:code"
printf '%s' "$(retire_payload R1 code)" | "$ROUTER" retire-craft 2>/dev/null
ok_retire=$?
[ "$ok_retire" -eq 0 ] && ok "arc: retire-craft releases the engaged craft" \
  || bad "arc: retire-craft failed (exit $ok_retire)"
run session-start "$(start_payload R1 resume)" >/dev/null
assert_allow "arc: after the switch the incoming craft loads" \
  "$(run guard "$(skill_payload R1 laws:prompt)")"

# 10b. It retires ONE craft, not the whole set. Under the shipped policy a surviving laws:prose
#      is INVISIBLE - nothing is incompatible with prose, so no guard decision can reveal whether
#      it is still engaged, and an assertion built on the shipped policy would pass just as
#      happily against a retire-craft that cleared the entire slot. So this runs a router copy
#      whose policy ALSO makes prose incompatible with prompt: now prose's survival has an
#      observable consequence, and clearing the set would show up as prompt being allowed.
twopair=$(mktemp -d)
cp "$ROUTER" "$twopair/skill-router.sh"
printf 'code prompt\nprose prompt\n' > "$twopair/incompatible-crafts.txt"
tp() { printf '%s' "$2" | "$twopair/skill-router.sh" "$1" 2>/dev/null; }
tp guard "$(skill_payload R2 laws:code)" >/dev/null
tp guard "$(skill_payload R2 laws:prose)" >/dev/null
printf '%s' "$(retire_payload R2 code)" | "$twopair/skill-router.sh" retire-craft 2>/dev/null
out=$(tp guard "$(skill_payload R2 laws:prompt)")
assert_deny "retire-craft leaves the crafts it was not asked to retire engaged" "$out" "laws:prose"
# ... and the one it WAS asked to retire is gone: nothing in that deny names laws:code.
case "$out" in
  *"laws:code"*) bad "  ... but the retired craft is still engaged too";;
  *) ok "  ... while the named craft is released";;
esac

# 10b-ii. When MORE THAN ONE engaged craft conflicts, the deny names them ALL. The gate retires the
#         whole conflicting set, so a deny naming only the first marker the glob returned would
#         promise the user a different outcome than the switch delivers - and which one it named
#         would depend on filesystem ordering. Same session, nothing retired: both are still
#         engaged. [LAW:one-source-of-truth]
tp guard "$(skill_payload R2b laws:code)" >/dev/null
tp guard "$(skill_payload R2b laws:prose)" >/dev/null
out=$(tp guard "$(skill_payload R2b laws:prompt)")
assert_deny "a deny names every conflicting craft, not just the first" "$out" "laws:code"
case "$out" in
  *"laws:prose"*) ok "  ... including the one the glob did not reach first";;
  *) bad "  ... but laws:prose is missing from the deny (got: $out)";;
esac
rm -rf "$twopair"

# 10c. Releasing what was never engaged is the postcondition already holding, not a failure -
#      the store may have been cleared, or the guard may have degraded and written no marker.
printf '%s' "$(retire_payload R3 code)" | "$ROUTER" retire-craft 2>/dev/null
[ $? -eq 0 ] && ok "retire-craft succeeds when the craft was never engaged" \
  || bad "retire-craft failed on an unengaged craft"

# 10d. Incomplete instructions are refused rather than silently retiring nothing.
printf '{"session_id":"R4"}' | "$ROUTER" retire-craft >/dev/null 2>&1
[ $? -eq 2 ] && ok "retire-craft refuses a request with no craft" \
  || bad "retire-craft accepted a request with no craft"
printf '{"craft":"code"}' | "$ROUTER" retire-craft >/dev/null 2>&1
[ $? -eq 2 ] && ok "retire-craft refuses a request with no session_id" \
  || bad "retire-craft accepted a request with no session_id"

# 10e. A craft name is interpolated into a path, so it must not be able to reach outside its own
#      slot. The traversal is aimed from a DIFFERENT session at R5's marker - "../../R5/main/code"
#      resolves to exactly the path R5's own marker occupies - because a traversal that lands
#      somewhere harmless would pass whether or not the name is sanitized.
run guard "$(skill_payload R5 laws:code)" >/dev/null
# R5x must be a real session with a real slot, or the ".." never resolves and the traversal fails
# for a reason that has nothing to do with sanitizing.
run guard "$(skill_payload R5x laws:prose)" >/dev/null
printf '%s' "$(retire_payload R5x ../../R5/main/code)" | "$ROUTER" retire-craft >/dev/null 2>&1
assert_deny "a traversal craft name cannot release another session's marker" \
  "$(run guard "$(skill_payload R5 laws:prompt)")" "laws:code"

# 11. The switch is offered ONLY where it can be enacted. Each case below is a session that
#     would be told to run laws-switch and then find no route - the offer must be withheld
#     instead, and the deny itself must survive intact every time.
sub_payload() { # <session_id> <agent_id> <skill> <transcript_path>
  printf '{"session_id":"%s","agent_id":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$2" "$4" "$3"
}

# 11a. A SUBAGENT must never be offered it. laws-switch would end the session through the
#      launcher's inspector - killing the PARENT - and operate on the parent's transcript.
#      The subagent escape hatch the deny recommends would destroy its own caller.
swdir2=$(mktemp -d); sw2=$(mktemp "$TMPDIR/sw2.XXXXXX.jsonl")
printf '%s' "$(sub_payload SUB1 AGENT7 laws:code "$sw2")"   | LAWS_SWITCH_DIR="$swdir2" LAWS_SWITCH_SESSION=SUB1 "$ROUTER" guard >/dev/null 2>&1
out=$(printf '%s' "$(sub_payload SUB1 AGENT7 laws:prompt "$sw2")" | LAWS_SWITCH_DIR="$swdir2" LAWS_SWITCH_SESSION=SUB1 "$ROUTER" guard 2>/dev/null)
assert_deny "a subagent is still refused the incompatible craft" "$out" "laws:code" "laws:prompt"
case "$out" in
  *"laws-switch"*) bad "  ... but was offered a switch that would kill its parent session";;
  *) ok "  ... and is offered no switch that would kill its parent session";;
esac
[ -f "$swdir2/pending.json" ] && bad "  ... and wrote a pending decision the parent would enact" \
                              || ok "  ... and wrote no pending decision for the parent to enact"
rm -rf "$swdir2"

# 11b. A transcript path that does not resolve. json_field's grammar truncates at an embedded
#      quote, so a mangled read reaches here as a path to nothing; acting on it would write a
#      pending.json naming a transcript the launcher cannot operate on.
swdir3=$(mktemp -d)
run guard "$(skill_payload SW3 laws:code)" >/dev/null
out=$(printf '%s' "$(switch_payload SW3 laws:prompt "$TMPDIR/does-not-exist.jsonl")" | LAWS_SWITCH_DIR="$swdir3" LAWS_SWITCH_SESSION=SW3 "$ROUTER" guard 2>/dev/null)
assert_deny "an unresolvable transcript path still refuses the load" "$out" "laws:code"
case "$out" in
  *"laws-switch"*) bad "  ... but offered a switch backed by a transcript that does not exist";;
  *) ok "  ... and offers no switch backed by a transcript that does not exist";;
esac
rm -rf "$swdir3"

# 11c. A quote in a real transcript path must land ESCAPED, so pending.json stays parseable.
#      This is the case the old json_field contract comment wrongly claimed could not arise.
swdir4=$(mktemp -d); qdir=$(mktemp -d)
qpath="$qdir/say\"hi\".jsonl"; : > "$qpath"
run guard "$(skill_payload SW4 laws:code)" >/dev/null
printf '{"session_id":"SW4","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}' \
  "$(printf '%s' "$qpath" | sed 's/"/\\"/g')" | LAWS_SWITCH_DIR="$swdir4" LAWS_SWITCH_SESSION=SW4 "$ROUTER" guard >/dev/null 2>&1
if [ -f "$swdir4/pending.json" ]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$swdir4/pending.json" 2>/dev/null; then
    ok "pending.json stays valid JSON when the transcript path contains a quote"
  else
    bad "pending.json is unparseable with a quote in the path (got: $(cat "$swdir4/pending.json"))"
  fi
else
  # Withholding the offer is also correct here - what must never happen is a corrupt file.
  ok "pending.json stays valid JSON when the transcript path contains a quote (offer withheld)"
fi
rm -rf "$swdir4" "$qdir"

# 11d. An unwritable switch dir. The directory existing does not make it writable, and an
#      offer whose decision never landed sends the agent to "no pending craft switch".
swdir5=$(mktemp -d); sw5=$(mktemp "$TMPDIR/sw5.XXXXXX.jsonl"); chmod 500 "$swdir5"
run guard "$(skill_payload SW5 laws:code)" >/dev/null
out=$(printf '%s' "$(switch_payload SW5 laws:prompt "$sw5")" | LAWS_SWITCH_DIR="$swdir5" LAWS_SWITCH_SESSION=SW5 "$ROUTER" guard 2>/dev/null)
err=$(printf '%s' "$(switch_payload SW5 laws:prompt "$sw5")" | LAWS_SWITCH_DIR="$swdir5" LAWS_SWITCH_SESSION=SW5 "$ROUTER" guard 2>&1 >/dev/null)
case "$out" in
  *"laws-switch"*) bad "an unwritable switch dir still advertised the switch";;
  *) ok "an unwritable switch dir offers no switch";;
esac
case "$err" in
  *"could not record the pending craft switch"*) ok "  ... and says so on stderr rather than failing quietly";;
  *) bad "  ... and warned nothing (got: $err)";;
esac
chmod 700 "$swdir5"; rm -rf "$swdir5"

# 11e. A transcript_path that does not resolve. 11c reaches this same branch through a quoted path,
#      but it accepts either outcome because the grammar decides which - so nothing there pins the
#      REPORT. Here the path is simply absent, which is deterministic, and the assertion is that a
#      resolution failure is distinguishable from the launcher legitimately withholding the offer
#      (subagent, nested claude, unpinned session). Both look like "deny, no switch" to the reader;
#      only the stderr line tells them whether the hook is broken.
swdir6=$(mktemp -d)
run guard "$(skill_payload SW6 laws:code)" >/dev/null
gone="$TMPDIR/definitely-not-here.$$.jsonl"; rm -f "$gone"
out=$(printf '%s' "$(switch_payload SW6 laws:prompt "$gone")" | LAWS_SWITCH_DIR="$swdir6" LAWS_SWITCH_SESSION=SW6 "$ROUTER" guard 2>/dev/null)
err=$(printf '%s' "$(switch_payload SW6 laws:prompt "$gone")" | LAWS_SWITCH_DIR="$swdir6" LAWS_SWITCH_SESSION=SW6 "$ROUTER" guard 2>&1 >/dev/null)
case "$out" in
  *"laws-switch"*) bad "an unresolvable transcript still advertised the switch";;
  *) ok "an unresolvable transcript offers no switch";;
esac
case "$err" in
  *"transcript_path did not resolve"*) ok "  ... and says so on stderr rather than falling through silently";;
  *) bad "  ... and warned nothing, so a broken hook reads as a deliberate withhold (got: $err)";;
esac
if [ -f "$swdir6/pending.json" ]; then
  bad "an unresolvable transcript still recorded a pending decision"
else
  ok "  ... and records no pending decision to be found later"
fi
rm -rf "$swdir6"

# 12. A NESTED claude is the case an "am I a subagent" test cannot see: its own session_id, no
#     agent_id, and it inherits LAWS_SWITCH_DIR and BUN_INSPECT from the launcher's environment.
#     Were it offered the switch it would overwrite the owning session's pending decision and
#     drive /exit down the launcher's inspector, killing the session that started it.
swdir6=$(mktemp -d); sw6=$(mktemp "$TMPDIR/sw6.XXXXXX.jsonl")
printf '%s' "$(switch_payload NESTED laws:code "$sw6")"   | LAWS_SWITCH_DIR="$swdir6" LAWS_SWITCH_SESSION=OWNER "$ROUTER" guard >/dev/null 2>&1
out=$(printf '%s' "$(switch_payload NESTED laws:prompt "$sw6")" | LAWS_SWITCH_DIR="$swdir6" LAWS_SWITCH_SESSION=OWNER "$ROUTER" guard 2>/dev/null)
assert_deny "a nested claude session is still refused the incompatible craft" "$out" "laws:code"
case "$out" in
  *"laws-switch"*) bad "  ... but was offered the owning session's switch";;
  *) ok "  ... and is offered no switch belonging to the session that launched it";;
esac
[ -f "$swdir6/pending.json" ] && bad "  ... and overwrote the owning session's pending decision" \
                              || ok "  ... and left the owning session's pending decision alone"
rm -rf "$swdir6"

# 12b. With no pinned session at all (the launcher disables the switch in one-shot mode, and any
#      plain `claude` has never had one), the offer must not appear even though the inherited
#      switch dir exists.
swdir7=$(mktemp -d); sw7=$(mktemp "$TMPDIR/sw7.XXXXXX.jsonl")
run guard "$(skill_payload SW7 laws:code)" >/dev/null
out=$(printf '%s' "$(switch_payload SW7 laws:prompt "$sw7")" | LAWS_SWITCH_DIR="$swdir7" "$ROUTER" guard 2>/dev/null)
case "$out" in
  *"laws-switch"*) bad "an unpinned session was offered the switch";;
  *) ok "an unpinned session is offered no switch";;
esac
rm -rf "$swdir7"

# 13. A policy file that is READABLE but names no pairs disables enforcement exactly as an
#     unreadable one does, so it must warn exactly as loudly. An unchecked grep exit status
#     used to let a comment-only file pass silently as "everything coexists".
emptypol=$(mktemp -d)
cp "$ROUTER" "$emptypol/skill-router.sh"
printf '# only comments here\n\n' > "$emptypol/incompatible-crafts.txt"
ep_code='{"session_id":"EP1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}'
ep_prompt='{"session_id":"EP1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}'
printf '%s' "$ep_code" | "$emptypol/skill-router.sh" guard >/dev/null 2>&1
out=$(printf '%s' "$ep_prompt" | "$emptypol/skill-router.sh" guard 2>/dev/null)
err=$(printf '%s' "$ep_prompt" | "$emptypol/skill-router.sh" guard 2>&1 >/dev/null)
assert_allow "a pairless policy file still allows the load (degraded)" "$out"
case "$err" in
  *"no craft pairs readable"*) ok "a pairless policy file warns on stderr rather than passing as 'everything coexists'";;
  *) bad "a pairless policy file disabled enforcement silently (stderr: $err)";;
esac
rm -rf "$emptypol"

# 14. A MALFORMED policy line (three or more tokens) is not an edge, and it is not silent.
#     This is the divergence case: `read -r from to` swallowed the third token into $to, so the
#     line was a permanent no-op here while laws-excise.js truncated it to a live code->prompt
#     edge and enforced it - two enforcers, one policy file, opposite rules, no symptom. The
#     matching row in laws-excise.test.js asserts the SAME line is rejected there, and neither
#     test is worth anything without the other. [LAW:single-enforcer]
badpol=$(mktemp -d)
cp "$ROUTER" "$badpol/skill-router.sh"
printf 'code prompt extra-note\n' > "$badpol/incompatible-crafts.txt"
bp_code='{"session_id":"BP1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}'
bp_prompt='{"session_id":"BP1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}'
printf '%s' "$bp_code" | "$badpol/skill-router.sh" guard >/dev/null 2>&1
# ONE invocation, both streams: a second laws:prompt load is a same-medium re-load that never
# reaches the policy read, so splitting stdout and stderr across two runs would assert on a
# quieter path than the one under test.
out=$(printf '%s' "$bp_prompt" | "$badpol/skill-router.sh" guard 2>"$badpol/err.txt")
err=$(cat "$badpol/err.txt")
assert_allow "a malformed 3-token policy line is not enforced as an edge" "$out"
case "$err" in
  *"ignoring malformed line (expected exactly two craft names): code prompt extra-note"*)
    ok "a malformed policy line is announced on stderr, not silently dropped";;
  *) bad "a malformed policy line was dropped silently (stderr: $err)";;
esac
rm -rf "$badpol"

# 14a. Rejecting the malformed line must not take the file's GOOD lines with it: a typo costs
#      one edge, not the whole policy.
mixpol=$(mktemp -d)
cp "$ROUTER" "$mixpol/skill-router.sh"
printf 'code prompt extra-note\ncode prompt\n' > "$mixpol/incompatible-crafts.txt"
mx_code='{"session_id":"MX1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}'
mx_prompt='{"session_id":"MX1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}'
printf '%s' "$mx_code" | "$mixpol/skill-router.sh" guard >/dev/null 2>&1
out=$(printf '%s' "$mx_prompt" | "$mixpol/skill-router.sh" guard 2>/dev/null)
assert_deny "a well-formed edge beside a malformed line is still enforced" "$out" "laws:code" "laws:prompt"
rm -rf "$mixpol"

# 15. The routing text's conflict clause is RENDERED FROM the policy file, not written out in
#     prose beside it. The injected text is what an agent actually reads at the moment it picks
#     a craft, so it has to name the real edges - and naming them by hand made it a second copy
#     that would go stale the day a second edge was added, while both enforcers silently obeyed
#     the file. These cases pin the rendering to the policy, so adding an edge to the file must
#     change the injected text with no edit to the script. [LAW:one-source-of-truth]
#
# The routing text is read back through the SessionStart emission - the same string the agent
# receives - rather than by sourcing the script for its variables, which would pin an internal
# name instead of the contract. [LAW:behavior-not-structure]
route_text_from() { # <router-dir-or-empty> -> the injected routing text
  local router=${1:-$ROUTER}
  printf '%s' "$(start_payload RT1 startup)" | "$router" session-start 2>/dev/null
}
contains() { # <label> <haystack> <needle>
  case "$2" in *"$3"*) ok "$1";; *) bad "$1 (missing '$3' in: $2)";; esac
}
excludes() { # <label> <haystack> <needle>
  case "$2" in *"$3"*) bad "$1 (unexpectedly found '$3' in: $2)";; *) ok "$1";; esac
}

# 15a. Under the shipped single-edge policy, the clause reads exactly this.
shipped_clause="These orderings are refused: once laws:code is engaged, laws:prompt is refused. An ordering is listed only because it was shown to corrupt real work - the engaged craft's standard degrades what you would write next in the refused one."
contains "routing text renders the shipped policy's single edge verbatim" \
  "$(route_text_from)" "$shipped_clause"

# 15b. A SECOND edge in the file appears in the text with no source edit - the whole point.
#      Joined with "; ", both clauses present, in the file's order.
twoedge=$(mktemp -d)
cp "$ROUTER" "$twoedge/skill-router.sh"
printf 'code prompt\nprose ticket\n' > "$twoedge/incompatible-crafts.txt"
te_text=$(route_text_from "$twoedge/skill-router.sh")
contains "a second policy edge reaches the routing text unaided" "$te_text" \
  "These orderings are refused: once laws:code is engaged, laws:prompt is refused; once laws:prose is engaged, laws:ticket is refused."
rm -rf "$twoedge"

# 15c. A policy with no well-formed edges says so, and does not emit a list-shaped opening with
#      no list behind it ("These orderings are refused: ." is an answer-shaped void).
noedge=$(mktemp -d)
cp "$ROUTER" "$noedge/skill-router.sh"
printf '# only comments here\n\n' > "$noedge/incompatible-crafts.txt"
ne_text=$(route_text_from "$noedge/skill-router.sh")
contains "a pairless policy renders the empty-case sentence" "$ne_text" \
  "No craft ordering is currently refused."
excludes "  ... and never the list opening with nothing after it" "$ne_text" \
  "These orderings are refused"
# The surrounding routing text is untouched by the empty case - only the clause varies.
contains "  ... while the rest of the routing text still stands" "$ne_text" \
  "Avoid stacking crafts even where allowed"
rm -rf "$noedge"

# 15d. A malformed line is skipped by the rendering EXACTLY as conflicts_with skips it - one
#      parser, one verdict. If the renderer had its own parser it could show the operator an
#      edge the guard does not enforce, which is the two-parsers defect one level up.
badrender=$(mktemp -d)
cp "$ROUTER" "$badrender/skill-router.sh"
printf 'prose ticket extra-note\ncode prompt\n' > "$badrender/incompatible-crafts.txt"
br_text=$(route_text_from "$badrender/skill-router.sh")
excludes "a malformed policy line is not rendered into the routing text" "$br_text" "extra-note"
# The needle is the CLAUSE form, not the bare craft name: "laws:prose" also occurs in the
# opening's Skill(laws:prose) and would make this assertion pass for the wrong reason.
excludes "  ... nor rendered as a truncated two-token edge" "$br_text" "laws:prose is engaged"
contains "  ... while the well-formed edge beside it still renders" "$br_text" \
  "These orderings are refused: once laws:code is engaged, laws:prompt is refused."
rm -rf "$badrender"

# 16. THE VIOLATION RECORD. Every detected violation - the guard's refusal and the observe
#     hook's unrouted write - lands as one JSONL line in the state-dir log, so violations can
#     be counted after the fact without a human having watched them happen. These cases assert
#     the record (the durable contract) and the nudge (the in-band one) together, since the
#     ticket's whole point is that the in-band signal alone dies with the conversation.
write_payload() { # <session_id> <tool> <file_path> [agent_id]
  local sid=$1 tool=$2 fp=$3 aid=${4:-}
  if [ -n "$aid" ]; then
    printf '{"session_id":"%s","agent_id":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$sid" "$aid" "$tool" "$fp"
  else
    printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$sid" "$tool" "$fp"
  fi
}
count_records() { # <needle> -> how many log lines contain it
  if [ -f "$VLOG" ]; then grep -c -- "$1" "$VLOG"; else echo 0; fi
}

# 16a. A guard refusal is recorded, naming the engaged set and the refused medium. The deny
#      itself is asserted by case 4; this is its surviving half.
run guard "$(skill_payload V1 laws:code)" >/dev/null
run guard "$(skill_payload V1 laws:prompt)" >/dev/null
v1=$(count_records '"session_id":"V1"')
[ "$v1" = 1 ] && ok "a guard refusal appends one violation record" \
              || bad "expected 1 record for V1, got $v1"
contains "  ... of kind incompatible-load" "$(grep '"session_id":"V1"' "$VLOG" 2>/dev/null)" '"kind":"incompatible-load"'
contains "  ... naming the engaged craft and refused medium" \
  "$(grep '"session_id":"V1"' "$VLOG" 2>/dev/null)" '"engaged":"code","medium":"prompt"'

# 16b. The non-load violation - THE case the epic documented (prose written while laws:code
#      was the engaged craft) - is recorded and nudged. prose is loadable beside code, so the
#      nudge offers the load.
run guard "$(skill_payload V2 laws:code)" >/dev/null
out=$(run observe "$(write_payload V2 Write /somewhere/evals/README.md)")
contains "an unrouted prose write nudges the agent in-band" "$out" "laws:prose"
contains "  ... offering the load, since prose is loadable beside code" "$out" "Skill(laws:prose)"
contains "  ... naming the engaged set" "$out" "laws:code"
v2=$(count_records '"session_id":"V2"')
[ "$v2" = 1 ] && ok "  ... and appends one violation record" || bad "expected 1 record for V2, got $v2"
contains "  ... of kind unrouted-medium-write with medium and file" \
  "$(grep '"session_id":"V2"' "$VLOG" 2>/dev/null)" '"kind":"unrouted-medium-write"'
contains "  ... classifying README.md as prose" \
  "$(grep '"session_id":"V2"' "$VLOG" 2>/dev/null)" '"medium":"prose","file":"/somewhere/evals/README.md"'

# 16c. The record is per EVENT, the nudge per MEDIUM: a second unrouted prose write in the
#      same session is counted again but not re-nudged - repeating the text on every write
#      would spend the session's context on noise while the count went quietly wrong.
out=$(run observe "$(write_payload V2 Edit /somewhere/evals/OTHER.md)")
assert_allow "a second unrouted write of the same medium emits no second nudge" "$out"
v2=$(count_records '"session_id":"V2"')
[ "$v2" = 2 ] && ok "  ... but is still recorded, keeping the count honest" \
              || bad "expected 2 records for V2, got $v2"

# 16d. The routed case is silent: writing the medium whose craft IS engaged is the system
#      working, and must leave neither nudge nor record.
run guard "$(skill_payload V3 laws:prose)" >/dev/null
out=$(run observe "$(write_payload V3 Write /docs/notes.md)")
assert_allow "a routed write (prose file, laws:prose engaged) emits nothing" "$out"
v3=$(count_records '"session_id":"V3"')
[ "$v3" = 0 ] && ok "  ... and records nothing" || bad "expected 0 records for V3, got $v3"

# 16e. When the written medium CONFLICTS with an engaged craft (prompt under laws:code), the
#      nudge must not recommend a load the guard would refuse - only the fresh-subagent route.
#      This also pins map ordering: */SKILL.md is prompt even though *.md is prose.
run guard "$(skill_payload V4 laws:code)" >/dev/null
out=$(run observe "$(write_payload V4 Write /repo/skills/foo/SKILL.md)")
contains "a conflicting-medium write nudges toward the subagent route" "$out" "fresh subagent seeded with only laws:prompt"
excludes "  ... and never offers the load the guard would refuse" "$out" "Skill(laws:prompt)"
contains "  ... naming the conflicting engaged craft" "$out" "laws:code"
contains "  ... with SKILL.md classified as prompt, not prose (map order wins)" \
  "$(grep '"session_id":"V4"' "$VLOG" 2>/dev/null)" '"medium":"prompt"'

# 16f. A write with NO craft engaged at all is the purest routing failure - the routing text
#      was injected every turn and nothing loaded. Recorded, and nudged toward the load.
out=$(run observe "$(write_payload V5 Write /app/src/main.py)")
contains "a write in an unrouted session nudges toward the load" "$out" "Skill(laws:code)"
contains "  ... and says nothing is engaged" "$out" "none"
contains "  ... recording an empty engaged set" \
  "$(grep '"session_id":"V5"' "$VLOG" 2>/dev/null)" '"engaged":"","medium":"code"'

# 16g. A path matching no map pattern is deliberately unclassified: no record, no nudge -
#      inference claims only what a path can prove.
out=$(run observe "$(write_payload V6 Write /data/blob.xyz)")
assert_allow "an unclassifiable file is not observed" "$out"
v6=$(count_records '"session_id":"V6"')
[ "$v6" = 0 ] && ok "  ... and not recorded" || bad "expected 0 records for V6, got $v6"

# 16h. A non-Write/Edit tool reaching observe is not its business.
out=$(run observe "$(write_payload V7 Bash /app/src/main.py)")
assert_allow "a non-write tool is ignored by observe" "$out"

# 16i. A subagent's slot is its own: the parent's engaged craft does not count for it, and the
#      parent's nudge dedupe does not silence it. Same isolation the guard keys on.
out=$(run observe "$(write_payload V2 Write /elsewhere/notes.md agentZ)")
contains "a subagent write is judged against its own (empty) engaged set" "$out" "laws:prose"
contains "  ... and nudged despite the parent having been nudged already" "$out" "Skill(laws:prose)"

# 16j. session-start on a fresh source resets the nudge dedupe along with the engaged set - a
#      /clear starts a new logical session, so its first violation deserves a fresh nudge.
run observe "$(write_payload V8 Write /docs/a.md)" >/dev/null
run session-start "$(start_payload V8 clear)" >/dev/null
out=$(run observe "$(write_payload V8 Write /docs/b.md)")
contains "after /clear the nudge fires again" "$out" "laws:prose"

# 16k. A missing medium map disables observation loudly, not silently - a dark telemetry layer
#      is the defect this hook exists to fix. Run a router copy with no map beside it.
nomap=$(mktemp -d)
cp "$ROUTER" "$nomap/skill-router.sh"
cp "$HERE/incompatible-crafts.txt" "$nomap/incompatible-crafts.txt"
nm_payload=$(write_payload V9 Write /docs/a.md)
out=$(printf '%s' "$nm_payload" | "$nomap/skill-router.sh" observe 2>/dev/null)
err=$(printf '%s' "$nm_payload" | "$nomap/skill-router.sh" observe 2>&1 >/dev/null)
assert_allow "a missing medium map emits no nudge (observation disabled)" "$out"
case "$err" in
  *"no rules readable"*) ok "  ... and says so on stderr";;
  *) bad "  ... but disabled observation silently (stderr: $err)";;
esac
v9=$(count_records '"session_id":"V9"')
[ "$v9" = 0 ] && ok "  ... and records nothing it could not classify" || bad "expected 0 records for V9, got $v9"

# 16l. An unwritable state dir degrades loudly: the record is lost but announced, and the
#      in-band nudge still goes out - one broken signal must not take the other with it.
rostate=$(mktemp -d); chmod 500 "$rostate"
uw_payload=$(write_payload V10 Write /docs/a.md)
out=$(printf '%s' "$uw_payload" | XDG_STATE_HOME="$rostate" "$ROUTER" observe 2>/dev/null)
err=$(printf '%s' "$uw_payload" | XDG_STATE_HOME="$rostate" "$ROUTER" observe 2>&1 >/dev/null)
chmod 700 "$rostate"; rm -rf "$rostate"
contains "an unwritable state dir still nudges in-band" "$out" "laws:prose"
case "$err" in
  *"could not record medium violation"*) ok "  ... and announces the lost record on stderr";;
  *) bad "  ... but lost the record silently (stderr: $err)";;
esac

# 16m. A malformed map line (three tokens) is not a rule and is announced, while well-formed
#      rules beside it still classify - the same one-parser discipline as the craft policy.
badmap=$(mktemp -d)
cp "$ROUTER" "$badmap/skill-router.sh"
cp "$HERE/incompatible-crafts.txt" "$badmap/incompatible-crafts.txt"
printf '*.md prose extra-note\n*.py code\n' > "$badmap/medium-map.txt"
bm_payload=$(write_payload V11 Write /app/src/main.py)
out=$(printf '%s' "$bm_payload" | "$badmap/skill-router.sh" observe 2>"$badmap/err.txt")
err=$(cat "$badmap/err.txt")
contains "a well-formed map rule beside a malformed line still classifies" "$out" "Skill(laws:code)"
case "$err" in
  *"ignoring malformed line"*) ok "  ... and the malformed line is announced";;
  *) bad "  ... but the malformed line was dropped silently (stderr: $err)";;
esac
bm_md=$(write_payload V12 Write /docs/a.md)
out=$(printf '%s' "$bm_md" | "$badmap/skill-router.sh" observe 2>/dev/null)
assert_allow "  ... while the malformed rule itself classifies nothing" "$out"
rm -rf "$badmap" "$nomap"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
