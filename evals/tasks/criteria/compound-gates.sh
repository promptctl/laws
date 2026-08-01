#!/usr/bin/env bash
# THE COMPOUND-GATES CRITERION, defined once and shared by every task that scores work with the
# target repo's own full gate set. Runs with CWD = the repo checkout; the task directory is $1
# (each task's check.sh passes its own). Exit 0 = the repo's gates (tests, typecheck, lint) all
# pass AND no existing test or conformance file was modified or deleted. Ground truth throughout:
# the repo's own gates and a mechanical diff against the pinned commit - never a judgment of the
# work against any skill, law, or rubric.
#
# [LAW:one-source-of-truth] two tasks scoring by this same pattern share THIS file - the criterion
#   cannot drift between them. A task with a different criterion writes its own check.sh; this
#   helper is one reusable criterion, not a criterion framework.
# Exit codes follow the harness contract: 0 = pass, 1 = a genuine verdict about the work,
# 2 = the criterion could NOT run - a harness error, never a fabricated FAIL. [LAW:no-silent-failure]
set -euo pipefail

task_dir="${1:-}"
[ -n "$task_dir" ] && [ -d "$task_dir" ] \
  || { echo "check: compound-gates needs the task directory as \$1" >&2; exit 2; }

command -v pnpm >/dev/null 2>&1 || { echo "check: pnpm is required to run this task's criterion" >&2; exit 2; }

# The pinned commit comes from the task's own manifest - the single authority for it, so the
# tests-unchanged diff can never drift from the commit the checkout was prepared at.
# [LAW:one-source-of-truth]
TASK_COMMIT=""
[ -f "$task_dir/manifest.sh" ] || { echo "check: missing manifest.sh in $task_dir" >&2; exit 2; }
# shellcheck disable=SC1091
. "$task_dir/manifest.sh" >/dev/null \
  || { echo "check: manifest.sh failed to source cleanly: $task_dir/manifest.sh" >&2; exit 2; }
[ -n "$TASK_COMMIT" ] || { echo "check: task manifest sets no TASK_COMMIT" >&2; exit 2; }
git cat-file -e "$TASK_COMMIT^{commit}" 2>/dev/null \
  || { echo "check: pinned commit $TASK_COMMIT is not in this checkout" >&2; exit 2; }

# Modifying or deleting an existing test/fixture would let broken work score as done, so it is a
# real FAIL verdict. Newly added test files are legitimate work and pass the M/D filter.
if ! git diff --diff-filter=MD --quiet "$TASK_COMMIT" -- '*.test.ts' test/ conformance/; then
  echo "check: existing test or conformance files were modified or deleted:" >&2
  git diff --diff-filter=MD --name-only "$TASK_COMMIT" -- '*.test.ts' test/ conformance/ >&2
  exit 1
fi

# Silence install stdout but let its stderr through, so a failure's diagnostic is visible rather
# than swallowed. [LAW:no-silent-failure]
pnpm install --frozen-lockfile >/dev/null || { echo "check: dependency install failed" >&2; exit 2; }

# The repo's own gates, each a real verdict on the work.
pnpm test      || { echo "check: test suite failed" >&2; exit 1; }
pnpm typecheck || { echo "check: typecheck failed" >&2; exit 1; }
pnpm lint      || { echo "check: lint failed" >&2; exit 1; }
