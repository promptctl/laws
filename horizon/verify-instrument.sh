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
#      It asserts the session reaches a state PAST those gates - `logged-out` OR `ready` -
#      and which of the two it gets is deliberately not the question. Both are reached
#      only by a session that drew its banner and its input box, which means onboarding
#      and the trust dialog are each settled, so either one proves exactly the
#      instrument's half and claims nothing about the operator's. Ordinarily it is
#      `logged-out`: Claude Code keys its credential to the config dir's PATH, so a
#      throwaway dir under $WORK is unauthenticated BY CONSTRUCTION, and no verification
#      can make it otherwise without touching a credential store, which this script will
#      not do. Demanding `logged-out` ALONE would promote that ordinary outcome into a
#      requirement and fail a sound instrument on a machine that happens to authenticate
#      some other way. The run asserts `ready`, against its own authenticated dir.
#   5. The HARNESS is pinned and recorded: the model the run's sessions use, and the
#      Claude Code binary itself. Both are properties of this machine rather than of
#      something fetched, so both are checked against the machine rather than against a
#      ref - the pinned symlink, the manifest's path and version, the model the config
#      dir actually imposes, and the version the booted session reports are all required
#      to describe one binary and one model. The mismatch gate is exercised in its
#      FAILING direction, since a gate only ever seen agreeing proves nothing.
#
#      An unset campaign pin is recorded as null and checked to be null: a reader decides
#      from that field whether a campaign's runs are comparable, so "recorded but not
#      held" must be unmistakable rather than inferred.
#   6. The run refuses to start when the REVIEWER's credential is absent. The reviewer is
#      a controlled variable, and a run that merges every pull request without one measured
#      a workflow the campaign does not claim - silently, because a pull request nobody
#      reviewed looks in the record exactly like one a reviewer had nothing to say about.
#      The credential is half of "the reviewer runs"; installing the workflow is the other
#      half, and it is not the instrument's job yet - see horizon_assert_reviewer_credential.
#      Driven from fixtures, not against the live repository: the verdict must be about
#      the instrument rather than about whether an operator's secret store is set up, and
#      both directions of the gate have to run whatever that store holds.
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
  horizon_provision_config_dir "$config_dir" "$WORK/run2"

  # Criterion 5d: the model the manifest records is the model the config dir imposes.
  # Read out of settings.json rather than trusted from the variable that wrote it: the key
  # name is Claude Code's, and a run whose model setting landed under a key the CLI does
  # not read would record a control while the sessions quietly took the CLI default -
  # which is the same silent shape as the trust key written under the wrong path.
  #
  # The non-empty half is the load-bearing one: it is what catches that regression. The
  # equality half became worth asserting once provisioning started reading the model back
  # out of manifest.json - it now checks that plumbing rather than comparing two readings
  # of one environment variable, which agreed by construction and could not fail.
  local settings_model recorded_model
  recorded_model="$(horizon_manifest_field "$WORK/run2/manifest.json" claude model)" \
    || fail "could not read claude.model from run2/manifest.json"
  settings_model="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1])).get("model", ""))
