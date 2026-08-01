#!/usr/bin/env bash
# THE CRITERION (test-suite shape). Runs with CWD = the repo checkout. Exit 0 = the task
# succeeded (the suite passes), nonzero = it did not. This is ground truth: the repo's OWN tests,
# not a judgment of the work against any skill, law, or rubric.
# Exit codes follow the harness contract: 0 = pass, 1 = the suite genuinely failed, 2 = the
# criterion could NOT run (a missing tool, a broken install) - a harness error, never a fabricated
# FAIL. [LAW:no-silent-failure]
set -euo pipefail

command -v pnpm >/dev/null 2>&1 || { echo "check: pnpm is required to run this task's criterion" >&2; exit 2; }
# Silence install stdout but let its stderr through, so a failure's diagnostic is visible rather
# than swallowed. [LAW:no-silent-failure]
pnpm install --frozen-lockfile >/dev/null || { echo "check: dependency install failed" >&2; exit 2; }
pnpm test   # exits 0 on pass, 1 on test failures - the verdict
