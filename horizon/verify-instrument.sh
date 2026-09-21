#!/usr/bin/env bash
# Verify the instrument against its three acceptance criteria:
#
#   1. Two invocations of pin-instrument.sh, same inputs, produce byte-identical
#      manifest.json files. Four of the refs a pin resolves move on their own -
#      memento's default branch, lit's default branch, the reviewer's `v1` tag, and
#      this checkout's own HEAD - so this script resolves all four exactly ONCE and
#      passes the same shas into both invocations. Otherwise a push, a tag move, or a
#      commit landing here between the two calls would fail this check for reasons
#      that have nothing to do with the instrument itself.
#   2. A session launched against the produced CLAUDE_CONFIG_DIR has exactly the
#      plugins the pinned marketplace lists installed and enabled, and nothing else -
#      no laws plugin, no owner CLAUDE.md, no owner memory.
#   3. The instrument can actually execute GOAL_PROMPT.md's loop: every skill that
#      loop names is present as a procedure, and is the pinned one. A directory
#      existing is not that test - it is how this verifier once went green against an
#      instrument whose skills were all pointer stubs. Each plugin's skills are checked
#      byte-for-byte against the snapshot they were pinned from: memento's
#      address-pr-reviews and message-in-a-bottle, and lit's next.
#   4. A REAL SESSION launched against the produced config dir gets past every gate the
#      instrument is responsible for. `claude plugin list` needs no credential and no
#      terminal, so it went green against a config dir that could not boot a session at
#      all - which is how a run reached an interactive dialog no unattended driver can
#      answer, twice. The check below boots one and reads the pane.
#
#      It asserts the session reaches `logged-out`, not `ready`, and that is the whole
#      point rather than a weakened test: Claude Code keys its credential to the config
#      dir's PATH, so a throwaway dir under $WORK is unauthenticated BY CONSTRUCTION and
#      no verification can make it otherwise without touching a credential store, which
#      this script will not do. `logged-out` is reached only by a session that drew its
#      banner and its input box, which means onboarding and the trust dialog are both
#      settled - so it proves exactly the instrument's half and claims nothing about the
#      operator's. The run asserts `ready` instead, against its own authenticated dir.
#
# [LAW:verifiable-goals] this script IS the machine-checkable "done" for the ticket;
# exit 0 means every criterion held on this run, exit nonzero says which one didn't.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

# Every tool this run reaches for, checked before the first line that reaches for one -
# including the `mktemp` just below, which at script scope would otherwise run before
# any check ran at all. Placement is the enforcement, so there is no ordering left to
# remember. Only the two-line bootstrap above precedes it, and it cannot be covered:
# `dirname` is what locates the file that defines the checker.
# [LAW:single-enforcer] [LAW:no-ambient-temporal-coupling]
horizon_need_base
horizon_need git
horizon_need gh
horizon_need claude
horizon_need python3
horizon_need lit
horizon_need diff
# Criterion 4 boots a real session; the run lives in tmux for isolation and so does this.
horizon_need tmux
# Reached only by criterion 4b, which puts a symlink in front of the project on purpose.
horizon_need ln

# Canonicalized at creation: on macOS mktemp -d hands back /var/... while the real
# path is /private/var/..., and the isolation check below compares a path derived from
# this against one the claude CLI may report already resolved. [LAW:one-source-of-truth]
WORK="$(cd "$(mktemp -d)" && pwd -P)"
# Its own session name, never HORIZON_TMUX_SESSION: that one is the run's machine-wide
# lock, and a verifier borrowing it would either be refused while a run is live or, worse,
# kill the run's session on the way out. $$ keeps two verifiers off each other too.
VERIFY_TMUX_SESSION="horizon-verify-$$"
# `|| true` on the kill, and it is load-bearing rather than defensive: this runs under
# errexit, so a kill that fails - which is the NORMAL case, because most runs never get
# far enough to create the session - would abort the handler on its first line, take the
# `rm -rf` with it, and hand back a failing status from a script whose every check passed.
# The trap is also the ONLY place the session is ended, so the success path and the
# horizon_die path leave nothing behind by the same line. [LAW:single-enforcer]
trap 'tmux kill-session -t "$VERIFY_TMUX_SESSION" 2>/dev/null || true; rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Usage: check_installed_skills <install_path> <snapshot_plugin_dir> <plugin_name> <skill>...
#
# Compared against the snapshot they were pinned from, never merely counted as
# directories: `claude plugin install` materialises symlinked skills into real files, so
# equality here is what proves the install carries the pinned bytes rather than something
# that happens to occupy the same name. The pin has already refused a snapshot whose
# skills were pointer stubs, so "same as the snapshot" is the whole remaining question.
# [LAW:one-source-of-truth]
check_installed_skills() {
  local install_path="$1" snapshot_plugin_dir="$2" name="$3" skill
  shift 3
  for skill in "$@"; do
    [ -d "$install_path/skills/$skill" ] || fail "installed $name is missing the '$skill' skill"
    diff -r "$snapshot_plugin_dir/skills/$skill" "$install_path/skills/$skill" >/dev/null \
      || fail "installed $name '$skill' differs from the pinned snapshot it came from"
  done
}

