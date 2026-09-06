#!/bin/bash
# Tests for the claude-laws launcher and its installer — the two files that make the craft switch
# reachable from a user's terminal at all.
#
# WHAT IS BEING ASSERTED. The launcher's contract is not "which lines it runs" but what a session
# actually receives: the argv `claude` is invoked with, the environment the guard and `laws-switch`
# read, and the exit code the user gets back. So every case drives the REAL launcher and the REAL
# launch.js, replacing only `claude` itself (LAWS_CLAUDE_BIN) — the one part that cannot run in a
# test. The stub records argv and environment, which is exactly the seam the router reads.
# [LAW:behavior-not-structure] a different implementation of the same contract passes these.
#
# The hosted plan is always tried first and always fails here (a shell script has no Bun module
# graph to extract), so these runs also exercise the fall back to stock claude on every single case.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LAUNCHER="$HERE/claude-laws"
INSTALLER="$HERE/install-launcher"

export TMPDIR
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; fail=$((fail+1)); }

assert_eq()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected [$3], got [$2]"; }
assert_match() { case "$2" in *$3*) ok "$1";; *) bad "$1" "expected to contain [$3], got [$2]";; esac; }
assert_miss()  { case "$2" in *$3*) bad "$1" "expected NOT to contain [$3], got [$2]";; *) ok "$1";; esac; }

# The stand-in for `claude`. It records what a real session would have been handed — its argv, and
# the three environment facts the switch depends on — and can be told what to exit with.
STUB="$TMPDIR/claude-stub"
cat > "$STUB" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" > "$STUB_STATE/argv"
printf '%s\n' "${LAWS_SWITCH_SESSION-}" > "$STUB_STATE/session"
printf '%s\n' "${LAWS_SWITCH_DIR-}" > "$STUB_STATE/dir"
# Whether the handoff directory is really there WHILE a session runs, which is when the guard and
# bun-host.mjs look for it. Asserting it exists afterwards would prove the opposite of the contract.
[ -d "${LAWS_SWITCH_DIR:-/nonexistent}" ] && printf 'yes\n' > "$STUB_STATE/dir_live"
exit "${STUB_EXIT:-0}"
EOS
chmod +x "$STUB"

