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

# ── Seeding: the shape of a seed bundle, and the fixed identity its commits carry ──
# A seed is a directory of exactly two parts: the tree that becomes the project repo,
# and the backlog that becomes its lit store. Naming them here rather than at each use
# keeps "what a seed is" in one place. [LAW:one-source-of-truth]
HORIZON_SEED_REPO_SUBDIR="repo"
HORIZON_SEED_BACKLOG_FILE="backlog.json"
# git derives a commit sha from the author/committer identity and timestamps as well as
# the tree, so a seeded repo can only have a reproducible HEAD if all four are pinned.
# They describe the instrument, not a person: the seed commit is machine-made.
HORIZON_SEED_COMMIT_NAME="horizon seed"
HORIZON_SEED_COMMIT_EMAIL="horizon@promptctl.invalid"
HORIZON_SEED_COMMIT_DATE="2026-01-01T00:00:00+00:00"

horizon_die() { printf 'ERROR [horizon]: %s\n' "$*" >&2; exit 1; }
horizon_log() { printf '[horizon] %s\n' "$*" >&2; }

horizon_need() {
  command -v "$1" >/dev/null 2>&1 || horizon_die "required command not found: $1"
}

# One owner for "what does sha256 of a file look like" - shasum when it is on PATH,
# sha256sum otherwise, on any platform - so both hashing entry points below fail the
# same way when neither is. Populates the HORIZON_SHA256_CMD array rather than
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
  horizon_sha256_file "$p" || horizon_die "could not hash lit binary at $p"
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
# The parse boundary for a git-object reference: fetch one and return "<sha>\t<type>".
# The tag-ref lookup and every dereference hop below read this same shape, so the
# response is checked in exactly one place. Captured into an assignment and read from a
# here-string, never `read < <(gh ...)` - that form reports only `read`'s own status, so
# a gh failure that had already emitted a line would sail past the check. jq renders a
# missing field as the literal "null" at exit 0, which is why "null" is rejected
# explicitly and not merely non-emptiness. [LAW:one-source-of-truth] [LAW:no-silent-failure]
# Usage: horizon_gh_object <api_endpoint> <what_this_is_doing>  -> prints "<sha>\t<type>"
horizon_gh_object() {
  local endpoint="$1" doing="$2" out sha type
  out="$(gh api "$endpoint" --jq '[.object.sha, .object.type] | @tsv')" \
    || horizon_die "could not $doing via gh api"
  read -r sha type <<<"$out"
  [ -n "$sha" ] && [ -n "$type" ] && [ "$sha" != "null" ] && [ "$type" != "null" ] \
    || horizon_die "gh api returned no usable sha/type while trying to $doing: '$out'"
  printf '%s\t%s\n' "$sha" "$type"
}

horizon_reviewer_sha() {
  local out sha type
  out="$(horizon_gh_object "repos/${REVIEWER_REPO}/git/refs/tags/${REVIEWER_TAG}" \
    "resolve ${REVIEWER_REPO}@${REVIEWER_TAG}")" || exit 1
  read -r sha type <<<"$out"
  # Dereference until a commit is actually in hand: an annotated tag's object is the
  # tag object, and git permits a tag to point at another tag, so a single hop is not
  # enough. The loop cannot spin - object shas are content addresses, so no tag can
  # reference itself or anything that references it.
  while [ "$type" = "tag" ]; do
    out="$(horizon_gh_object "repos/${REVIEWER_REPO}/git/tags/${sha}" \
      "dereference tag object $sha")" || exit 1
    read -r sha type <<<"$out"
  done
  [ "$type" = "commit" ] \
    || horizon_die "${REVIEWER_REPO}@${REVIEWER_TAG} resolves to a $type, not a commit"
  printf '%s\n' "$sha"
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

# ══ SEEDING: appspec + fresh repo + lit init (promptctl-horizon-7ry.2) ═════════════
#
# THE MODEL: a seed bundle is the whole definition of a run's time zero - the tree that
# becomes the project repo, plus the backlog that becomes its lit store. Seeding is a
# pure function of that bundle: the same bundle yields the same starting state, every
# time, with nothing read from the network, the clock, or the operator's environment.
# [LAW:types-are-the-program] the bundle IS time zero; there is no second description
# of the starting state to keep in sync with it.

# Usage: horizon_seed_backlog_path <seed_dir>  -> validated path to the seed's backlog
#
# The one place a seed bundle's layout is checked, returning the path that could not
# have been returned had the bundle been malformed - so no caller re-checks, and a
# typo'd seed directory fails here rather than as a confusing `lit` error three steps
# later. [LAW:parse-dont-validate]
horizon_seed_backlog_path() {
  local seed_dir="$1"
  [ -n "$seed_dir" ] || horizon_die "horizon_seed_backlog_path: no seed directory given"
  [ -d "$seed_dir" ] || horizon_die "seed directory does not exist: $seed_dir"
  [ -d "$seed_dir/$HORIZON_SEED_REPO_SUBDIR" ] \
    || horizon_die "seed is missing its '$HORIZON_SEED_REPO_SUBDIR/' tree: $seed_dir"
  [ -f "$seed_dir/$HORIZON_SEED_BACKLOG_FILE" ] \
    || horizon_die "seed is missing $HORIZON_SEED_BACKLOG_FILE: $seed_dir"
  printf '%s\n' "$seed_dir/$HORIZON_SEED_BACKLOG_FILE"
}

# Usage: horizon_seed_digest <seed_dir>  -> sha256 over the bundle's entire content
#
# Hashes the sorted "<sha256>  <relative-path>" listing rather than a tarball, so the
# digest is immune to archive metadata (mtimes, uid/gid, ordering) and changes only when
# a seed file's path or bytes change. This is what lets a manifest state which seed a
# run actually started from, instead of merely naming a directory. LC_ALL=C fixes the
# sort under any locale.
horizon_seed_digest() {
  local seed_dir="$1" listing
  listing="$(
    cd "$seed_dir" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r rel; do
      printf '%s  %s\n' "$(horizon_sha256_file "$rel")" "$rel" || exit 1
    done
  )" || horizon_die "could not hash seed bundle: $seed_dir"
  [ -n "$listing" ] || horizon_die "seed bundle contains no files: $seed_dir"
  printf '%s' "$listing" | horizon_sha256_stdin
}

