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
#
# It also records the one thing about a launch that is NOT argv and that the real claude would react
# to where a stub cannot: the switch machinery it inherited in its environment — the session pin, the
# switch dir, and the launcher pid laws-switch signals through. A recovered launch must inherit none
# of it (section 6), and an ordinary one must inherit all of it (section 1's baseline).
STUB="$TMPDIR/claude-stub"
cat > "$STUB" <<'EOS'
#!/bin/bash
n=$(( $(cat "$STUB_STATE/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$STUB_STATE/count"
printf '%s\n' "$*" > "$STUB_STATE/argv.$n"
printf '%s|%s|%s\n' "${LAWS_SWITCH_SESSION-}" "${LAWS_SWITCH_DIR-}" "${LAWS_LAUNCHER_PID-}" > "$STUB_STATE/env.$n"
case " $STUB_SWITCH_ON " in
  *" $n "*)
    # The transcript starts with laws:code engaged, so the first switch moves to prompt. Every
    # switch here is code→prompt, because the conflict edge runs ONE WAY: prompt-then-code is
    # ordinary allowed work and would not trigger anything. So a SECOND switch has to re-engage
    # code first — legitimate once the earlier code load is tombstoned — and then conflict on the
    # next incoming laws:prompt, exactly as a real session would.
    incoming=prompt
    if [ "$n" != 1 ]; then
      node -e '
        const fs = require("fs"), [file, sid] = process.argv.slice(1);
        fs.appendFileSync(file, JSON.stringify({ type: "user", isMeta: true, uuid: "p" + Date.now(),
          parentUuid: "u3", sessionId: sid, timestamp: new Date().toISOString(), sourceToolUseID: "toolu_p",
          message: { role: "user", content: [{ type: "text",
            text: "Base directory for this skill: /plugins/laws/skills/code\n\n<CODE BODY>" }] } }) + "\n");
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

# Every per-launch record the stub keeps is cleared together. Clearing argv but leaving env behind
# would let a previous section's launch answer this section's question. Extra arguments are
# additional paths to clear alongside them.
reset_stub() { # [extra paths...]
  rm -f "$STUB_STATE"/count "$STUB_STATE"/argv.* "$STUB_STATE"/env.* "$@"
}

# ---- 1. one switch: the loop applies the surgery, releases the craft, and resumes -------------
export STUB_SID="LAUNCH1"
export STUB_TRANSCRIPT="$TMPDIR/launch1.jsonl"
export STUB_SWITCH_ON="1"
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
reset_stub

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

# The baseline the recovery-session assertions in section 6 are measured against: an ORDINARY launch
# carries the whole handshake. Without this, "the recovered session inherits nothing" would pass
# just as well on a launcher that never exported anything at all. The third field is the launcher
# pid laws-switch signals through, and it must be a real pid, not merely non-empty.
case "$(cat "$STUB_STATE/env.1" 2>/dev/null)" in
  ''|'||') bad "an ordinary launch inherited no switch machinery at all (env: $(cat "$STUB_STATE/env.1" 2>/dev/null))";;
  *'|'*'|'[0-9]*) ok "an ordinary launch inherits the session pin, the switch dir and the launcher pid";;
  *) bad "an ordinary launch is missing part of the switch machinery (env: $(cat "$STUB_STATE/env.1" 2>/dev/null))";;
esac

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
reset_stub

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

# ---- 3. the session the switch belongs to is pinned, and one-shot mode gets no switch --------
# The launcher exports LAWS_SWITCH_DIR and LAWS_LAUNCHER_PID into every process the agent spawns, so
# a nested claude inherits the whole handshake. Pinning the session id is what lets the guard tell
# the owning session from anything else by identity rather than inference.
export STUB_SID="LAUNCH3"
export STUB_TRANSCRIPT="$TMPDIR/launch3.jsonl"
export STUB_SWITCH_ON=""
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
reset_stub
export LAWS_CLAUDE_BIN="$STUB"

"$LAUNCHER" --model opus >/dev/null 2>&1
case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
  *"--session-id "*) ok "the launcher pins the session id it owns";;
  *) bad "the launcher did not pin a session id (argv: $(cat "$STUB_STATE/argv.1" 2>/dev/null))";;
esac

