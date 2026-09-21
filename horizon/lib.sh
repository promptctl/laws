#!/usr/bin/env bash
# Primitives for the horizon eval's controlled-inclusion instrument.
#
# THE MODEL: a fresh CLAUDE_CONFIG_DIR per run, populated through the real `claude
# plugin` CLI — never by hand-writing its internal JSON — with exactly one
# marketplace exposing exactly the plugins the GOAL_PROMPT loop needs (memento, and
# lit's plugin for /next), each pinned to a recorded git ref via a `git archive`
# snapshot rather than a live directory pointer. Nothing else is declared in that
# marketplace, so nothing else can ever become installable, let alone enabled: the
# isolation is what the marketplace does NOT list, not a runtime filter.
# [LAW:types-are-the-program] the marketplace.json we generate IS the admitted set;
# provisioning and the verifier both read it rather than keeping a list of their own.
#
# [LAW:one-source-of-truth] every pinned identity (plugin refs, lit binary, reviewer
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
# THE ONE REPOSITORY EVERY RUN DRIVES. It already exists, and this eval never creates or
# deletes a repository - which is why nothing here needs a credential capable of
# destroying one. Public, because the reviewer is a GitHub Action and Actions minutes are
# unmetered on public repositories.
#
# It is scratch space, not a record. A run's PRs and review threads are captured onto disk
# into the run bundle by horizon_capture_prs; leaving them to live in a GitHub repo would
# make the bundle depend on that repo surviving untouched forever, which is exactly the
# fragility capture exists to remove.
HORIZON_RUN_REPO="promptctl/horizon-eval"

# ── Where a run lives on this machine ──────────────────────────────────────────────
# Two paths, deliberately NOT nested, because they have opposite lifetimes.
#
# HORIZON_CONFIG_DIR is PERSISTENT, and its exact path is load-bearing: Claude Code
# names the OS keychain entry holding the run's credential after a hash of this path, so
# "is this authenticated" is a question about WHERE the directory is, not what is in it.
# Wiping it keeps the login; building it somewhere else loses it. login.sh authenticates
# it once, and every run afterwards rebuilds it in place.
#
# HORIZON_WORK_DIR holds ONE RUN'S OUTPUT and must not exist when a run starts, so a
# previous run's transcripts and commits can never be mistaken for this one's.
#
# Nesting the first inside the second is how this went wrong before: the run dir's
# freshness guard then had to refuse the very directory the credential is bound to, and
# no run could start after a login had happened. Separate paths make the guard correct
# by construction rather than by a special case. [LAW:decomposition]
: "${HORIZON_CONFIG_DIR:=$HOME/.horizon/config}"
: "${HORIZON_WORK_DIR:=$HOME/.horizon/run}"

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
# tar/base64 stay with pin-instrument.sh only because they are reached from nothing
# else at all.
HORIZON_BASE_TOOLS=(awk cp find grep mkdir mktemp mv rm sed sleep sort tr wc)

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

# ── plugins: each pinned from the repo that owns it, never from this checkout ───────
# A run's plugins are memento and lit, and this repo carries a copy of neither, so there
# is nothing here a run could be provisioned from even by accident.
# [LAW:one-source-of-truth] each plugin has exactly one home and the instrument reads
# from it - a snapshot of a second copy is not a pin, it is a lie with a sha attached.
#
# Both are the same kind of thing - a plugin directory inside its owner's repository,
# pinned by fetching one commit - so both go through the same fetch, snapshot and
# marketplace functions below, told apart only by the values each passes in.
# [LAW:one-type-per-behavior]
#
# `HEAD` rather than a branch name for each default ref: the remote owns which branch is
# its default, and a name copied into this file is that fact going stale - a rename would
# break every default invocation. git asks the remote directly, so there is nothing here
# to drift. [LAW:one-source-of-truth]
: "${HORIZON_MEMENTO_REPO_URL:=https://github.com/promptctl/memento}"
: "${HORIZON_MEMENTO_DEFAULT_REF:=HEAD}"
HORIZON_MEMENTO_PLUGIN_SUBDIR="memento"
# The skills the GOAL_PROMPT loop needs from memento. Together with HORIZON_LIT_SKILLS
# this is the whole definition of "the plugins are fit for the loop"; the pin checks each
# snapshot against its list and the verifier checks each install against the same list.
HORIZON_MEMENTO_SKILLS=(address-pr-reviews message-in-a-bottle)
# The binary the session boundary is made of, relative to memento's plugin directory.
# Named once: the pin checks it in the snapshot and verify-instrument checks it as installed.
HORIZON_MEMENTO_RELAUNCH_REL_PATH="skills/message-in-a-bottle/bin/finalize-session"

# lit's pickup procedure, /next, ships in lit's Claude plugin, which lives in lit's own
# repository beside the binary's source. It is pinned from there by commit, like memento,
# and not from the lit binary on PATH: `lit init` stopped writing it into projects when
# the plugin took it over, and the binary exposes its build commit only as human output
# that lit documents as not for parsing.
: "${HORIZON_LIT_REPO_URL:=https://github.com/promptctl/links-issue-tracker}"
: "${HORIZON_LIT_DEFAULT_REF:=HEAD}"
HORIZON_LIT_PLUGIN_SUBDIR="claude-plugin"
HORIZON_LIT_SKILLS=(next)

# A moved skill leaves this heading behind. Checking it is a convention check, not proof
# that a body contains a procedure; it earns its place because a pointer standing where a
# procedure should be is exactly how this instrument once went green while broken.
HORIZON_MOVED_SKILL_HEADING='^# Moved$'

# Fetch one commit of a plugin's owning repository into an object store of our own and
# resolve the ref against it. Depth 1: a run needs one commit's tree, never the history
# behind it.
#
# Returns the resolved sha rather than leaving callers to read FETCH_HEAD afterwards.
# That ref is ambient state in the fetched store - a second fetch into the same store
# moves it under any caller still working from the first - so the sha travels as a
# value from here on. [LAW:no-ambient-temporal-coupling]
# Usage: horizon_git_fetch <repo_url> <git_dir> <ref>  -> prints the resolved commit sha
horizon_git_fetch() {
  local repo_url="$1" git_dir="$2" ref="$3"
  git init --bare -q "$git_dir" \
    || horizon_die "could not create an object store at $git_dir"
  git -C "$git_dir" fetch --depth 1 "$repo_url" "$ref" \
    || horizon_die "could not fetch '$ref' from $repo_url"
  git -C "$git_dir" rev-parse --verify 'FETCH_HEAD^{commit}' 2>/dev/null \
    || horizon_die "'$ref' in $repo_url does not resolve to a commit"
}

# Usage: horizon_git_tree_sha <git_dir> <commit_sha>  -> tree sha of that commit
horizon_git_tree_sha() {
  local git_dir="$1" commit_sha="$2"
  git -C "$git_dir" rev-parse --verify "${commit_sha}^{tree}" 2>/dev/null \
    || horizon_die "no tree for commit $commit_sha in $git_dir"
}

# Usage: horizon_plugin_rel_path <plugin_name> <plugin_subdir>  -> that plugin's
# directory, relative to the pinned dir
#
# The one spelling of where a plugin sits in a snapshot. Each owner's whole tree is
# extracted under its own plugin name, so two owners' trees cannot collide whatever
# their top-level files are called - memento's tree even carries its own
# .claude-plugin/marketplace.json, which lands inside memento/ where nothing registers it.
horizon_plugin_rel_path() {
  printf '%s/%s\n' "$1" "$2"
}

# Extract a pinned commit's whole tree under <pinned_dir>/<plugin_name>, and refuse it
# unless every named skill is there as a procedure. This directory - not a live clone -
# is what gets registered, so a later push to the owner's repo can never leak into an
# already-pinned run.
#
# The WHOLE tree, not just the plugin subdir: memento keeps one copy of each skill at
# its repo root and symlinks it into every plugin that ships it, so an archive of the
# plugin directory alone extracts dangling links. Snapshotting the closure is what makes
# the pin self-contained; `claude plugin install` then materialises those links into
# real files in its cache.
# Usage: horizon_build_plugin_snapshot <git_dir> <commit_sha> <pinned_dir> <plugin_name> <plugin_subdir> <skill>...
horizon_build_plugin_snapshot() {
  local git_dir="$1" commit_sha="$2" pinned_dir="$3" name="$4" subdir="$5"
  shift 5
  local tree_dir="$pinned_dir/$name"
  rm -rf "$tree_dir"
  mkdir -p "$tree_dir"
  git -C "$git_dir" archive "$commit_sha" \
    | tar -x -C "$tree_dir" \
    || horizon_die "git archive of $name at $commit_sha failed"
  local plugin_dir
  plugin_dir="$pinned_dir/$(horizon_plugin_rel_path "$name" "$subdir")"
  [ -d "$plugin_dir" ] \
    || horizon_die "$name at $commit_sha carries no $subdir/ plugin directory"
  # Each required skill, present and carrying a procedure, checked at pin time. `-f`
  # follows the symlink, so a skill whose closure did not come along fails HERE rather
  # than as an agent mid-run finding nothing behind the name. [LAW:no-silent-failure]
  local skill skill_file
  for skill in "$@"; do
    skill_file="$plugin_dir/skills/$skill/SKILL.md"
    [ -f "$skill_file" ] \
      || horizon_die "$name at $commit_sha does not provide the '$skill' skill"
    # Negated, never `grep -q ... && die`: that form's own exit status is 1 on the
    # healthy path, which under the callers' `set -e` aborts the pin on a good skill.
    ! grep -q "$HORIZON_MOVED_SKILL_HEADING" "$skill_file" \
      || horizon_die "$name at $commit_sha ships '$skill' as a pointer stub, not a procedure"
  done
}

