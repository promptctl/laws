#!/usr/bin/env bash
# The configuration (arm) format and the machinery that resolves a skill body from git. A
# configuration says ONLY "which guidance, at which version" - a skill name plus a git ref, or no
# skill at all (the control arm). It hard-codes no task: no repo, no commit, no success criterion.
# That orthogonality is what makes an arm a first-class, swappable thing, so any task can be paired
# with any arm and the same task run identically across arms.
#
# THE FORMAT. A configuration is a directory:
#   <config>/manifest.sh  - sourced; DATA ONLY:
#       CONFIG_SKILL    - the skill name (e.g. "code", "prompt"), or EMPTY for the control arm.
#       CONFIG_REF      - the git ref (in the laws repo) whose body to load. Required for a skill
#                         arm; empty for control.
#       CONFIG_SUMMARY  - one-line human description.
#
# THE SKILL VERSION IS A GIT REF AND IS THE SINGLE SOURCE OF TRUTH. The body is read straight from
# git at that ref at resolve time (`git show <ref>:<path>`), never from a checked-in copy - so
# there is no second representation of a skill body that could drift from the one in git.
#
# The body path follows the repo convention - but is DERIVED from git rather than hard-coded, so
# it stays correct as the repo changes: the body is `skills/<name>/references/craft.md` when that
# exists at the ref (laws:prompt, laws:prose, laws:ticket), otherwise `skills/<name>/SKILL.md`
# (laws:code, laws:chat, laws:application-spec). Deriving reproduces the documented convention
# without duplicating the repo's structure in a list here. [LAW:one-source-of-truth]
#
# [LAW:no-silent-failure] A ref or a body path that does not exist in git aborts nonzero - it
#   never loads an empty or stale body, and never lets the control arm's "no body" hide a lookup
#   that actually failed.
# [LAW:effects-at-boundaries] the git reads are gathered here.

set -o pipefail

cfg_die() { printf 'ERROR [config]: %s\n' "$*" >&2; exit 1; }
cfg_log() { printf '[config] %s\n' "$*" >&2; }

# The laws repo the refs live in. The harness ships inside that repo, so its toplevel is the
# default; overridable for running the machinery against a checkout elsewhere.
cfg_laws_root() {
  local here="${BASH_SOURCE[0]%/*}"
  if [ -n "${CONFIG_LAWS_REPO:-}" ]; then printf '%s\n' "$CONFIG_LAWS_REPO"; return 0; fi
  git -C "$here" rev-parse --show-toplevel 2>/dev/null \
    || cfg_die "cannot locate the laws repo (set CONFIG_LAWS_REPO)"
}

# Read the three fields of a manifest into stdout as three lines (skill, ref, summary), sourced in
# a subshell so nothing leaks. Rejects a manifest that smuggles in a task field - a configuration
# is orthogonal to task, structurally. [LAW:types-are-the-program]
# Usage: cfg_fields <config_dir>   -> prints skill\nref\nsummary
cfg_fields() {
  local dir="$1"
  [ -n "$dir" ] || cfg_die "cfg_fields: no config dir given"
  [ -d "$dir" ] || cfg_die "cfg_fields: not a directory: $dir"
  local man="$dir/manifest.sh"
  [ -f "$man" ] || cfg_die "cfg_fields: missing manifest.sh in $dir"

  local smuggled
  smuggled="$(grep -nE '^[[:space:]]*(TASK_REPO|TASK_COMMIT|TASK_SUMMARY|CONFIG_TASK|TASK_CRITERION|CHECK)[[:space:]]*=' "$man" | head -1)"
  [ -z "$smuggled" ] || cfg_die "cfg_fields: manifest sets a task field (a configuration is orthogonal to task): $smuggled"

  local out
  out="$(set -e; CONFIG_SKILL=""; CONFIG_REF=""; CONFIG_SUMMARY=""
         # shellcheck disable=SC1090
         . "$man" >/dev/null                       # stdout suppressed, stderr flows [LAW:no-silent-failure]
         printf '%s\n%s\n%s\n' "$CONFIG_SKILL" "$CONFIG_REF" "$CONFIG_SUMMARY")" \
    || cfg_die "cfg_fields: manifest.sh failed to source cleanly: $man"
  printf '%s\n' "$out"
}