# One-shot: a relaunch would re-send the positional prompt and re-execute the user's request, so
# the switch is unavailable rather than dangerous. Enforced by withholding the pin the guard
# requires, not by a warning alone.
reset_stub
out=$("$LAUNCHER" -p 'do the thing' 2>&1 >/dev/null)
case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
  *"--session-id "*) bad "one-shot mode still pinned a session, so the switch stays reachable";;
  *) ok "one-shot mode pins no session, so the guard can offer no switch";;
esac
case "$out" in
  *"one-shot"*) ok "  ... and says why on stderr";;
  *) bad "  ... and said nothing about it (stderr: $out)";;
esac

# A user-supplied session selector is not a degraded switch, it is a BROKEN LAUNCH: real claude
# exits with "--session-id can only be used with --continue or --resume if --fork-session is also
# specified". The stub cannot reproduce that refusal, so the assertion is on the argv the launcher
# builds - the pin must never reach claude alongside the user's own selector.
#
# EVERY SPELLING, INCLUDING THE `=`-JOINED ONE. claude accepts `--resume=<uuid>` exactly as it
# accepts `--resume <uuid>` (measured), so a scan that only recognises the space-separated form sees
# the joined one as a positional, offers the switch, and mints the conflicting pin anyway - the
# failure this whole section exists to prevent, reachable through a spelling nobody tested.
for sel in -c --continue -r --resume --continue=42 --resume=USER-RESUME-ID; do
  reset_stub
  out=$("$LAUNCHER" "$sel" 2>&1 >/dev/null)
  case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
    *"--session-id "*) bad "$sel still pinned a session, so claude would refuse to launch at all";;
    *) ok "$sel pins no session, so the launch is not broken by a conflicting pin";;
  esac
  case "$out" in
    *"session selector"*) ok "  ... and says why on stderr";;
    *) bad "  ... and said nothing about it (stderr: $out)";;
  esac
done

# The user's own selector must still REACH claude untouched - withholding the pin is the whole
# change, and dropping or rewriting the flag the user typed would be a different bug wearing the
# same fix. The last iteration above was the joined spelling, so this also proves the launcher
# recognises that spelling without normalising it into some other one on the way through.
case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
  *"--resume=USER-RESUME-ID"*) ok "the user's own session selector is passed through untouched";;
  *) bad "the launcher swallowed the user's selector (argv: $(cat "$STUB_STATE/argv.1" 2>/dev/null))";;
esac

# A user-supplied --session-id is the same class of broken launch: minting a second id would put
# TWO --session-id flags on one command line, so claude either refuses or opens a session under an
# id the user never asked for. The assertion counts the flag rather than looking for the pin,
# because "the launcher added one of its own" and "the user's is still there" are both wrong to
# miss and the count catches either.
reset_stub
out=$("$LAUNCHER" --session-id USER-PINNED-ID 2>&1 >/dev/null)
n=$(grep -o -- '--session-id' "$STUB_STATE/argv.1" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 1 ] && ok "a user-supplied --session-id is not joined by a second, conflicting pin" \
             || bad "argv carries $n --session-id flags: $(cat "$STUB_STATE/argv.1" 2>/dev/null)"
case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
  *"--session-id USER-PINNED-ID"*) ok "  ... and the id the user chose is the one that survives";;
  *) bad "  ... but the surviving id is not the user's (argv: $(cat "$STUB_STATE/argv.1" 2>/dev/null))";;
esac

# The same pin in its joined spelling. Counting the flag is what catches the real failure here: a
# scan that misses `--session-id=<id>` reads it as a positional and mints its own alongside it, and
# the count goes to 2 while both the user's id and a valid-looking pin are still present.
reset_stub
out=$("$LAUNCHER" --session-id=USER-JOINED-ID 2>&1 >/dev/null)
n=$(grep -o -- '--session-id' "$STUB_STATE/argv.1" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 1 ] && ok "a joined --session-id=<id> is not joined by a second, conflicting pin" \
             || bad "argv carries $n --session-id flags: $(cat "$STUB_STATE/argv.1" 2>/dev/null)"
case "$(cat "$STUB_STATE/argv.1" 2>/dev/null)" in
  *"--session-id=USER-JOINED-ID"*) ok "  ... and the joined id reaches claude exactly as typed";;
  *) bad "  ... but the joined id did not survive (argv: $(cat "$STUB_STATE/argv.1" 2>/dev/null))";;
