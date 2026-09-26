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

# 5c. DIRECTION: the conflict edge runs ONE WAY. code degrades prompts, so code-then-prompt is
#     refused (5b above) - but prompt-then-code is ordinary work and must be ALLOWED. A false
#     refusal here costs the user a fresh session to escape a conflict that never existed.
#
#     It is also the assertion that pins the ARGUMENT ORDER at the callsite: under the old
#     symmetric predicate a reversed (incoming, engaged) call could not be told apart from the
#     right one; reversing them now inverts this exact case.
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

# 9. The refusal offers no way to switch. Nothing in this plugin can enact a switch against a
#    live conversation any more, so an offer to do so would send the agent to a command that does
#    not exist. The one honest alternative is a fresh session, and the refusal names it.
run guard "$(skill_payload SW1 laws:code)" >/dev/null
out=$(run guard "$(skill_payload SW1 laws:prompt)")
assert_deny "the refusal names a fresh session as the way to the other craft" "$out" "/clear"
assert_deny "  ... and keeps the subagent escape hatch" "$out" "fresh subagent"
# The deny legitimately says "no in-session switch", so the negative test is on the vocabulary of
# the removed offer - its command and its choices - not on the word itself.
case "$out" in
  *"laws-switch"*|*"tombstone"*|*"rewind"*|*"Run '"*) bad "  ... but still offers a switch nothing can enact (got: $out)";;
  *) ok "  ... and offers no switch";;
esac

# 9b. When MORE THAN ONE engaged craft conflicts, the deny names them ALL, not whichever marker the
#     glob returned first. Under the shipped policy nothing but code conflicts with prompt, so this
#     runs a router copy whose policy also makes prose incompatible with prompt. [LAW:no-silent-failure]
twopair=$(mktemp -d)
cp "$ROUTER" "$twopair/skill-router.sh"
printf 'code prompt\nprose prompt\n' > "$twopair/incompatible-crafts.txt"
tp() { printf '%s' "$2" | "$twopair/skill-router.sh" "$1" 2>/dev/null; }
tp guard "$(skill_payload R2b laws:code)" >/dev/null
tp guard "$(skill_payload R2b laws:prose)" >/dev/null
out=$(tp guard "$(skill_payload R2b laws:prompt)")
assert_deny "a deny names every conflicting craft, not just the first" "$out" "laws:code" "laws:prose"
rm -rf "$twopair"

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
#     `read -r from to` swallows the third token into $to, so without the extra field the line
#     was a permanent no-op with no symptom - a typo in the policy silently turned the guard off
#     for that edge. [LAW:no-silent-failure]
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
# Every line malformed leaves no edge, so the guard is off - and says so, as a missing or
# comment-only file does. The per-line note alone is not that signal.
case "$err" in
  *"no craft pairs readable"*) ok "a policy file with no well-formed line warns that enforcement is disabled";;
  *) bad "a policy file with no well-formed line disabled enforcement without the warning (stderr: $err)";;
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
out=$(printf '%s' "$mx_prompt" | "$mixpol/skill-router.sh" guard 2>"$mixpol/err.txt")
assert_deny "a well-formed edge beside a malformed line is still enforced" "$out" "laws:code" "laws:prompt"
case "$(cat "$mixpol/err.txt")" in
  *"no craft pairs readable"*) bad "a policy with a surviving edge claimed enforcement is disabled";;
  *) ok "a policy with a surviving edge does not claim enforcement is disabled";;
esac
rm -rf "$mixpol"

# 14b. A CRLF policy file is an edge, not a typo. `read` does not split on \r, so the edge used
#      to parse as to="prompt\r": two tokens, no warning, never a match - a policy saved from a
#      Windows editor would silently disable the guard.
crlfpol=$(mktemp -d)
cp "$ROUTER" "$crlfpol/skill-router.sh"
# The code->prompt line carries no comment on purpose: a comment strip would take the \r with it
# and hide the bug this case exists to catch.
printf 'code prompt\r\n# a note\r\nprose prompt # why\r\n\r\n' > "$crlfpol/incompatible-crafts.txt"
cr_code='{"session_id":"CR1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}'
cr_prompt='{"session_id":"CR1","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}'
printf '%s' "$cr_code" | "$crlfpol/skill-router.sh" guard >/dev/null 2>&1
out=$(printf '%s' "$cr_prompt" | "$crlfpol/skill-router.sh" guard 2>"$crlfpol/err.txt")
assert_deny "a CRLF policy line is enforced as an edge" "$out" "laws:code" "laws:prompt"
case "$(cat "$crlfpol/err.txt")" in
  *"malformed"*|*"no craft pairs readable"*) bad "a CRLF policy file was reported as broken (stderr: $(cat "$crlfpol/err.txt"))";;
  *) ok "a CRLF policy file parses without a warning";;
esac
rm -rf "$crlfpol"

# 15. The routing text reaches the agent VERBATIM. Tests 15a-15d asserted the rendered
#     conflict clause and were removed with the renderer, which also removed the only
#     assertions on the session-start emission itself - leaving the routing prose, the one
#     string every session actually receives, covered by nothing.
rt_out=$(run session-start "$(start_payload RT1 startup)")
case "$rt_out" in
  *'"hookEventName":"SessionStart"'*) ok "session-start emits a SessionStart payload";;
  *) bad "session-start emits a SessionStart payload (got: $rt_out)";;
esac
case "$rt_out" in
  *'identify the medium of your primary deliverable'*) ok "  ... carrying the routing text";;
  *) bad "  ... carrying the routing text (got: $rt_out)";;
esac

# 15a. And the prose survives shell-special characters. ROUTE_TEXT's heredoc was unquoted
#      while it interpolated the conflict clause; with that gone it is quoted, and this is
#      what says so. Unquote it again and a reworded line containing a $ or a backtick
#      expands at hook launch - or breaks the JSON - and every other test here stays green.
#      Only mutating the shipped file can see that; reading the heredoc cannot.
rtmut=$(mktemp -d)
cp "$ROUTER" "$rtmut/skill-router.sh"
cp "$HERE/incompatible-crafts.txt" "$rtmut/incompatible-crafts.txt"
mutant='Load the craft for $HOME and `id` and note the cost.'
awk -v repl="$mutant" '
  /^read -r -d .. ROUTE_TEXT <</ { print; getline; print repl; next }
  { print }
' "$rtmut/skill-router.sh" > "$rtmut/mutated.sh"
mv "$rtmut/mutated.sh" "$rtmut/skill-router.sh"
chmod +x "$rtmut/skill-router.sh"
# The mutation must have landed, or the assertion below passes without testing anything.
if grep -qF 'and `id` and note the cost.' "$rtmut/skill-router.sh"; then
  ok "  ... (routing-text mutation applied)"
else
  bad "routing-text mutation did not apply - the next assertion would pass vacuously"
fi
rt_mut_out=$(printf '%s' "$(start_payload RT2 startup)" | "$rtmut/skill-router.sh" session-start 2>/dev/null)
case "$rt_mut_out" in
  *'$HOME'*'`id`'*) ok "  ... and shell-special characters in it are emitted verbatim";;
  *) bad "  ... and shell-special characters in it are emitted verbatim (expanded or mangled: $rt_mut_out)";;
esac
rm -rf "$rtmut"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
