#!/usr/bin/env bash
# Verify the seeding step against its acceptance criteria:
#
#   1. Seeding twice from the same seed bundle yields equivalent starting states - the
#      same files (byte-identical seed-manifest.json, which carries the committed tree's
#      sha) and a backlog of the same shape (byte-identical backlog-shape.json).
#   2. The starting state is actually the SEED's. Reproducibility alone is worthless
#      here: a seeding that silently dropped every dependency edge, or half the
#      backlog, would reproduce that damage perfectly and pass criterion 1. So the
#      seeded backlog is compared back against the seed bundle itself - every ticket,
#      its parent, and every blocks edge - keyed by title, independently of the
#      positional-key logic backlog.py uses, so the two cannot agree by sharing a bug.
#   3. The repo is a genuine fresh-history project with no remote: `lit init` adopts a
#      backlog from a git remote when it finds one, so a remote here would mean the
#      starting state could come from somewhere other than the seed.
#   4. Every file under the seed's `repo/` tree is committed byte-for-byte. This is a
#      different claim from criterion 1: matching manifests prove the two runs agree
#      with each other, which would hold just as well if both had committed the wrong
#      bytes. This is the only check that ties a committed tree back to the seed.
#
# [LAW:verifiable-goals] this script IS the machine-checkable "done" for the ticket;
# exit 0 means every criterion held on this run, exit nonzero says which one didn't.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

SEED_DIR="${1:-$SCRIPT_DIR/seeds/macklebox}"

WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