# Derive the body path for a skill at a ref: craft.md if it exists there, else SKILL.md, else fail.
# Usage: cfg_body_path <laws_root> <ref> <skill>   -> prints the path
cfg_body_path() {
  local root="$1" ref="$2" skill="$3"
  # The skill name is interpolated into a path; restrict it to a safe token so it cannot traverse
  # out of skills/<name>/ (e.g. "../.."). [LAW:no-silent-failure]
  case "$skill" in
    ''|*[!A-Za-z0-9_-]*) cfg_die "cfg_body_path: unsafe skill name (allowed: letters, digits, - _): $skill" ;;
  esac
  local craft="skills/$skill/references/craft.md" main="skills/$skill/SKILL.md"
  if git -C "$root" cat-file -e "$ref:$craft" 2>/dev/null; then printf '%s\n' "$craft"; return 0; fi
  if git -C "$root" cat-file -e "$ref:$main"  2>/dev/null; then printf '%s\n' "$main";  return 0; fi
  cfg_die "no skill body for '$skill' at ref '$ref' (looked for $craft and $main)"
}

# ── Validate a configuration against the format ─────────────────────────────────────────
# A control arm sets an empty CONFIG_SKILL (and no ref). A skill arm sets both CONFIG_SKILL and
# CONFIG_REF, and the ref+body must resolve in git. A half-filled manifest (skill without ref, or
# ref without skill) is rejected so a typo cannot silently degrade a skill arm into control.
# Usage: cfg_validate <config_dir>
cfg_validate() {
  local dir="$1"
  local f; f="$(cfg_fields "$dir")" || exit $?
  local skill ref summary root
  skill="$(printf '%s' "$f" | sed -n '1p')"
  ref="$(printf '%s' "$f" | sed -n '2p')"
  summary="$(printf '%s' "$f" | sed -n '3p')"
  [ -n "$summary" ] || cfg_die "cfg_validate: manifest sets no CONFIG_SUMMARY in $dir"

  if [ -z "$skill" ]; then
    [ -z "$ref" ] || cfg_die "cfg_validate: control arm (empty CONFIG_SKILL) must not set CONFIG_REF: $dir"
    return 0
  fi
  [ -n "$ref" ] || cfg_die "cfg_validate: skill arm '$skill' sets no CONFIG_REF in $dir"
  root="$(cfg_laws_root)"
  git -C "$root" rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
    || cfg_die "cfg_validate: CONFIG_REF does not resolve in the laws repo: $ref"
  cfg_body_path "$root" "$ref" "$skill" >/dev/null   # aborts if no body at the ref
}

# ── Resolve the body text ───────────────────────────────────────────────────────────────
# Print the skill body at the configured ref to stdout, straight from git. The control arm prints
# NOTHING and returns 0 - a deliberate "no body", distinct from a failed lookup, which aborts.
# Usage: cfg_resolve <config_dir>   -> prints body on stdout (empty for control)
cfg_resolve() {
  local dir="$1"
  cfg_validate "$dir" || exit $?
  local f; f="$(cfg_fields "$dir")" || exit $?
  local skill ref root path
  skill="$(printf '%s' "$f" | sed -n '1p')"
  ref="$(printf '%s' "$f" | sed -n '2p')"
  [ -n "$skill" ] || { cfg_log "control arm ($dir): no body"; return 0; }
  root="$(cfg_laws_root)"
  path="$(cfg_body_path "$root" "$ref" "$skill")"
  git -C "$root" show "$ref:$path" 2>/dev/null \
    || cfg_die "cfg_resolve: could not read $ref:$path from the laws repo"
}