esac
case "$out" in
  *"session id"*) ok "  ... and says why the switch is unavailable on stderr";;
  *) bad "  ... and said nothing about it (stderr: $out)";;
esac

# ---- 4. a switch that retires MORE THAN ONE craft releases every one of them -----------------
# The shipped policy has a single pair, so two conflicting crafts can never both be engaged under
# it and this path would be untestable in place. So the whole launcher is run from a temp plugin
# root whose policy ALSO makes prose incompatible with prompt — the same trick skill-router.test.sh
# uses. Both halves are real: the real excise computes the set, the real router holds the locks.
#
# Releasing only one is the defect under test, and it is INVISIBLE unless the survivor has a
# consequence: the assertion is therefore that laws:prompt is allowed afterwards, which can only
# be true if every conflicting marker is gone.
tp="$TMPDIR/plugin"
mkdir -p "$tp/bin" "$tp/hooks/scripts"
cp "$LAUNCHER" "$tp/bin/claude-laws"
cp "$HERE/../hooks/scripts/laws-excise.js" "$HERE/../hooks/scripts/skill-router.sh" "$tp/hooks/scripts/"
printf 'code prompt\nprose prompt\n' > "$tp/hooks/scripts/incompatible-crafts.txt"

export STUB_SID="LAUNCH4"
export STUB_TRANSCRIPT="$TMPDIR/launch4.jsonl"
export STUB_SWITCH_ON="1"
node -e '
  const [file, sid] = process.argv.slice(1);
  const craft = (uuid, parent, medium, ts) => JSON.stringify({ type: "user", isMeta: true, uuid,
    parentUuid: parent, sessionId: sid, timestamp: ts, sourceToolUseID: "toolu_" + uuid,
    message: { role: "user", content: [{ type: "text",
      text: "Base directory for this skill: /plugins/laws/skills/" + medium + "\n\n<BODY>" }] } });
  const said = (uuid, parent, text) => JSON.stringify({ type: "user", uuid, parentUuid: parent,
    sessionId: sid, message: { role: "user", content: text } });
  require("fs").writeFileSync(file, [
    said("u1", null, "start"),
    craft("u2", "u1", "code",  "2026-08-23T00:01:00.000Z"),
    said("u3", "u2", "work under code"),
    craft("u4", "u3", "prose", "2026-08-23T00:02:00.000Z"),
    said("u5", "u4", "work under prose"),
  ].join("\n") + "\n");
' "$STUB_TRANSCRIPT" "$STUB_SID"
reset_stub

# Engage both through the temp router, so both locks are real.
tpr() { printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' \
          "$STUB_SID" "$1" | "$tp/hooks/scripts/skill-router.sh" guard 2>/dev/null; }
tpr laws:code >/dev/null
tpr laws:prose >/dev/null

"$tp/bin/claude-laws" >/dev/null 2>&1

tomb=$(grep -c '\[TOMBSTONE\]' "$STUB_TRANSCRIPT")
[ "$tomb" = 2 ] && ok "both conflicting crafts are tombstoned in the transcript" \
                || bad "expected 2 tombstones, got $tomb"

out=$(tpr laws:prompt)
case "$out" in
  *'"deny"'*) bad "a craft survived the switch, so laws:prompt is still refused ($out)";;
  *) ok "every retired craft is released, so the switched-to craft can finally load";;
esac

# ---- 5. laws-switch reads the choice by POSITION, never by "first token without a dash" -------
# `--summary "some text"` puts a bare word in argv that is not a choice. A scan for the first
# non-flag token picks that word up and reports `unknown choice "some text"`, which blames the
# caller for the parser's mistake. The choice is args[0] or it is a usage error.
SWITCH="$HERE/laws-switch"
sw_dir="$TMPDIR/switchargs"
mkdir -p "$sw_dir"
write_pending() { # <dir>
  printf '{"sessionId":"SWITCHARGS","transcript":"%s","incomingMedium":"prompt","current":"code"}\n' \
    "$TMPDIR/switchargs.jsonl" > "$1/pending.json"
}

