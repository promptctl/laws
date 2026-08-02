#!/bin/bash
# Unit tests for the skill-router medium-lock guard. Pure bash, no jq - same dependency
# stance as the script under test, so the test runs anywhere the hook does.
#
# Each case feeds a synthetic hook payload (the exact shape Claude Code delivers on
# stdin, captured from a real PreToolUse run) to skill-router.sh and asserts the visible
# contract: an allowed load emits nothing, a refused load emits a deny decision. State is
# isolated under a throwaway TMPDIR so a run never touches a real session's lock.

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

# 4. A DIFFERENT medium in the same session is refused, naming both media.
assert_deny "second medium (laws:prompt) refused" "$(run guard "$(skill_payload S2 laws:prompt)")" \
  "laws:code" "laws:prompt"

# 5. A subagent (distinct agent_id, shared session_id) gets its own lock - the dispatch
#    escape hatch survives. It may load laws:prompt even though the parent holds laws:code.
assert_allow "subagent isolated by agent_id, second medium allowed" \
  "$(run guard "$(skill_payload S2 laws:prompt agentX)")"

# 6. The meta-skill "laws" (no colon) is not a medium craft.
assert_allow "meta-skill laws (no colon) allowed" "$(run guard "$(skill_payload S3 laws)")"
assert_allow "medium after meta-skill still allowed as first" "$(run guard "$(skill_payload S3 laws:code)")"

# 7. session-start on a fresh source (clear) resets the lock; the next medium is first again.
run guard "$(skill_payload S4 laws:code)" >/dev/null
run session-start "$(start_payload S4 clear)" >/dev/null
assert_allow "after /clear, a new medium is allowed as first" "$(run guard "$(skill_payload S4 laws:prompt)")"

# 8. session-start on a continuing source (compact) preserves the lock; a switch still refused.
run guard "$(skill_payload S5 laws:code)" >/dev/null
run session-start "$(start_payload S5 compact)" >/dev/null
assert_deny "after compaction, switching medium still refused" \
  "$(run guard "$(skill_payload S5 laws:prompt)")" "laws:code" "laws:prompt"

# 8b. resume - the other continuing source - preserves the lock just like compact.
run guard "$(skill_payload S8 laws:code)" >/dev/null
run session-start "$(start_payload S8 resume)" >/dev/null
assert_deny "after resume, switching medium still refused" \
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
#     failure is announced on stderr - otherwise a lost lock would let the next different
#     medium slip through as a first load. A read-only TMPDIR makes the lock mkdir fail.
ro=$(mktemp -d); chmod 500 "$ro"
ro_payload=$(skill_payload S7 laws:code)
out=$(printf '%s' "$ro_payload" | TMPDIR="$ro" "$ROUTER" guard 2>/dev/null)
err=$(printf '%s' "$ro_payload" | TMPDIR="$ro" "$ROUTER" guard 2>&1 >/dev/null)
chmod 700 "$ro"; rm -rf "$ro"
assert_allow "unwritable lock store still allows the load" "$out"
case "$err" in *"could not write medium lock"*) ok "unwritable lock store warns on stderr";; *) bad "unwritable lock store did not warn (got: $err)";; esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
