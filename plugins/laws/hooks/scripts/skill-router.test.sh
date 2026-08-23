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

# 5c. SYMMETRY: incompatibility is a pair, not a hub - loading laws:code after laws:prompt is
#     refused just the same. (There is no "exclusive" craft; only this pair conflicts.)
run guard "$(skill_payload S10 laws:prompt)" >/dev/null
assert_deny "laws:code after laws:prompt refused (symmetric)" \
  "$(run guard "$(skill_payload S10 laws:code)")" "laws:code" "laws:prompt"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