write_pending "$sw_dir"
out=$(env -u LAWS_LAUNCHER_PID LAWS_SWITCH_DIR="$sw_dir" "$SWITCH" --summary "some text" rewind_summarize 2>&1 >/dev/null)
status=$?
case "$out" in
  *"some text"*) bad "the summary value was taken for the choice (stderr: $out)";;
  *) ok "a --summary value before the positional is never mistaken for the choice";;
esac
[ "$status" -ne 0 ] && ok "  ... and a choice that is not first is a usage error, not a guess" \
                    || bad "  ... but the misordered invocation was accepted (exit $status)"
[ -f "$sw_dir/pending.json" ] && ok "  ... and the pending decision is left intact for a real choice" \
                              || bad "  ... but the pending decision was consumed by a failed parse"
case "$out" in
  *"the choice comes first"*) ok "  ... and the error names the real problem: the order";;
  *) bad "  ... but the error misdiagnoses it (stderr: $out)";;
esac

# The positive half: the documented order still resolves, all the way to a written request. The
# session cannot be ended here (no launcher to signal), which is a later, separate failure - the
# request on disk is the evidence the choice parsed.
rm -f "$sw_dir/request.json"
env -u LAWS_LAUNCHER_PID LAWS_SWITCH_DIR="$sw_dir" "$SWITCH" rewind_summarize --summary "what I did" >/dev/null 2>&1
if [ -f "$sw_dir/request.json" ]; then
  got=$(node -e 'const r=require(process.argv[1]);process.stdout.write(r.choice+"|"+r.summary)' "$sw_dir/request.json")
  [ "$got" = "rewind_summarize|what I did" ] \
    && ok "the positional choice and its summary are recorded as given" \
    || bad "the request recorded $got"
else
  bad "the documented argument order wrote no request at all"
fi

# ---- 6. a switch that cannot be completed hands the session back --------------------------------
# Every failure between "claude exited" and "resume" used to exit with no relaunch, leaving the
# user with NO session - worse than the state they were in before asking for the switch. These
# three are the failures, and each must reopen the session with the same selector that opened it.
#
# The real laws-excise cannot be made to fail on demand without lying about the transcript, so the
# launcher runs from a temp plugin root whose excise is a double. Everything else is the real
# launcher, including the argv it builds - which is what the assertions read.
tpr2="$TMPDIR/plugin-recover"
mkdir -p "$tpr2/bin" "$tpr2/hooks/scripts"
cp "$LAUNCHER" "$tpr2/bin/claude-laws"
cp "$HERE/../hooks/scripts/skill-router.sh" "$tpr2/hooks/scripts/"
cp "$HERE/../hooks/scripts/incompatible-crafts.txt" "$tpr2/hooks/scripts/"
cat > "$tpr2/hooks/scripts/laws-excise.js" <<'EOJ'
// Test double for `laws-excise.js --apply`. FAKE_APPLY names which of the launcher's post-apply
// failures to produce; anything else is a bug in the test, so it exits loudly rather than 0.
const m = process.env.FAKE_APPLY;
const out = (o) => process.stdout.write(JSON.stringify(o) + '\n');
if (m === 'fail') { process.stderr.write('fake-excise: the apply failed\n'); process.exit(1); }
else if (m === 'garbage') { process.stdout.write('this is not json\n'); }
else if (m === 'noresumefield') { out({ sessionId: process.env.STUB_SID, switchedFrom: ['code'], switchedTo: 'prompt', choice: 'tombstone' }); }
else if (m === 'nameless') { out({ sessionId: '', switchedFrom: [], switchedTo: 'prompt', choice: 'tombstone', resume: true }); }
else if (m === 'noresume') { out({ sessionId: process.env.STUB_SID, switchedFrom: ['code'], switchedTo: 'prompt', choice: 'reject', resume: false }); }
// One completed switch, then a failure - the only way to reach recovery on a LATER pass, where the
// launcher's selector is already `--resume` rather than the initial pin.
else if (m === 'okthenfail') {
  const fs = require('fs'), f = process.env.STUB_STATE + '/apply-count';
  const n = Number(fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : 0) + 1;
  fs.writeFileSync(f, String(n));
  if (n === 1) out({ sessionId: process.env.STUB_SID, switchedFrom: ['code'], switchedTo: 'prompt', choice: 'tombstone', resume: true });
  else { process.stderr.write('fake-excise: the apply failed\n'); process.exit(1); }
}
else { process.stderr.write('fake-excise: FAKE_APPLY unset\n'); process.exit(3); }
EOJ