# Usage: horizon_assert_relaunch_binary <memento_plugin_dir> <commit_sha>
#
# memento's relaunch binary, executable. The skill check proves the procedure is there;
# this proves the thing the session boundary is MADE of is there. A snapshot missing it
# boots, works one session, and then never hands off - a run does not notice for hours;
# it just stops committing and burns its wall-clock ceiling. [LAW:no-silent-failure]
horizon_assert_relaunch_binary() {
  local plugin_dir="$1" commit_sha="$2"
  local relaunch="$plugin_dir/$HORIZON_MEMENTO_RELAUNCH_REL_PATH"
  [ -x "$relaunch" ] \
    || horizon_die "memento at $commit_sha carries no executable finalize-session at $relaunch.
The session boundary IS that binary, so this instrument could never cross one."
}

# Usage: horizon_write_marketplace <pinned_dir> [<plugin_name> <plugin_subdir> <commit_sha>]...
#
# Write the marketplace a run registers: exactly the plugins named here, each pointing at
# its snapshot. What a run can install is what this file lists, so this file IS the
# inclusion control - provisioning installs every plugin it lists and nothing else, and
# the verifier requires exactly this set installed.
# [LAW:types-are-the-program] the marketplace.json we generate IS the admitted set.
horizon_write_marketplace() {
  local pinned_dir="$1"
  shift
  [ "$#" -gt 0 ] && [ $(($# % 3)) -eq 0 ] \
    || horizon_die "horizon_write_marketplace: plugins come as <name> <subdir> <commit> triples"
  local entries=()
  while [ "$#" -gt 0 ]; do
    entries+=("$1" "./$(horizon_plugin_rel_path "$1" "$2")" "$3")
    shift 3
  done
  mkdir -p "$pinned_dir/.claude-plugin"
  python3 - "$pinned_dir/.claude-plugin/marketplace.json" "$HORIZON_MARKETPLACE_NAME" "${entries[@]}" <<'PY' \
    || horizon_die "could not write the pinned marketplace in $pinned_dir"
import json, sys

out, marketplace, *flat = sys.argv[1:]
plugins = [
    {"name": name, "source": source, "description": f"Pinned snapshot at {commit}."}
    for name, source, commit in zip(flat[0::3], flat[1::3], flat[2::3])
]
with open(out, "w") as fh:
    json.dump({
        "name": marketplace,
        "description": "Pinned, controlled-inclusion snapshot for the horizon eval instrument. "
                       "Exposes exactly: " + ", ".join(p["name"] for p in plugins) + ".",
        "owner": {"name": "Brandon Fryslie"},
        "plugins": plugins,
    }, fh, indent=2)
    fh.write("\n")
PY
}

# Usage: horizon_marketplace_plugins <pinned_dir>  -> one plugin name per line
#
# The reader of the admitted set, for the two places that act on it: provisioning and
# the verifier. An empty list is refused, because installing nothing would boot a run
# with no workflow at all.
horizon_marketplace_plugins() {
  local pinned_dir="$1"
  python3 - "$pinned_dir/.claude-plugin/marketplace.json" <<'PY' \
    || horizon_die "could not read the plugins listed in $pinned_dir/.claude-plugin/marketplace.json"
import json, sys

names = [p["name"] for p in json.load(open(sys.argv[1]))["plugins"]]
if not names:
    sys.exit("the pinned marketplace lists no plugins")
print("\n".join(names))
PY
}

# Register the snapshot marketplace and install every plugin it lists into a fresh
# CLAUDE_CONFIG_DIR, through the real `claude plugin` CLI - the plugin cache's on-disk
# shape is that CLI's to own, not ours to hand-write. [LAW:single-enforcer]
# Usage: horizon_provision_config_dir <config_dir> <pinned_dir>
horizon_provision_config_dir() {
  local config_dir="$1" pinned_dir="$2" names name
  names="$(horizon_marketplace_plugins "$pinned_dir")"
  rm -rf "$config_dir"
  mkdir -p "$config_dir"
  CLAUDE_CONFIG_DIR="$config_dir" claude plugin marketplace add "$pinned_dir" \
    >/dev/null || horizon_die "failed to add pinned marketplace at $pinned_dir"
  # stdin is /dev/null inside the loop: the loop reads the plugin names from its own
  # stdin, and a claude that read stdin would swallow the names still waiting there.
  while read -r name; do
    CLAUDE_CONFIG_DIR="$config_dir" claude plugin install \
      "${name}@${HORIZON_MARKETPLACE_NAME}" --scope user \
      </dev/null >/dev/null || horizon_die "failed to install ${name}@${HORIZON_MARKETPLACE_NAME}"
  done <<<"$names"
}

# ── lit: the binary's only version surface is `lit version`, whose output lit documents
# as human-readable and not for parsing, so the recorded identity is the binary actually
# on PATH: its resolved path and its content hash. A run that silently picked up a
# different lit binary than the one recorded is exactly the drift this instrument exists
# to catch.
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

# Usage: horizon_manifest_field <manifest_file> <section> <key>  -> that recorded value
#
# THE reader of both manifests (manifest.json and seed-manifest.json share one shape:
# sections of scalar fields). Read back rather than re-derived, so what a run acts on and
# what its manifest describes cannot come from two computations - the pinned commit a
# goal is issued from, the project name a seed was written under. Section and key are
# values, not a reader per field: a reader hardwired to one section once handed the
# wrong repository's sha to the other's lookup. [LAW:one-source-of-truth] [LAW:composability]
horizon_manifest_field() {
  local manifest="$1" section="$2" key="$3"
  [ -f "$manifest" ] || horizon_die "no manifest at $manifest"
  python3 -c '
import json, sys
section, key = sys.argv[2], sys.argv[3]
value = json.load(open(sys.argv[1])).get(section, {}).get(key)
if not value:
    sys.exit("manifest records no %s.%s" % (section, key))
print(value)
' "$manifest" "$section" "$key" || horizon_die "could not read ${section}.${key} from $manifest"
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

# Usage: horizon_bind_remote <project_dir>
#
# Makes $HORIZON_RUN_REPO this run's origin, holding exactly the seeded history and
# nothing else. That is the whole job: the remote's time zero.
#
# WHY A SHARED, PRE-EXISTING REPO. The alternative - one new repo per run - has to answer
# "when is it safe to create this?", and every answer is a claim about a moment in the
# driver's execution order rather than a fact about the domain. Create it before the
# session boots and each boot failure mints a repo no run ever used; create it after the
# goal is issued and the agent racing to its first push decides whether origin exists.
# Landing between them works only for as long as nobody reorders the lines, and it leaves
# the eval wanting a credential that can delete repositories to clean up after itself.
# A repository that simply always exists has no such moment to get wrong.
# [LAW:no-ambient-temporal-coupling] correctness stops depending on call position.
#
# RESET AT THE START, NOT AT THE END. A run that crashes never reaches its own cleanup, so
# tidying afterwards leaves the next run to start from wreckage - and "usually clean"
# is not a time zero. Doing it here makes the state a run begins from a function of this
# call alone, whatever the last run did or how it died.
#
# WHAT SURVIVES A RESET, stated because it is a real divergence rather than an oversight:
# pull requests can be closed but never deleted, so closed PRs accumulate and PR numbers
# keep climbing across runs. Run five does not start at #1. Nothing else carries over.
#
# The remote's identity is not recorded anywhere by this function - the project's own git
# config holds it, and a second copy in the run's output could only ever disagree with it.
# [LAW:one-source-of-truth]
horizon_bind_remote() {
  local project_dir="$1" repo="$HORIZON_RUN_REPO"
  [ -d "$project_dir" ] || horizon_die "horizon_bind_remote: no project at $project_dir"

  # Listed into a variable first: a command substitution feeding a `for` never trips
  # errexit, so an unchecked listing that failed would clean up nothing and say nothing.
  # [LAW:no-silent-failure]
  local prs branches
  prs="$(horizon_remote_open_prs "$repo")"

  # Closing a PR with --delete-branch retires the pull request and its head branch in one
  # call, so the two cannot come apart and leave a branch whose PR is gone.
  local pr
  for pr in $prs; do
    horizon_log "closing leftover PR #$pr"
    gh pr close "$pr" --repo "$repo" --delete-branch \
      || horizon_die "could not close leftover PR #$pr in $repo"
  done

  # Listed after the PRs are closed, so this is what survived --delete-branch rather
  # than a list that names branches the loop above already removed.
  branches="$(horizon_remote_branches "$repo")"
  # Branches an agent pushed without ever opening a PR are left behind by the loop above.
  # master is skipped rather than attempted-and-forgiven: GitHub refuses to delete a
  # default branch, and letting that refusal pass would be indistinguishable from a real
  # permission failure going unnoticed. [LAW:no-silent-failure]
  local branch
  for branch in $branches; do
    [ "$branch" = "master" ] && continue
    horizon_log "deleting leftover branch $branch"
    gh api -X DELETE "repos/$repo/git/refs/heads/$branch" \
      || horizon_die "could not delete leftover branch $branch in $repo"
  done

  horizon_project_git "$project_dir" remote add origin "git@github.com:${repo}.git" \
    || horizon_die "could not point $project_dir at $repo"
  # Force, because the seed is a fresh history unrelated to whatever the last run left on
  # master. This is the line that makes the shared repo equivalent to a new one.
  horizon_project_git "$project_dir" push --force --quiet origin master \
    || horizon_die "could not push the seeded history to $repo"

  horizon_assert_remote_at_time_zero "$project_dir" "$repo"
}

# Usage: horizon_assert_remote_at_time_zero <project_dir> <repo>
#
# The four things that must be true of the remote before a run starts, checked against
# GitHub rather than inferred from the commands that just ran - each of those reported
# success, and success at the API is not the same fact as the state being right.
#
# `default_branch` is in here because it silently decides where pull requests go: the run
# agent calls `gh pr create` with no --base, which resolves to the default branch, so a
# repo whose default names something other than the branch the work is on produces a first
# unit of work that cannot be proposed. [LAW:verifiable-goals] this is the shape of "the
# remote is ready", written down where it can be run.
horizon_assert_remote_at_time_zero() {
  local project_dir="$1" repo="$2"

  local pushed head
  pushed="$(horizon_project_git "$project_dir" rev-parse refs/remotes/origin/master)" \
    || horizon_die "origin/master does not exist in $repo - nothing was pushed"
  head="$(horizon_project_head "$project_dir")"
  [ "$pushed" = "$head" ] \
    || horizon_die "origin/master ($pushed) is not the seeded HEAD ($head)"

  local default_branch
  default_branch="$(gh api "repos/$repo" --jq .default_branch)" \
    || horizon_die "could not read the default branch of $repo"
  [ "$default_branch" = "master" ] \
    || horizon_die "$repo has default branch '$default_branch', not master - the run agent's PRs would target a branch the work is not on"

  local open_prs
  open_prs="$(horizon_remote_open_prs "$repo")"
  [ -z "$open_prs" ] \
    || horizon_die "$repo still has open PR(s) #${open_prs//$'\n'/, #} - the run would inherit a previous run's work as its own"

  local extra_branches
  extra_branches="$(horizon_remote_branches "$repo" | sed '/^master$/d')"
  [ -z "$extra_branches" ] \
    || horizon_die "$repo still carries branches from a previous run: ${extra_branches//$'\n'/, }"
}

# Usage: horizon_remote_open_prs <repo>  -> open PR numbers, one per line
# Usage: horizon_remote_branches <repo>  -> branch names, one per line
#
# Paginated, so "every open PR" and "every branch" mean what they say past the API's
# default page; the reset and the time-zero assertion both read through these, so they
# cannot disagree about what the remote holds. [LAW:one-source-of-truth]
horizon_remote_open_prs() {
  local repo="$1"
  gh api --paginate "repos/$repo/pulls?state=open&per_page=100" --jq '.[].number' \
    || horizon_die "could not list open PRs in $repo"
}
horizon_remote_branches() {
  local repo="$1"
  gh api --paginate "repos/$repo/branches?per_page=100" --jq '.[].name' \
    || horizon_die "could not list branches in $repo"
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

# Usage: horizon_auth_state <config_dir>  -> `logged-in` or `logged-out`
#
# The one reader of whether a config dir can authenticate, and it asks the only party
# that knows, by making a request. `claude auth status` answers from the stored
# credential's presence, and a refresh token the server has already retired reads as
# logged in right up to the moment a session boots, fails to refresh, and stops at a
# login prompt - which is how the first acceptance run spent its only turn (2026-09-07).
# Status is a map of the credential; the request is the territory.
# [FRAMING:representation] Price: one one-turn haiku request per check.
#
# The probe is kept from doing anything but authenticate: no tools and one turn, so it
# cannot act; an empty working directory, so no CLAUDE.md of the caller's reaches it;
# no session persistence, so no transcript lands in <config>/projects for the capture
# to mistake for a session of the run. Print mode does not stop at the workspace-trust
# dialog (verified: every probe ran from a directory no config dir had ever seen), so
# the fresh directory needs no boot state. Not --bare: that skips the stored credential
# too, and reports every config dir logged out.
#
# It answers with a word rather than an exit code, so callers under `set -e` can branch
# on the answer without the shell treating "logged out" as a crashed command. The
# refusal exits 1, the same exit a crash gives, so the answer is read from the result
# envelope instead: `is_error` false is logged in; `is_error` true whose `result` is the
# authentication refusal is logged out - the CLI carries no code for that case, only
# the message, so the text is the discriminator and a rewording fails loudly below,
# never silently; anything else is not an answer. [LAW:parse-dont-validate]
horizon_auth_state() {
  local config_dir="$1" probe_dir envelope state rc=0
  [ -n "$config_dir" ] || horizon_die "horizon_auth_state: no config dir given"
  probe_dir="$(mktemp -d)" || horizon_die "horizon_auth_state: could not create a probe dir"
  # stdin is /dev/null, not the caller's. From v2.1.270 `claude -p` with a non-terminal
  # stdin waits 3s for piped input and then warns on stderr, and that warning lands in
  # front of the envelope - an unattended driver never has a terminal, so every check
  # died as "no result envelope" while the envelope said logged in.
  envelope="$(cd "$probe_dir" && CLAUDE_CONFIG_DIR="$config_dir" claude -p 'Reply with the single word ok' \
    --output-format json --model haiku --max-turns 1 --tools "" --no-session-persistence </dev/null 2>&1)" || true
  rm -rf "$probe_dir"
  state="$(printf '%s' "$envelope" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
if d.get("type") == "result" and d.get("is_error") is False:
    print("logged-in")
elif d.get("is_error") is True and str(d.get("result", "")).startswith("Failed to authenticate"):
    print("logged-out")
else:
    sys.exit(2)
')" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$state" ;;
    2) horizon_die "the auth probe against $config_dir was refused for a reason other than login:
$envelope" ;;
    *) horizon_die "the auth probe against $config_dir produced no result envelope:
$envelope" ;;
  esac
}

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
  local config_dir="$1" state
  # Assigned, then compared: a reader that dies inside `[ "$(...)" ]` is not seen by
  # errexit, and its message would be followed by this one, which would be wrong.
  state="$(horizon_auth_state "$config_dir")"
  [ "$state" = logged-in ] \
    || horizon_die "the run's config dir cannot authenticate: $config_dir
Run horizon/login.sh (it needs a browser); runs are unattended from then until the
credential is retired server-side, which a long gap between runs can do on its own.
Note the credential is bound to this PATH, so logging in somewhere else will not help."
}

# Usage: horizon_write_boot_state <config_dir> <project_dir>
#
# A freshly provisioned config dir stops at interactive gates that no unattended run can
# answer: first-run onboarding, the workspace trust dialog, and the bypass-permissions
# disclaimer. Each is recorded as a settled fact here, so the session boots straight to a
# ready input box.
#
# These are the CLI's own keys, not a private format: its error text for an untrusted
# workspace names `projects[<dir>].hasTrustDialogAccepted: true` in this exact file as
# the supported alternative to clicking the dialog.
#
# The gates live in TWO files, because the CLI moved one of them. Up to 2.1.226 the
# bypass-permissions acceptance was `bypassPermissionsModeAccepted` in .claude.json; by
# 2.1.252 a migration relocates it to settings.json as `skipDangerousModePermissionPrompt`
# and DELETES the original key. That migration only fires if the old key is present when
# it runs - and it runs during horizon_provision_config_dir, before this function writes
# anything. Writing the old key afterwards therefore lands in a slot whose migration has
# already gone by: the value sits in the file looking correct, is never migrated, and the
# startup dialog does not honour it. The run then stops at a disclaimer no unattended
# session can answer, while the config file reads as fully settled.
#
# So the acceptance is written where THIS version reads it, and the superseded key is not
# written at all - two spellings of one fact are two things that can disagree, and the
# dead one is the one that looks right. [LAW:one-source-of-truth] Verified on 2.1.252 by
# removing the legacy key entirely and confirming the session still boots to a live input
# box; if a future version moves it again, this is the seam that has to move with it.
#
# Written AFTER horizon_provision_config_dir, which rm -rf's the directory - order that
# matters, so it is stated where it can be seen rather than left to the caller to
# remember. Both files are MERGED into rather than replaced: provisioning leaves real
# state in each (settings.json carries the pinned marketplace and the enabled plugins),
# and clobbering either would make this a second writer of a file the CLI owns.
horizon_write_boot_state() {
  local config_dir="$1" project_dir="$2"
  [ -d "$config_dir" ] || horizon_die "horizon_write_boot_state: no config dir at $config_dir"
  [ -d "$project_dir" ] || horizon_die "horizon_write_boot_state: no project dir at $project_dir"
  python3 - "$config_dir/.claude.json" "$config_dir/settings.json" "$project_dir" <<'PY' \
    || horizon_die "could not write unattended boot state into $config_dir"
import json, os, sys

config_path, settings_path, project = sys.argv[1:]


def merge(path, apply):
    existing = {}
    if os.path.exists(path):
        with open(path) as f:
            existing = json.load(f)
    apply(existing)
    with open(path, "w") as f:
        json.dump(existing, f, indent=2)
        f.write("\n")


def gates(config):
    config["hasCompletedOnboarding"] = True
    config["theme"] = "dark"
    entry = config.setdefault("projects", {}).setdefault(project, {})
    entry["hasTrustDialogAccepted"] = True
    entry["hasCompletedProjectOnboarding"] = True


def bypass(settings):
    settings["skipDangerousModePermissionPrompt"] = True


merge(config_path, gates)
merge(settings_path, bypass)
PY
}

# Usage: horizon_take_run_lock
#
# THE LOCK. Every resource a run holds is a machine-wide singleton - the config dir at its
# fixed path, the tmux session name, the shared remote - so the run is serialized by ONE
# thing all of them share: the tmux session it will live in. Creating it is the lock -
# tmux refuses a duplicate name atomically, so two drivers cannot both pass - and it is
# taken before anything shared is touched, then held until horizon_release_run_lock. The
# session starts on the default shell; horizon_launch_session replaces that with claude.
# It disappears with the server on any kind of death, so there is no lock file to go
# stale. [LAW:single-enforcer] one checkpoint for "one run at a time".
horizon_take_run_lock() {
  tmux new-session -d -s "$HORIZON_TMUX_SESSION" -x 200 -y 50 \
    || horizon_die "a run is live in tmux session $HORIZON_TMUX_SESSION, or a killed driver left it.
One run at a time; \`tmux kill-session -t $HORIZON_TMUX_SESSION\` clears a session no run is using."
}

# Usage: horizon_release_run_lock
#
# Judged on the postcondition, not on the kill: a session that already died released the
# lock itself, whichever side of the kill it died on. A session that outlives a failed
# kill is the failure, reported with tmux's own reason. [LAW:no-silent-failure]
horizon_release_run_lock() {
  local err
  err="$(tmux kill-session -t "$HORIZON_TMUX_SESSION" 2>&1)" && return 0
  # has-session reports absence on stderr and by exit status; absence is the answer here.
  # [LAW:no-silent-failure] exception: the status is read, the text is noise.
  ! tmux has-session -t "$HORIZON_TMUX_SESSION" 2>/dev/null \
    || horizon_die "could not end the run session $HORIZON_TMUX_SESSION: $err"
}

# Usage: horizon_launch_session <config_dir> <project_dir> <goal_file>
#
# The ONE write that starts a run: claude replaces the placeholder shell in the locked
# session's pane, with the pinned /goal as its prompt. Inside tmux because that single
# choice decides whether the run stays isolated - see horizon_assert_transport, which is
# how that claim gets checked instead of assumed.
#
# CLAUDE_CONFIG_DIR is set in the SESSION's environment rather than exported: a pane
# spawned on an already-running tmux server inherits the server's environment, not the
# caller's, so an exported value would silently not arrive and the run would read the
# operator's real config. [LAW:no-silent-failure]
#
# THE GOAL IS THE LAUNCH PROMPT, never typed into the input box afterwards. Pasted at the
# pinned wording's size, a /goal is collapsed into a "[Pasted text #n]" placeholder and
# submitted as a plain message, so the session reads the wording with no goal in force
# (acceptance attempt 3, v2.1.263). Given as the prompt argument the same text executes,
# and nothing waits on an input box being ready. The command reaches tmux as separate
# words, so no shell runs: the prose arrives byte for byte, and claude is itself the pane
# process horizon_assert_transport looks for. horizon_wait_goal_in_force confirms it.
horizon_launch_session() {
  local config_dir="$1" project_dir="$2" goal_file="$3"
  tmux set-environment -t "$HORIZON_TMUX_SESSION" CLAUDE_CONFIG_DIR "$config_dir" \
    || horizon_die "could not bind CLAUDE_CONFIG_DIR into the run session"
  tmux respawn-pane -k -t "$HORIZON_TMUX_SESSION" -c "$project_dir" \
    claude --dangerously-skip-permissions "/goal $(<"$goal_file")" \
    || horizon_die "could not launch claude in the run session"
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
  # The pane goes in the message. What stops a boot is almost always something the pane is
  # displaying and waiting on - an interactive gate the boot state did not settle, a login
  # prompt, a crash - and a bare "did not become ready" sends the reader to go find that
  # out by hand, at which point the session may already have been cleaned up. An error
  # should say where to look; this one can simply say what it saw. [LAW:no-silent-failure]
  horizon_die "session did not reach a ready input box within ${HORIZON_BOOT_TIMEOUT_SECONDS}s.
The pane was showing:
$(horizon_pane 2>&1 | grep -v '^[[:space:]]*$')"
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

# A claude that REACHES the pane is one finalize-session will find by the same walk -
# and reaching it includes BEING it. `tmux respawn-pane <cmd>` execs the command as the
# pane process itself rather than under a shell, so on the ordinary launch the pid of
# claude IS pane_pid. A test that walked only strict ancestors rejected exactly the
# arrangement it exists to confirm. (No apostrophes in here: this whole program is a
# single-quoted shell string, and one would end it.)
# Bounded so a cycle in a mangled ps snapshot cannot spin.
def reaches_pane(pid):
    for _ in range(32):
        if pid == pane_pid:
            return True
        pid = parent.get(pid)
        if pid is None or pid == 0:
            return False
    return False

claudes = [p for p, n in name.items() if n.rsplit("/", 1)[-1] == "claude"]
if not any(reaches_pane(p) for p in claudes):
    sys.exit("no claude process runs under the run pane (pid %d); finalize-session "
             "would relaunch instead of resetting in place, losing CLAUDE_CONFIG_DIR"
             % pane_pid)
' "$pane_pid" || horizon_die "run session will not hand off through the in-place transport"
}

# Usage: horizon_capture_transcripts <config_dir> <work_dir>
#
# Moves the run's session transcripts into the run's own output directory.
#
# WHY THIS IS NOT OPTIONAL. Transcripts are the primary record of a run - the thing a
# human reads to judge what happened - and Claude Code writes them inside the CONFIG dir,
# which is a fixed path shared by every run and which horizon_provision_config_dir wipes
# on the way in. So a finished run's record survives only until the next run starts, and
# nothing anywhere would report that it had gone. The record is moved to where the rest of
# the run's output already lives, which is also the directory that gets archived. Moved,
# not copied: the config dir then holds no transcripts between runs, so what a later run
# finds there is only ever its own.
#
# Called from an exit handler rather than at the end of a successful run: a run that died
# is the one whose transcripts are most worth reading, and it never reaches its own last
# line. After the session is ended, so the record is final when it moves.
# [LAW:no-silent-failure]
horizon_capture_transcripts() {
  local work_dir="$2" source target="$2/transcripts"
  source="$(horizon_live_transcripts_dir "$1")"
  [ -d "$source" ] || horizon_die "no transcripts at $source - the run never booted a session"
  mkdir -p "$work_dir" || horizon_die "could not create $work_dir to capture transcripts into"
  # REFUSED rather than merged into, and this is the one that hides best: `mv` given an
  # existing directory moves the source INSIDE it, so a second close-out over the same
  # bundle produces transcripts/projects/<slug>/*.jsonl. Nothing complains - the count
  # below recurses and reports the right number - but sessions.py globs */*.jsonl one
  # level up, matches nothing, and finds neither sessions nor foreign transcripts, so its
  # own refusal cannot fire either. The bundle ends up recording a run of zero sessions
  # and zero tokens with every capture marked ok. [LAW:no-silent-failure]
  [ ! -e "$target" ] \
    || horizon_die "$target already exists: this bundle has been captured once already, and moving a second set of transcripts in would nest them where nothing reads them"
  mv "$source" "$target" || horizon_die "could not capture transcripts into $target"
  printf '%s transcript(s)\n' "$(find "$target" -name '*.jsonl' | wc -l | tr -d ' ')"
}

# Usage: horizon_live_transcripts_dir <config_dir>  -> where Claude Code writes them
#
# Claude Code's own layout, named once. Both the capture above and the analysis below reach
# it, and a second spelling of `projects` is a second claim about a directory this codebase
# does not own. [LAW:one-source-of-truth]
horizon_live_transcripts_dir() {
  printf '%s/projects\n' "$1"
}

# Usage: horizon_report <transcripts_dir> <project_dir> <goal_file>  -> the run's JSON report
#
# The project's commits are gathered here and handed to sessions.py, which reads the
# transcripts and does the analysis. The split is deliberate: this side is the effect
# (ask git what exists right now), that side is a pure function of what it is given, so
# the same verdict can be recomputed from an archived run with nothing running.
# [LAW:effects-at-boundaries]
#
# %cI is strict ISO-8601 and %H the full sha - a fixed, machine-oriented format rather
# than whatever the operator's log.date or format.pretty config would otherwise impose.
# The transcripts are named by DIRECTORY rather than by config dir, because this is read
# from two places whose transcripts sit in different trees: live, out of the config dir the
# run is writing into, and afterwards out of the bundle the close-out moved them to. One
# function, one meaning, and an archived run is genuinely recomputable rather than only
# claimed to be. [LAW:composability]
horizon_report() {
  local transcripts_dir="$1" project_dir="$2" goal_file="$3" commits
  commits="$(horizon_project_git "$project_dir" log --reverse --format='%H%x09%cI')" \
    || horizon_die "could not read the project's commit log in $project_dir"
  printf '%s\n' "$commits" \
    | python3 "$HORIZON_LIB_DIR/sessions.py" "$transcripts_dir" "$project_dir" "$goal_file" \
    || horizon_die "could not analyse the run's sessions"
}

# Usage: horizon_report_counts < report
#   -> "<consecutive committing sessions> <lost carries> <session one goal in force: 1|0>"
#
# The one reader of the report's keys outside sessions.py. sessions.test.py runs it
# against real sessions.py output, so the two sides cannot drift apart unnoticed.
# [LAW:one-source-of-truth]
horizon_report_counts() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["consecutive_with_commits"], d["goal_carries_expected"] - d["goal_carries_intact"],
      int(d["session_one_goal_in_force"]))
' || horizon_die "could not read the run report"
}

# Usage: horizon_wait_goal_in_force <config_dir> <project_dir> <goal_file>
#
# The run is not live until session one's transcript records the pinned goal EXECUTED.
# Launching with the goal as the prompt is the one form verified to execute; this is what
# turns "verified once" into "checked on every run". Waited for rather than read once,
# because the command is recorded a few boot entries in. Stopping here is not the driver
# repairing anything - session one's goal is the driver's own write, and a run whose
# first goal never took would otherwise be observed for hours as a lost carry it is not.
# [LAW:verifiable-goals] [LAW:no-silent-failure]
horizon_wait_goal_in_force() {
  local config_dir="$1" project_dir="$2" goal_file="$3"
  local report counts reached drifted in_force waited=0
  while :; do
    report="$(horizon_report "$(horizon_live_transcripts_dir "$config_dir")" "$project_dir" "$goal_file")"
    # Assigned, then split: a reader that dies inside a here-string is not seen by errexit.
    counts="$(printf '%s' "$report" | horizon_report_counts)"
    read -r reached drifted in_force <<<"$counts"
    [ "$in_force" = 1 ] && return 0
    [ "$waited" -lt "$HORIZON_BOOT_TIMEOUT_SECONDS" ] \
      || horizon_die "session one's pinned /goal was not in force within ${HORIZON_BOOT_TIMEOUT_SECONDS}s.
The report shows what the transcript recorded (goal_received is null when no /goal executed):
$report"
    sleep "$HORIZON_POLL_SECONDS"
    waited=$((waited + HORIZON_POLL_SECONDS))
  done
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
  local report counts reached=0 drifted in_force last_seen=-1

  while [ "$SECONDS" -lt "$deadline" ]; do
    report="$(horizon_report "$(horizon_live_transcripts_dir "$config_dir")" "$project_dir" "$goal_file")"
    counts="$(printf '%s' "$report" | horizon_report_counts)"
    read -r reached drifted in_force <<<"$counts"

    if [ "$reached" != "$last_seen" ]; then
      horizon_log "sessions with committed work, consecutively: $reached/$target"
      last_seen="$reached"
    fi

    # THE CARRY IS CHECKED, NOT JUST COUNTED. sessions.py already computed whether every
    # boundary handed the successor the pinned wording; reading only the commit count
    # would let a run report success while the goal degraded across each reset - the
    # instrument looking healthiest exactly where it is broken, which is the one outcome
    # this whole design refuses. The driver still does not REPAIR a lost carry: memento's
    # goal-carry is the controlled variable under measurement, so this stops the run and
    # reports, and never re-issues. [LAW:no-silent-failure]
    if [ "$drifted" -gt 0 ]; then
      printf '%s\n' "$report"
      horizon_die "the pinned goal did not survive $drifted session boundary/boundaries.
The wording each session actually received is in goal_received above. A paraphrase there
means the agent passed finalize-session a different --goal. A null means no /goal
executed in that session at all - a carried goal that was pasted instead of executed
arrives as plain text and leaves exactly this."
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

# ══ THE RUN BUNDLE: identically-structured, complete, reviewable (promptctl-horizon-7ry.4) ═
#
# With no scored layer anywhere in this eval, the BUNDLE IS THE OUTPUT. A human opens one
# run beside another and reads them; nothing downstream turns either into a verdict. So
# reviewability is not packaging around the product - it is the product, and the two
# things it has to be are COMPLETE (the record outlives the machine that made it) and
# IDENTICAL IN SHAPE (two bundles are comparable because the same fact is in the same
# place in both).
#
# THE SHAPE IS A FIXED RECORD, NOT A FIXED SET OF FILES. A run that died while seeding and
# a run that finished the backlog leave the same paths and the same keys; only the VALUES
# differ, and a capture that could not run is a value - `"ok": false` with the reason -
# rather than an absent file. That distinction is the whole design: an absent file makes a
# reader guess between "this run had none" and "the capture broke", and those are opposite
# findings. [LAW:dataflow-not-control-flow] [LAW:no-silent-failure]

# THE LAYOUT, DECLARED ONCE, as data. Three consumers read this and only this: the capture
# below creates what it names, the bundle's own README renders it for the human, and
# verify-bundle.sh checks a bundle against it. A second list anywhere - a path spelled
# again in the verifier, a line hand-written into the README - is the two-clocks failure
# with a directory tree for a face. [LAW:one-source-of-truth]
#
# The bundle's own record of the capture, named here because two things need to agree on
# it: the close-out writes it, and the inventory step has to skip it - a step whose result
# is one of the rows that file is built from cannot check that the file is there.
HORIZON_BUNDLE_RECORD="run.json"

# How much of a capture step's output `run.json` carries. Long enough for any message the
# steps here actually write, short enough that one chatty failure cannot bury the other
# nine rows in the file a reader opens first.
HORIZON_DETAIL_MAX=400

# Tab-separated `<path><TAB><what it holds>`, one per line.
HORIZON_BUNDLE_LAYOUT='README.md	this file: what each path below holds, and where the three things reviewers come for live
run.json	when the run ran, what it drove, and which of the captures below landed
goal.md	the exact /goal wording this run issued, byte for byte
loop.json	what the run did: its sessions, their commits, whether the goal survived each handoff, and what it all cost in tokens
instrument/	the pinned environment - manifest.json names every controlled variable, pinned/ is the plugin snapshots it names
seed/	time zero AND the produced repo: the project is seeded here and then worked in place, so its git history is the whole build
transcripts/	one directory per project slug, one .jsonl per session - the primary record of what the agent actually did
prs/	every pull request this run opened, each with its review threads, plus the PR number the run started above
backlog/	the lit backlog as it stood when the run ended - every ticket, its state, and its comments'

# Usage: horizon_bundle_layout_paths  -> one bundle-relative path per line
#
# The projection the verifier needs. Derived from the declaration rather than typed out
# beside it, so a path added above is checked below without anyone remembering to.
horizon_bundle_layout_paths() {
  printf '%s\n' "$HORIZON_BUNDLE_LAYOUT" | awk -F'\t' 'NF { print $1 }'
}

# Usage: horizon_project_remote_repo <project_dir>  -> `owner/name`
#
# The project's own git config is the authority on which repository this run drove -
# horizon_bind_remote set it and deliberately recorded it nowhere else. Read here rather
# than copied into the bundle, so the bundle cannot come to disagree with the repo it
# describes. [LAW:one-source-of-truth]
horizon_project_remote_repo() {
  local project_dir="$1" url
  url="$(horizon_project_git "$project_dir" remote get-url origin)" \
    || horizon_die "no origin in $project_dir - the run was never bound to a remote"
  # Both spellings git accepts for the same remote, reduced to the one `gh` wants - and
  # anything else REFUSED rather than passed through. The old fallback returned whatever
  # it was given, so a path remote came back as `/tmp/x/remote`, which `gh api
  # repos/$repo/pulls` and the GraphQL owner/name variables then carried as if it were a
  # repository. A remote this cannot read is a run bound to something the PR capture
  # cannot describe, and saying so beats inventing a slug for it.
  # [LAW:parse-dont-validate] what comes back is an owner/name or nothing.
  local repo
  repo="$(printf '%s\n' "$url" | sed -n -e 's#^git@github\.com:##p' -e 's#^https://github\.com/##p')"
  repo="${repo%.git}"
  case "$repo" in
    */*/*|"" ) horizon_die "origin in $project_dir is not a GitHub remote this can read: $url" ;;
    */* ) printf '%s\n' "$repo" ;;
    * ) horizon_die "origin in $project_dir is not a GitHub remote this can read: $url" ;;
  esac
}