' "$config_dir/settings.json")" || fail "could not read $config_dir/settings.json"
  [ -n "$settings_model" ] \
    || fail "the provisioned config dir carries no model setting, so its sessions would take whatever default the CLI ships"
  [ "$settings_model" = "$recorded_model" ] \
    || fail "the config dir pins model '$settings_model' but the manifest records '$recorded_model'"
  pass "the provisioned config dir imposes the recorded model ($recorded_model)"

  local plugin_list admitted
  # The PINNED binary interrogates the pinned config dir, for the same reason provisioning
  # uses it: the plugin cache's shape belongs to the CLI version that wrote it, so reading
  # it back with a different one asks a question about a config dir nobody built.
  # DISABLE_AUTOUPDATER for the same reason provisioning sets it: this is the real CLI
  # against the live install, and an update it triggers can prune the version run2 pinned
  # out from under the criteria below that check run2 against what was recorded.
  plugin_list="$(CLAUDE_CONFIG_DIR="$config_dir" DISABLE_AUTOUPDATER=1 "$WORK/run2/bin/claude" plugin list --json)" \
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

  # Criterion 5a: the harness pin resolves to a real executable, and every field
  # describing it agrees with that one file. The pin is only worth anything if the symlink
  # the run execs, the path the manifest names, and the version it claims are three views
  # of the same binary - which is exactly what two independent lookups cannot promise.
  local pinned_link="$WORK/run1/bin/claude" recorded_claude_path recorded_claude_version
  [ -L "$pinned_link" ] || fail "the pin wrote no claude symlink at $pinned_link"
  [ -x "$pinned_link" ] || fail "the pinned claude symlink is not executable: $pinned_link"
  recorded_claude_path="$(horizon_manifest_field "$WORK/run1/manifest.json" claude binary_path)" \
    || fail "could not read claude.binary_path from run1/manifest.json"
  recorded_claude_version="$(horizon_manifest_field "$WORK/run1/manifest.json" claude version)" \
    || fail "could not read claude.version from run1/manifest.json"
  local link_target
  link_target="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$pinned_link")" \
    || fail "could not resolve the pinned claude symlink"
  [ "$link_target" = "$recorded_claude_path" ] \
    || fail "the pinned symlink resolves to $link_target but the manifest records $recorded_claude_path"
  # Asked of the binary the symlink points at, so a manifest version copied from anywhere
  # else - an install path, an earlier run - cannot pass. [LAW:one-source-of-truth]
  local link_version
  link_version="$(horizon_claude_version "$pinned_link")" \
    || fail "could not read a version out of the pinned claude symlink at $pinned_link"
  [ "$link_version" = "$recorded_claude_version" ] \
    || fail "the pinned binary reports $link_version but the manifest records $recorded_claude_version"
  pass "the pinned claude symlink, the recorded path and the recorded version all describe one binary ($recorded_claude_version)"

  # Criterion 5b: an unset pin is recorded as NO CONTROL, not as a control that passed.
  # This is the field a reader of a bundle uses to decide whether a campaign's runs are
  # comparable at all, so "absent" has to be unmistakable rather than inferred from the
  # version field looking plausible. [LAW:no-silent-failure]
  local recorded_pin
  recorded_pin="$(python3 -c '
