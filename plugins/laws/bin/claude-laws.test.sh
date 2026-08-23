#!/bin/bash
# Integration tests for the claude-laws launcher — the relaunch loop that makes a chosen craft
# switch actually take effect.
#
# These exist because the launcher is where the two halves of a switch MEET, and neither half's
# own suite reaches it: laws-excise.test.js proves the transcript surgery, skill-router.test.sh
# proves the guard, and a switch can still fail end to end with both of them green. So the test
# drives the REAL launcher against a REAL transcript and a REAL router, replacing only `claude`
# itself (LAWS_CLAUDE_BIN) — the one part that cannot run in a test.
#
# The stub records its argv per invocation and requests a switch by writing the same request.json
# the in-session `laws-switch` writes, so the launcher cannot tell it from the real thing.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LAUNCHER="$HERE/claude-laws"
ROUTER="$HERE/../hooks/scripts/skill-router.sh"

export TMPDIR
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail+1)); }

export STUB_STATE="$TMPDIR/stub"
mkdir -p "$STUB_STATE"

# A craft-load transcript line has the exact shape craftMediumOf detects; building it with node
# keeps the fixture honest JSON rather than hand-rolled string concatenation.
write_transcript() { # <path> <session-id>
  node -e '
    const [file, sid] = process.argv.slice(1);
    const line = (o) => JSON.stringify(o);
    const rows = [
      line({ type: "user", uuid: "u1", parentUuid: null, sessionId: sid, timestamp: "2026-08-23T00:00:00.000Z",
             message: { role: "user", content: "start the work" } }),
      line({ type: "user", isMeta: true, uuid: "u2", parentUuid: "u1", sessionId: sid,
             timestamp: "2026-08-23T00:01:00.000Z", sourceToolUseID: "toolu_u2",
             message: { role: "user", content: [{ type: "text",
               text: "Base directory for this skill: /plugins/laws/skills/code\n\n<THE LAWS BODY>" }] } }),
      line({ type: "assistant", uuid: "u3", parentUuid: "u2", sessionId: sid,
             timestamp: "2026-08-23T00:02:00.000Z", message: { role: "assistant", content: "did the work" } }),
    ];
    require("fs").writeFileSync(file, rows.join("\n") + "\n");
  ' "$1" "$2"
}

# The stub stands in for `claude`. It records argv, and on the passes named in STUB_SWITCH_ON it
# writes a switch request exactly as laws-switch would.
STUB="$TMPDIR/claude-stub"
cat > "$STUB" <<'EOS'
#!/bin/bash
n=$(( $(cat "$STUB_STATE/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$STUB_STATE/count"
printf '%s\n' "$*" > "$STUB_STATE/argv.$n"
case " $STUB_SWITCH_ON " in
  *" $n "*)
    # The transcript starts with laws:code engaged, so the first switch moves to prompt. A later
    # switch has to move back to code — and first has to put the laws:prompt load in the
    # transcript, or there is no conflict left for the launcher to act on.
    incoming=prompt
    if [ "$n" != 1 ]; then
      incoming=code
      node -e '
        const fs = require("fs"), [file, sid] = process.argv.slice(1);
        fs.appendFileSync(file, JSON.stringify({ type: "user", isMeta: true, uuid: "p" + Date.now(),
          parentUuid: "u3", sessionId: sid, timestamp: new Date().toISOString(), sourceToolUseID: "toolu_p",
          message: { role: "user", content: [{ type: "text",
            text: "Base directory for this skill: /plugins/laws/skills/prompt\n\n<PROMPT BODY>" }] } }) + "\n");
      ' "$STUB_TRANSCRIPT" "$STUB_SID"
    fi
    printf '{"sessionId":"%s","transcript":"%s","incomingMedium":"%s","choice":"tombstone"}\n' \
      "$STUB_SID" "$STUB_TRANSCRIPT" "$incoming" > "$LAWS_SWITCH_DIR/request.json"
    ;;
esac
exit 0
EOS
chmod +x "$STUB"
export LAWS_CLAUDE_BIN="$STUB"

count_resume() { grep -o -- '--resume' "$1" | wc -l | tr -d ' '; }

# ---- 1. one switch: the loop applies the surgery, releases the craft, and resumes -------------
export STUB_SID="LAUNCH1"
export STUB_TRANSCRIPT="$TMPDIR/launch1.jsonl"
export STUB_SWITCH_ON="1"
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
rm -f "$STUB_STATE"/count "$STUB_STATE"/argv.*

# Engage laws:code through the real guard, so the release has a real marker to remove.
printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}' \
  "$STUB_SID" | "$ROUTER" guard >/dev/null 2>&1

"$LAUNCHER" --model opus >/dev/null 2>&1
status=$?
[ "$status" -eq 0 ] && ok "the launcher exits cleanly once no switch remains" \
                    || bad "the launcher exited $status"

[ "$(cat "$STUB_STATE/count")" = 2 ] && ok "a switch relaunches the session exactly once" \
                                     || bad "expected 2 launches, got $(cat "$STUB_STATE/count")"

if [ -f "$STUB_STATE/argv.2" ]; then
  case "$(cat "$STUB_STATE/argv.2")" in
    *"--resume $STUB_SID"*) ok "the relaunch resumes the session the switch names";;
    *) bad "the relaunch did not resume $STUB_SID (argv: $(cat "$STUB_STATE/argv.2"))";;
  esac
  case "$(cat "$STUB_STATE/argv.2")" in
    *"--model opus"*) ok "the relaunch keeps the user's own flags";;
    *) bad "the relaunch dropped the user's flags (argv: $(cat "$STUB_STATE/argv.2"))";;
  esac
else
  bad "the session was never relaunched"
  bad "  (flag check skipped)"
fi

grep -q '\[TOMBSTONE\]' "$STUB_TRANSCRIPT" \
  && ok "the switch was applied to the transcript" \
  || bad "the transcript was not modified"

# The half that used to be missing: the resumed session must be able to load the craft it
# switched TO. A --resume keeps the same session_id, so this is the same lock slot that refused.
out=$(printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}' \
  "$STUB_SID" | "$ROUTER" guard 2>/dev/null)
[ -z "$out" ] && ok "after the relaunch the incoming craft actually loads" \
              || bad "the incoming craft is still refused after the switch (got: $out)"

# ---- 2. two switches in one launcher lifetime: flags must not accumulate ----------------------
export STUB_SID="LAUNCH2"
export STUB_TRANSCRIPT="$TMPDIR/launch2.jsonl"
export STUB_SWITCH_ON="1 2"
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
rm -f "$STUB_STATE"/count "$STUB_STATE"/argv.*

"$LAUNCHER" --model opus >/dev/null 2>&1

[ "$(cat "$STUB_STATE/count")" = 3 ] && ok "two switches relaunch the session twice" \
                                     || bad "expected 3 launches, got $(cat "$STUB_STATE/count")"

if [ -f "$STUB_STATE/argv.3" ]; then
  n=$(count_resume "$STUB_STATE/argv.3")
  [ "$n" = 1 ] && ok "a second switch replaces the resume rather than appending another" \
               || bad "argv carries $n --resume flags after two switches: $(cat "$STUB_STATE/argv.3")"
else
  bad "the session was never relaunched a second time"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