# Usage: horizon_remote_highest_pr <repo>  -> the highest PR number, or 0
#
# Pull requests can be closed but never deleted, so a shared repository's PR numbers climb
# across runs and run five does not start at #1. This is read at time zero, right after the
# reset, and everything numbered above it is THIS run's work - by construction, not by
# guessing from a creation timestamp that a slow clock or a long queue can put on the wrong
# side of the line. [LAW:parse-dont-validate] the watermark is the proof, kept.
horizon_remote_highest_pr() {
  local repo="$1"
  gh api "repos/$repo/pulls?state=all&per_page=1&sort=created&direction=desc" \
    --jq '(.[0].number // 0)' \
    || horizon_die "could not read the highest PR number in $repo"
}

# Usage: horizon_record_remote_time_zero <bundle_dir> <repo>
#
# Called once, immediately after the remote is reset, because the fact it records is only
# true at that moment: afterwards the run's own PRs are indistinguishable from the previous
# run's leavings by number alone. Recorded INTO the bundle rather than held in a variable
# so that a run which dies mid-flight still says where its PRs begin.
horizon_record_remote_time_zero() {
  local bundle_dir="$1" repo="$2" highest
  highest="$(horizon_remote_highest_pr "$repo")"
  mkdir -p "$bundle_dir/prs" || horizon_die "could not create $bundle_dir/prs"
  printf '{\n  "highest_pr_at_reset": %s\n}\n' "$highest" > "$bundle_dir/prs/time-zero.json" \
    || horizon_die "could not record the remote's time zero"
  horizon_log "remote time zero: PRs above #$highest belong to this run"
}

