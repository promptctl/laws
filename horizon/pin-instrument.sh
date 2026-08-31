#!/usr/bin/env bash
# Pin the horizon eval's controlled-inclusion instrument, one run at a time.
#
# WHY: a long-horizon run is only readable against a baseline if every controlled
# variable is nailed down and RECORDED - memento at a git ref, lit's binary identity,
# the reviewer action's tag resolved to its actual commit, and the standard /goal
# wording. This script is the one command that builds that environment and writes the
# manifest proving what it built. [LAW:verifiable-goals] "done" for a run is: the
# manifest exists and every field in it resolves back to something checkable.
#
# Usage:
#   horizon/pin-instrument.sh <run-dir> [memento-ref]
#
# <run-dir>     directory to build the run's environment in (created fresh; an
#               existing run-dir is refused rather than silently merged into -
#               [LAW:no-silent-failure], a stale leftover file must never masquerade
#               as this run's output).
# [memento-ref] git ref to pin memento at, resolved against this repo. Defaults to
#               the repo's current HEAD. A campaign that wants one fixed memento ref
#               across every run in the campaign (promptctl-horizon-7ry.5) passes it
#               explicitly on every invocation rather than relying on this default.
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

main() {
  local run_dir="${1:-}" memento_ref="${2:-}"
  [ -n "$run_dir" ] || horizon_die "usage: pin-instrument.sh <run-dir> [memento-ref]"
  [ -e "$run_dir" ] && horizon_die "run-dir already exists, refusing to overwrite: $run_dir"

  horizon_need git
  horizon_need gh
  horizon_need claude
  horizon_need python3

  local repo_root
  repo_root="$(horizon_repo_root)"
  [ -z "$memento_ref" ] && memento_ref="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"

  mkdir -p "$run_dir"

  horizon_log "resolving memento ref: $memento_ref"
  local memento_sha memento_tree_sha
  memento_sha="$(horizon_resolve_memento_ref "$repo_root" "$memento_ref")"
  memento_tree_sha="$(horizon_memento_tree_sha "$repo_root" "$memento_sha")"
  horizon_log "memento pinned at $memento_sha (tree $memento_tree_sha)"

  horizon_log "building pinned memento snapshot"
  horizon_build_memento_snapshot "$repo_root" "$memento_sha" "$run_dir/pinned"

  horizon_log "provisioning isolated CLAUDE_CONFIG_DIR"
  horizon_provision_config_dir "$run_dir/config" "$run_dir/pinned"

  horizon_log "recording lit's binary identity"
  local lit_path lit_sha256
  lit_path="$(horizon_lit_path)"
  lit_sha256="$(horizon_lit_sha256)"

  horizon_log "resolving reviewer ${REVIEWER_REPO}@${REVIEWER_TAG}"
  local reviewer_sha reviewer_prompt_sha256
  reviewer_sha="$(horizon_reviewer_sha)"
  reviewer_prompt_sha256="$(horizon_reviewer_prompt_sha256 "$reviewer_sha")"
  horizon_log "reviewer pinned at $reviewer_sha"

  horizon_log "recording the standard /goal wording"
  local goal_sha256
  goal_sha256="$(horizon_goal_wording_sha256 "$repo_root")"

  python3 - "$run_dir/manifest.json" \
    "$memento_sha" "$memento_tree_sha" \
    "$lit_path" "$lit_sha256" \
    "$REVIEWER_REPO" "$REVIEWER_TAG" "$reviewer_sha" "$REVIEWER_PROMPT_PATH" "$reviewer_prompt_sha256" \
    "$goal_sha256" <<'PY'
import json, sys

(out, memento_sha, memento_tree_sha, lit_path, lit_sha256,
 reviewer_repo, reviewer_tag, reviewer_sha, reviewer_prompt_path, reviewer_prompt_sha256,
 goal_sha256) = sys.argv[1:]

manifest = {
    "schema_version": 1,
    "instrument": "promptctl-horizon",
    "memento": {
        "ref": memento_sha,
        "tree_sha": memento_tree_sha,
    },
    "lit": {
        "binary_path": lit_path,
        "sha256": lit_sha256,
    },
    "reviewer": {
        "repo": reviewer_repo,
        "tag": reviewer_tag,
        "resolved_sha": reviewer_sha,
        "prompt_path": reviewer_prompt_path,
        "prompt_sha256": reviewer_prompt_sha256,
    },
    "goal_wording": {
        "path": "horizon/GOAL_PROMPT.md",
        "sha256": goal_sha256,
    },
}

with open(out, "w") as f:
    json.dump(manifest, f, sort_keys=True, indent=2)
    f.write("\n")
PY

  horizon_log "manifest written: $run_dir/manifest.json"
}

main "$@"
