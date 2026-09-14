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

# Canonicalized at creation: on macOS mktemp -d hands back /var/... while the real
# path is /private/var/..., and the isolation check below compares a path derived from
# this against one the claude CLI may report already resolved. [LAW:one-source-of-truth]
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

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

  horizon_log "all checks passed"
}

main "$@"