# One query per pull request, and it is one query on purpose: a PR's body, its reviews and
# its review threads are read together or they are read at inconsistent moments, and a
# thread resolved between two REST calls would be captured as both open and closed.
#
# GraphQL rather than REST because `isResolved` exists nowhere else, and a review thread's
# resolution is not decoration here - the workflow under measurement is one where an agent
# answers review findings, so "was this thread ever settled" is the observation.
#
# The DIFF is deliberately absent: the produced repository is in the bundle with its whole
# history, so the authority on what a PR changed is already captured, and a second copy of
# it could only ever disagree. [LAW:one-source-of-truth]
HORIZON_PR_QUERY='
query($owner:String!, $name:String!, $number:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      number title url state isDraft merged createdAt mergedAt closedAt
      baseRefName headRefName headRefOid body
      author { login }
      commits(first:100) {
        totalCount
        pageInfo { hasNextPage }
        nodes { commit { oid messageHeadline committedDate } }
      }
      comments(first:100) {
        pageInfo { hasNextPage }
        nodes { author { login } createdAt body }
      }
      reviews(first:100) {
        pageInfo { hasNextPage }
        nodes { author { login } state submittedAt body }
      }
      reviewThreads(first:100) {
        pageInfo { hasNextPage }
        nodes {
          isResolved isOutdated path line
          comments(first:100) {
            pageInfo { hasNextPage }
            nodes { author { login } createdAt body }
          }
        }
      }
    }
  }
}'