import json, sys
print(json.dumps(json.load(open(sys.argv[1]))["claude"]["version_pin"]))
' "$WORK/run1/manifest.json")" || fail "could not read claude.version_pin from run1/manifest.json"
  if [ -n "${HORIZON_CLAUDE_VERSION_PIN:-}" ]; then
    [ "$recorded_pin" = "\"$HORIZON_CLAUDE_VERSION_PIN\"" ] \
      || fail "a campaign pin of $HORIZON_CLAUDE_VERSION_PIN was recorded as $recorded_pin"
  else
    [ "$recorded_pin" = null ] \
      || fail "no campaign pin was set, but the manifest records $recorded_pin rather than null - a reader would credit this run with a control it never had"
  fi
  pass "the manifest states which version control was applied: version_pin=$recorded_pin"

  # Criterion 5c: the gate refuses a mismatch. Exercised in the FAILING direction with a
  # version no install can be, because the passing direction is what every other check
  # here already runs through - a gate only ever seen agreeing is a gate that could be
  # returning success unconditionally.
  local pin_refusal=""
  if pin_refusal="$( HORIZON_CLAUDE_VERSION_PIN=0.0.0-not-a-real-version \
      "$SCRIPT_DIR/pin-instrument.sh" "$WORK/pin-mismatch" "$memento_sha" "$reviewer_sha" \
      "$goal_ref" "$lit_sha" 2>&1 )"; then
    fail "pin-instrument.sh built a run against a version the campaign does not pin"
  fi
  case "$pin_refusal" in
    *"0.0.0-not-a-real-version"*) ;;
    *) fail "the refusal did not name the pinned version it wanted: $pin_refusal" ;;
  esac
  case "$pin_refusal" in
    *"$recorded_claude_version"*) ;;
    *) fail "the refusal did not name the version actually installed: $pin_refusal" ;;
  esac
  pass "a campaign pin refuses a run on the wrong harness version, naming both versions"

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
  # The THIRD gate horizon_write_boot_state settles. Without a state of its own it read as
  # `forming`, so a run stopped here burned the whole boot timeout and then reported that
  # the pane drew nothing recognisable - about a dialog that was on screen throughout.
  got="$(printf '%s\n' " WARNING: Claude Code running in Bypass Permissions mode" " ❯ No, exit" "   Yes, I accept" " Enter to confirm · Esc to cancel" | horizon_boot_state)"
  [ "$got" = bypass-disclaimer ] || fail "the bypass-permissions disclaimer classified as '$got', not bypass-disclaimer"
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "▝▜██████▀  Opus 5 (1M context) · API Usage Billing" "❯ " "  ⏵⏵ bypass permissions on (shift+tab to cycle)                    Not logged in · Run /login" | horizon_boot_state)"
  [ "$got" = logged-out ] || fail "a not-logged-in pane classified as '$got', not logged-out"
  # The OTHER wording, and the one a baseline campaign actually meets: a config dir that
  # was logged in when the campaign started and whose refresh token the server retired
  # part way through. It needs no mistake by anyone, only elapsed time, so the run that
  # hits it is a later run of a long campaign - the most expensive possible moment to
  # discover the pane vocabulary only covered the other spelling.
  #
  # The WORDING is recorded, from the run that hit it on 2026-09-07. The PLACEMENT is
  # inferred: it is put in the same right-hand status-line slot the captured `Not logged
  # in` occupies, because both are that one widget reporting on one credential. Said
  # plainly because it is the weakest evidence in this block - and bounded, because if the
  # real pane puts it elsewhere this reads as `ready` and the run is refused moments later
  # by horizon_wait_goal_in_force, which reads the transcript instead of the pane.
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "❯ " "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents      Login expired · Please run /login" | horizon_boot_state)"
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
  # MID-TURN, captured from a live pane with a tool actually running. run-loop.sh hands
  # session one the `/goal` wording as its launch prompt, so the run's own wait polls a
  # pane that is already working - never the idle splash the other fixtures show.
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "  ✓ Bash  " "  ⏵⏵ bypass permissions on (shift+tab to cycle) · PR #70 · ← 1 agent" | horizon_boot_state)"
  [ "$got" = ready ] || fail "a pane mid-turn classified as '$got', not ready"

  # AND THE CONVERSE, which is the one that costs a campaign. Every pattern above is a
  # string the run can legitimately PRINT: an agent checking `gh auth status`, a grep over
  # this very file. Matched anywhere in the capture they turn the wait into a fatal false
  # failure - it dies on any settled state it did not want - so a healthy run is killed
  # mid-flight with a confident wrong diagnosis. Each of these must read as `ready`.
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "  ● Bash(gh auth status)" "    Not logged in" "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents" | horizon_boot_state)"
  [ "$got" = ready ] || fail "an agent printing 'Not logged in' as tool output classified the session as '$got'"
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "  ● Bash(grep Accessing horizon/lib.sh)" "    lib.sh: Accessing workspace:" "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_boot_state)"
  [ "$got" = ready ] || fail "an agent printing 'Accessing workspace:' as tool output classified the session as '$got'"
  got="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "  ● the picker says Choose the text style" "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_boot_state)"
  [ "$got" = ready ] || fail "an agent printing 'Choose the text style' as tool output classified the session as '$got'"
  # The one that matters most, and the reason the login notice is tested at all: the SAME
  # banner appears in both, so a classifier that only looked for it would call the dead
  # session ready. That was the behaviour here until 2026-09-21.
  pass "the pane classifier separates ready from logged-out, onboarding, untrusted and forming, and reads the chrome rather than what a run prints into the pane"

  # Criterion 5e: the version reader, against the same captured panes. It is the only
  # reading taken from the running process rather than from a file the driver resolved,
  # so a parse that quietly returned nothing would turn the cross-check into a no-op that
  # passes on every version. Fixtures, for the same reason the classifier has them: a live
  # boot exhibits exactly one version and would never exercise a mismatch.
  local ver
  ver="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.278" "▝▜██████▀  Opus 5 (1M context) · API Usage Billing" "❯ " "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_pane_version)"
  [ "$ver" = 2.1.278 ] || fail "the banner version read as '$ver', not 2.1.278"
  # A pane reset in place keeps the previous session's banner above the current one, which
  # is the ordinary shape here: the run resets its ONE session over and over. The last
  # banner is the running version; the first is history.
  ver="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.1.263" " (reset)" " ▐▛███▛█   Claude Code v2.1.278" "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_pane_version)"
  [ "$ver" = 2.1.278 ] || fail "a pane carrying two banners read as '$ver', not the later 2.1.278"
  # A version carrying a suffix reads out WHOLE. This is the half the two readers have to
  # agree on: horizon_claude_version records what the binary says, this reads what the
  # banner shows, and horizon_assert_booted_version compares them for equality - so a
  # banner pattern that stopped at the first non-digit would record `2.2.0-rc.1`, read
  # back `2.2.0`, and refuse every run on a pre-release with a message blaming the pin.
  # Both patterns are built from HORIZON_VERSION_RE now; this is what says so.
  ver="$(printf '%s\n' " ▐▛███▛█   Claude Code v2.2.0-rc.1" "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_pane_version)"
  [ "$ver" = 2.2.0-rc.1 ] \
    || fail "a suffixed banner version read as '$ver', not the whole 2.2.0-rc.1 - the banner and binary version grammars have drifted apart again"
  # Emptiness is the honest answer when the banner has scrolled off, and it must be
  # distinguishable from a version: horizon_assert_booted_version treats it as "proves
  # nothing" rather than as a mismatch, and that branch only exists if this returns empty.
  ver="$(printf '%s\n' "  ● Bash(echo hi)" "  ⏵⏵ bypass permissions on (shift+tab to cycle)" | horizon_pane_version)"
  [ -z "$ver" ] || fail "a pane with no banner reported version '$ver' instead of nothing"
  pass "the pane version reader takes the running session's banner, prefers the latest after a reset, reads a suffixed version whole, and reports absence as absence"

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
  # `-r`, NOT `-u`, and the difference is the whole effect. `-u` unsets the name in the
  # SESSION environment, after which tmux copies the server's GLOBAL environment into the
  # new pane and the variable arrives anyway - verified on the installed tmux: a global
  # value survived `-u` into a respawned pane and did not survive `-r`. Since the server
  # usually inherits its environment from the operator's own shell, `-u` would have been a
  # scrub that scrubbed nothing in exactly the case it exists for.
  #
  # Removed from the session's environment rather than asserted about. This narrows the
  # vectors; it cannot close them, and the criterion below does NOT rest on it having done
  # so - a proxy behind ANTHROPIC_BASE_URL or a cloud role could still authenticate, and
  # no list here would be provably complete. So the scrub is what makes the ordinary
  # outcome deterministic, and accepting `ready` as well as `logged-out` is what keeps an
  # exotic one from failing a good instrument. [LAW:no-ambient-temporal-coupling]
  local leaked
  for leaked in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN \
                ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX; do
    tmux set-environment -t "$VERIFY_TMUX_SESSION" -r "$leaked" \
      || fail "could not clear $leaked from the verification session's environment"
  done
  # Suppressed here too, for the same reason horizon_launch_session suppresses it: this is
  # a real Claude Code booting against a live install, and an auto-update it triggers
  # repoints the `claude` on PATH for the whole machine. It would land between run1's pin
  # and the criteria below that compare run2 against what was recorded, failing a sound
  # instrument for something the verifier itself caused. The run is guarded and its
  # verification was not, which is the guard having a hole exactly where it is tested.
  tmux set-environment -t "$VERIFY_TMUX_SESSION" DISABLE_AUTOUPDATER 1 \
    || fail "could not disable the auto-updater in the verification session"
  # THE PINNED SYMLINK, exactly as run-loop.sh launches it, not a bare `claude`. Launching
  # the bare name here would verify a binary the run does not execute and leave the pin
  # itself - the one new thing this criterion exists to exercise - never run at all.
  tmux respawn-pane -k -t "$VERIFY_TMUX_SESSION" -c "$verify_link" \
    "$WORK/run2/bin/claude" --dangerously-skip-permissions \
    || fail "could not launch the pinned claude in the verification session"
  # EITHER state past the gates, because the question this criterion asks is "did the
  # session get past the gates the instrument owns" and both answer it - both require the
  # banner and a painted status line, which onboarding and the trust dialog each preclude.
  # Demanding `logged-out` alone would conflate that question with "and it has no
  # credential", which is a fact about the operator's environment rather than about the
  # instrument, and would fail a good instrument on a machine that happens to carry one.
  # Kept, not discarded: criterion 5f reads its version out of THIS capture, the one the
  # wait reached its verdict on, rather than going back to tmux for a pane that has moved
  # on. A bare call would also spill the whole pane into this script's own output, which
  # is a column of PASS lines. [LAW:no-ambient-temporal-coupling]
  #
  # Checked, because a command substitution swallows the exit: horizon_die inside one ends
  # the SUBSHELL, and errexit would then abort this script on the assignment having
  # printed no FAIL line at all - the same invisible shape the unreadable-pane criterion
  # above exists to catch. The wait's own diagnosis still reaches stderr; this adds the
  # accounting. [LAW:no-silent-failure]
  local verify_pane
  verify_pane="$(horizon_await_boot_state "$VERIFY_TMUX_SESSION" logged-out ready)" \
    || fail "the verification session never reached 'logged-out' or 'ready' - its diagnosis is above"
  pass "a real session against the produced config dir clears onboarding and the trust dialog"

  # Criterion 5f: the booted session reports the version the manifest recorded. Every
  # other check on the pin reads files the driver resolved; this one asks the process.
  # It is what makes "the recorded version is the version that ran" a checked claim
  # rather than a chain of plausible lookups. [LAW:verifiable-goals]
  # Checked assignment, not nested into the argument list: a failing substitution there
  # has its status discarded, and the assert would run against an empty expectation.
  local booted_expected
  booted_expected="$(horizon_manifest_field "$WORK/run2/manifest.json" claude version)" \
    || fail "could not read claude.version from run2/manifest.json"
  horizon_assert_booted_version "$VERIFY_TMUX_SESSION" "$booted_expected" <<<"$verify_pane"
  pass "the booted session runs the version the manifest records ($booted_expected)"

  # The SAME live session, asked for the state the RUN asks for. Without this the wait is
  # only ever exercised on the path where it agrees, so a wait that returned success for
  # any settled state would pass everything above while leaving run-loop.sh to march a
  # dead session through a whole run - the exact defect this ticket exists for, reinstated
  # with the gate still green. Here the discriminator has to do its job in the failing
  # direction, on a real pane, and say which state it actually found.
  # Asked for a state this session provably is NOT - it has a banner, so it is past
  # onboarding by construction. Chosen over asking for `ready` so the check does not
  # depend on whether the session came up logged-out or authenticated: it exercises the
  # discriminator itself, on a real pane, under either outcome above.
  local refusal=""
  if refusal="$( horizon_await_boot_state "$VERIFY_TMUX_SESSION" onboarding 2>&1 )"; then
    fail "the wait accepted a booted session as 'onboarding' - it would accept any state at all, and the run would launch into a session that accepts nothing"
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
    *"wanted one of: onboarding"*) ;;
    *) fail "the refusal did not name the state it wanted: $refusal" ;;
  esac
  case "$refusal" in
    *"booted to 'logged-out'"*|*"booted to 'ready'"*) ;;
    *) fail "the refusal did not name the state it actually found: $refusal" ;;
  esac
  pass "the wait refuses a state it did not ask for, naming both what it found and what it wanted"

  # Criterion 6: the reviewer-credential gate, driven from fixtures rather than against the
  # live repository. Asking GitHub here would make this verdict depend on an operator's
  # secret store - a machine with the secret unset would be told the INSTRUMENT is broken -
  # and it would exercise only whichever direction that store happened to be in. Both
  # directions are the point, and the refusing one is the one the .3 run needed.
  #
  # `gh` is replaced on PATH inside subshells and never in this script's own environment:
  # every criterion above reaches the real GitHub, and a stub leaking past this block would
  # quietly answer for them too. [LAW:no-ambient-temporal-coupling]
  local gh_stub="$WORK/gh-stub"
  mkdir -p "$gh_stub" || fail "could not create $gh_stub"
  # Serves exactly the two calls the gate makes and refuses anything else BY NAME, so a
  # gate that grows a third question fails here rather than being waved through by a stub
  # that says yes to everything. The two listings are answered SEPARATELY, because the
  # whole point of there being two is that they hold different names. `!` makes a listing
  # itself fail, which is a different answer from "the secret is absent" and has to stay
  # different.
  #
  # It checks the WHOLE call shape - arity, `--paginate`, and the jq filter - and not just
  # the subcommand, because a stub that answers any shape lets the real call drift beneath a
  # green verdict. Change the filter to `.[].name` and every fixture below still passes,
  # while the live gate takes gh's nonzero exit for an unreadable listing and refuses every
  # run there is: a verifier certifying an instrument that cannot start. Dropping
  # `--paginate` is the same failure with a rarer trigger. The cost is that a
  # semantically-identical rewrite of the filter fails here too, and that is the trade
  # taken deliberately - this fixture's contract is "I am gh, and I answer these two calls".
  # [LAW:no-silent-failure]
  cat > "$gh_stub/gh" <<'GH_FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
