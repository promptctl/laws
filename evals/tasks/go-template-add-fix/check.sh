#!/usr/bin/env bash
# THE CRITERION (test-suite shape). Runs with CWD = the repo checkout. Exit 0 = the task
# succeeded (the suite passes), nonzero = it did not. This is ground truth: the repo's OWN tests,
# not a judgment of the work against any skill, law, or rubric.
# [LAW:no-silent-failure] a broken install aborts nonzero (a conservative FAIL) rather than
# reporting a fabricated pass.
set -euo pipefail

command -v pnpm >/dev/null 2>&1 || { echo "check: pnpm is required to run this task's criterion" >&2; exit 1; }
pnpm install --frozen-lockfile >/dev/null 2>&1 || { echo "check: dependency install failed" >&2; exit 1; }
pnpm test