main() {
  local repo_root memento_sha lit_sha reviewer_sha goal_ref
  # memento's and lit's default branches are moving refs, exactly like the reviewer's
  # `v1` tag: resolved once here and handed to both runs as shas, so a push landing
  # between the two invocations cannot fail the reproducibility check for reasons that
  # have nothing to do with the instrument.
  horizon_log "resolving memento once for both runs: ${HORIZON_MEMENTO_REPO_URL}@${HORIZON_MEMENTO_DEFAULT_REF}"
  memento_sha="$(horizon_git_fetch "$HORIZON_MEMENTO_REPO_URL" "$WORK/memento.git" "$HORIZON_MEMENTO_DEFAULT_REF")"
  horizon_log "resolving lit's plugin once for both runs: ${HORIZON_LIT_REPO_URL}@${HORIZON_LIT_DEFAULT_REF}"
  lit_sha="$(horizon_git_fetch "$HORIZON_LIT_REPO_URL" "$WORK/lit.git" "$HORIZON_LIT_DEFAULT_REF")"

  horizon_log "resolving reviewer once for both runs: ${REVIEWER_REPO}@${REVIEWER_TAG}"
  reviewer_sha="$(horizon_reviewer_sha)"

  # This checkout's HEAD is a moving ref too - anything committing here between the two
  # runs would otherwise change goal_wording under them. Pinned once, like the others.
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  goal_ref="$(horizon_resolve_commit "$repo_root" "HEAD")"

  local run
  for run in run1 run2; do
    horizon_log "$run: pinning memento $memento_sha, lit plugin $lit_sha"
    "$SCRIPT_DIR/pin-instrument.sh" "$WORK/$run" "$memento_sha" "$reviewer_sha" "$goal_ref" "$lit_sha"
  done

  if diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >/dev/null; then
    pass "two invocations produced byte-identical manifest.json"
  else
    diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >&2 || true
    fail "manifests diverged between two invocations with unchanged inputs"
  fi

  # A THROWAWAY config dir under $WORK, never the machine's real, authenticated one: a
  # verification must not wipe the directory a run launches against. Built from run 2's
  # snapshot, which is also the one the installed skills are compared against below.
  local config_dir="$WORK/config" pinned_dir="$WORK/run2/pinned"
  horizon_log "provisioning a throwaway config dir from run 2's snapshot"
  horizon_provision_config_dir "$config_dir" "$pinned_dir"

  local plugin_list admitted
  plugin_list="$(CLAUDE_CONFIG_DIR="$config_dir" claude plugin list --json)" \
    || fail "could not read claude plugin list --json from the isolated config dir"
  admitted="$(horizon_marketplace_plugins "$pinned_dir")"

  # One line per installed plugin, "<name>\t<real install path>", printed only once the
  # installed set is exactly the admitted set and every one of them is enabled.
  # sys.exit, never assert: -O / PYTHONOPTIMIZE compiles asserts out, which would turn
  # this acceptance check into a silent pass on any input. [LAW:no-silent-failure]
  local installed
  installed="$(printf '%s' "$plugin_list" | python3 -c '
import json, os, sys
marketplace, admitted = sys.argv[1], sys.argv[2].split("\n")
plugins = json.load(sys.stdin)
expected = sorted(f"{name}@{marketplace}" for name in admitted)
ids = sorted(p["id"] for p in plugins)
if ids != expected:
    sys.exit(f"expected exactly {expected} installed, got {ids}")
for p in plugins:
    if p["enabled"] is not True:
        sys.exit(p["id"] + " is installed but not enabled")
    print(p["id"].split("@")[0] + "\t" + os.path.realpath(p["installPath"]))
' "$HORIZON_MARKETPLACE_NAME" "$admitted")" \
    || fail "claude plugin list did not show exactly the pinned marketplace's plugins enabled"
  pass "isolated config dir has exactly the pinned plugins installed and enabled: $(printf '%s' "$admitted" | tr '\n' ' ')"

  [ -f "$config_dir/CLAUDE.md" ] && fail "isolated config dir has a CLAUDE.md - owner guidance leaked in"
  pass "isolated config dir carries no CLAUDE.md"

  # Session memory lives under $CLAUDE_CONFIG_DIR/projects/*/memory/ - checked as
  # actual memory *content* at that path, not the mere existence of projects/,
  # which install-time bookkeeping unrelated to memory could in principle also
  # create and would otherwise make this a false failure.
  local memory_files
  memory_files="$(find "$config_dir/projects" -path '*/memory/*' -type f 2>/dev/null || true)"
  [ -n "$memory_files" ] && fail "isolated config dir has memory content: $memory_files"
  pass "isolated config dir carries no memory content"

  # Checked in the INSTALLED location under the config dir, via installPath from
  # claude plugin list - not the pinned/ snapshot source dir, which only proves the
  # git-archive extraction worked, never that `claude plugin install` wired the
  # skills up where a launched session would actually see them. And checked as
  # actually falling under $config_dir - otherwise a plugin CLI that resolved
  # "user" scope to some shared location outside this run's isolation would still
  # pass by finding the skills wherever they really landed.
  local name install_path memento_install="" lit_install=""
  while IFS=$'\t' read -r name install_path; do
    case "$install_path" in
      "$config_dir"/*) ;;
      *) fail "installed $name path ($install_path) is not under the isolated config dir ($config_dir)" ;;
    esac
    case "$name" in
      memento) memento_install="$install_path" ;;
      lit) lit_install="$install_path" ;;
    esac
  done <<<"$installed"
  # The loop needs these two by name. The admitted-set check above already failed on a
  # marketplace listing anything else; this fails on one that forgot either of them.
  [ -n "$memento_install" ] || fail "the pinned marketplace does not admit memento"
  [ -n "$lit_install" ] || fail "the pinned marketplace does not admit lit, so a run has no /next"

  check_installed_skills "$memento_install" \
    "$pinned_dir/$(horizon_plugin_rel_path memento "$HORIZON_MEMENTO_PLUGIN_SUBDIR")" \
    memento "${HORIZON_MEMENTO_SKILLS[@]}"
  # diff compares bytes, not mode bits; the relaunch binary has to be runnable as installed.
  [ -x "$memento_install/$HORIZON_MEMENTO_RELAUNCH_REL_PATH" ] \
    || fail "installed memento's finalize-session is not executable: $memento_install/$HORIZON_MEMENTO_RELAUNCH_REL_PATH"
  pass "installed memento carries the pinned skills, byte for byte, with the relaunch binary executable"

  check_installed_skills "$lit_install" \
    "$pinned_dir/$(horizon_plugin_rel_path lit "$HORIZON_LIT_PLUGIN_SUBDIR")" \
    lit "${HORIZON_LIT_SKILLS[@]}"
  pass "installed lit plugin carries the pinned /next skill, byte for byte"

  local recorded_lit_sha256 actual_lit_sha256
  recorded_lit_sha256="$(horizon_manifest_field "$WORK/run1/manifest.json" lit sha256)" \
    || fail "could not read lit.sha256 from run1/manifest.json"
  actual_lit_sha256="$(horizon_lit_sha256)"
  [ "$recorded_lit_sha256" = "$actual_lit_sha256" ] \
    || fail "recorded lit sha256 ($recorded_lit_sha256) does not match the lit currently on PATH ($actual_lit_sha256)"
  pass "lit on PATH matches the manifest's recorded identity"

  # Criterion 4a: the pane classifier, against panes captured from real sessions put into
  # each state on purpose. Kept as fixtures rather than left to the live boot below, which
  # can only ever exhibit ONE state per run: a classifier whose failure branches are never
  # executed is the tautology this repo has already shipped once. Every string here was
  # read off a v2.1.278 pane, not composed to match the regex. [LAW:verifiable-goals]
  local got
  got="$(printf '%s\n' " Let's get started." " Choose the text style that looks best with your terminal" "   1. Auto (match terminal)" | horizon_boot_state)"
  [ "$got" = onboarding ] || fail "the theme picker pane classified as '$got', not onboarding"
  got="$(printf '%s\n' " Accessing workspace:" " /private/tmp/x/proj" " Quick safety check: Is this a project you created or one you trust? (Like your own code" " ❯ No, exit" "   Yes, I trust this folder" | horizon_boot_state)"
  [ "$got" = untrusted ] || fail "the trust-dialog pane classified as '$got', not untrusted"
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "▝▜██████▀  Opus 5 (1M context) · API Usage Billing" "❯ " "  ⏵⏵ bypass permissions on (shift+tab to cycle)                    Not logged in · Run /login" | horizon_boot_state)"
  [ "$got" = logged-out ] || fail "a not-logged-in pane classified as '$got', not logged-out"
  # The OTHER wording, and the one a baseline campaign actually meets: a config dir that
  # was logged in when the campaign started and whose refresh token the server retired
  # part way through. It needs no mistake by anyone, only elapsed time, so the run that
  # hits it is a later run of a long campaign - the most expensive possible moment to
  # discover the pane vocabulary only covered the other spelling. Observed 2026-09-07.
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "❯ " "  Login expired · Please run /login" | horizon_boot_state)"
  [ "$got" = logged-out ] || fail "an expired-login pane classified as '$got', not logged-out"
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "❯ " "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents" | horizon_boot_state)"
  [ "$got" = ready ] || fail "an authenticated pane classified as '$got', not ready"
  got="$(printf '%s\n' "" "   ░░░░░░░░" | horizon_boot_state)"
  [ "$got" = forming ] || fail "a pane that has drawn nothing classified as '$got', not forming"
  # THE RACE. Banner and input box painted, status line not yet - so the login notice, if
  # this session has one coming, has not had anywhere to appear. Answering `ready` here is
  # answering from an absence, and it would hand a dead-credential session to the run for
  # the one reason that must never be enough: the evidence against it had not arrived.
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "❯ " | horizon_boot_state)"
  [ "$got" = forming ] || fail "a pane whose status line has not painted classified as '$got', not forming"
  # The one that matters most, and the reason the login notice is tested at all: the SAME
  # banner appears in both, so a classifier that only looked for it would call the dead
  # session ready. That was the behaviour here until 2026-09-21.
  pass "the pane classifier separates ready from logged-out, onboarding, untrusted and forming"

  # A pane that CANNOT be read must end the wait with a diagnosis rather than in silence.
  # Checked against a session name that does not exist, which needs no session and costs
  # nothing: the failing read is the same one a session that died on startup produces, and
  # tmux destroys a session with its last pane, so that is not hypothetical. This guards a
  # regression that reached this file once and was invisible in every other check - under
  # `set -o pipefail` a bare assignment from the pane read tripped errexit and exited 1
  # having printed NOTHING, horizon_die's own message going to a discarded stderr, after a
  # column of PASS lines had already been printed. [LAW:no-silent-failure]
  local dead_refusal=""
  if dead_refusal="$( horizon_await_boot_state "horizon-verify-no-such-session-$$" ready 2>&1 )"; then
    fail "waiting on a session that does not exist returned success"
  fi
  case "$dead_refusal" in
    *"could not be read"*) ;;
    *) fail "waiting on an unreadable pane did not say so: ${dead_refusal:-(it printed nothing at all, which is the regression this checks for)}" ;;
  esac
  pass "a pane that cannot be read ends the wait with a diagnosis, not in silence"

  # Criterion 4b: boot a real session against the config dir this script just produced.
  #
  # The project is reached through a SYMLINK on purpose. Claude Code records a workspace
  # under its RESOLVED path, so the trust key horizon_write_boot_state writes has to be
  # resolved too - and on this platform an operator whose HORIZON_WORK_DIR sits anywhere
  # under /tmp or /var supplies an unresolved path without doing anything unusual. Passing
  # a symlink here makes that difference exist on every machine instead of only on the
  # ones where it happens to: drop the resolution and this boots to `untrusted`.
  local verify_project="$WORK/project" verify_link="$WORK/project-via-symlink"
  mkdir -p "$verify_project" || fail "could not create $verify_project"
  ( cd "$verify_project" && git init -q . ) || fail "could not init the verification project"
  ln -s "$verify_project" "$verify_link" || fail "could not create $verify_link"
  horizon_write_boot_state "$config_dir" "$verify_link"

  horizon_log "booting a real session against the produced config dir"
  tmux new-session -d -s "$VERIFY_TMUX_SESSION" -x 200 -y 50 \
    || fail "could not create the verification tmux session $VERIFY_TMUX_SESSION"
  tmux set-environment -t "$VERIFY_TMUX_SESSION" CLAUDE_CONFIG_DIR "$config_dir" \
    || fail "could not bind CLAUDE_CONFIG_DIR into the verification session"
  # "Unauthenticated by construction" is true of the KEYCHAIN credential, which Claude Code
  # keys to the config dir's path - and false of a token in the environment, which
  # authenticates any config dir at all. Left alone, whether one even reaches the pane is
  # worse than wrong, it is nondeterministic: a tmux server starting fresh inherits this
  # shell's environment while an already-running one does not, so the same machine would
  # pass or fail this criterion by whether tmux happened to be up. An operator with a
  # reviewer token exported - CLAUDE_CODE_OAUTH_TOKEN is exactly that, and rotating it is
  # routine here - would be told the instrument is broken when their shell is the cause.
  # Removed from the session's environment rather than asserted about, so the precondition
  # this criterion rests on is TRUE instead of merely checked.
  # [LAW:no-ambient-temporal-coupling]
  local leaked
  for leaked in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
    tmux set-environment -t "$VERIFY_TMUX_SESSION" -u "$leaked" \
      || fail "could not clear $leaked from the verification session's environment"
  done
  tmux respawn-pane -k -t "$VERIFY_TMUX_SESSION" -c "$verify_link" \
    claude --dangerously-skip-permissions \
    || fail "could not launch claude in the verification session"
  horizon_await_boot_state "$VERIFY_TMUX_SESSION" logged-out
  pass "a real session against the produced config dir clears onboarding and the trust dialog, leaving only the credential"

  # The SAME live session, asked for the state the RUN asks for. Without this the wait is
  # only ever exercised on the path where it agrees, so a wait that returned success for
  # any settled state would pass everything above while leaving run-loop.sh to march a
  # dead session through a whole run - the exact defect this ticket exists for, reinstated
  # with the gate still green. Here the discriminator has to do its job in the failing
  # direction, on a real pane, and say which state it actually found.
  local refusal=""
  if refusal="$( horizon_await_boot_state "$VERIFY_TMUX_SESSION" ready 2>&1 )"; then
    fail "waiting for 'ready' accepted a session that is only 'logged-out' - the run would launch into a session that accepts nothing"
  fi
  # A non-zero exit is not by itself evidence of the RIGHT refusal. The same wait also
  # exits non-zero when the session has died between the two calls - and that one comes
  # back EMPTY, because what failed was the pane read - and when it simply timed out in
  # `forming`. Both are ruled out by name first, so a dead session is reported as a dead
  # session instead of as a classifier that forgot to name its states.
  # [LAW:parse-dont-validate]
  [ -n "$refusal" ] \
    || fail "waiting for 'ready' failed without a word, so the verification session most likely died between the two waits"
  case "$refusal" in
    *"never left 'forming'"*) fail "waiting for 'ready' timed out rather than refusing a logged-out session: $refusal" ;;
    *"could not be read"*) fail "the verification session died between the two waits: $refusal" ;;
  esac
  case "$refusal" in
    *"booted to 'logged-out'"*"wanted 'ready'"*) ;;
    *) fail "the refusal did not name the state it found and the state it wanted: $refusal" ;;
  esac
  case "$refusal" in
    *"horizon/login.sh"*) ;;
    *) fail "the refusal did not tell the operator how to fix a logged-out config dir: $refusal" ;;
  esac
  pass "waiting for 'ready' refuses a logged-out session, naming both states and the fix"

  horizon_log "all checks passed"
}

main "$@"