# Usage: horizon_capture_prs <bundle_dir> <project_dir>  -> a one-line detail on success
#
# Every pull request the run opened, written one file per PR beside an index. Scoped by the
# watermark horizon_record_remote_time_zero wrote, so a shared repository's older PRs are
# never adopted as this run's work.
#
# TRUNCATION IS A FAILURE, NOT A TRIM. Each connection above is fetched at the API's
# maximum page and every `hasNextPage` is checked: a PR with more than 100 review comments
# stops the capture rather than being written short. A bundle that silently holds most of a
# review thread is worse than one that holds none, because only the second announces
# itself. [LAW:no-silent-failure]
# Usage: horizon_require_bundle_project <project_dir>
#
# The one check for "this bundle has a project to read". Every capture that needs one asks
# here rather than spelling the test out again, because three copies of a rule is three
# places to change it and two of them get changed. [LAW:single-enforcer]
#
# A bundle with no project is a real state, not a broken one: the run died before seeding
# finished. What must not happen is a capture treating that as an empty result.
horizon_require_bundle_project() {
  [ -n "$1" ] && [ -d "$1" ] \
    || horizon_die "no project in this bundle - the run ended before seeding finished"
}

horizon_capture_prs() {
  local bundle_dir="$1" project_dir="$2"
  local prs_dir="$bundle_dir/prs" time_zero="$bundle_dir/prs/time-zero.json"
  horizon_require_bundle_project "$project_dir"
  [ -f "$time_zero" ] \
    || horizon_die "no $time_zero: the remote was never reset, so which PRs are this run's is unknowable"

  local repo watermark
  repo="$(horizon_project_remote_repo "$project_dir")"
  watermark="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["highest_pr_at_reset"])' "$time_zero")" \
    || horizon_die "could not read the PR watermark from $time_zero"

  # state=all: a run's closed-without-merging PRs are part of what it did, and reading only
  # the open ones would quietly drop exactly the PRs a review rejected.
  local numbers
  numbers="$(gh api --paginate "repos/$repo/pulls?state=all&per_page=100" --jq '.[].number')" \
    || horizon_die "could not list the pull requests of $repo"

  local number captured=0
  for number in $numbers; do
    [ "$number" -gt "$watermark" ] || continue
    # Staged and moved, for the reason the loop capture is: a redirect is opened before
    # the command runs, so a query that failed left a zero-byte pr-NNNN.json in the
    # bundle. run.json would record the failure, but prs.py re-run over the archived
    # bundle months later dies on an empty file instead of on the real cause.
    local staged
    staged="$(mktemp "${TMPDIR:-/tmp}/horizon-pr.XXXXXX")" \
      || horizon_die "could not make a staging file for PR #$number"
    gh api graphql -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$number" \
        -f query="$HORIZON_PR_QUERY" \
      > "$staged" \
      || { rm -f "$staged"; horizon_die "could not capture PR #$number of $repo"; }
    mv "$staged" "$prs_dir/pr-$(printf '%04d' "$number").json" \
      || horizon_die "could not write the capture of PR #$number"
    captured=$((captured + 1))
  done

  python3 "$HORIZON_LIB_DIR/prs.py" "$prs_dir" \
    || horizon_die "could not index the captured pull requests"
  printf '%d pull request(s) above #%s\n' "$captured" "$watermark"
}

