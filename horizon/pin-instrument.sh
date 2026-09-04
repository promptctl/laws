#!/usr/bin/env bash
# Pin the horizon eval's controlled-inclusion instrument, one run at a time.
#
# WHY: a long-horizon run is only readable against a baseline if every controlled
# variable is nailed down and RECORDED - memento at a git ref, lit's binary identity
# and the pickup procedure it embeds, the reviewer action's tag resolved to its actual
# commit, and the standard /goal wording. This script is the one command that builds
# that environment and writes the manifest proving what it built.
# [LAW:verifiable-goals] "done" for a run is: the manifest exists and every field in it
# resolves back to something checkable.
#
# Usage:
#   horizon/pin-instrument.sh <run-dir> [memento-ref] [reviewer-sha] [goal-ref]
#
# <run-dir>      directory to build the run's environment in (created fresh; an
#                existing run-dir is refused rather than silently merged into -
#                [LAW:no-silent-failure], a stale leftover file must never masquerade
#                as this run's output).
# [memento-ref]  git ref to pin memento at, resolved against the repository that OWNS
#                memento (promptctl/memento), not this checkout - what is left here is
#                pointer stubs. Defaults to that repo's default branch. A campaign that
#                wants one fixed ref across every run in the campaign
#                (promptctl-horizon-7ry.5) passes it explicitly on every invocation
#                rather than relying on this default, which tracks a moving branch.
# [reviewer-sha] commit sha to pin the reviewer action at, skipping the live
#                `v1`-tag resolution. A caller that needs two invocations to agree
#                on the reviewer's identity without racing the moving tag twice -
#                verify-instrument.sh's reproducibility check is exactly this -
#                resolves it once and passes it here explicitly.
# [goal-ref]     ref of THIS repo to read the standard /goal wording at. Defaults to
#                this checkout's `HEAD`, which moves whenever anything commits here -
#                so the same caller that pins the two refs above pins this one too,
#                or a commit landing mid-verification fails the reproducibility check
#                for a reason that has nothing to do with the instrument.
#
# Produces, under <run-dir>:
#   pinned/                 the memento git-archive snapshot + its marketplace.json
#   config/                 the fresh CLAUDE_CONFIG_DIR (memento installed, nothing else)
#   manifest.json           every pinned identity, canonical JSON, no timestamps -
#                           so two invocations with unchanged inputs are byte-identical

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
horizon_need cat
# Reached from inside lib.sh pipelines - git archive | tar, and the reviewer prompt
# decode. Absent, pipefail would blame the tool at the head of the pipe instead of
# the one that is actually missing.
horizon_need tar
horizon_need base64

# Scratch that exists only to produce recorded identities: memento's objects, and the
# throwaway repos lit writes its /next procedure into. Neither is an output of the
# run - everything they establish reaches the run dir as a manifest field or as the
# pinned snapshot - so the run dir keeps its three documented outputs and nothing else.
# Script scope, not main's: the EXIT trap runs after main's locals are gone, and under
# `set -u` a trap reaching for a dead local dies on the way out, replacing the real
# error with a bogus one. [LAW:no-ambient-temporal-coupling]
WORK="$(mktemp -d)" || horizon_die "could not create a scratch directory"
trap 'rm -rf "$WORK"' EXIT