export STUB_TRANSCRIPT="$TMPDIR/recover.jsonl"
export STUB_SWITCH_ON="1"
for mode in fail garbage noresumefield nameless; do
  export FAKE_APPLY="$mode"
  export STUB_SID="RECOVER-$mode"
  write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
  reset_stub

  err=$("$tpr2/bin/claude-laws" --model opus 2>&1 >/dev/null)
  status=$?

  [ "$(cat "$STUB_STATE/count" 2>/dev/null)" = 2 ] \
    && ok "$mode: the session is reopened rather than left closed" \
    || bad "$mode: expected 2 launches, got $(cat "$STUB_STATE/count" 2>/dev/null)"
  # The assertion is on the SHAPE of the recovery argv, not on whether the stub accepted it. A stub
  # takes any argv, including one the real claude refuses - "Session ID <uuid> is already in use."
  # for a second claim on the pinned id - so "recovery relaunched" would pass while the shipped
  # launcher reopens nothing. The id must come back as a --resume, and the pin must be gone.
  if [ -f "$STUB_STATE/argv.2" ]; then
    first=$(cat "$STUB_STATE/argv.1"); second=$(cat "$STUB_STATE/argv.2")
    pinned=${first##*--session-id }; pinned=${pinned%% *}
    case "$second" in
      *"--resume $pinned"*) ok "$mode:   ... by RESUMING the id the first launch pinned";;
      *) bad "$mode:   ... but did not resume $pinned (argv: $second)";;
    esac
    case "$second" in
      *--session-id*) bad "$mode:   ... and re-pinned --session-id, which claude refuses (argv: $second)";;
      *) ok "$mode:   ... never re-pinning an id claude has already held";;
    esac
    case "$second" in
      *"--model opus"*) ok "$mode:   ... and keeps the user's own flags";;
      *) bad "$mode:   ... but dropped the user's flags (argv: $second)";;
    esac
    # The recovered session must not be OFFERED a switch it cannot deliver. The three variables
    # were exported once and outlive the failure, so a recovered session would write request.json,
    # end itself, and land back in recover() - which reads nothing and exits, taking the request
    # with it through the EXIT trap. Withdrawing them is what turns a silently discarded decision
    # into a switch that was never on the table.
    case "$(cat "$STUB_STATE/env.2" 2>/dev/null)" in
      '||') ok "$mode:   ... with the switch machinery withdrawn, so no switch can be lost there";;
      *) bad "$mode:   ... but the recovered session still carries it ($(cat "$STUB_STATE/env.2" 2>/dev/null))";;
    esac
  else
    bad "$mode:   ... (no second launch to compare)"
    bad "$mode:   ... (pin check skipped)"
    bad "$mode:   ... (flag check skipped)"
    bad "$mode:   ... (switch-machinery check skipped)"
  fi
  [ "$status" -eq 1 ] && ok "$mode:   ... and the failed switch is still reported by the exit status" \
                      || bad "$mode:   ... but exited $status"
  case "$err" in
    *"reopening the session as it was"*) ok "$mode:   ... and says on stderr what it did";;
    *) bad "$mode:   ... and said nothing about it (stderr: $err)";;
  esac
done
unset FAKE_APPLY

# Recovery on a LATER pass, where the launcher's selector is already `--resume <sid>` from a switch
# that completed. Nothing may be re-derived here either: the selector passes through as it stands,
# still resuming the same session, still carrying the user's flags. Covered separately from the
# first-pass cases because a fix that only rewrites the initial pin would leave this pass wrong -
# and because it is the only pass whose expected id is one the test knows up front.
export FAKE_APPLY=okthenfail
export STUB_SID="RECOVER-later"
export STUB_SWITCH_ON="1 2"
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
reset_stub "$STUB_STATE/apply-count"

err=$("$tpr2/bin/claude-laws" --model opus 2>&1 >/dev/null)
status=$?

[ "$(cat "$STUB_STATE/count" 2>/dev/null)" = 3 ] \
  && ok "later-pass: a failure after one completed switch still reopens the session" \
  || bad "later-pass: expected 3 launches, got $(cat "$STUB_STATE/count" 2>/dev/null)"
