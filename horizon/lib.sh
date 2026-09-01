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

# Where this library lives, so it can reach the helpers that ship beside it without
# depending on the caller's CWD or on which script sourced it.
HORIZON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# The coreutils reached from this file on its callers' behalf, declared here because a
# caller cannot know what lib.sh invokes for it. Each script previously carried its own
# partial copy of this list - which is how they drifted apart, several of them omitting a
# tool they reach on every run. [LAW:one-source-of-truth] one list, one owner; a script
# declares only the tools it invokes itself.
#
# This is what lib.sh MAY invoke, not what any one caller will: each script enters at a
# different point, so a caller reaching only part of the surface over-declares a coreutil
# or two. That is the accepted trade - an exact list per caller needs a tool set per
# function, and the five drifting per-script copies this replaced are the worse failure.
# cat/tar/base64 stay with pin-instrument.sh only because they are reached from nothing
# else at all.
HORIZON_BASE_TOOLS=(awk cp find mkdir mktemp rm sort tr)

horizon_need_base() {
  local tool
  for tool in "${HORIZON_BASE_TOOLS[@]}"; do horizon_need "$tool"; done
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

# Usage: horizon_goal_wording_file <repo_root> <commit_sha> <out_file>
#
# Writes the pinned /goal wording, taken from the same commit horizon_goal_wording_sha256
# hashes, to <out_file>. The driver issues THIS file rather than the one in the working
# tree: manifest.json records the wording's sha256 at the pinned commit, so a run that
# issued an uncommitted local edit would report a controlled variable it did not use -
# and it would look identical in the manifest. Same commit for the hash and the issue,
# by construction. [LAW:one-source-of-truth]
horizon_goal_wording_file() {
  local repo_root="$1" commit_sha="$2" out="$3"
  git -C "$repo_root" show "${commit_sha}:${HORIZON_GOAL_PROMPT_REL_PATH}" > "$out" 2>/dev/null \
    || horizon_die "missing ${HORIZON_GOAL_PROMPT_REL_PATH} at ${commit_sha}"
  [ -s "$out" ] || horizon_die "${HORIZON_GOAL_PROMPT_REL_PATH} is empty at ${commit_sha}"
}

# Usage: horizon_manifest_memento_ref <manifest_file>  -> the commit the run pinned
#
# Read back from the manifest rather than re-resolved, so the wording issued into the run
# and the wording the manifest describes cannot come from two different commits.
horizon_manifest_memento_ref() {
  local manifest="$1"
  [ -f "$manifest" ] || horizon_die "no manifest at $manifest"
  python3 -c '
import json, sys
ref = json.load(open(sys.argv[1])).get("memento", {}).get("ref")
if not ref:
    sys.exit("manifest records no memento.ref")
print(ref)
' "$manifest" || horizon_die "could not read memento.ref from $manifest"
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
  # A seed bundle is regular files and directories only. Refused here rather than
  # handled, so horizon_seed_digest's "entire content" is true by construction instead
  # of by remembering to hash link targets too: a symlink has no content to hash, and
  # copying one into the project would make time zero depend on a path outside the seed.
  # [LAW:parse-dont-validate]
  local irregular
  irregular="$(find "$seed_dir" ! -type f ! -type d -print)" \
    || horizon_die "could not scan seed bundle: $seed_dir"
  [ -z "$irregular" ] \
    || horizon_die "seed bundle contains non-regular files (symlinks and devices are not supported in a seed): $irregular"
  # A newline in a filename is legal on POSIX and would split one path into two lines of
  # horizon_seed_digest's newline-delimited listing, pairing the wrong hash with the
  # wrong path and yielding a confidently wrong digest. Refused at the same boundary and
  # for the same reason as symlinks, so the digest loop can stay line-oriented.
  local newline_names
  newline_names="$(find "$seed_dir" -name '*
*' -print)" || horizon_die "could not scan seed bundle: $seed_dir"
  [ -z "$newline_names" ] \
    || horizon_die "seed bundle contains a filename with an embedded newline: $newline_names"
  # horizon_project_populate copies repo/'s contents INTO an already-initialised project,
  # and cp merges rather than replaces - so a repo/ tree carrying its own .git would
  # overwrite the fresh HEAD, config and refs in place, with nothing raised and every
  # later guarantee (fresh history, no remote, the recorded HEAD) then reading a git dir
  # the seed supplied. Plausible whenever a seed is assembled by copying a real checkout.
  # -iname because a case-insensitive filesystem would let .GIT reach the same place.
  local git_dirs
  git_dirs="$(find "$seed_dir/$HORIZON_SEED_REPO_SUBDIR" -iname '.git' -print)" \
    || horizon_die "could not scan seed bundle: $seed_dir"
  [ -z "$git_dirs" ] \
    || horizon_die "seed's $HORIZON_SEED_REPO_SUBDIR/ tree contains a .git entry, which would overwrite the seeded project's own git dir: $git_dirs"
  printf '%s\n' "$seed_dir/$HORIZON_SEED_BACKLOG_FILE"
}

# Usage: horizon_seed_digest <seed_dir>  -> sha256 over the bundle's entire content
#
# Hashes the sorted "<sha256>  <relative-path>" listing rather than a tarball, so the
# digest is immune to archive metadata (mtimes, uid/gid, ordering) and changes only when
# a seed file's path or bytes change. This is what lets a manifest state which seed a
# run actually started from, instead of merely naming a directory. LC_ALL=C fixes the
# sort under any locale.
#
# Scoped to the two parts the seed model defines, never the whole directory: a bundle may
# also carry documentation (PROVENANCE.md), which no step of seeding reads. Hashing it
# would make a typo fix in that prose report two runs from an identical time zero as
# having started from different seeds - the one thing this digest exists to answer.
#
# Validates the bundle itself rather than trusting a caller to have done it first: the
# "regular files only" guarantee this loop relies on is horizon_seed_backlog_path's to
# make, and an ordering requirement that lives only in caller discipline is one an
# alternate caller can skip. [LAW:single-enforcer] [LAW:no-ambient-temporal-coupling]
horizon_seed_digest() {
  local seed_dir="$1" listing rel hash
  horizon_seed_backlog_path "$seed_dir" >/dev/null
  listing="$(
    cd "$seed_dir" || exit 1
    find "$HORIZON_SEED_REPO_SUBDIR" "$HORIZON_SEED_BACKLOG_FILE" -type f -print \
      | LC_ALL=C sort | while IFS= read -r rel; do
      # Captured into its own checked assignment: a command substitution's exit status
      # is discarded when it sits in an argument list, so `printf ... || exit 1` would
      # only ever report printf's own success and emit a line with an empty hash - a
      # confidently wrong seed digest. [LAW:no-silent-failure]
      hash="$(horizon_sha256_file "$rel")" || exit 1
      [ -n "$hash" ] || exit 1
      printf '%s  %s\n' "$hash" "$rel" || exit 1
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
# commit.gpgsign would make the commit sha depend on a signing key, init.templateDir
# would copy arbitrary local hooks into every seeded repo, and core.hooksPath would let
# an existing hook of any kind run against seed commits - including post-commit, which
# --no-verify does not suppress and which could amend or append to HEAD after the fact.
horizon_project_git() {
  local project_dir="$1"; shift
  git -C "$project_dir" \
    -c "user.name=$HORIZON_SEED_COMMIT_NAME" \
    -c "user.email=$HORIZON_SEED_COMMIT_EMAIL" \
    -c commit.gpgsign=false \
    -c init.templateDir= \
    -c core.hooksPath= \
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
#
# Validates the bundle first for the same reason horizon_seed_digest does: "no symlinks"
# is what keeps this cp from pulling a path outside the seed into the project, and that
# guarantee belongs to horizon_seed_backlog_path, not to whichever caller remembered to
# run it. [LAW:no-ambient-temporal-coupling]
horizon_project_populate() {
  local project_dir="$1" seed_dir="$2"
  horizon_seed_backlog_path "$seed_dir" >/dev/null
  cp -R "$seed_dir/$HORIZON_SEED_REPO_SUBDIR/." "$project_dir/" \
    || horizon_die "could not copy the seed tree into $project_dir"
}

# Usage: horizon_project_commit <project_dir> <message>
#
# --no-verify because a seeded repo installs lit's pre-push hook; core.hooksPath is
# emptied in horizon_project_git for the hooks --no-verify does not reach. Neither may
# alter what a seed commit contains.
#
# All four identity fields and both dates are passed as environment, because git ranks
# GIT_AUTHOR_NAME and its siblings ABOVE user.name from any config source, `-c`
# included. Pinning identity only through `-c` left an operator who exports those - CI
# wrappers and personal dotfiles both do - authoring the seed commit under their own
# name, which changes the commit sha and so makes time zero machine-dependent. Two
# seedings on one machine still agree, so verify-seed.sh could not have caught it.
horizon_project_commit() {
  local project_dir="$1" message="$2"
  horizon_project_git "$project_dir" add -A \
    || horizon_die "git add failed in $project_dir"
  GIT_AUTHOR_NAME="$HORIZON_SEED_COMMIT_NAME" \
  GIT_AUTHOR_EMAIL="$HORIZON_SEED_COMMIT_EMAIL" \
  GIT_COMMITTER_NAME="$HORIZON_SEED_COMMIT_NAME" \
  GIT_COMMITTER_EMAIL="$HORIZON_SEED_COMMIT_EMAIL" \
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

# ══ THE UNATTENDED LOOP: /goal to completion across resets (promptctl-horizon-7ry.3) ═
#
# THE MODEL: the driver builds time zero, launches the FIRST session, and from then on
# only OBSERVES. Every later session is produced by memento's own relaunch, which this
# eval measures rather than provides - a driver that re-issued the goal itself, or
# restarted a stalled session, would be measuring the driver instead of the workflow.
# So the primitives below divide cleanly into two kinds, and the division is the point:
# a few that WRITE (provision boot state, launch session one) and the rest that only
# READ (is it authenticated, is it ready, which transport, what happened).
# [LAW:effects-at-boundaries]

# The tmux session the run lives in. A run is launched INSIDE tmux deliberately - see
# horizon_assert_transport for why that single fact decides whether the run is isolated.
HORIZON_TMUX_SESSION="horizon-run"
# Every readiness probe in finalize-session greps the pane for this, so the driver holds
# itself to the same test rather than inventing a second notion of "up".
# [LAW:one-source-of-truth] Verified still matching at Claude Code v2.1.226.
HORIZON_BANNER_RE='Claude Code v[0-9]'
HORIZON_BOOT_TIMEOUT_SECONDS=120
HORIZON_POLL_SECONDS=2

# Usage: horizon_assert_authenticated <config_dir>
#
# Asserted BEFORE any session is launched, because an unauthenticated config dir does
# not fail loudly at launch - it boots to a login prompt and waits forever, which in an
# unattended run is indistinguishable from an agent thinking hard. [LAW:no-silent-failure]
#
# Claude Code keys its stored credential to the config dir's PATH (the OS keychain entry
# is named from a hash of it), so authentication is a property of WHERE the config dir
# is, not of what is inside it: wiping the directory keeps the login, moving it loses
# the login. That is why a run is built at a fixed working path - see run-loop.sh.
horizon_assert_authenticated() {
  # Not named `status`: that is a read-only special variable in zsh, so the name would
  # make this library unsourceable outside bash for no benefit at all.
  local config_dir="$1" auth_json=""
  [ -n "$config_dir" ] || horizon_die "horizon_assert_authenticated: no config dir given"

  # `claude auth status` EXITS 1 WHEN SIMPLY LOGGED OUT, while still printing a complete
  # JSON answer. So its exit status does not mean "the command failed" and must not be
  # branched on: doing so reports a missing login as an unreadable command, sending the
  # operator to look for a broken CLI instead of running login.sh. The payload is the
  # answer; whether it arrived at all is checked below, where an empty or unparseable
  # response is a genuinely different failure with its own message. Not suppressed with
  # 2>/dev/null either - stderr still reaches the operator.
  auth_json="$(CLAUDE_CONFIG_DIR="$config_dir" claude auth status)" || true

  [ -n "$auth_json" ] \
    || horizon_die "'claude auth status' produced no output for $config_dir"

  # Parsed rather than grepped: `loggedIn` is a JSON boolean, and a grep for the word
  # would match the field name just as happily in a false response. Each cause exits
  # with its own code so the caller can tell them apart, rather than one nonzero
  # standing for two different things.
  printf '%s' "$auth_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(3)
sys.exit(0 if d.get("loggedIn") is True else 4)
'
  case "$?" in
    0) return 0 ;;
    3) horizon_die "'claude auth status' did not return JSON for $config_dir:
$auth_json" ;;
    4) horizon_die "the run's config dir is not logged in: $config_dir
Run horizon/login.sh once (it needs a browser); every run after that is unattended.
Note the credential is bound to this PATH, so logging in somewhere else will not help." ;;
    *) horizon_die "could not determine whether $config_dir is authenticated" ;;
  esac
}

