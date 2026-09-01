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
#   5. Time zero does not depend on the operator. Criterion 1 cannot see this: both of
#      its seedings read one environment and agree with each other whatever it says. So
#      the seed is built once more under an environment exporting GIT_AUTHOR_NAME and
#      its siblings - which git ranks above `user.name` from any config source - and the
#      commit sha must be unmoved.
#   6. A malformed seed is refused rather than absorbed. Criteria 1-5 all describe what a
#      GOOD seed produces, and would pass just as happily on a pipeline that quietly
#      accepted a broken one. Each of these is built deliberately and required to fail:
#      a dangling `parent`, a dangling `depends_on`, a repeated `local_id`, and a `repo/`
#      tree carrying its own `.git` (which would be merge-copied over the project's).
#      This criterion is also what keeps criterion 2 honest - the comparison there
#      follows the seed's local_id graph without checking it, because `lit import` will
#      not accept a seed where those references dangle, and that is asserted here rather
#      than assumed of a binary this repo does not build.
#   7. Nothing a seed ships gets to execute: a `post-commit` file in the seed's `repo/`
#      tree is ordinary content, so seeding must succeed and the hook must never run.
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
  horizon_need_base
  horizon_need git
  horizon_need lit
  horizon_need python3
  # Invoked directly by the checks below; named here so a missing one fails with this
  # instrument's own error rather than a bare "command not found".
  horizon_need diff
  horizon_need cmp
  horizon_need sed
  horizon_need wc

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

  # Read back from the manifest seed-run.sh wrote, never recomputed from $SEED_DIR:
  # seed-run.sh resolves the seed to an absolute path before taking its basename, so a
  # `basename "$SEED_DIR"` here disagrees with it for inputs like `.` or `..` and would
  # point every check below at a directory that is not the project. The two manifests
  # were just proven identical, so run1's answer is the answer. [LAW:one-source-of-truth]
  local project_name run1_project run2_project
  project_name="$(python3 - "$WORK/run1/seed-manifest.json" <<'PY'
import json, sys
name = json.load(open(sys.argv[1]))["project"]["name"]
if not name or "/" in name or name in (".", ".."):
    sys.exit(f"manifest records an unusable project name: {name!r}")
print(name)
PY
)" || fail "could not read the project name from seed-manifest.json"
  run1_project="$WORK/run1/$project_name"
  run2_project="$WORK/run2/$project_name"

  # The manifest's tree_sha is the committed files' identity, so an identical manifest
  # already proves "same files". Stated separately because that is the ticket's wording
  # and a reader should not have to infer which manifest field carried it.
  local tree1 tree2
  tree1="$(horizon_project_tree "$run1_project")"
  tree2="$(horizon_project_tree "$run2_project")"
  [ "$tree1" = "$tree2" ] \
    || fail "the two seeded repos committed different trees ($tree1 vs $tree2)"
  pass "both seedings committed the identical git tree ($tree1)"

  # The seeded store is compared against the seed bundle itself. The program is fed in
  # on a quoted heredoc and both inputs arrive as file paths, so shell quoting cannot
  # reach inside it - a single quote in a message would otherwise have closed a
  # `python3 -c '...'` argument and silently handed python a different program.
  horizon_lit_export "$run1_project" > "$WORK/run1-export.json" \
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

