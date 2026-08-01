#!/usr/bin/env bash
# THE CRITERION: the shared compound-gates criterion (tests + typecheck + lint + tests-unchanged
# diff detector), defined once in ../criteria/compound-gates.sh and handed this task's directory
# so it reads the pinned commit from this task's own manifest. [LAW:one-source-of-truth]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/../criteria/compound-gates.sh" "$HERE"
