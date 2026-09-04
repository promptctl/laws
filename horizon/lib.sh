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
HORIZON_BASE_TOOLS=(awk cp find grep mkdir mktemp rm sort tr)

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

# ── memento: pinned from the repo that owns it, never from this checkout ───────────
# memento's skills live in promptctl/memento and this repo carries no copy of them,
# so there is nothing here a run could be provisioned from even by accident.
# [LAW:one-source-of-truth] the skills have exactly one home and the instrument reads
# from it - a snapshot of a second copy is not a pin, it is a lie with a sha
# attached.
: "${HORIZON_MEMENTO_REPO_URL:=https://github.com/promptctl/memento}"
# `HEAD` rather than a branch name: the remote owns which branch is its default, and a
# name copied into this file is that fact going stale - a rename would break every
# default invocation. git asks the remote directly, so there is nothing here to drift.
# [LAW:one-source-of-truth]
: "${HORIZON_MEMENTO_DEFAULT_REF:=HEAD}"
HORIZON_MEMENTO_PLUGIN_SUBDIR="memento"
# The skills the GOAL_PROMPT loop needs *from the plugin*. `next` is deliberately not
# among them: it is a pointer in memento too, because the pickup procedure now ships
# inside the lit binary, and it is checked where it actually lands - see
# HORIZON_NEXT_SKILL_REL_PATH in the lit section below. This array is the whole
# definition of "the plugin is fit for the loop"; the pin checks the snapshot against
# it and the verifier checks the install against it, both reading this one list.
HORIZON_MEMENTO_SKILLS=(address-pr-reviews message-in-a-bottle)
# A moved skill leaves this heading behind - it is how memento's own `next` pointer is
# written, the one pointer left in this ecosystem. Checking it is a convention check,
# not proof that a body contains a procedure; it earns its place because a pointer
# standing where a procedure should be is exactly how this instrument went green while
# broken.
HORIZON_MOVED_SKILL_HEADING='^# Moved$'

# Fetch the pinned memento objects into an object store of our own and resolve the ref
# against it. Depth 1: a run needs one commit's tree, never the history behind it.
#
# Returns the resolved sha rather than leaving callers to read FETCH_HEAD afterwards.
# That ref is ambient state in the fetched store - a second fetch into the same store
# moves it under any caller still working from the first - so the sha travels as a
# value from here on. [LAW:no-ambient-temporal-coupling]
# Usage: horizon_memento_fetch <git_dir> <ref>  -> prints the resolved commit sha
horizon_memento_fetch() {
  local git_dir="$1" ref="$2"
  git init --bare -q "$git_dir" \
    || horizon_die "could not create the memento object store at $git_dir"
  git -C "$git_dir" fetch --depth 1 "$HORIZON_MEMENTO_REPO_URL" "$ref" \
    || horizon_die "could not fetch '$ref' from $HORIZON_MEMENTO_REPO_URL"
  git -C "$git_dir" rev-parse --verify 'FETCH_HEAD^{commit}' 2>/dev/null \
    || horizon_die "memento ref does not resolve to a commit: $ref"
}

# Usage: horizon_memento_tree_sha <git_dir> <commit_sha>  -> tree sha of that commit
horizon_memento_tree_sha() {
  local git_dir="$1" commit_sha="$2"
  git -C "$git_dir" rev-parse --verify "${commit_sha}^{tree}" 2>/dev/null \
    || horizon_die "no tree for memento commit $commit_sha"
}