answer() {
  if [ "$1" = "!" ]; then
    printf 'gh fixture: HTTP 403\n' >&2; exit 1
  fi
  printf '%s\n' $1
}
if [ "$#" -ne 5 ] || [ "$1" != "api" ] || [ "$2" != "--paginate" ] \
    || [ "$4" != "--jq" ] || [ "$5" != ".secrets[].name" ]; then
  printf 'gh fixture: unexpected call shape: %s\n' "$*" >&2; exit 1
fi
case "$3" in
  repos/*/actions/organization-secrets)
    answer "${HORIZON_FIXTURE_ORG_SECRETS:-}" ;;
  repos/*/actions/secrets)
    answer "${HORIZON_FIXTURE_REPO_SECRETS:-}" ;;
  *)
    printf 'gh fixture: unexpected endpoint: %s\n' "$3" >&2; exit 1 ;;
esac
GH_FIXTURE
  chmod +x "$gh_stub/gh" || fail "could not make the gh fixture executable"
  # Sourced into a fresh bash rather than called here, because horizon_die EXITS: called in
  # this shell it would end the verifier mid-criterion with no FAIL line, which is the
  # invisible shape this file checks for elsewhere. [LAW:no-silent-failure]
  # The repository comes in as an argument rather than spelled here, so this exercises the
  # name a run actually passes instead of a second copy of it. [LAW:one-source-of-truth]
  # Single-quoted deliberately: $1 and $2 are the inner shell's positional parameters, set
  # by the arguments after `bash -c`, and expanding them here would substitute this
  # script's own instead.
  # shellcheck disable=SC2016
  local gate='. "$1" && horizon_assert_reviewer_credential "$2"'

  # The refusing direction first: both listings answer, and neither carries this name.
  local no_secret=""
  if no_secret="$( PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="SOME_OTHER_SECRET" \
      HORIZON_FIXTURE_ORG_SECRETS="OPENAI_API_KEY" \
      bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" 2>&1 )"; then
    fail "the reviewer gate accepted a repository carrying no $REVIEWER_SECRET - every run would merge its pull requests unreviewed"
  fi
  case "$no_secret" in
    *"$REVIEWER_SECRET"*) ;;
    *) fail "the refusal did not name the secret it wanted: $no_secret" ;;
  esac
  case "$no_secret" in
    *"$HORIZON_RUN_REPO"*) ;;
    *) fail "the refusal did not name the repository it read: $no_secret" ;;
  esac

  # A name this one is a PREFIX of, which is the near miss that actually exists on this
  # fleet: the keychain items holding reviewer tokens are named
  # CLAUDE_CODE_OAUTH_TOKEN_<ACCOUNT>, so a repository secret copied from one carries the
  # account suffix. The action reads the bare name and would find nothing, so a membership
  # test that matched on substring would pass a run straight into the silent failure this
  # gate exists to stop.
  if PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="${REVIEWER_SECRET}_SOMEACCOUNT" \
      bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" >/dev/null 2>&1; then
    fail "the reviewer gate accepted ${REVIEWER_SECRET}_SOMEACCOUNT as $REVIEWER_SECRET - the action reads the bare name and would find nothing"
  fi

  # EITHER listing failing is an unknown, not an absent secret. The two want opposite fixes
  # - fix gh access versus set a secret - so a refusal that blamed the wrong one would send
  # an operator to the wrong place with a message that reads certain. Both listings are
  # exercised, because a guard on only one of them is a guard with a hole exactly where
  # nobody looked. [LAW:no-silent-failure]
  local unreadable=""
  if unreadable="$( PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="!" \
      HORIZON_FIXTURE_ORG_SECRETS="" \
      bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" 2>&1 )"; then
    fail "the reviewer gate treated a failed repository secret listing as a pass"
  fi
  case "$unreadable" in
    *"is unknown here"*) ;;
    *) fail "a failed repository secret listing was reported as an absent secret: $unreadable" ;;
  esac
  if unreadable="$( PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="" \
      HORIZON_FIXTURE_ORG_SECRETS="!" \
      bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" 2>&1 )"; then
    fail "the reviewer gate treated a failed organization secret listing as a pass"
  fi
  case "$unreadable" in
    *"is unknown here"*) ;;
    *) fail "a failed organization secret listing was reported as an absent secret: $unreadable" ;;
  esac

  # And the two accepting directions, so the gate is not simply refusing everything - and
  # so the ORG one has a check of its own. An organization secret shared with the repo
  # authenticates the action exactly as a repository secret does, and it appears in a
  # listing the repository call knows nothing about: a gate reading only the first would
  # refuse a healthy run and blame a credential that was set. Confirmed disjoint on the
  # live remote before this was written.
  PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="SOME_OTHER_SECRET $REVIEWER_SECRET" \
    HORIZON_FIXTURE_ORG_SECRETS="OPENAI_API_KEY" \
    bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" >/dev/null 2>&1 \
    || fail "the reviewer gate refused a repository that does carry $REVIEWER_SECRET"
  PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="SOME_OTHER_SECRET" \
    HORIZON_FIXTURE_ORG_SECRETS="$REVIEWER_SECRET" \
    bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" >/dev/null 2>&1 \
    || fail "the reviewer gate refused a repository whose $REVIEWER_SECRET is shared from the organization - the action would have authenticated and the run was blocked for a cause that was not true"
  # An unreadable listing is an UNKNOWN, and an unknown is only worth refusing over when no
  # listing produced the name. A gate that died on the first failing call would abort runs
  # whose credential was sitting in the listing that answered perfectly well, and blame a
  # credential that was set - the wrong-cause refusal again, this time triggered by a
  # transient 403 rather than by a missing secret. Both directions, because the gate stops
  # at the first listing that carries the name, so the failing call falls on the other side
  # each time. [LAW:no-silent-failure]
  PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="!" \
    HORIZON_FIXTURE_ORG_SECRETS="$REVIEWER_SECRET" \
    bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" >/dev/null 2>&1 \
    || fail "the reviewer gate refused a run over an unreadable repository listing while the organization listing carried $REVIEWER_SECRET - the action would have authenticated and the run was blocked for a cause that was not true"
  PATH="$gh_stub:$PATH" HORIZON_FIXTURE_REPO_SECRETS="$REVIEWER_SECRET" \
    HORIZON_FIXTURE_ORG_SECRETS="!" \
    bash -c "$gate" _ "$SCRIPT_DIR/lib.sh" "$HORIZON_RUN_REPO" >/dev/null 2>&1 \
    || fail "the reviewer gate refused a run over an unreadable organization listing while the repository itself carried $REVIEWER_SECRET - the action would have authenticated and the run was blocked for a cause that was not true"
  pass "the reviewer gate accepts $REVIEWER_SECRET from either the repository or the organization, refuses its absence and a suffixed near-miss, tells an unreadable listing from an absent secret, and lets neither listing's failure override a credential the other one proved"

  horizon_log "all checks passed"
}

main "$@"