# Total without a check of its own: this runs only on a seed `lit import` already
# accepted (seeding precedes the comparison), and lit rejects a dangling parent, a
# dangling depends_on, and a duplicate local_id outright. Re-checking here would be a
# second enforcer of lit's own invariant, free to drift from it. [LAW:single-enforcer]
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
  local roots remotes
  roots="$(horizon_project_git "$run1_project" rev-list --max-parents=0 HEAD)" \
    || fail "could not list root commits in the seeded repo"
  [ "$(printf '%s\n' "$roots" | wc -l | tr -d ' ')" = "1" ] \
    || fail "seeded repo does not have exactly one root commit: $roots"
  pass "seeded repo has fresh history (a single root commit)"

  remotes="$(horizon_project_git "$run1_project" remote)" \
    || fail "could not list remotes in the seeded repo"
  [ -z "$remotes" ] \
    || fail "seeded repo has a git remote ($remotes); lit init would adopt its backlog"
  pass "seeded repo has no git remote"

  # Every file the seed's repo tree declares must be committed, byte for byte. This is
  # the "contains the spec" half of the ticket's end state, checked against the seed
  # rather than against a count.
  local rel missing=0
  while IFS= read -r rel; do
    if ! horizon_project_git "$run1_project" show "HEAD:$rel" \
         | cmp -s - "$SEED_DIR/$HORIZON_SEED_REPO_SUBDIR/$rel"; then
      printf 'FAIL: seeded repo does not carry %s byte-identically\n' "$rel" >&2
      missing=1
    fi
  done < <(cd "$SEED_DIR/$HORIZON_SEED_REPO_SUBDIR" && find . -type f -print \
             | sed 's|^\./||' | LC_ALL=C sort)
  [ "$missing" -eq 0 ] || fail "the seed's repo tree is not fully present in the commit"
  pass "seeded repo carries the seed's tree byte-identically"

  # Seeding twice on one machine cannot show whether the commit identity is actually
  # pinned: both runs read the same environment and agree with each other whatever it
  # says. git ranks GIT_AUTHOR_NAME and its siblings above user.name from every config
  # source, `-c` included, so only a seeding run against an environment that tries to
  # override the identity proves the pin holds - and an unpinned identity moves the
  # commit sha, making time zero differ per operator. [LAW:verifiable-goals]
  local hostile_head expected_head
  GIT_AUTHOR_NAME="operator" GIT_AUTHOR_EMAIL="operator@elsewhere.invalid" \
  GIT_COMMITTER_NAME="operator" GIT_COMMITTER_EMAIL="operator@elsewhere.invalid" \
    "$SCRIPT_DIR/seed-run.sh" "$WORK/hostile" "$SEED_DIR" >/dev/null 2>&1 \
    || fail "seeding under an overriding git identity environment failed"
  hostile_head="$(horizon_project_head "$WORK/hostile/$project_name")" \
    || fail "could not read HEAD of the hostile-environment seeding"
  expected_head="$(horizon_project_head "$run1_project")" \
    || fail "could not read HEAD of the seeded repo"
  [ "$hostile_head" = "$expected_head" ] \
    || fail "an exported git identity changed the seed commit ($hostile_head vs $expected_head); time zero would differ per operator"
  pass "an exported git identity does not change the seed commit"

  # The comparison above indexes the seed's own local_id graph directly, which is total
  # only because `lit import` refuses a seed whose references do not resolve - and that
  # is a claim about a binary this repo does not build. Asserted here rather than
  # trusted: if lit ever accepts one of these, this fails by name and says that the
  # lookups now need a guard of their own. [LAW:verifiable-goals]
  local case_name
  for case_name in dangling-parent dangling-depends-on duplicate-local-id; do
    if seed_is_refused "$case_name"; then
      pass "a seed with a $case_name reference is refused by the pipeline"
    else
      fail "a seed with a $case_name reference was ACCEPTED; verify-seed's local_id lookups are no longer total and now need an explicit check"
    fi
  done

  # A seed whose repo/ tree carries its own .git would be merge-copied over the freshly
  # initialised one, and a commit hook shipped in that tree must never execute. Both are
  # refusals the seed boundary owes; asserted rather than assumed. [LAW:verifiable-goals]
  if bundle_is_refused git-dir-in-repo; then
    pass "a seed whose repo/ tree carries a .git entry is refused"
  else
    fail "a seed carrying repo/.git was ACCEPTED; it would overwrite the seeded project's own git dir"
  fi

  local hook_marker="$WORK/seed-hook-fired"
  if bundle_is_refused vendored-post-commit-hook "$hook_marker"; then
    fail "seeding a bundle that merely contains a post-commit file failed; the file is ordinary content and must not stop a seeding"
  fi
  [ ! -e "$hook_marker" ] \
    || fail "a post-commit file shipped in the seed's repo/ tree executed during seeding"
  pass "a post-commit file shipped in a seed does not execute"

  horizon_log "all checks passed"
}

# Usage: bundle_is_refused <case> [marker_path]  -> 0 when seeding the bundle fails
#
# Builds a corrupted repo/ tree rather than a corrupted backlog, so it is a sibling of
# seed_is_refused rather than a mode inside it.
bundle_is_refused() {
  local case_name="$1"
  local marker="${2:-}"
  local bad="$WORK/badtree-$case_name"
  cp -R "$SEED_DIR" "$bad" || fail "could not copy the seed for the $case_name case"
  case "$case_name" in
    git-dir-in-repo)
      mkdir -p "$bad/$HORIZON_SEED_REPO_SUBDIR/.git" \
        || fail "could not build the $case_name case"
      printf 'CLOBBERED\n' > "$bad/$HORIZON_SEED_REPO_SUBDIR/.git/HEAD" \
        || fail "could not build the $case_name case"
      ;;
    vendored-post-commit-hook)
      printf '#!/bin/sh\ntouch %s\n' "$marker" \
        > "$bad/$HORIZON_SEED_REPO_SUBDIR/post-commit" \
        || fail "could not build the $case_name case"
      chmod +x "$bad/$HORIZON_SEED_REPO_SUBDIR/post-commit" \
        || fail "could not build the $case_name case"
      ;;
    *) fail "unknown bundle case: $case_name" ;;
  esac
  ! "$SCRIPT_DIR/seed-run.sh" "$WORK/refused-$case_name" "$bad" >/dev/null 2>&1
}

# Usage: seed_is_refused <case>  -> 0 when seeding the corrupted seed fails
#
# Corrupts one reference in a throwaway copy of the seed and seeds from it. Returns the
# refusal as a value for the caller to assert on, rather than aborting here, so a seed
# that is wrongly ACCEPTED is reported as this check's own failure.
seed_is_refused() {
  local case_name="$1"
  local bad="$WORK/bad-$case_name"
  cp -R "$SEED_DIR" "$bad" || fail "could not copy the seed for the $case_name case"
  python3 - "$bad/$HORIZON_SEED_BACKLOG_FILE" "$case_name" <<'PY' \
    || fail "could not build the $case_name case"
import json, sys

path, case = sys.argv[1], sys.argv[2]
seed = json.load(open(path))

if case == "dangling-parent":
    entry = next(d for d in seed if d.get("parent"))
    entry["parent"] = "no-such-local-id"
elif case == "dangling-depends-on":
    entry = next(d for d in seed if d.get("depends_on"))
    entry["depends_on"] = ["no-such-local-id"]
elif case == "duplicate-local-id":
    seed[-1]["local_id"] = seed[0]["local_id"]
else:
    sys.exit(f"unknown case: {case}")

json.dump(seed, open(path, "w"), indent=2)
PY
  ! "$SCRIPT_DIR/seed-run.sh" "$WORK/refused-$case_name" "$bad" >/dev/null 2>&1
}

main "$@"