[ "$status" -eq 1 ] && ok "later-pass:   ... and still reports the failed switch by exit status" \
                    || bad "later-pass:   ... but exited $status"
if [ -f "$STUB_STATE/argv.3" ]; then
  third=$(cat "$STUB_STATE/argv.3")
  case "$third" in
    *"--resume $STUB_SID"*) ok "later-pass:   ... carrying the existing --resume through unchanged";;
    *) bad "later-pass:   ... but lost the --resume $STUB_SID (argv: $third)";;
  esac
  case "$third" in
    *--session-id*) bad "later-pass:   ... and re-pinned --session-id (argv: $third)";;
    *) ok "later-pass:   ... with no --session-id anywhere on the relaunch";;
  esac
  case "$third" in
    *"--model opus"*) ok "later-pass:   ... and keeps the user's own flags";;
    *) bad "later-pass:   ... but dropped the user's flags (argv: $third)";;
  esac
  case "$(cat "$STUB_STATE/env.3" 2>/dev/null)" in
    '||') ok "later-pass:   ... and the recovered session is offered no switch either";;
    *) bad "later-pass:   ... but it still carries the switch machinery ($(cat "$STUB_STATE/env.3" 2>/dev/null))";;
  esac
else
  bad "later-pass:   ... (no third launch to inspect)"
  bad "later-pass:   ... (pin check skipped)"
  bad "later-pass:   ... (flag check skipped)"
  bad "later-pass:   ... (switch-machinery check skipped)"
fi
unset FAKE_APPLY

# ---- 7. resume:false is honored as data, not re-derived from the other fields ------------------
# SWITCH_ACTIONS decides once whether a choice leaves anything to resume into; `reject` says no.
# A launcher that infers "there is a session id, so resume" would release a craft the choice
# deliberately kept engaged. The surviving lock is what makes that difference visible.
export FAKE_APPLY=noresume
export STUB_SID="NORESUME1"
export STUB_TRANSCRIPT="$TMPDIR/noresume.jsonl"
export STUB_SWITCH_ON="1"
write_transcript "$STUB_TRANSCRIPT" "$STUB_SID"
reset_stub

printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:code"}}' \
  "$STUB_SID" | "$ROUTER" guard >/dev/null 2>&1

"$tpr2/bin/claude-laws" --model opus >/dev/null 2>&1
status=$?
[ "$status" -eq 0 ] && ok "a resume:false result is not a failure" || bad "exited $status on resume:false"

# Reopening the session unchanged still means REOPENING it, and the id that pinned the first launch
# cannot open it a second time: real claude answers "Error: Session ID <uuid> is already in use."
# and exits 1 with no session (measured). So the relaunch here has to arrive as --resume on that
# same id, exactly like the recovery relaunches in section 6. A stub accepts any argv, which is
# precisely why this asserts on the SHAPE - the earlier version of this test asserted the pin was
# still there and locked the bug in.
if [ -f "$STUB_STATE/argv.2" ]; then
  first=$(cat "$STUB_STATE/argv.1"); second=$(cat "$STUB_STATE/argv.2")
  pinned=${first##*--session-id }; pinned=${pinned%% *}
  case "$second" in
    *"--resume $pinned"*) ok "a resume:false result reopens the pinned session by RESUMING it";;
    *) bad "resume:false did not resume $pinned (argv: $second)";;
  esac
  case "$second" in
    *--session-id*) bad "resume:false re-pinned --session-id, which claude refuses (argv: $second)";;
    *) ok "  ... never re-pinning an id claude has already held";;
  esac
else
  bad "the session was not reopened after a resume:false result"
  bad "  (pin check skipped)"
fi

out=$(printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"laws:prompt"}}' \
  "$STUB_SID" | "$ROUTER" guard 2>/dev/null)
case "$out" in
  *'"deny"'*) ok "  ... and retires nothing, so the craft it kept is still engaged";;
  *) bad "  ... but the craft was retired anyway, so laws:prompt now loads (got: $out)";;
esac
unset FAKE_APPLY