# run <label> [args...] -> populates $out (stderr) and the recorded files; sets $rc
run() {
  STUB_STATE="$TMPDIR/state.$1"; export STUB_STATE
  rm -rf "$STUB_STATE"; mkdir -p "$STUB_STATE"
  shift
  out=$(LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" "$@" 2>&1 >/dev/null)
  rc=$?
}
recorded() { cat "$STUB_STATE/$1" 2>/dev/null; }

# ---------------------------------------------------------------- the three setup jobs

run happy --model opus
assert_eq  'a hosted launch pins a minted --session-id' \
           "$(recorded argv)" "--session-id $(recorded session) --model opus"
assert_match 'the minted id is a uuid' "$(recorded session)" '-'
assert_miss  'the happy path logs no degrade' "$out" 'craft switching disabled'
[ -n "$(recorded dir)" ] && ok 'LAWS_SWITCH_DIR reaches the session' \
                         || bad 'LAWS_SWITCH_DIR reaches the session' 'it was empty'
assert_eq  'the handoff directory exists while the session runs' "$(recorded dir_live)" 'yes'
[ -d "$(recorded dir)" ] && bad 'the handoff directory is removed afterwards' 'it is still there' \
                         || ok 'the handoff directory is removed afterwards'
assert_eq  "the user's own flags reach claude unchanged" \
           "$(recorded argv)" "--session-id $(recorded session) --model opus"

# The pin and the export must be the SAME id: the router's eligibility test is an equality check
# between the session_id claude reports and the exported variable, so two different values would
# make every session ineligible while looking perfectly configured.
sid=$(recorded session)
assert_match 'the exported id and the pinned id are the same value' "$(recorded argv)" "--session-id $sid"

run exitcode; :
STUB_STATE="$TMPDIR/state.exitcode" STUB_EXIT=42 LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" >/dev/null 2>&1
assert_eq "claude's exit code is the launcher's exit code" "$?" '42'

# ---------------------------------------------------------------- the argv exclusions

# Each of these breaks the launch outright if the pin is added anyway: claude refuses --session-id
# alongside a session selector, and two --session-id flags are not a legal command line.
for sel in -c --continue -r --resume; do
  run "sel$sel" "$sel"
  assert_miss "a $sel launch is not pinned"          "$(recorded argv)" '--session-id'
  assert_match "a $sel launch says why"              "$out" 'craft switching disabled'
  assert_eq   "a $sel launch keeps the user's flag"  "$(recorded argv)" "$sel"
done

# The `=` spelling is a separate case because a scan over WHOLE tokens misses it and then mints a
# second --session-id onto the same command line — the exact broken launch the scan prevents.
run eqform --resume=abc123
assert_miss 'the = spelling of a selector is not pinned' "$(recorded argv)" '--session-id'
# Both halves, matching what the --session-id case below already asserts for its arm. Trimming the
# token and then forwarding the TRIMMED form would suppress the pin correctly and still break the
# user's session, and the negative assertion alone cannot see that.
assert_eq   'and the = spelling itself is passed through unchanged' "$(recorded argv)" '--resume=abc123'
run ownid --session-id=deadbeef
assert_miss "the user's own --session-id is not doubled" "$(recorded argv)" '--session-id deadbeef'
assert_eq   "the user's own --session-id is passed through" "$(recorded argv)" '--session-id=deadbeef'

# -p IS EXCLUDED, AND THE REASON MATTERS BECAUSE IT IS NOT THE OLD ONE. The original arm was about
# a relaunch re-sending the prompt, and it died with the relaunch — `claude --session-id <uuid> -p`
# parses fine. What keeps the arm is a different fact, measured on 2.1.259: under -p the app never
# constructs the class that owns a conversation, so the seam never fires and laws-switch fails with
# no-seam-ever-announced-a-conversation, having already spent the pending decision. The identical
# steps in a real PTY switch live. Offering there is a promise with nowhere to land.
run oneshot -p 'say ok'
assert_miss  'a -p session is not pinned, because it could never enact a switch' "$(recorded argv)" '--session-id'
assert_match 'and says the switch is unavailable' "$out" 'craft switching disabled'
assert_match 'naming enactment, not flag parsing, as the reason' "$out" 'never enacted'
assert_eq    "and still runs the user's one-shot" "$(recorded argv)" '-p say ok'

# ---------------------------------------------------------------- the degrade paths

# Nothing about a missing node is recoverable, but the user asked for a session and must still get
# one.
#
# THE ABSENCE IS BUILT, NOT BORROWED. This used to run with PATH=/usr/bin:/bin on the reasoning that
# node lives elsewhere — true on macOS, false on any Debian/Ubuntu box where the distro `nodejs`
# package puts it at /usr/bin/node. There the test would find a real node, take the normal path, and
# fail on correct code: a false alarm caused by the host's layout rather than by a regression, which
# is worse than not testing it. So the directory holds exactly the utilities the launcher needs and
# nothing else, and "there is no node" becomes a property this test constructs.
# `bash` is in the list because the launcher's shebang is `/usr/bin/env bash`, and env resolves the
# interpreter through PATH — a directory without it fails before the script's first line, with
# `env: bash: No such file or directory` rather than anything about node.
NODELESS="$TMPDIR/nodeless"; mkdir -p "$NODELESS"
for u in bash mktemp readlink head grep dirname basename cat rm mkdir sed; do
  src=$(command -v "$u") && ln -sf "$src" "$NODELESS/$u"
done
[ -e "$NODELESS/node" ] && bad 'the nodeless PATH really has no node' 'a node symlink leaked in' \
                        || ok 'the nodeless PATH really has no node'
STUB_STATE="$TMPDIR/state.nonode"; export STUB_STATE; mkdir -p "$STUB_STATE"
out=$(PATH="$NODELESS" LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" --model opus 2>&1 >/dev/null)
assert_match 'no node degrades to plain claude, loudly' "$out" 'node not found'
assert_eq    'no node still starts the session the user asked for' "$(recorded argv)" '--model opus'
assert_miss  'no node means no pin, because nothing can host the switch' "$(recorded argv)" '--session-id'

# ---------------------------------------------------------------- the failures that cannot degrade

# EVERY CASE HERE IS A FORK BOMB IF THE GUARD IS WRONG, which is why they are enumerated rather
# than represented by one example. Removing the guard and running this file spawned 1,545 processes
# and took the machine's load average past 100 — so "the suite hangs" is the FAILURE mode, and a
# passing run has to mean the guard fired, not that one spelling happened to be recognised.
out=$(LAWS_CLAUDE_BIN="$LAUNCHER" "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a claude that resolves to the launcher exits rather than looping' "$rc" '78'
assert_match 'and says what resolved to what' "$out" 'resolves to a claude-laws launcher'

# Through a symlink, which is how the installed launcher is normally reached.
ln -sf "$LAUNCHER" "$TMPDIR/aliased-claude"
out=$(LAWS_CLAUDE_BIN="$TMPDIR/aliased-claude" "$LAUNCHER" 2>&1); rc=$?
assert_eq 'the loop is caught through a symlink too' "$rc" '78'

# THE CASE AN IDENTITY CHECK MISSES. The installed stub is a DIFFERENT file from this launcher — it
# only execs it — so "is the resolved binary me?" answers no and lets the recursion through. A user
# who points `claude` at the thing install-launcher put on their PATH is the likeliest way to reach
# this at all, so it is the case the guard most has to catch.
STUBBIN="$TMPDIR/stubbin"; "$INSTALLER" "$STUBBIN" >/dev/null 2>&1
out=$(LAWS_CLAUDE_BIN="$STUBBIN/claude-laws" "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a claude that resolves to the INSTALLED STUB is refused too' "$rc" '78'
assert_match 'and names the stub as a launcher' "$out" 'resolves to a claude-laws launcher'

# And the same alias reached through the stub first, which is what a user actually types.
out=$(LAWS_CLAUDE_BIN="$STUBBIN/claude-laws" "$STUBBIN/claude-laws" 2>&1); rc=$?
assert_eq 'the stub launching itself is refused rather than recursing' "$rc" '78'

# THE BOUND, tested independently of what it is a bound on. The marker check is a judgement about a
# file and could be wrong about a spelling nobody has met; the depth ceiling is what makes being
# wrong cost a message instead of a fork bomb. Entering already-deep asserts it fires on its own.
out=$(LAWS_LAUNCH_DEPTH=8 LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a launch nested past the ceiling stops' "$rc" '78'
assert_match 'and says how deep it was' "$out" 'nested 9 launchers deep'

# ...and does not fire on the nesting an agent legitimately does, which is two or three deep. A
# ceiling that caught honest use would be worse than the recursion it prevents.
run nested3; :
STUB_STATE="$TMPDIR/state.nested3"; export STUB_STATE; mkdir -p "$STUB_STATE"
LAWS_LAUNCH_DEPTH=2 LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" >/dev/null 2>&1
assert_match 'a legitimately nested launch still starts a session' "$(recorded argv)" '--session-id'

# The real binary must NOT trip the marker check, or the guard makes every session unlaunchable.
# A legitimate nested `claude` resolves here, so this is the arm that keeps the check honest.
if [ -n "${REAL_CLAUDE:=$(command -v claude || true)}" ]; then
  out=$(head -c 400 "$(readlink -f "$REAL_CLAUDE")" 2>/dev/null | grep -c 'LAWS_LAUNCHER_SELF_MARKER')
  assert_eq 'the real claude binary carries no launcher marker' "$out" '0'
fi

# Same built directory as the no-node case, and for the same reason: "there is no claude on PATH"
# has to be a fact this test creates, not one it hopes the host happens to have.
# A DEPTH INHERITED FROM THE ENVIRONMENT IS PARSED, NOT EVALUATED. Bash arithmetic re-expands what
# it is handed, so `a[$(...)]` runs the substitution inside the subscript and still evaluates to a
# clean number — the command executes and the depth comes out right, which is why nothing looks
# wrong afterwards. The sentinel is the assertion: a launch must not be able to run it.
rm -f "$TMPDIR/pwned"
STUB_STATE="$TMPDIR/state.inject"; export STUB_STATE; mkdir -p "$STUB_STATE"
LAWS_LAUNCH_DEPTH='a[$(touch '"$TMPDIR"'/pwned)]' LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" >/dev/null 2>&1
[ -e "$TMPDIR/pwned" ] && bad 'an inherited depth cannot execute a command' 'the payload ran' \
                       || ok 'an inherited depth cannot execute a command'
assert_match 'and a junk depth still starts a session' "$(recorded argv)" '--session-id'

# A non-numeric depth counts as no depth rather than aborting the launch: the ceiling has to keep
# working, and a corrupted counter has no partial value worth salvaging.
STUB_STATE="$TMPDIR/state.junkdepth"; export STUB_STATE; mkdir -p "$STUB_STATE"
out=$(LAWS_LAUNCH_DEPTH='not-a-number' LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" 2>&1 >/dev/null)
assert_miss 'a junk depth is not mistaken for a deep nest' "$out" 'launchers deep'

# THE DIGIT STRINGS A CHARACTER TEST ADMITS, each of which broke the ceiling a different way before
# the parse produced a canonical integer instead of approving one. Enumerated rather than sampled,
# because they fail differently and a fix for one is not a fix for another.
#
#   2^64 wrapped to 1, so the ceiling never fired at all — the bypass itself.
#   A 25-digit string wrapped to 1590897978359414784 and REFUSED a legitimate launch.
#   08 is all digits and octal to bash: "value too great for base", a raw shell error to the user.
for d in 18446744073709551616 9999999999999999999999999 08 007 0000000009; do
  STUB_STATE="$TMPDIR/state.depth$d"; export STUB_STATE; mkdir -p "$STUB_STATE"
  out=$(LAWS_LAUNCH_DEPTH="$d" LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" --model opus 2>&1 >/dev/null)
  assert_miss "a depth of $d cannot pose as a deep nest"   "$out" 'launchers deep'
  assert_miss "a depth of $d raises no shell arithmetic error" "$out" 'value too great'
  # match, not equality: an accepted depth is a legitimate launch, so the argv also carries the pin
  assert_match "and a depth of $d still starts the session" "$(recorded argv)" '--model opus'
  assert_match "and a depth of $d is still a hosted launch" "$(recorded argv)" '--session-id'
done

# The ceiling must still fire on the honest spellings, or the parse above bought safety by breaking
# the thing it protects.
out=$(LAWS_LAUNCH_DEPTH=99 LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" 2>&1); rc=$?
assert_eq 'a two-digit depth is a real depth and still hits the ceiling' "$rc" '78'

# THE MINTED ID IS PARSED TOO. node's stdout can be reached before console.log by a NODE_OPTIONS
# preload or an injected agent, and a garbled id is passed to claude as --session-id and fails the
# launch outright — the one failure this file has no degrade for. Only the mint call is polluted, so
# the rest of the launch is unchanged and the case isolates the value under test.
POLLUTED="$TMPDIR/pollutednode"; mkdir -p "$POLLUTED"
REALNODE=$(command -v node)
cat > "$POLLUTED/node" <<EOS
#!/bin/bash
if [ "\$1" = "-e" ]; then printf 'apm-injector: instrumentation attached\n'; fi
exec "$REALNODE" "\$@"
EOS
chmod +x "$POLLUTED/node"
STUB_STATE="$TMPDIR/state.polluted"; export STUB_STATE; mkdir -p "$STUB_STATE"
out=$(PATH="$POLLUTED:$PATH" LAWS_CLAUDE_BIN="$STUB" "$LAUNCHER" --model opus 2>&1 >/dev/null)
assert_match 'a polluted mint degrades instead of pinning garbage' "$out" 'could not mint a session id'
assert_miss  'and nothing is pinned'                    "$(recorded argv)" '--session-id'
assert_eq    'and the session the user asked for still starts' "$(recorded argv)" '--model opus'

# THE LAST UNCOVERED DEGRADE. A launcher whose plugin tree has no launch.js cannot host, and the
# user still asked for a session. Reached here by copying the launcher somewhere its plugin is not,
# which is also what a mis-resolved PLUGIN_DIR would produce.
ORPHAN="$TMPDIR/orphan"; mkdir -p "$ORPHAN/bin"
cp "$LAUNCHER" "$ORPHAN/bin/claude-laws"; chmod +x "$ORPHAN/bin/claude-laws"
STUB_STATE="$TMPDIR/state.nolaunch"; export STUB_STATE; mkdir -p "$STUB_STATE"
out=$(LAWS_CLAUDE_BIN="$STUB" "$ORPHAN/bin/claude-laws" --model opus 2>&1 >/dev/null)
assert_match 'a missing launch.js degrades to plain claude, loudly' "$out" 'launcher not found at'
assert_eq    'and the session the user asked for still starts' "$(recorded argv)" '--model opus'
assert_miss  'unhosted means unpinned' "$(recorded argv)" '--session-id'

# `command -v` resolving a NAME is not the same as finding a FILE. An exported function named
# claude resolves to the bare word, and `readlink -f` on a word that names no file exits 1 with
# empty output, so the resolved path is empty and the exec below would be a bare one.
out=$(claude() { :; }; export -f claude; env -u LAWS_CLAUDE_BIN "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a shell function named claude is refused, not exec-ed' "$rc" '127'
assert_match 'and the message names the real cause' "$out" 'not an executable file'

# THE TWO CASES EMPTINESS MISSES, which are why the check is "runnable regular file" and not `-n`.
# LAWS_CLAUDE_BIN is taken from the caller and never checked, so it can name something that exists
# and still cannot be run. Without these a `-n` check passes the whole suite.
NOTEXEC="$TMPDIR/not-executable"; printf '#!/bin/sh\nexit 0\n' > "$NOTEXEC"; chmod -x "$NOTEXEC"
out=$(LAWS_CLAUDE_BIN="$NOTEXEC" "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a claude that exists but is not executable is refused' "$rc" '127'
assert_match 'and the message names the file it means' "$out" "$NOTEXEC"

# A directory passes `-x` — that is what makes it traversable — so it is the case that separates
# "executable" from "a thing exec can run".
out=$(LAWS_CLAUDE_BIN="$TMPDIR" "$LAUNCHER" 2>&1); rc=$?
assert_eq    'a claude that is a directory is refused' "$rc" '127'
assert_match 'and says so the same way' "$out" 'not an executable file'

out=$(env PATH="$NODELESS" LAWS_CLAUDE_BIN= "$LAUNCHER" 2>&1); rc=$?
assert_eq    'no claude anywhere exits 127' "$rc" '127'
assert_match 'and says so' "$out" "no 'claude' on PATH"

# ---------------------------------------------------------------- the installer

BIN="$TMPDIR/bin"
out=$("$INSTALLER" "$BIN" 2>&1); rc=$?
assert_eq    'the installer succeeds' "$rc" '0'
assert_match 'and reports where it put the launcher' "$out" "$BIN/claude-laws"
[ -x "$BIN/claude-laws" ] && ok 'the installed stub is executable' \
                          || bad 'the installed stub is executable' 'it is not'

# The installed stub must reach a session, which is the only claim the install actually makes.
STUB_STATE="$TMPDIR/state.installed"; export STUB_STATE; mkdir -p "$STUB_STATE"
LAWS_CLAUDE_BIN="$STUB" "$BIN/claude-laws" --model opus >/dev/null 2>&1
assert_match 'a session started through the installed stub is pinned' "$(recorded argv)" '--session-id'
assert_match 'and carries the user flags' "$(recorded argv)" '--model opus'

out=$("$INSTALLER" "$BIN" 2>&1); rc=$?
assert_eq 'installing twice replaces our own stub rather than refusing' "$rc" '0'

# The default target is built from $HOME, and under `set -u` an unset HOME would abort with bash's
# own unbound-variable message — the one failure in this file that would arrive without a diagnosis,
# in exactly the minimal container where it is most likely and least debuggable.
out=$(env -u HOME "$INSTALLER" 2>&1); rc=$?
assert_eq    'an unset HOME is diagnosed, not left to bash' "$rc" '1'
assert_match 'and names the argument that fixes it' "$out" 'install-launcher <directory>'
out=$(env -u HOME "$INSTALLER" "$TMPDIR/homeless" 2>&1); rc=$?
assert_eq    'and an explicit directory works without HOME at all' "$rc" '0'

# THE INSTALLER PROVES WHAT IT INSTALLED, rather than reporting success because a write returned 0.
# A copy of the plugin whose launcher cannot run is the one situation where the write succeeds and
# the install is still worthless, so it is the situation that decides whether the probe earns its
# place. Without this case the probe can be deleted with every other test still green.
BROKEN="$TMPDIR/brokenplugin"
mkdir -p "$BROKEN"; cp -R "$HERE/.." "$BROKEN/laws"
# The marker definition stays: without it the installer refuses earlier, for a different and equally
# correct reason, and this case would pass while testing something else entirely.
printf "#!/usr/bin/env bash\nLAWS_LAUNCHER_SELF_MARKER='LAWS_LAUNCHER_SELF_MARKER'\nexit 9\n" \
  > "$BROKEN/laws/bin/claude-laws"
chmod +x "$BROKEN/laws/bin/claude-laws"
out=$("$BROKEN/laws/bin/install-launcher" "$TMPDIR/bin2" 2>&1); rc=$?
assert_eq    'an install whose launcher cannot run fails' "$rc" '1'
assert_match 'and says the launcher it installed did not reach a session' "$out" 'did not reach a session'

# EXIT 0 IS NOT ARRIVAL. A launcher that returns cleanly without ever invoking the binary it was
# handed is the case the exit code alone cannot see, and it is the reason the probe's stand-in
# records being run rather than merely being pointed at. Without this the recording can be deleted
# and the case above still passes on its exit code.
SILENT="$TMPDIR/silentplugin"
mkdir -p "$SILENT"; cp -R "$HERE/.." "$SILENT/laws"
printf "#!/usr/bin/env bash\nLAWS_LAUNCHER_SELF_MARKER='LAWS_LAUNCHER_SELF_MARKER'\nexit 0\n" \
  > "$SILENT/laws/bin/claude-laws"
chmod +x "$SILENT/laws/bin/claude-laws"
out=$("$SILENT/laws/bin/install-launcher" "$TMPDIR/bin4" 2>&1); rc=$?
assert_eq    'an install whose launcher exits 0 without launching fails' "$rc" '1'
assert_match 'and names what did not happen' "$out" 'never invoked the binary'

# A launcher with no marker definition cannot be stamped into a stub that the guard would recognise,
# so the installer refuses rather than writing one that reintroduces the recursion it prevents.
UNMARKED="$TMPDIR/unmarkedplugin"
mkdir -p "$UNMARKED"; cp -R "$HERE/.." "$UNMARKED/laws"
printf '#!/usr/bin/env bash\nexit 0\n' > "$UNMARKED/laws/bin/claude-laws"
chmod +x "$UNMARKED/laws/bin/claude-laws"
out=$("$UNMARKED/laws/bin/install-launcher" "$TMPDIR/bin3" 2>&1); rc=$?
assert_eq    'an installer that cannot find the marker refuses to write a stub' "$rc" '1'
assert_match 'and says why that matters' "$out" 'not be recognised as a launcher'
[ -e "$TMPDIR/bin3/claude-laws" ] && bad 'and writes no stub at all' 'one was written' \
                                  || ok 'and writes no stub at all'

# THE TOKEN ROUND-TRIPS, tested with a token the installer cannot have been born knowing. Reading
# the real launcher's token and finding it in the stub would pass just as well if the installer
# spelled that same string itself, which is the drift this design exists to make unrepresentable —
# so the launcher this case installs from has a RENAMED token, and only reading carries it through.
RENAMED="$TMPDIR/renamedplugin"
mkdir -p "$RENAMED"; cp -R "$HERE/.." "$RENAMED/laws"
sed "s/^LAWS_LAUNCHER_SELF_MARKER='[^']*'/LAWS_LAUNCHER_SELF_MARKER='MARKER_RENAMED_BY_THE_TEST'/" \
  "$LAUNCHER" > "$RENAMED/laws/bin/claude-laws"
chmod +x "$RENAMED/laws/bin/claude-laws"
out=$("$RENAMED/laws/bin/install-launcher" "$TMPDIR/bin5" 2>&1); rc=$?
assert_eq 'an install from a launcher with a renamed token succeeds' "$rc" '0'
grep -qF 'MARKER_RENAMED_BY_THE_TEST' "$TMPDIR/bin5/claude-laws" \
  && ok 'and the stub carries the renamed token, so the installer never spells one' \
  || bad 'and the stub carries the renamed token, so the installer never spells one' \
        "stub says: $(cat "$TMPDIR/bin5/claude-laws" 2>/dev/null | head -3)"

# A FAILED INSTALL MUST NOT COST THE USER A WORKING ONE. Re-running the installer after a plugin
# update is the flow the README tells people to take, so the case where the replacement turns out to
# be broken is a normal one, not an exotic one. The old shape wrote the stub at the destination and
# probed afterwards, which meant a failed probe had already destroyed what it was checking against.
GOOD="$TMPDIR/bin6"; "$INSTALLER" "$GOOD" >/dev/null 2>&1
before=$(cat "$GOOD/claude-laws")
out=$("$BROKEN/laws/bin/install-launcher" "$GOOD" 2>&1); rc=$?
assert_eq 'installing a broken launcher over a good one fails'  "$rc" '1'
assert_eq 'and the working launcher is exactly as it was'       "$(cat "$GOOD/claude-laws")" "$before"
assert_match 'and the failure says nothing was changed'         "$out" 'nothing was changed'
# The staging directory is an implementation detail the user must never meet, so no exit path may
# leave one behind — including the failing one just exercised.
leftovers=$(find "$GOOD" -maxdepth 1 -name '.claude-laws-install.*' | wc -l | tr -d ' ')
assert_eq 'and no staging directory is left in the target directory' "$leftovers" '0'

# OWNERSHIP IS THE TOKEN, NOT THE SENTENCE. A stub written by a version of this installer whose
# marker line was worded differently is still our own work, and must not be diagnosed as a foreign
# file the user has to move aside — that would block the upgrade path on nothing but a reworded
# comment. This stub carries the token under wording no version of the installer has ever used.
REWORDED="$TMPDIR/bin7"; mkdir -p "$REWORDED"
TOKEN=$(sed -n "s/^LAWS_LAUNCHER_SELF_MARKER='\([^']*\)'.*/\1/p" "$LAUNCHER" | head -1)
printf '#!/usr/bin/env bash\n# %s :: emitted by some future wording of install-launcher\nexit 0\n' \
  "$TOKEN" > "$REWORDED/claude-laws"
chmod +x "$REWORDED/claude-laws"
out=$("$INSTALLER" "$REWORDED" 2>&1); rc=$?
assert_eq    'a stub whose marker line is worded differently is still recognised as ours' "$rc" '0'
assert_match 'and it is replaced rather than refused' "$(cat "$REWORDED/claude-laws")" 'LAUNCHER='

# Someone else's claude-laws is theirs. Replacing it silently is how an installer eats a file its
# user cared about, so the marker — a fact about the file — is what authorises the overwrite.
mkdir -p "$TMPDIR/foreign"; printf '#!/bin/sh\necho mine\n' > "$TMPDIR/foreign/claude-laws"
out=$("$INSTALLER" "$TMPDIR/foreign" 2>&1); rc=$?
assert_eq    'the installer refuses to clobber a file it did not write' "$rc" '1'
assert_match 'and says why' "$out" 'not written by this installer'
assert_eq    'and leaves that file untouched' "$(cat "$TMPDIR/foreign/claude-laws")" "$(printf '#!/bin/sh\necho mine')"

# A plugin update moves the install directory, so every stub eventually points at a path that is
# gone. That has to name the cause and the cure, not surface as `command not found`.
sed "s|^LAUNCHER=.*|LAUNCHER=/nonexistent/laws/bin/claude-laws|" "$BIN/claude-laws" > "$BIN/stale"
chmod +x "$BIN/stale"
out=$("$BIN/stale" 2>&1); rc=$?
assert_eq    'a stub whose plugin is gone exits 78' "$rc" '78'
assert_match 'and names the missing plugin' "$out" '/nonexistent/laws/bin/claude-laws'
assert_match 'and names the fix' "$out" 'install-launcher'
assert_match 'and offers a session in the meantime' "$out" "run 'claude'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
