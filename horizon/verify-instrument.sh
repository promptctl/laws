#!/usr/bin/env bash
# Verify the instrument against its two acceptance criteria:
#
#   1. Two invocations of pin-instrument.sh, same inputs, produce byte-identical
#      manifest.json files.
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

main() {
  local repo_root ref
  repo_root="$(horizon_repo_root)"
  ref="$(git -C "$repo_root" rev-parse HEAD)"

  horizon_log "run 1: pinning at $ref"
  "$SCRIPT_DIR/pin-instrument.sh" "$WORK/run1" "$ref"
  horizon_log "run 2: pinning at $ref"
  "$SCRIPT_DIR/pin-instrument.sh" "$WORK/run2" "$ref"

  if diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >/dev/null; then
    pass "two invocations produced byte-identical manifest.json"
  else
    diff -u "$WORK/run1/manifest.json" "$WORK/run2/manifest.json" >&2 || true
    fail "manifests diverged between two invocations with unchanged inputs"
  fi

  local config_dir="$WORK/run1/config"
  local plugin_list
  plugin_list="$(CLAUDE_CONFIG_DIR="$config_dir" claude plugin list --json)"

  echo "$plugin_list" | python3 -c '
import json, sys
plugins = json.load(sys.stdin)
ids = [p["id"] for p in plugins]
assert ids == ["memento@promptctl-horizon"], f"expected only memento installed, got {ids}"
assert plugins[0]["enabled"] is True, "memento is installed but not enabled"
' || fail "claude plugin list did not show exactly memento@promptctl-horizon enabled"
  pass "isolated config dir has exactly memento installed and enabled"

  [ -f "$config_dir/CLAUDE.md" ] && fail "isolated config dir has a CLAUDE.md - owner guidance leaked in"
  pass "isolated config dir carries no CLAUDE.md"

  local memento_skills="$WORK/run1/pinned/plugins/memento/skills"
  [ -d "$memento_skills/next" ] || fail "pinned memento snapshot is missing the 'next' skill"
  [ -d "$memento_skills/message-in-a-bottle" ] || fail "pinned memento snapshot is missing 'message-in-a-bottle'"
  [ -d "$memento_skills/address-pr-reviews" ] || fail "pinned memento snapshot is missing 'address-pr-reviews'"
  pass "pinned memento snapshot carries the standard memento commands"

  local recorded_lit_sha256 actual_lit_sha256
  recorded_lit_sha256="$(python3 -c 'import json; print(json.load(open("'"$WORK"'/run1/manifest.json"))["lit"]["sha256"])')"
  actual_lit_sha256="$(horizon_lit_sha256)"
  [ "$recorded_lit_sha256" = "$actual_lit_sha256" ] \
    || fail "recorded lit sha256 ($recorded_lit_sha256) does not match the lit currently on PATH ($actual_lit_sha256)"
  pass "lit on PATH matches the manifest's recorded identity"

  horizon_log "all checks passed"
}

main "$@"