# Usage: horizon_capture_backlog <bundle_dir> <project_dir>  -> a one-line detail
#
# The backlog as it stood when the run ended: every ticket the agent created, closed, or
# left behind, with its comments. lit's own export format, not a private one, so nothing
# here can drift from what lit means by a ticket.
#
# The HISTORY comes with it: a lit export carries `events` beside `issues` and `comments`,
# so every state change a ticket went through is in this one document. That is why there is
# no second capture for it - and why reaching into lit's git store to reconstruct the same
# history would be a second reading of a fact lit already states. [LAW:one-source-of-truth]
horizon_capture_backlog() {
  local bundle_dir="$1" project_dir="$2"
  # Its own statement, and not a style preference: bash expands every word of a `local`
  # before it assigns any of them, so `out="$bundle_dir/..."` on the line above would read
  # whatever `bundle_dir` meant in the CALLER, bash being dynamically scoped. This function
  # wrote to `/backlog/export.json` when called on its own and silently worked when called
  # from horizon_capture_bundle, which happens to use that same name - so renaming a local
  # in the caller would have moved this file without a word. [LAW:no-shared-mutable-globals]
  local out="$bundle_dir/backlog/export.json"
  horizon_require_bundle_project "$project_dir"
  mkdir -p "$bundle_dir/backlog" || horizon_die "could not create $bundle_dir/backlog"
  # Staged outside the bundle and moved in only once it has been read, for the same reason
  # loop.json and the PR captures are: everything below can refuse, and a refusal that
  # left the document where it was written would put a well-formed `{"issues": []}` in the
  # bundle under the name the README sends a reviewer to. They would read "this run
  # created no tickets" off a file whose own capture said it failed.
  local staged
  staged="$(mktemp "${TMPDIR:-/tmp}/horizon-backlog.XXXXXX")" \
    || horizon_die "could not make a staging file for the backlog export"
  horizon_lit_export "$project_dir" > "$staged"
  # Indexed, not searched: an export without `issues` is not a thin backlog, it is a
  # document this code does not understand, and the KeyError says so where a `.get` default
  # would report a healthy empty backlog. [LAW:no-silent-failure]
  #
  # And ZERO tickets is refused rather than counted, because it is not a state a horizon
  # project can legally be in: every run is seeded from a seed bundle that imports a
  # backlog, so the tickets exist before the agent has done anything at all. What produces
  # an empty export instead is `lit export` hitting a sync it cannot resolve - measured
  # 2026-09-21: it printed a blocking error to stderr, EXITED 0, and wrote
  # `{"issues": [], "comments": [], "events": []}`. Exit status alone would have recorded
  # that as `"ok": true, "detail": "0 ticket(s)"`, which a reader can only read as "this
  # run created nothing" - the opposite finding from the truth, and exactly the ambiguity
  # this bundle exists to make impossible. [LAW:parse-dont-validate] the shape this accepts
  # is an export OF A SEEDED PROJECT, not an export.
  python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
issues, comments, events = doc["issues"], doc["comments"], doc["events"]
if not issues:
    sys.exit("the export holds no tickets at all. Every run is seeded with a backlog, so "
             "this is a broken export rather than an empty one - `lit export` exits 0 on "
             "a sync it cannot resolve and writes exactly this document.")
print("%d ticket(s), %d comment(s), %d event(s)"
      % (len(issues), len(comments), len(events)))' "$staged" \
    || horizon_die "the backlog export from $project_dir is not a readable export of a seeded project"
  mv "$staged" "$out" || horizon_die "could not write $out"
}