# Extract the pinned commit's whole tree into <snapshot_dir> and write a marketplace
# over it that declares exactly one plugin. This directory - not a live clone - is what
# gets registered, so a later push to memento can never leak into an already-pinned run.
#
# The WHOLE tree, not just the plugin subdir: memento keeps one copy of each skill at
# the repo root and symlinks it into every plugin that ships it, so an archive of
# `memento/` alone extracts dangling links. Snapshotting the closure is what makes the
# pin self-contained; `claude plugin install` then materialises those links into real
# files in its cache.
#
# The archive also carries memento's own marketplace.json, which declares a second
# plugin (auto-bottle). Overwriting it here IS the inclusion control - what a run can
# install is what this file lists, and it lists one thing.
# [LAW:types-are-the-program] the marketplace.json we generate IS the admitted set.
# Usage: horizon_build_memento_snapshot <git_dir> <commit_sha> <snapshot_dir>
horizon_build_memento_snapshot() {
  local git_dir="$1" commit_sha="$2" snapshot_dir="$3"
  rm -rf "$snapshot_dir"
  mkdir -p "$snapshot_dir"
  git -C "$git_dir" archive "$commit_sha" \
    | tar -x -C "$snapshot_dir" \
    || horizon_die "git archive of memento at $commit_sha failed"
  local plugin_dir="$snapshot_dir/$HORIZON_MEMENTO_PLUGIN_SUBDIR"
  [ -d "$plugin_dir" ] \
    || horizon_die "memento at $commit_sha carries no $HORIZON_MEMENTO_PLUGIN_SUBDIR/ plugin directory"
  # Each required skill, present and carrying a procedure, checked at pin time. `-f`
  # follows the symlink, so a skill whose closure did not come along fails HERE rather
  # than as an agent mid-run finding nothing behind the name. [LAW:no-silent-failure]
  local skill skill_file
  for skill in "${HORIZON_MEMENTO_SKILLS[@]}"; do
    skill_file="$plugin_dir/skills/$skill/SKILL.md"
    [ -f "$skill_file" ] \
      || horizon_die "memento at $commit_sha does not provide the '$skill' skill"
    # Negated, never `grep -q ... && die`: that form's own exit status is 1 on the
    # healthy path, which under the callers' `set -e` aborts the pin on a good skill.
    ! grep -q "$HORIZON_MOVED_SKILL_HEADING" "$skill_file" \
      || horizon_die "memento at $commit_sha ships '$skill' as a pointer stub, not a procedure"
  done
  mkdir -p "$snapshot_dir/.claude-plugin"
  cat > "$snapshot_dir/.claude-plugin/marketplace.json" <<EOF
{
  "name": "$HORIZON_MARKETPLACE_NAME",
  "description": "Pinned, controlled-inclusion snapshot for the horizon eval instrument. Exposes exactly one plugin: memento, at $commit_sha.",
  "owner": {"name": "Brandon Fryslie"},
  "plugins": [
    {"name": "memento", "source": "./$HORIZON_MEMENTO_PLUGIN_SUBDIR", "description": "Agent-native workflow tooling (pinned snapshot, $commit_sha)."}
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

# The pickup half of the GOAL_PROMPT loop is no longer a plugin skill at all: it ships
# inside the lit binary, and `lit init` writes it into the project at this path. So the
# instrument's third named skill is pinned exactly like the other two - by the content
# lit actually produces, recorded in the manifest - and a lit too old to produce it
# fails the pin rather than a run. [LAW:one-source-of-truth]
HORIZON_NEXT_SKILL_REL_PATH=".claude/skills/next/SKILL.md"

# Usage: horizon_lit_next_skill_write <project_dir>  -> path of the /next skill lit wrote
#
# One `lit init` against one fresh project, returning the file it produced. Built on the
# seeding primitives (defined further down this file) so the probe repo carries the same
# neutralised git config a seeded project does.
horizon_lit_next_skill_write() {
  local project_dir="$1"
  horizon_project_init "$project_dir"
  horizon_lit_init "$project_dir"
  local skill_file="$project_dir/$HORIZON_NEXT_SKILL_REL_PATH"
  [ -f "$skill_file" ] \
    || horizon_die "the lit on PATH does not write $HORIZON_NEXT_SKILL_REL_PATH, so a run's agent has no way to pull a ticket - it needs a lit newer than 0.11.0 (\`lit version\`; \`lit upgrade\`)"
  ! grep -q "$HORIZON_MOVED_SKILL_HEADING" "$skill_file" \
    || horizon_die "the lit on PATH writes $HORIZON_NEXT_SKILL_REL_PATH as a pointer stub, not a procedure"
  printf '%s\n' "$skill_file"
}

# Usage: horizon_lit_next_skill_sha256 <scratch_dir>  -> sha256 of the /next skill the
# lit on PATH writes
#
# Running lit is the only way to read this identity: the procedure is embedded in the
# binary, so nothing on disk to hash and no version string to trust.
#
# Twice, under two deliberately different project names, because one recorded hash can
# only stand for every run if the bytes are a property of the BINARY. lit does derive
# project-specific state from the directory name - the issue prefix comes from it - so
# this file's independence of that name is a real property to establish, not one to
# assume: were it ever templated, every call site probes under its own fixed name, so
# the manifest would record a hash no real run reproduces and every check here would
# stay green. That is the failure this instrument exists to refuse.
# [LAW:verifiable-goals] [LAW:behavior-not-structure] the check is what lit produces,
# never which version it claims to be.
horizon_lit_next_skill_sha256() {
  local scratch="$1"
  [ -n "$scratch" ] || horizon_die "horizon_lit_next_skill_sha256: no scratch directory given"
  local file_a file_b sha_a sha_b
  file_a="$(horizon_lit_next_skill_write "$scratch/lit-next-probe")"
  file_b="$(horizon_lit_next_skill_write "$scratch/a-differently-named-project")"
  sha_a="$(horizon_sha256_file "$file_a")" || horizon_die "could not hash $file_a"
  sha_b="$(horizon_sha256_file "$file_b")" || horizon_die "could not hash $file_b"
  [ "$sha_a" = "$sha_b" ] \
    || horizon_die "the /next procedure lit writes depends on the project directory name ($sha_a vs $sha_b), so no single recorded hash describes every run"
  printf '%s\n' "$sha_a"
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

# ── the standard /goal wording: pinned by content hash at a commit of THIS repo,
# where GOAL_PROMPT.md lives, never off the live working tree - an uncommitted local
# edit must not produce a manifest value with no corresponding commit to audit it
# against. That commit is this repo's own, no longer memento's: once memento moved to
# its own repository the two shas stopped describing the same thing, and one variable
# standing for two facts is a manifest that cannot be audited. [LAW:one-source-of-truth]

# Usage: horizon_resolve_commit <repo_root> <ref>  -> prints the resolved commit sha
horizon_resolve_commit() {
  local repo_root="$1" ref="$2"
  git -C "$repo_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null \
    || horizon_die "ref does not resolve to a commit in $repo_root: $ref"
}

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