main() {
  local run_dir="${1:-}" memento_ref="${2:-}" reviewer_sha_override="${3:-}" goal_ref="${4:-}"
  [ -n "$run_dir" ] || horizon_die "usage: pin-instrument.sh <run-dir> [memento-ref] [reviewer-sha] [goal-ref]"
  [ -e "$run_dir" ] && horizon_die "run-dir already exists, refusing to overwrite: $run_dir"

  local repo_root
  repo_root="$(horizon_repo_root "$SCRIPT_DIR")"
  [ -z "$memento_ref" ] && memento_ref="$HORIZON_MEMENTO_DEFAULT_REF"
  # Defaulted to a ref and resolved unconditionally below, never branched on whether an
  # override was given: resolving an explicit sha returns that sha and additionally
  # proves it exists in this checkout. [LAW:dataflow-not-control-flow]
  [ -z "$goal_ref" ] && goal_ref="HEAD"

  mkdir -p "$run_dir"

  horizon_log "fetching memento from $HORIZON_MEMENTO_REPO_URL at $memento_ref"
  local memento_sha memento_tree_sha
  memento_sha="$(horizon_memento_fetch "$WORK/memento.git" "$memento_ref")"
  memento_tree_sha="$(horizon_memento_tree_sha "$WORK/memento.git" "$memento_sha")"
  horizon_log "memento pinned at $memento_sha (tree $memento_tree_sha)"

  horizon_log "building pinned memento snapshot"
  horizon_build_memento_snapshot "$WORK/memento.git" "$memento_sha" "$run_dir/pinned"

  horizon_log "provisioning isolated CLAUDE_CONFIG_DIR"
  horizon_provision_config_dir "$run_dir/config" "$run_dir/pinned"

  horizon_log "recording lit's binary identity"
  local lit_path lit_sha256
  # Resolved once and hashed at that exact path - binary_path and sha256 in the
  # manifest must describe the same file, which two independent `command -v lit`
  # resolutions cannot guarantee. [LAW:one-source-of-truth]
  lit_path="$(horizon_lit_path)"
  lit_sha256="$(horizon_sha256_file "$lit_path")" \
    || horizon_die "could not hash lit binary at $lit_path"

  horizon_log "recording the /next procedure this lit embeds"
  local next_skill_sha256
  next_skill_sha256="$(horizon_lit_next_skill_sha256 "$WORK/lit-next-probe")"

  # `tag` alone would imply resolved_sha was obtained by resolving it, which is false
  # whenever a sha is handed in - the common case, since verify-instrument.sh overrides
  # on both runs. resolved_from records which actually happened, so no reader infers a
  # check that never ran. [LAW:verifiable-goals]
  local reviewer_sha reviewer_resolved_from
  if [ -n "$reviewer_sha_override" ]; then
    horizon_log "reviewer pinned at $reviewer_sha_override (given, not resolved)"
    reviewer_sha="$reviewer_sha_override"
    reviewer_resolved_from="override"
  else
    horizon_log "resolving reviewer ${REVIEWER_REPO}@${REVIEWER_TAG}"
    reviewer_sha="$(horizon_reviewer_sha)"
    reviewer_resolved_from="tag"
    horizon_log "reviewer pinned at $reviewer_sha"
  fi
  local reviewer_prompt_sha256
  reviewer_prompt_sha256="$(horizon_reviewer_prompt_sha256 "$reviewer_sha")"

  horizon_log "recording the standard /goal wording"
  # A commit of this repo, not memento's sha: GOAL_PROMPT.md lives here, and since
  # memento moved out the two commits describe different repositories.
  local goal_sha256
  goal_ref="$(horizon_resolve_commit "$repo_root" "$goal_ref")"
  goal_sha256="$(horizon_goal_wording_sha256 "$repo_root" "$goal_ref")"

  python3 - "$run_dir/manifest.json" \
    "memento_repo_url=$HORIZON_MEMENTO_REPO_URL" \
    "memento_ref=$memento_sha" \
    "memento_tree_sha=$memento_tree_sha" \
    "lit_binary_path=$lit_path" \
    "lit_sha256=$lit_sha256" \
    "lit_next_skill_path=$HORIZON_NEXT_SKILL_REL_PATH" \
    "lit_next_skill_sha256=$next_skill_sha256" \
    "reviewer_repo=$REVIEWER_REPO" \
    "reviewer_tag=$REVIEWER_TAG" \
    "reviewer_resolved_sha=$reviewer_sha" \
    "reviewer_resolved_from=$reviewer_resolved_from" \
    "reviewer_prompt_path=$REVIEWER_PROMPT_PATH" \
    "reviewer_prompt_sha256=$reviewer_prompt_sha256" \
    "goal_wording_path=$HORIZON_GOAL_PROMPT_REL_PATH" \
    "goal_wording_ref=$goal_ref" \
    "goal_wording_sha256=$goal_sha256" \
    <<'PY' || horizon_die "failed to write manifest.json"
import json, sys

# Named pairs, not a positional list: every field here is a hex string or a path, so a
# transposed pair would produce a plausible-looking manifest that silently attributes
# one identity to another. A missing or misspelled key raises KeyError and takes the
# whole pin down instead. [LAW:parse-dont-validate] [LAW:no-silent-failure]
out, *pairs = sys.argv[1:]
f = dict(p.split("=", 1) for p in pairs)

manifest = {
    "schema_version": 2,
    "instrument": "promptctl-horizon",
    "memento": {
        "repo_url": f["memento_repo_url"],
        "ref": f["memento_ref"],
        "tree_sha": f["memento_tree_sha"],
    },
    "lit": {
        "binary_path": f["lit_binary_path"],
        "sha256": f["lit_sha256"],
        "next_skill_path": f["lit_next_skill_path"],
        "next_skill_sha256": f["lit_next_skill_sha256"],
    },
    "reviewer": {
        "repo": f["reviewer_repo"],
        "tag": f["reviewer_tag"],
        "resolved_sha": f["reviewer_resolved_sha"],
        "resolved_from": f["reviewer_resolved_from"],
        "prompt_path": f["reviewer_prompt_path"],
        "prompt_sha256": f["reviewer_prompt_sha256"],
    },
    "goal_wording": {
        "path": f["goal_wording_path"],
        "ref": f["goal_wording_ref"],
        "sha256": f["goal_wording_sha256"],
    },
}

with open(out, "w") as fh:
    json.dump(manifest, fh, sort_keys=True, indent=2)
    fh.write("\n")
PY

  horizon_log "manifest written: $run_dir/manifest.json"
}

main "$@"