# Usage: horizon_bundle_project_dir <bundle_dir>  -> the project's path, or empty
#
# The name seed-run.sh recorded, never a basename re-derived here. A bundle whose run died
# before seeding has no project, and that is a real state rather than an error: it reads
# back as empty, and the captures that need a project refuse by name.
# [LAW:one-source-of-truth]
horizon_bundle_project_dir() {
  local bundle_dir="$1" seed_manifest="$1/seed/seed-manifest.json" name
  [ -f "$seed_manifest" ] || return 0
  name="$(horizon_manifest_field "$seed_manifest" project name)" || return 0
  printf '%s/seed/%s\n' "$bundle_dir" "$name"
}

# Usage: horizon_write_bundle_readme <bundle_dir>  -> a one-line detail
#
# The bundle's own front page, rendered from HORIZON_BUNDLE_LAYOUT so the map cannot drift
# from the territory it describes: a path added to the declaration appears here without
# anyone remembering to write it twice. [LAW:one-source-of-truth]
#
# This file is what the ticket's acceptance actually rests on - "a reviewer locates any
# run's PR review threads, ticket history, and token totals WITHOUT READING HARNESS CODE" -
# so those three are named explicitly further down rather than left to be inferred from a
# directory listing.
horizon_write_bundle_readme() {
  local bundle_dir="$1"
  {
    cat <<'EOT'
# A horizon run bundle

One run of the long-horizon eval: an agent was handed a seeded repository and a `/goal`,
and then built on it across session boundaries with no human input. Everything that run
produced or consumed is in this directory, and nothing outside it is needed to read the
run - not the machine it ran on, not the GitHub repository it pushed to, not the harness.

There is no score here and there is not meant to be one. The bundle is the eval's output:
a person reads it, and reads another beside it. `loop.json` and `prs/index.json` count
things, and counting is all they do - no file in this bundle renders a verdict.

## What is in here

EOT
    printf '%s\n' "$HORIZON_BUNDLE_LAYOUT" | awk -F'\t' 'NF { printf "- `%s` - %s\n", $1, $2 }'
    cat <<'EOT'

`run.json` answers the same questions for every run, with the same keys, whether the run
finished the backlog or died in its first minute: every capture above has an entry there,
and one that could not run says so and says why rather than leaving you an absent file to
interpret. The `layout` entry names any path in the list above that this bundle does not
have - a run that died before it was seeded genuinely has no `seed/`, and that is written
down rather than left for you to notice.

So nothing here has to be guessed at. Read `run.json` first: an empty result whose capture
says `"ok": true` means the run produced nothing, and a capture that failed is named,
with its reason, beside the others that did not.

## The three things people come here for

**PR review threads** - `prs/index.json` lists every pull request the run opened, with how
many review threads each drew and how many were never resolved. The threads themselves,
comment by comment, are in `prs/pr-NNNN.json` under `reviewThreads`, each carrying
`isResolved`. `prs/time-zero.json` records the PR number the run started above: the eval
drives one shared repository, so lower numbers belong to earlier runs.

**Ticket history** - `backlog/export.json` is the `lit` backlog as the run left it. Its
`issues` are the tickets, `comments` what was said on them, and `events` every state change
each one went through - created, started, closed - in order. That is the ticket history;
there is nothing else to consult for it.

**Token totals** - `loop.json`, under `tokens`. `sessions` is what the agent's own sessions
spent, `subprocesses` what the headless `claude` processes their tools spawned spent (the
adversarial code reviewer is one, and it is not small), and `total` is the sum. The four
figures are kept apart rather than added into one number, because a cached read and a
generated token differ in price by more than an order of magnitude and one combined figure
would be a lie with a number attached.

## Reading it again later

`loop.json` can be recomputed from this bundle alone:

    horizon/sessions.py <bundle>/transcripts <project-path> <bundle>/goal.md < commits.tsv

where `<project-path>` is `project.path` from `run.json` - the absolute path the project
had WHILE THE RUN RAN, not where this bundle now sits. Transcripts record the directory
they were written in, so a moved bundle needs the original path to match them up; pass the
wrong one and the tool says so rather than reporting a run in which nothing happened.

`prs/index.json` can be rebuilt the same way, with `horizon/prs.py <bundle>/prs`.
EOT
  } > "$bundle_dir/README.md" \
    || horizon_die "could not write $bundle_dir/README.md"
  printf '%s path(s) described\n' "$(horizon_bundle_layout_paths | wc -l | tr -d ' ')"
}

# Usage: horizon_capture_step <name> <command> [args...]  -> `<name><TAB><1|0><TAB><detail>`
#
# One captured part of the bundle, reduced to a row. Output and errors are merged on
# purpose: on the failing path the step's `horizon_die` message IS the detail, and routing
# it anywhere but into the record would leave `run.json` saying a capture failed without
# saying why - which is the same as not recording it. [LAW:no-silent-failure]
horizon_capture_step() {
  local name="$1"; shift
  local detail status
  detail="$("$@" 2>&1)"
  status=$?
  # Flattened to one line, because the row is tab-separated and a detail containing either
  # a tab or a newline would silently become a different number of fields.
  detail="$(printf '%s' "$detail" | tr '\n\t' '  ')"
  # And bounded. `run.json` is the surface two bundles get compared on, and a step that
  # failed can print a great deal: `lit export` alone emits a 2.4 KB block of agent
  # instructions on a sync it cannot resolve. One such value pushes every other capture
  # off the page. The cut is announced in the text, so nobody reads a sentence that stops
  # mid-word as the whole reason - the full message is still on the run's own stderr.
  if [ "${#detail}" -gt "$HORIZON_DETAIL_MAX" ]; then
    detail="${detail:0:$HORIZON_DETAIL_MAX} ... (truncated)"
  fi
  if [ "$status" -eq 0 ]; then
    printf '%s\t1\t%s\n' "$name" "${detail:-captured}"
  else
    printf '%s\t0\t%s\n' "$name" "${detail:-failed with no message}"
  fi
  return "$status"
}