# Usage: horizon_project_git <project_dir> <git args...>
#
# Every git invocation against a seeded project routes through here, so the determinism
# settings cannot be applied to some commits and forgotten on others.
# [LAW:single-enforcer] The `-c` overrides neutralise the operator's global config:
# commit.gpgsign would make the commit sha depend on a signing key, and
# init.templateDir would copy arbitrary local hooks into every seeded repo.
horizon_project_git() {
  local project_dir="$1"; shift
  git -C "$project_dir" \
    -c "user.name=$HORIZON_SEED_COMMIT_NAME" \
    -c "user.email=$HORIZON_SEED_COMMIT_EMAIL" \
    -c commit.gpgsign=false \
    -c init.templateDir= \
    "$@"
}

# Usage: horizon_project_init <project_dir>
#
# A fresh repo with NO remote, deliberately: `lit init` inspects the git remotes and
# adopts a backlog it finds there (that is how this instrument recovered the reference
# run's own backlog). A seeded project that carried a remote would silently start from
# that remote's backlog instead of the seed's. [LAW:no-silent-failure]
# HEAD is pointed at master explicitly rather than relying on `init.defaultBranch`,
# whose value differs between machines and git versions.
horizon_project_init() {
  local project_dir="$1"
  mkdir -p "$project_dir" || horizon_die "could not create project dir: $project_dir"
  horizon_project_git "$project_dir" init -q \
    || horizon_die "git init failed in $project_dir"
  horizon_project_git "$project_dir" symbolic-ref HEAD refs/heads/master \
    || horizon_die "could not set the initial branch to master in $project_dir"
  local remotes
  remotes="$(horizon_project_git "$project_dir" remote)" \
    || horizon_die "could not list remotes in $project_dir"
  [ -z "$remotes" ] \
    || horizon_die "freshly initialised project already has a remote: $remotes"
}

# Usage: horizon_project_populate <project_dir> <seed_dir>
#
# Copies the seed's repo tree in as-is. `cp` of the directory's *contents* - the
# trailing /. - rather than the directory itself, so the seed's own directory name never
# becomes a stray level inside the project.
horizon_project_populate() {
  local project_dir="$1" seed_dir="$2"
  cp -R "$seed_dir/$HORIZON_SEED_REPO_SUBDIR/." "$project_dir/" \
    || horizon_die "could not copy the seed tree into $project_dir"
}

# Usage: horizon_project_commit <project_dir> <message>
#
# --no-verify because a seeded repo installs lit's pre-push hook, and an operator's
# global core.hooksPath could attach arbitrary commit hooks; neither may alter what a
# seed commit contains. The dates are passed as environment rather than config because
# git reads author/committer timestamps only from there.
horizon_project_commit() {
  local project_dir="$1" message="$2"
  horizon_project_git "$project_dir" add -A \
    || horizon_die "git add failed in $project_dir"
  GIT_AUTHOR_DATE="$HORIZON_SEED_COMMIT_DATE" \
  GIT_COMMITTER_DATE="$HORIZON_SEED_COMMIT_DATE" \
  horizon_project_git "$project_dir" commit -q --no-verify -m "$message" \
    || horizon_die "git commit failed in $project_dir: $message"
}

# Usage: horizon_project_head <project_dir>  -> HEAD commit sha
horizon_project_head() {
  horizon_project_git "$1" rev-parse HEAD \
    || horizon_die "could not read HEAD in $1"
}

# Usage: horizon_project_tree <project_dir>  -> tree sha of HEAD
#
# The committed tree's identity, independent of commit metadata - the field that answers
# "did two seedings produce the same files" on its own terms.
horizon_project_tree() {
  horizon_project_git "$1" rev-parse 'HEAD^{tree}' \
    || horizon_die "could not read HEAD's tree in $1"
}

# ── lit, always against the project's own store ────────────────────────────────────
# lit locates its workspace from the current directory's git dir and has no --repo flag,
# so every call is made from inside the project. The subshell keeps that `cd` from
# leaking into the caller, which would silently retarget later commands at the wrong
# store. [LAW:no-ambient-temporal-coupling]
horizon_lit_init() {
  local project_dir="$1"
  ( cd "$project_dir" && lit init ) >/dev/null \
    || horizon_die "lit init failed in $project_dir"
}

horizon_lit_export() {
  local project_dir="$1"
  ( cd "$project_dir" && lit export ) \
    || horizon_die "lit export failed in $project_dir"
}

# Usage: horizon_lit_import <project_dir> <docs_file>
horizon_lit_import() {
  local project_dir="$1" docs="$2"
  ( cd "$project_dir" && lit import --path "$docs" ) >/dev/null \
    || horizon_die "lit import failed in $project_dir (from $docs)"
}