# ---- 8. laws-switch ends the session by SIGNALLING the launcher's own child --------------------
# The switch is completed by SIGTERM, not an inspector. laws-switch finds the session — its ancestor
# whose parent is LAWS_LAUNCHER_PID — and signals it. This is the one behaviour that replaced the
# whole inspector channel, so it gets a real process tree rather than a stub: launcher → session →
# tool-shell → laws-switch, mirroring how the in-session command actually runs (a Bash-tool
# descendant of the very session it must end).
#
# The SESSION traps SIGTERM and writes a marker, and NOTHING ELSE in the tree does. So the marker is
# a precise pin: it appears only if the pid laws-switch signalled is the session — not the launcher
# (that would kill this test's own subprocess, not the session), not the tool-shell it had to climb
# past, not laws-switch itself. A walk that resolves the wrong node leaves the marker absent and the
# case fails. The `; true` in the tool-shell stops bash from exec-collapsing it, so the walk really
# does have a non-session frame to climb over. Every wait here is bounded, so a broken walk that
# signals nothing fails by timeout rather than hanging the suite.
sig_dir="$TMPDIR/sigtest"; mkdir -p "$sig_dir"
sig_marker="$sig_dir/session-was-signalled"
printf '{"sessionId":"SIG","transcript":"%s","incomingMedium":"prompt","current":"code"}\n' \
  "$TMPDIR/sig.jsonl" > "$sig_dir/pending.json"

cat > "$sig_dir/launcher.sh" <<'EOL'
#!/bin/bash
# I am the launcher; my pid is what the session's parent must equal. I run the session as a direct
# child, exactly as claude-laws runs claude.
export LAWS_LAUNCHER_PID=$$
export LAWS_SWITCH_DIR="$1"
bash "$2" "$3" "$4"   # session.sh <marker> <switch-bin>
EOL
cat > "$sig_dir/session.sh" <<'EOS8'
#!/bin/bash
marker="$1"; switch="$2"
trap 'echo hit > "$marker"; exit 0' TERM
# tool-shell → laws-switch, a frame deeper than the session, so the ancestry walk must climb past it.
bash -c '"$0" tombstone; true' "$switch" >/dev/null 2>&1 &
for _ in $(seq 1 100); do [ -f "$marker" ] && break; sleep 0.1; done
EOS8

rm -f "$sig_marker" "$sig_dir/request.json"
bash "$sig_dir/launcher.sh" "$sig_dir" "$sig_dir/session.sh" "$sig_marker" "$SWITCH"

[ -f "$sig_marker" ] \
  && ok "laws-switch signals the session — the launcher's own child, not the launcher or the tool-shell" \
  || bad "the session was not signalled (marker absent; laws-switch resolved the wrong pid or none)"
[ -f "$sig_dir/request.json" ] \
  && ok "  ... and records the choice before ending the session, so the launcher can apply it" \
  || bad "  ... but wrote no request.json, so the launcher would have nothing to apply"
[ ! -f "$sig_dir/pending.json" ] \
  && ok "  ... and consumes the pending decision it acted on" \
  || bad "  ... but left pending.json behind, so the guard would re-offer a switch already taken"

# Standalone: run with NO launcher in the ancestry (LAWS_LAUNCHER_PID unset). The choice must still
# be recorded — the request survives to be applied on any manual exit — and the failure to signal
# must be loud, never a silently dropped switch. [LAW:no-silent-failure]
sig_dir2="$TMPDIR/sigtest2"; mkdir -p "$sig_dir2"
printf '{"sessionId":"SIG2","transcript":"%s","incomingMedium":"prompt","current":"code"}\n' \
  "$TMPDIR/sig2.jsonl" > "$sig_dir2/pending.json"
out=$(env -u LAWS_LAUNCHER_PID LAWS_SWITCH_DIR="$sig_dir2" "$SWITCH" tombstone 2>&1 >/dev/null)
status=$?
[ -f "$sig_dir2/request.json" ] \
  && ok "with no launcher to signal, the choice is still recorded for a manual exit" \
  || bad "with no launcher, the choice was dropped rather than recorded"
[ "$status" -ne 0 ] && ok "  ... and the inability to end the session is reported, not swallowed" \
                    || bad "  ... but laws-switch exited 0 as though it had ended the session"
case "$out" in
  *"not started by claude-laws"*) ok "  ... naming why: no launcher pid to find the session under";;
  *) bad "  ... but the error does not name the cause (stderr: $out)";;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