# Usage: horizon_capture_bundle <config_dir> <bundle_dir> <started_iso>
#
# THE ONE CLOSE-OUT. Called from the driver's exit handler on every path there is -
# success, a failed assertion, a dead session, the wall-clock ceiling - because the run
# most worth reading is the one that died, and it never reaches its own last line.
#
# Every step below runs on every path. None of them is skipped for a run that got no
# further than the lock: a step with nothing to capture records WHY, and `run.json` ends up
# with the same keys either way. That is what makes two bundles comparable - not that they
# hold the same things, but that they answer the same questions. [LAW:dataflow-not-control-flow]
#
# A failed step fails the run. The transcripts, the record, the reviews and the backlog are
# the entire product of a run, so a run whose product did not land is not a success however
# well the agent worked. [LAW:no-silent-failure]
horizon_capture_bundle() {
  local config_dir="$1" bundle_dir="$2" started="$3"
  local status=0 rows=() project_dir ended

  # NOT created here, and that is the point. This handler is installed the moment the
  # lock exists, which is before the driver creates its work dir, so it also runs for
  # failures that happened before there was a run at all - a config dir that could not
  # authenticate is the common one. Creating the directory then leaves a bundle recording
  # nothing, and the NEXT invocation refuses to start because `[ ! -e $HORIZON_WORK_DIR ]`
  # finds it: "work dir already holds a run", about a run that never began. "A refused
  # invocation leaves nothing behind" has to hold for the close-out too.
  if [ ! -d "$bundle_dir" ]; then
    horizon_log "no bundle to capture: the run ended before it created $bundle_dir"
    return 0
  fi

  # First, and before anything reads them: the transcripts live in the config dir, which is
  # a fixed path the NEXT run wipes, so every later step here is reading a record that only
  # exists because this one moved it.
  rows+=("$(horizon_capture_step transcripts \
              horizon_capture_transcripts "$config_dir" "$bundle_dir")") || status=1

  project_dir="$(horizon_bundle_project_dir "$bundle_dir")"

  rows+=("$(horizon_capture_step loop \
              horizon_capture_loop "$bundle_dir" "$project_dir")") || status=1
  rows+=("$(horizon_capture_step prs \
              horizon_capture_prs "$bundle_dir" "$project_dir")") || status=1
  rows+=("$(horizon_capture_step backlog \
              horizon_capture_backlog "$bundle_dir" "$project_dir")") || status=1
  rows+=("$(horizon_capture_step readme \
              horizon_write_bundle_readme "$bundle_dir")") || status=1
  # Last, so it sees everything the steps above produced. Two of the declared paths -
  # instrument/ and seed/ - are written by the pin and the seed rather than by any capture,
  # so without this the record would account for the parts this function happens to own and
  # stay silent about the rest. A bundle's inventory has to cover the whole bundle.
  rows+=("$(horizon_capture_step layout \
              horizon_check_bundle_layout "$bundle_dir")") || status=1

  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || horizon_die "could not read the clock"
  printf '%s\n' "${rows[@]}" \
    | python3 "$HORIZON_LIB_DIR/bundle.py" "$bundle_dir" "$HORIZON_BUNDLE_RECORD" "$started" "$ended" "$project_dir" \
    || horizon_die "could not write $bundle_dir/run.json"

  horizon_log "bundle captured: $bundle_dir"
  return "$status"
}

# Usage: horizon_check_bundle_layout <bundle_dir>  -> a one-line detail
#
# The bundle's inventory, taken against the one declaration of its shape. This is what
# makes "identically structured" a fact a reader can check rather than a promise the
# instrument makes about itself: a path the layout declares and the bundle lacks is named
# here, in the bundle's own record, on the run it went missing. [LAW:verifiable-goals]
horizon_check_bundle_layout() {
  local bundle_dir="$1" path missing=() present=0
  while read -r path; do
    # The record cannot inventory itself: this check is one of the steps whose results
    # that file is written FROM, so at this moment it does not exist yet and never can.
    # Skipped by the one name lib.sh holds for it, not by a second spelling here.
    [ "$path" = "$HORIZON_BUNDLE_RECORD" ] && continue
    if [ -e "$bundle_dir/$path" ]; then
      present=$((present + 1))
    else
      missing+=("$path")
    fi
  done < <(horizon_bundle_layout_paths)
  [ "${#missing[@]}" -eq 0 ] \
    || horizon_die "the bundle is missing declared path(s): ${missing[*]}"
  # Both numbers, because they differ by one on purpose and a bare "8 present" against a
  # nine-line layout reads as a bundle short of a file until you work out which.
  printf '%d of %d declared path(s) present; %s is written from this step and cannot inventory itself\n' \
    "$present" "$(horizon_bundle_layout_paths | wc -l | tr -d ' ')" "$HORIZON_BUNDLE_RECORD"
}

# Usage: horizon_capture_loop <bundle_dir> <project_dir>  -> a one-line detail
#
# The run's record, written here rather than by the observer's stdout redirect. The
# redirect only produced a file when the observer got far enough to print one: acceptance
# attempt 1 was stopped by hand four minutes in and left `loop.json` empty, and a run that
# died before the observer started left none at all. The record of a run that failed is the
# record most worth having, so it is written from the close-out like everything else.
horizon_capture_loop() {
  local bundle_dir="$1" project_dir="$2"
  horizon_require_bundle_project "$project_dir"
  # The transcripts capture runs first and MOVES the directory into place, so its absence
  # here means that step did not land - never that the run held no sessions. Without this,
  # sessions.py globs a directory that is not there, matches nothing, and writes a
  # loop.json of zero sessions and zero tokens: `run.json` then carries `loop: ok` beside
  # `transcripts: failed`, and a reader who opens loop.json on its own - which the bundle
  # README invites - sees a clean report of a run that did nothing. An EMPTY transcripts/
  # is a different thing and stays legal: the run died before booting a session, and all
  # zeros is then the truth. [LAW:no-silent-failure]
  [ -d "$bundle_dir/transcripts" ] \
    || horizon_die "no transcripts/ in this bundle - the transcripts capture did not land, so there is nothing to analyse and a zero here would be a fabrication"
  # Built beside the bundle and moved in, never written through a redirect onto its final
  # name: bash opens a redirect BEFORE running the command, so `> loop.json` that failed -
  # a refused analysis, an unreadable git log - left a zero-byte loop.json behind while
  # the step reported failure. The layout inventory then counts the path as present and a
  # reader who opens loop.json on its own, which the bundle README invites, gets an empty
  # file. That is the very shape acceptance attempt 1 produced and this capture exists to
  # remove, so the file appears only once it is whole. [LAW:no-silent-failure]
  # Staged OUTSIDE the bundle, not beside the file under a .partial name. horizon_report
  # ends in horizon_die, and a die exits - so an `|| rm` cleanup after it never runs, and
  # a staging file inside the bundle would simply stay there under a different name.
  # Somewhere the bundle does not reach is the only version of this that holds.
  local staged
  staged="$(mktemp "${TMPDIR:-/tmp}/horizon-loop.XXXXXX")" \
    || horizon_die "could not make a staging file for loop.json"
  horizon_report "$bundle_dir/transcripts" "$project_dir" "$bundle_dir/goal.md" \
    > "$staged"
  mv "$staged" "$bundle_dir/loop.json" || horizon_die "could not write $bundle_dir/loop.json"
  # Moved into place FIRST and then refused, because this record is not broken - it is
  # complete, and it says the token totals are unsafe. A reader needs to see it.
  local disagreements
  disagreements="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["usage_disagreements"])' "$bundle_dir/loop.json")" \
    || horizon_die "could not read the token bookkeeping from $bundle_dir/loop.json"
  [ "$disagreements" = 0 ] \
    || horizon_die "$disagreements message(s) in this run reported more than one usage, so the token totals are a floor rather than a count - see usage_disagreements in loop.json"
  printf '%s\n' "$(horizon_report_counts < "$bundle_dir/loop.json" \
    | awk '{ printf "%s consecutive committing session(s), %s lost carry/carries", $1, $2 }')"
}