main() {
  horizon_need git
  horizon_need lit
  horizon_need python3
  # horizon_seed_digest and horizon_sha256_file hash through a pipeline ending in awk.
  horizon_need awk
  # Invoked directly by the checks below; named here so a missing one fails with this
  # instrument's own error rather than a bare "command not found".
  horizon_need diff
  horizon_need cmp
  horizon_need sed

  local backlog
  backlog="$(horizon_seed_backlog_path "$SEED_DIR")"

  horizon_log "run 1: seeding from $SEED_DIR"
  "$SCRIPT_DIR/seed-run.sh" "$WORK/run1" "$SEED_DIR"
  horizon_log "run 2: seeding from $SEED_DIR"
  "$SCRIPT_DIR/seed-run.sh" "$WORK/run2" "$SEED_DIR"

  local f
  for f in seed-manifest.json backlog-shape.json; do
    if diff -u "$WORK/run1/$f" "$WORK/run2/$f" >/dev/null; then
      pass "two seedings produced byte-identical $f"
    else
      diff -u "$WORK/run1/$f" "$WORK/run2/$f" >&2 || true
      fail "$f diverged between two seedings from the same seed"
    fi
  done

  # The manifest's tree_sha is the committed files' identity, so an identical manifest
  # already proves "same files". Stated separately because that is the ticket's wording
  # and a reader should not have to infer which manifest field carried it.
  local tree1 tree2
  tree1="$(horizon_project_tree "$WORK/run1/$(basename "$SEED_DIR")")"
  tree2="$(horizon_project_tree "$WORK/run2/$(basename "$SEED_DIR")")"
  [ "$tree1" = "$tree2" ] \
    || fail "the two seeded repos committed different trees ($tree1 vs $tree2)"
  pass "both seedings committed the identical git tree ($tree1)"

  # The seeded store is compared against the seed bundle itself. The program is fed in
  # on a quoted heredoc and both inputs arrive as file paths, so shell quoting cannot
  # reach inside it - a single quote in a message would otherwise have closed a
  # `python3 -c '...'` argument and silently handed python a different program.
  horizon_lit_export "$WORK/run1/$(basename "$SEED_DIR")" > "$WORK/run1-export.json" \
    || fail "could not export the seeded backlog"
  # sys.exit, never assert: -O / PYTHONOPTIMIZE compiles asserts out, which would turn
  # this into a silent pass on any input. [LAW:no-silent-failure]
  python3 - "$backlog" "$WORK/run1-export.json" <<'PY' \
    || fail "the seeded backlog does not match the seed bundle"
import json, sys

seed = json.load(open(sys.argv[1]))
export = json.load(open(sys.argv[2]))

live = [i for i in export["issues"] if not i.get("deleted_at")]
by_id = {i["id"]: i for i in live}
# Filtered to live endpoints once, so every by_id lookup below is total. An edge into a
# soft-deleted row would otherwise crash with a traceback that this script's own error
# handling would then report as "the seeded backlog does not match the seed bundle" -
# naming a mismatch that was never detected. [LAW:parse-dont-validate]
relations = [r for r in export["relations"]
             if r.get("src_id") in by_id and r.get("dst_id") in by_id]
parent_of = {r["src_id"]: r["dst_id"]
             for r in relations if r.get("type") == "parent-child"}

# Title is the join column between the seed and the store. A seed that repeated a
# title would make this comparison lie by matching the wrong pair, so it is rejected
# outright rather than resolved arbitrarily.
seed_titles = [d["title"] for d in seed]
if len(set(seed_titles)) != len(seed_titles):
    sys.exit("seed contains duplicate titles; cannot verify it unambiguously")
if len(live) != len(seed):
    sys.exit(f"seeded backlog has {len(live)} issues, seed declares {len(seed)}")

missing = set(seed_titles) - {i["title"] for i in live}
if missing:
    sys.exit(f"seed items missing from the seeded backlog: {sorted(missing)}")

title_of_local = {d["local_id"]: d["title"] for d in seed}

expected_parent = {d["title"]: title_of_local[d["parent"]]
                   for d in seed if d.get("parent")}
actual_parent = {i["title"]: by_id[parent_of[i["id"]]]["title"]
                 for i in live if i["id"] in parent_of}
if expected_parent != actual_parent:
    sys.exit(f"parentage differs.\n  expected: {sorted(expected_parent.items())}"
             f"\n  actual:   {sorted(actual_parent.items())}")

# The seed states an item is blocked BY each entry in depends_on; lit stores that edge
# as src=blocked, dst=blocker. Both sides are reduced to (blocker, blocked) titles.
expected_deps = {(title_of_local[b], d["title"])
                 for d in seed for b in d.get("depends_on", [])}
actual_deps = {(by_id[r["dst_id"]]["title"], by_id[r["src_id"]]["title"])
               for r in relations if r.get("type") == "blocks"}
if expected_deps != actual_deps:
    sys.exit(f"dependency edges differ.\n  missing: {sorted(expected_deps - actual_deps)}"
             f"\n  extra:   {sorted(actual_deps - expected_deps)}")

for d in seed:
    got = next(i for i in live if i["title"] == d["title"])
    for seed_field, store_field in (("type", "issue_type"), ("topic", "topic"),
                                    ("description", "description")):
        if got[store_field] != d[seed_field]:
            sys.exit(f"{d['title']!r}: {seed_field} is {got[store_field]!r}, "
                     f"seed says {d[seed_field]!r}")

print(f"verified {len(seed)} seeded issues and {len(expected_deps)} dependency edges",
      file=sys.stderr)
PY
  pass "the seeded backlog matches the seed bundle (tickets, parentage, blocks edges)"

  # Fresh history means the seeded repo's first commit has no parent - it is a new
  # project, not a branch off some existing history that a later reader could trace
  # back into another repo.
  local project_dir roots remotes
  project_dir="$WORK/run1/$(basename "$SEED_DIR")"
  roots="$(horizon_project_git "$project_dir" rev-list --max-parents=0 HEAD)" \
    || fail "could not list root commits in the seeded repo"
  [ "$(printf '%s\n' "$roots" | wc -l | tr -d ' ')" = "1" ] \
    || fail "seeded repo does not have exactly one root commit: $roots"
  pass "seeded repo has fresh history (a single root commit)"

  remotes="$(horizon_project_git "$project_dir" remote)" \
    || fail "could not list remotes in the seeded repo"
  [ -z "$remotes" ] \
    || fail "seeded repo has a git remote ($remotes); lit init would adopt its backlog"
  pass "seeded repo has no git remote"

  # Every file the seed's repo tree declares must be committed, byte for byte. This is
  # the "contains the spec" half of the ticket's end state, checked against the seed
  # rather than against a count.
  local rel missing=0
  while IFS= read -r rel; do
    if ! horizon_project_git "$project_dir" show "HEAD:$rel" \
         | cmp -s - "$SEED_DIR/$HORIZON_SEED_REPO_SUBDIR/$rel"; then
      printf 'FAIL: seeded repo does not carry %s byte-identically\n' "$rel" >&2
      missing=1
    fi
  done < <(cd "$SEED_DIR/$HORIZON_SEED_REPO_SUBDIR" && find . -type f -print \
             | sed 's|^\./||' | LC_ALL=C sort)
  [ "$missing" -eq 0 ] || fail "the seed's repo tree is not fully present in the commit"
  pass "seeded repo carries the seed's tree byte-identically"

  horizon_log "all checks passed"
}

main "$@"
