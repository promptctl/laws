#!/usr/bin/env bash
# Verify the instrument against its two acceptance criteria:
#
#   1. Two invocations of pin-instrument.sh, same inputs, produce byte-identical
#      manifest.json files. The reviewer's `v1` tag is resolved live over the
#      network by pin-instrument.sh, so this script resolves it exactly ONCE and
#      passes the same sha into both invocations - otherwise a tag moving between
#      the two calls (or a flaky API response) would fail this check for reasons
#      that have nothing to do with the instrument itself.
#   2. A session launched against the produced CLAUDE_CONFIG_DIR has memento
#      installed and enabled, and has nothing else installed - no laws plugin, no
#      owner CLAUDE.md, no owner memory - because the pinned marketplace never
#      declared anything but memento in the first place.
#
# [LAW:verifiable-goals] this script IS the machine-checkable "done" for the ticket;
# exit 0 means both criteria held on this run, exit nonzero says which one didn't.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

# Canonicalized at creation: on macOS mktemp -d hands back /var/... while the real
# path is /private/var/..., and the isolation check below compares a path derived from
# this against one the claude CLI may report already resolved. [LAW:one-source-of-truth]
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

main() {
  horizon_need git
  horizon_need gh
  horizon_need claude
  horizon_need python3
  horizon_need lit

  local repo_root ref reviewer_sha
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  # Routed through the same lib.sh primitive pin-instrument.sh uses for a bare
  # "HEAD" - no raw git call out here. [LAW:single-enforcer]
  ref="$(horizon_resolve_memento_ref "$repo_root" "HEAD")"

  horizon_log "resolving reviewer once for both runs: ${REVIEWER_REPO}@${REVIEWER_TAG}"
  reviewer_sha="$(horizon_reviewer_sha)"

  horizon_log "run 1: pinning at $ref"
  "$SCRIPT_DIR/pin-instrument.sh" "$WORK/run1" "$ref" "$reviewer_sha"
  horizon_log "run 2: pinning at $ref"
  "$SCRIPT_DIR/pin-instrument.sh" "$WORK/run2" "$ref" "$reviewer_sha"

  if diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >/dev/null; then
    pass "two invocations produced byte-identical manifest.json"
  else
    diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >&2 || true
    fail "manifests diverged between two invocations with unchanged inputs"
  fi

  local config_dir="$WORK/run1/config"
  local plugin_list
  plugin_list="$(CLAUDE_CONFIG_DIR="$config_dir" claude plugin list --json)" \
    || fail "could not read claude plugin list --json from the isolated config dir"

  # sys.exit, never assert: -O / PYTHONOPTIMIZE compiles asserts out, which would turn
  # this acceptance check into a silent pass on any input. [LAW:no-silent-failure]
  echo "$plugin_list" | python3 -c '
import json, sys
expected_id = f"memento@{sys.argv[1]}"
plugins = json.load(sys.stdin)
ids = [p["id"] for p in plugins]
if ids != [expected_id]:
    sys.exit(f"expected only {expected_id} installed, got {ids}")
if plugins[0]["enabled"] is not True:
    sys.exit("memento is installed but not enabled")
' "$HORIZON_MARKETPLACE_NAME" || fail "claude plugin list did not show exactly memento@${HORIZON_MARKETPLACE_NAME} enabled"
  pass "isolated config dir has exactly memento installed and enabled"

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
  local install_path
  install_path="$(echo "$plugin_list" \
    | python3 -c 'import json, os, sys; print(os.path.realpath(json.load(sys.stdin)[0]["installPath"]))')" \
    || fail "could not read installPath from claude plugin list --json"
  case "$install_path" in
    "$config_dir"/*) ;;
    *) fail "installed plugin path ($install_path) is not under the isolated config dir ($config_dir)" ;;
  esac
  local memento_skills="$install_path/skills"
  [ -d "$memento_skills/next" ] || fail "installed memento is missing the 'next' skill"
  [ -d "$memento_skills/message-in-a-bottle" ] || fail "installed memento is missing 'message-in-a-bottle'"
  [ -d "$memento_skills/address-pr-reviews" ] || fail "installed memento is missing 'address-pr-reviews'"
  pass "installed memento (under the config dir) carries the standard memento commands"

  local recorded_lit_sha256 actual_lit_sha256
  recorded_lit_sha256="$(python3 -c 'import json; print(json.load(open("'"$WORK"'/run1/manifest.json"))["lit"]["sha256"])')" \
    || fail "could not read lit.sha256 from run1/manifest.json"
  actual_lit_sha256="$(horizon_lit_sha256)"
  [ "$recorded_lit_sha256" = "$actual_lit_sha256" ] \
    || fail "recorded lit sha256 ($recorded_lit_sha256) does not match the lit currently on PATH ($actual_lit_sha256)"
  pass "lit on PATH matches the manifest's recorded identity"

  horizon_log "all checks passed"
}

main "$@"
