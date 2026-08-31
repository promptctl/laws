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
HORIZON_GOAL_PROMPT_REL_PATH="horizon/GOAL_PROMPT.md"

horizon_die() { printf 'ERROR [horizon]: %s\n' "$*" >&2; exit 1; }
horizon_log() { printf '[horizon] %s\n' "$*" >&2; }

horizon_need() {
  command -v "$1" >/dev/null 2>&1 || horizon_die "required command not found: $1"
}

# One owner for "what does sha256 of a file look like" - shasum on macOS,
# sha256sum elsewhere - so both hashing entry points below fail the same way
# when neither is present. Populates the HORIZON_SHA256_CMD array rather than
# returning a string to split, so a tool name or flag can never be mangled by
# word-splitting or globbing. [LAW:one-source-of-truth]
horizon_sha256_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    HORIZON_SHA256_CMD=(shasum -a 256)
  elif command -v sha256sum >/dev/null 2>&1; then
    HORIZON_SHA256_CMD=(sha256sum)
  else
    horizon_die "no sha256 tool found (need shasum or sha256sum)"
  fi
}

horizon_sha256_file() {
  local HORIZON_SHA256_CMD
  horizon_sha256_cmd
  "${HORIZON_SHA256_CMD[@]}" "$1" | awk '{print $1}'
}

horizon_sha256_stdin() {
  local HORIZON_SHA256_CMD
  horizon_sha256_cmd
  "${HORIZON_SHA256_CMD[@]}" | awk '{print $1}'
}

# GNU base64 decodes with `-d`; stock BSD base64 (macOS without coreutils)
# needs `-D`. Probe the actually-installed binary once, against empty input,
# rather than guessing from `uname` or consuming real data on a failed
# attempt.
horizon_base64_decode_stdin() {
  if base64 -d </dev/null >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

# Usage: horizon_repo_root <anchor_dir>  -> repo root containing anchor_dir
#
# Anchored to the caller-supplied directory (callers pass $SCRIPT_DIR), never
# to the invoking process's CWD - a script invoked by absolute path from
# inside some other repo must still pin the repo it lives in, not whatever
# repo the caller happened to be standing in.
horizon_repo_root() {
  local anchor="$1"
  [ -n "$anchor" ] || horizon_die "horizon_repo_root: no anchor directory given"
  git -C "$anchor" rev-parse --show-toplevel 2>/dev/null \
    || horizon_die "not inside a git repo: $anchor"
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
  # Captured into a checked assignment, not nested straight into the next call's
  # argument list - a nested `$(horizon_lit_path)` that fails would have its exit()
  # discarded (it only ends the inner subshell), silently handing
  # horizon_sha256_file an empty filename instead of surfacing horizon_die's message.
  local p
  p="$(horizon_lit_path)"
  horizon_sha256_file "$p"
}

# ── reviewer: resolve the moving `v1` tag to the exact commit it points at right now,
# and hash the prompt file at that commit, via the GitHub API - no local clone
# required, no assumption that one is present or current.
#
# A tag ref's `.object` is the commit directly for a LIGHTWEIGHT tag, but for
# an ANNOTATED tag (the common case for a release tag like v1) it is the tag
# object itself, whose sha is not a commit and 404s against the Contents API
# used below. Dereference it one extra hop when `.object.type` says "tag".
# Usage: horizon_reviewer_sha  -> prints the resolved commit sha for $REVIEWER_TAG
horizon_reviewer_sha() {
  local out sha type
  # Captured into a checked assignment, then read from a here-string: `read` from a
  # process substitution reports only its OWN status, so a gh failure that had already
  # emitted a full line would slip past the `||` and the else arm below would print a
  # non-commit sha as the pin. [LAW:no-silent-failure]
  out="$(
    gh api "repos/${REVIEWER_REPO}/git/refs/tags/${REVIEWER_TAG}" \
      --jq '[.object.sha, .object.type] | @tsv'
  )" || horizon_die "could not resolve ${REVIEWER_REPO}@${REVIEWER_TAG} via gh api"
  read -r sha type <<<"$out"
  # This is the parse boundary for the API response: a tsv missing either field must
  # abort, never fall through to the else arm as an untyped "not a tag".
  [ -n "$sha" ] && [ -n "$type" ] \
    || horizon_die "gh api returned no sha/type for ${REVIEWER_REPO}@${REVIEWER_TAG}: '$out'"
  if [ "$type" = "tag" ]; then
    gh api "repos/${REVIEWER_REPO}/git/tags/${sha}" --jq '.object.sha' \
      || horizon_die "could not dereference annotated tag ${REVIEWER_TAG} (object $sha) to a commit"
  else
    printf '%s\n' "$sha"
  fi
}

# Usage: horizon_reviewer_prompt_sha256 <reviewer_commit_sha>
horizon_reviewer_prompt_sha256() {
  local sha="$1" content
  content="$(
    gh api "repos/${REVIEWER_REPO}/contents/${REVIEWER_PROMPT_PATH}?ref=${sha}" --jq '.content'
  )" || horizon_die "could not fetch ${REVIEWER_PROMPT_PATH} at ${sha} via gh api"
  # The Contents API omits `content` (renders as JSON null, i.e. the literal
  # string "null" through --jq) for files over ~1MB or non-blob entries. That
  # string is valid base64 alphabet, so an unchecked decode would silently
  # hash garbage instead of failing. [LAW:no-silent-failure]
  [ -n "$content" ] && [ "$content" != "null" ] \
    || horizon_die "gh api returned no content for ${REVIEWER_PROMPT_PATH} at ${sha}"
  printf '%s' "$content" | tr -d '\n' | horizon_base64_decode_stdin | horizon_sha256_stdin
}

# ── the standard /goal wording: pinned by content hash at the same resolved repo
# commit memento is pinned at (GOAL_PROMPT.md lives in this same repo), never off
# the live working tree - an uncommitted local edit must not produce a manifest
# value with no corresponding commit to audit it against.
# Usage: horizon_goal_wording_sha256 <repo_root> <commit_sha>
horizon_goal_wording_sha256() {
  local repo_root="$1" commit_sha="$2" tmp
  tmp="$(mktemp)"
  # Written to a real file and checked before hashing - not piped straight through
  # and inspected with PIPESTATUS after the fact - so a missing file can never
  # print a "hash of nothing" before the error is caught, and the exact bytes
  # (not a shell-string copy, which would eat trailing newlines) reach the hash.
  if ! git -C "$repo_root" show "${commit_sha}:${HORIZON_GOAL_PROMPT_REL_PATH}" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    horizon_die "missing ${HORIZON_GOAL_PROMPT_REL_PATH} at ${commit_sha}"
  fi
  local hash
  hash="$(horizon_sha256_file "$tmp")" \
    || { rm -f "$tmp"; horizon_die "could not hash ${HORIZON_GOAL_PROMPT_REL_PATH} at ${commit_sha}"; }
  rm -f "$tmp"
  printf '%s\n' "$hash"
}
