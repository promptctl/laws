#!/usr/bin/env bash
# Primitives for the horizon eval's controlled-inclusion instrument.
#
# THE MODEL: a fresh CLAUDE_CONFIG_DIR per run, populated through the real `claude
# plugin` CLI — never by hand-writing its internal JSON — with exactly one
# marketplace exposing exactly one plugin (memento), pinned to a recorded git ref via
# a `git archive` snapshot rather than a live directory pointer. Nothing else is
# declared in that marketplace, so nothing else can ever become installable, let
# alone enabled: the isolation is what the marketplace does NOT list, not a runtime
# filter. [LAW:types-are-the-program] the marketplace.json we generate IS the
# admitted set; there is no separate check to keep in sync with it.
#
# [LAW:one-source-of-truth] every pinned identity (memento ref, lit binary, reviewer
# tag, goal wording) is read fresh from its one authority on every call — nothing is
# cached or copied ahead of time and reused stale.
# [LAW:effects-at-boundaries] every git/gh/claude/shasum invocation lives in this
# file; pin-instrument.sh only sequences these calls and writes the manifest.
# [LAW:no-silent-failure] every external call is checked; a missing tool, an
# unresolvable ref, or a failed install aborts loudly with `horizon_die`.

set -o pipefail

# ── Pinned identity of the reviewer (data, not a mode) ─────────────────────────────
: "${REVIEWER_REPO:=promptctl/copirate-code-review-agent}"
: "${REVIEWER_TAG:=v1}"
: "${REVIEWER_PROMPT_PATH:=review-agent/instructions.md}"
HORIZON_MARKETPLACE_NAME="promptctl-horizon"

horizon_die() { printf 'ERROR [horizon]: %s\n' "$*" >&2; exit 1; }
horizon_log() { printf '[horizon] %s\n' "$*" >&2; }

horizon_need() {
  command -v "$1" >/dev/null 2>&1 || horizon_die "required command not found: $1"
}

horizon_sha256_file() {
  # One owner for "what does sha256 of a file look like" - shasum on macOS, sha256sum
  # elsewhere. [LAW:one-source-of-truth]
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    horizon_die "no sha256 tool found (need shasum or sha256sum)"
  fi
}

horizon_sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

horizon_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || horizon_die "not inside a git repo"
}

# ── memento: pinned by git-archive snapshot, never by a live directory pointer ─────
# Usage: horizon_resolve_memento_ref <repo_root> <ref>  -> prints the resolved commit sha
horizon_resolve_memento_ref() {
  local repo_root="$1" ref="$2"
  git -C "$repo_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null \
    || horizon_die "memento ref does not resolve to a commit: $ref"
}

# Usage: horizon_memento_tree_sha <repo_root> <commit_sha>  -> tree sha of plugins/memento
horizon_memento_tree_sha() {
  local repo_root="$1" commit_sha="$2"
  git -C "$repo_root" rev-parse --verify "${commit_sha}:plugins/memento" 2>/dev/null \
    || horizon_die "plugins/memento does not exist at $commit_sha"
}

# Extract plugins/memento at the pinned commit into <snapshot_dir>/plugins/memento and
# write a single-plugin marketplace.json alongside it. This directory - not the live
# repo - is what gets registered as the marketplace, so a later commit to memento on
# this checkout can never leak into an already-pinned run.
# Usage: horizon_build_memento_snapshot <repo_root> <commit_sha> <snapshot_dir>
horizon_build_memento_snapshot() {
  local repo_root="$1" commit_sha="$2" snapshot_dir="$3"
  rm -rf "$snapshot_dir"
  mkdir -p "$snapshot_dir"
  git -C "$repo_root" archive "$commit_sha" -- plugins/memento \
    | tar -x -C "$snapshot_dir" \
    || horizon_die "git archive of plugins/memento at $commit_sha failed"
  [ -d "$snapshot_dir/plugins/memento" ] \
    || horizon_die "archive produced no plugins/memento tree"
  mkdir -p "$snapshot_dir/.claude-plugin"
  cat > "$snapshot_dir/.claude-plugin/marketplace.json" <<EOF
{
  "name": "$HORIZON_MARKETPLACE_NAME",
  "description": "Pinned, controlled-inclusion snapshot for the horizon eval instrument. Exposes exactly one plugin: memento, at $commit_sha.",
  "owner": {"name": "Brandon Fryslie"},
  "plugins": [
    {"name": "memento", "source": "./plugins/memento", "description": "Agent-native workflow tooling (pinned snapshot, $commit_sha)."}
  ]
}
EOF
}

# Register the snapshot marketplace and install memento into a fresh CLAUDE_CONFIG_DIR,
# through the real `claude plugin` CLI - the plugin cache's on-disk shape is that CLI's
# to own, not ours to hand-write. [LAW:single-enforcer]
# Usage: horizon_provision_config_dir <config_dir> <snapshot_dir>
horizon_provision_config_dir() {
  local config_dir="$1" snapshot_dir="$2"
  rm -rf "$config_dir"
  mkdir -p "$config_dir"
  CLAUDE_CONFIG_DIR="$config_dir" claude plugin marketplace add "$snapshot_dir" \
    >/dev/null || horizon_die "failed to add pinned marketplace at $snapshot_dir"
  CLAUDE_CONFIG_DIR="$config_dir" claude plugin install \
    "memento@${HORIZON_MARKETPLACE_NAME}" --scope user \
    >/dev/null || horizon_die "failed to install memento@${HORIZON_MARKETPLACE_NAME}"
}

# ── lit: no version string exists (`lit doctor` reports "dev build (build date
# unknown)"), so the recorded identity is the binary actually on PATH: its resolved
# path and its content hash. A run that silently picked up a different lit binary
# than the one recorded is exactly the drift this instrument exists to catch.
horizon_lit_path() {
  command -v lit || horizon_die "lit not found on PATH"
}

horizon_lit_sha256() {
  horizon_sha256_file "$(horizon_lit_path)"
}

# ── reviewer: resolve the moving `v1` tag to the exact commit it points at right now,
# and hash the prompt file at that commit, via the GitHub API - no local clone
# required, no assumption that one is present or current.
# Usage: horizon_reviewer_sha  -> prints the resolved commit sha for $REVIEWER_TAG
horizon_reviewer_sha() {
  gh api "repos/${REVIEWER_REPO}/git/refs/tags/${REVIEWER_TAG}" --jq '.object.sha' \
    || horizon_die "could not resolve ${REVIEWER_REPO}@${REVIEWER_TAG} via gh api"
}

# Usage: horizon_reviewer_prompt_sha256 <reviewer_commit_sha>
horizon_reviewer_prompt_sha256() {
  local sha="$1"
  gh api "repos/${REVIEWER_REPO}/contents/${REVIEWER_PROMPT_PATH}?ref=${sha}" \
      --jq '.content' \
    | tr -d '\n' | base64 -d | horizon_sha256_stdin \
    || horizon_die "could not fetch ${REVIEWER_PROMPT_PATH} at ${sha} via gh api"
}

# ── the standard /goal wording: pinned by content hash, same as everything else here.
# Usage: horizon_goal_wording_sha256 <repo_root>
horizon_goal_wording_sha256() {
  local repo_root="$1"
  local f="$repo_root/horizon/GOAL_PROMPT.md"
  [ -f "$f" ] || horizon_die "missing $f"
  horizon_sha256_file "$f"
}
