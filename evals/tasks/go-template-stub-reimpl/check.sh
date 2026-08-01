#!/usr/bin/env bash
# THE CRITERION (compound engineer-standard shape). Runs with CWD = the repo checkout. Exit 0 =
# the repo's own quality gates (tests, typecheck, lint) all pass AND no existing test or
# conformance file was modified or deleted. Ground truth throughout: the repo's own gates and a
# mechanical diff against the pinned commit - never a judgment of the work against any skill,
# law, or rubric.
# Exit codes follow the harness contract: 0 = pass, 1 = a genuine verdict about the work,
# 2 = the criterion could NOT run - a harness error, never a fabricated FAIL. [LAW:no-silent-failure]
set -euo pipefail

command -v pnpm >/dev/null 2>&1 || { echo "check: pnpm is required to run this task's criterion" >&2; exit 2; }

# The pinned commit comes from the task's own manifest - the single authority for it, so the
# tests-unchanged diff can never drift from the commit the checkout was prepared at.
# [LAW:one-source-of-truth]
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_COMMIT=""
# shellcheck source=manifest.sh
. "$HERE/manifest.sh" >/dev/null
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
