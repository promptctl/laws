#!/usr/bin/env bash
# Seed a horizon run's time zero: appspec + fresh-history git repo + lit init + backlog.
#
# WHY: the seed is the experiment's time zero, and every run of every arm has to start
# from the same line - a difference here contaminates every downstream comparison, and
# would do it invisibly, since a backlog that merely LOOKS similar still changes what
# the agent picks up first. This script is the one command that builds that starting
# state, and it records what it built so the claim is checkable rather than assumed.
# [LAW:verifiable-goals] "done" for a seeding is: the manifest and the backlog shape
# exist, and a second seeding of the same bundle reproduces them byte for byte
# (horizon/verify-seed.sh is that check).
#
# Usage:
#   horizon/seed-run.sh <run-dir> <seed-dir> [project-name]
#
# <run-dir>        directory to build the starting state in (created fresh; an existing
#                  run-dir is refused rather than merged into, so a stale leftover can
#                  never masquerade as this seeding's output - as in pin-instrument.sh).
# <seed-dir>       the seed bundle: a `repo/` tree that becomes the project, and a
#                  backlog.json that becomes its lit store. horizon/seeds/macklebox is
#                  the reference seed, recovered from the reference run itself.
# [project-name]   the project directory's name, defaulting to the seed bundle's. This
#                  is not cosmetic: `lit init` derives the issue prefix from the
#                  repository's directory name, so the name is part of time zero.
#
# Produces, under <run-dir>:
#   <project-name>/     the seeded project - fresh history, spec committed, lit
#                       initialised, backlog and its dependency edges loaded
#   backlog-shape.json  the seeded backlog with generated ids replaced by structural
#                       position: what "the same backlog" means, as a comparable value
#   seed-manifest.json  canonical JSON, no timestamps - two seedings of one bundle are
#                       byte-identical

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

BACKLOG_PY="$SCRIPT_DIR/backlog.py"

main() {
  local run_dir="${1:-}" seed_dir="${2:-}" project_name="${3:-}"
  [ -n "$run_dir" ] && [ -n "$seed_dir" ] \
    || horizon_die "usage: seed-run.sh <run-dir> <seed-dir> [project-name]"
  [ -e "$run_dir" ] && horizon_die "run-dir already exists, refusing to overwrite: $run_dir"

  horizon_need git
  horizon_need lit
  horizon_need python3
  # Reached only from inside lib.sh - the seed tree copy, and awk trailing every
  # sha256. Absent, the failure would name the wrong tool.
  horizon_need cp
  horizon_need awk

  # Resolved before anything is created, so a malformed seed fails with nothing built.
  local backlog seed_digest
  backlog="$(horizon_seed_backlog_path "$seed_dir")"
  seed_dir="$(cd "$seed_dir" && pwd)"
  backlog="$(cd "$(dirname "$backlog")" && pwd)/$(basename "$backlog")"
  seed_digest="$(horizon_seed_digest "$seed_dir")"
  [ -z "$project_name" ] && project_name="$(basename "$seed_dir")"
  # A project name is one path segment, never a path. `lit init` derives the issue
  # prefix from this directory's name, so a single segment is what it always meant -
  # and a name containing `/` or `..` would place the project outside <run-dir>, where
  # the refuse-to-overwrite check above never looked. [LAW:parse-dont-validate]
  case "$project_name" in
    */*|.|..) horizon_die "project-name must be a single path segment, not '$project_name'" ;;
  esac

  mkdir -p "$run_dir"
  run_dir="$(cd "$run_dir" && pwd)"
  local project_dir="$run_dir/$project_name"

  horizon_log "seeding '$project_name' from $seed_dir"
  horizon_project_init "$project_dir"
  horizon_project_populate "$project_dir" "$seed_dir"
  # Two commits, mirroring the reference run's own history: the spec lands first and the
  # lit integration files second, so a reader of the seeded repo sees the same shape of
  # beginning the reference run had.
  horizon_project_commit "$project_dir" "Initial commit: $project_name specification"

  horizon_log "initialising lit"
  horizon_lit_init "$project_dir"
  horizon_project_commit "$project_dir" "Add lit integration files (AGENTS.md, CLAUDE.md)"

  # One import, one transaction: the seed's backlog file IS a lit import spec, so
  # parentage and the cross-epic `blocks` edges are declared in it and wired by lit
  # itself. There is no second schema here to drift from the one lit enforces, and a
  # malformed seed rolls back whole rather than leaving a half-built backlog.
  # [LAW:single-enforcer]
  horizon_log "seeding the backlog"
  horizon_lit_import "$project_dir" "$backlog"

  horizon_log "recording the seeded backlog's shape"
  horizon_lit_export "$project_dir" \
    | python3 "$BACKLOG_PY" > "$run_dir/backlog-shape.json" \
    || horizon_die "could not compute the seeded backlog's shape"

  local head_commit tree_sha shape_sha256 lit_path lit_sha256
  head_commit="$(horizon_project_head "$project_dir")"
  tree_sha="$(horizon_project_tree "$project_dir")"
  shape_sha256="$(horizon_sha256_file "$run_dir/backlog-shape.json")" \
    || horizon_die "could not hash backlog-shape.json"
  # Resolved once and hashed at that exact path, so both manifest fields describe the
  # same file. lit's identity belongs in a SEED manifest and not only in the instrument
  # manifest: AGENTS.md and CLAUDE.md are rendered from the binary's embedded templates,
  # so the lit on PATH is a genuine input to the committed tree. [LAW:one-source-of-truth]
  lit_path="$(horizon_lit_path)"
  lit_sha256="$(horizon_sha256_file "$lit_path")" \
    || horizon_die "could not hash lit binary at $lit_path"

  python3 - "$run_dir/seed-manifest.json" \
    "$project_name" "$seed_digest" "$head_commit" "$tree_sha" \
    "$shape_sha256" "$lit_path" "$lit_sha256" \
    <<'PY' || horizon_die "failed to write seed-manifest.json"
import json, sys

(out, project_name, seed_digest, head_commit, tree_sha,
 shape_sha256, lit_path, lit_sha256) = sys.argv[1:]

manifest = {
    "schema_version": 1,
    "instrument": "promptctl-horizon-seed",
    "seed": {
        "digest": seed_digest,
    },
    "project": {
        "name": project_name,
        "branch": "master",
        "head_commit": head_commit,
        "tree_sha": tree_sha,
    },
    "backlog": {
        "shape_sha256": shape_sha256,
    },
    "lit": {
        "binary_path": lit_path,
        "sha256": lit_sha256,
    },
}

with open(out, "w") as f:
    json.dump(manifest, f, sort_keys=True, indent=2)
    f.write("\n")
PY

  horizon_log "seeded: $project_dir (HEAD $head_commit)"
  horizon_log "manifest written: $run_dir/seed-manifest.json"
}

main "$@"