# Usage: horizon_write_boot_state <config_dir> <project_dir>
#
# A freshly provisioned config dir stops at four interactive gates that no unattended
# run can answer: the workspace trust dialog, first-run onboarding, the custom-API-key
# prompt, and the bypass-permissions acceptance. Each is recorded as a settled fact
# here, so the session boots straight to a ready input box.
#
# These are the CLI's own keys, not a private format: its error text for an untrusted
# workspace names `projects[<dir>].hasTrustDialogAccepted: true` in this exact file as
# the supported alternative to clicking the dialog.
#
# Written AFTER horizon_provision_config_dir, which rm -rf's the directory - order that
# matters, so it is stated where it can be seen rather than left to the caller to
# remember. Merges into whatever the CLI already wrote instead of replacing the file:
# provisioning leaves real state there, and clobbering it would be a second writer of a
# file the CLI owns. [LAW:one-source-of-truth]
horizon_write_boot_state() {
  local config_dir="$1" project_dir="$2"
  [ -d "$config_dir" ] || horizon_die "horizon_write_boot_state: no config dir at $config_dir"
  [ -d "$project_dir" ] || horizon_die "horizon_write_boot_state: no project dir at $project_dir"
  python3 - "$config_dir/.claude.json" "$project_dir" <<'PY' \
    || horizon_die "could not write unattended boot state into $config_dir/.claude.json"
import json, os, sys

path, project = sys.argv[1:]
config = {}
if os.path.exists(path):
    with open(path) as f:
        config = json.load(f)

config["hasCompletedOnboarding"] = True
config["theme"] = "dark"
config["bypassPermissionsModeAccepted"] = True
projects = config.setdefault("projects", {})
entry = projects.setdefault(project, {})
entry["hasTrustDialogAccepted"] = True
entry["hasCompletedProjectOnboarding"] = True

with open(path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
}

# Usage: horizon_launch_session <config_dir> <project_dir>
#
# The ONE write that starts a run. claude is launched inside a detached tmux session
# because that single choice decides whether the run stays isolated - see
# horizon_assert_transport, which is how that claim gets checked instead of assumed.
#
# CLAUDE_CONFIG_DIR is passed with tmux's own `-e` rather than exported into the
# environment: a tmux session created on an ALREADY-RUNNING server inherits the
# server's environment, not the caller's, so an exported value would silently not
# arrive and the run would read the operator's real config. [LAW:no-silent-failure]
horizon_launch_session() {
  local config_dir="$1" project_dir="$2"
  tmux kill-session -t "$HORIZON_TMUX_SESSION" 2>/dev/null || true
  tmux new-session -d -s "$HORIZON_TMUX_SESSION" -x 200 -y 50 -c "$project_dir" \
    -e CLAUDE_CONFIG_DIR="$config_dir" \
    "claude --dangerously-skip-permissions" \
    || horizon_die "could not launch the run session in tmux"
}

# Usage: horizon_pane  -> the run session's pane contents
horizon_pane() {
  tmux capture-pane -t "$HORIZON_TMUX_SESSION" -p \
    || horizon_die "could not read the run session's pane (is it still alive?)"
}

# Usage: horizon_wait_ready
#
# Waits for the banner rather than for a fixed sleep: readiness is a state the pane
# reports, not a duration to bet on. [LAW:no-ambient-temporal-coupling]
horizon_wait_ready() {
  local waited=0
  while [ "$waited" -lt "$HORIZON_BOOT_TIMEOUT_SECONDS" ]; do
    if horizon_pane 2>/dev/null | grep -qE "$HORIZON_BANNER_RE"; then
      return 0
    fi
    sleep "$HORIZON_POLL_SECONDS"
    waited=$((waited + HORIZON_POLL_SECONDS))
  done
  horizon_die "session did not reach a ready input box within ${HORIZON_BOOT_TIMEOUT_SECONDS}s"
}

# Usage: horizon_send <text_file>
#
# Types a file's contents into the session's input box and submits it. Delivered through
# a tmux buffer rather than `send-keys <text>`, so no shell or tmux metacharacter in the
# text can be interpreted on the way in - the pinned goal wording is prose, and prose
# contains quotes.
horizon_send() {
  local text_file="$1"
  [ -f "$text_file" ] || horizon_die "horizon_send: no such file: $text_file"
  tmux load-buffer -b horizon-send "$text_file" \
    || horizon_die "could not load the text to send into a tmux buffer"
  tmux paste-buffer -d -b horizon-send -t "$HORIZON_TMUX_SESSION" -p \
    || horizon_die "could not paste into the run session"
  sleep 0.5
  tmux send-keys -t "$HORIZON_TMUX_SESSION" Enter \
    || horizon_die "could not submit into the run session"
}

# Usage: horizon_assert_transport
#
# THE ISOLATION CHECK. finalize-session chooses how to hand off by walking its own
# process ancestry for a live tmux pane. When it finds one it resets THIS process in
# place, and the run keeps the CLAUDE_CONFIG_DIR, PATH and flags it was launched with
# because nothing is relaunched. When it does not, it spawns a fresh tmux session
# instead - and a session created on an already-running server inherits the SERVER's
# environment, so the successor reads the operator's real config while every log line
# still reports success. That is the whole isolation guarantee of the instrument turning
# off, with nothing raised. [LAW:no-silent-failure]
#
# The precondition for the good path is exactly "claude runs under a live pane of our
# session", so that is what gets asserted - before the run is trusted, not after it has
# produced a contaminated bundle. Checked from the outside, by ancestry, rather than by
# asking the agent to run a dry-run: an assertion that costs a turn is one a long
# campaign will be tempted to skip. [LAW:parse-dont-validate]
horizon_assert_transport() {
  local pane_pid
  pane_pid="$(tmux display-message -p -t "$HORIZON_TMUX_SESSION" '#{pane_pid}')" \
    || horizon_die "could not read the run session's pane pid"
  [ -n "$pane_pid" ] || horizon_die "run session reported an empty pane pid"
  # ps output is parsed once, in one place, rather than re-shelled per ancestry hop.
  ps -eo pid=,ppid=,comm= | python3 -c '
import sys

pane_pid = int(sys.argv[1])
parent, name = {}, {}
for line in sys.stdin:
    parts = line.split(None, 2)
    if len(parts) < 3:
        continue
    pid, ppid, comm = parts
    try:
        parent[int(pid)] = int(ppid)
    except ValueError:
        continue
    name[int(pid)] = comm.strip()

# A claude whose ancestry reaches the pane is one finalize-session will find by the
# same walk. Bounded so a cycle in a mangled ps snapshot cannot spin.
def under_pane(pid):
    for _ in range(32):
        pid = parent.get(pid)
        if pid is None or pid == 0:
            return False
        if pid == pane_pid:
            return True
    return False

claudes = [p for p, n in name.items() if n.rsplit("/", 1)[-1] == "claude"]
if not any(under_pane(p) for p in claudes):
    sys.exit("no claude process runs under the run pane (pid %d); finalize-session "
             "would relaunch instead of resetting in place, losing CLAUDE_CONFIG_DIR"
             % pane_pid)
' "$pane_pid" || horizon_die "run session will not hand off through the in-place transport"
}

# Usage: horizon_report <config_dir> <project_dir> <goal_file>  -> the run's JSON report
#
# The project's commits are gathered here and handed to sessions.py, which reads the
# transcripts and does the analysis. The split is deliberate: this side is the effect
# (ask git what exists right now), that side is a pure function of what it is given, so
# the same verdict can be recomputed from an archived run with nothing running.
# [LAW:effects-at-boundaries]
#
# %cI is strict ISO-8601 and %H the full sha - a fixed, machine-oriented format rather
# than whatever the operator's log.date or format.pretty config would otherwise impose.
horizon_report() {
  local config_dir="$1" project_dir="$2" goal_file="$3" commits
  commits="$(horizon_project_git "$project_dir" log --reverse --format='%H%x09%cI')" \
    || horizon_die "could not read the project's commit log in $project_dir"
  printf '%s\n' "$commits" \
    | python3 "$HORIZON_LIB_DIR/sessions.py" "$config_dir" "$project_dir" "$goal_file" \
    || horizon_die "could not analyse the run's sessions"
}

# Usage: horizon_observe <config_dir> <project_dir> <goal_file> <target_sessions> <max_minutes>
#
# Watches until the run has produced <target_sessions> consecutive sessions of committed
# work, or the wall-clock ceiling stops it. Prints the final report to stdout.
#
# The two limits are arguments rather than globals the caller happens to have set: a
# function that silently reads its caller's variables only works for that one caller,
# and reads whatever a later one leaves lying around. [LAW:composability]
#
# It only ever READS. A driver that nudged a quiet session, or re-issued a goal that
# failed to carry, would be repairing the very mechanism this eval is measuring - the
# run would then look healthiest exactly where the instrument is broken. So the two ways
# this ends are "the target was reached" and "it stopped short, and here is the record",
# and the second is a loud failure rather than a partial success. [LAW:no-silent-failure]
horizon_observe() {
  local config_dir="$1" project_dir="$2" goal_file="$3"
  local target="$4" max_minutes="$5"
  local deadline=$((SECONDS + max_minutes * 60))
  local report reached=0 last_seen=-1

  while [ "$SECONDS" -lt "$deadline" ]; do
    report="$(horizon_report "$config_dir" "$project_dir" "$goal_file")"
    reached="$(printf '%s' "$report" | python3 -c '
import json, sys
print(json.load(sys.stdin)["consecutive_with_commits"])
')" || horizon_die "could not read the run report"

    if [ "$reached" != "$last_seen" ]; then
      horizon_log "sessions with committed work, consecutively: $reached/$target"
      last_seen="$reached"
    fi
    if [ "$reached" -ge "$target" ]; then
      printf '%s\n' "$report"
      return 0
    fi
    # The session dying is not the same fact as the target being met, and only one of
    # them is success. Checked every pass so a crashed run ends in minutes rather than
    # burning the whole ceiling in silence.
    tmux has-session -t "$HORIZON_TMUX_SESSION" 2>/dev/null || {
      printf '%s\n' "$report"
      horizon_die "the run session died after $reached consecutive committing session(s)"
    }
    sleep 30
  done

  printf '%s\n' "$report"
  horizon_die "run hit its ${max_minutes}-minute ceiling with $reached/$target consecutive committing sessions"
}
