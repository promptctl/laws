#!/usr/bin/env bash
# Resolve a configuration to its skill body, printed on stdout (empty for the control arm).
# [LAW:cli] exit code is the contract: 0 = resolved (a body, or a deliberate empty for control),
# nonzero = the ref/path did not resolve (never an empty body standing in for a failed lookup).
# Usage: resolve-config.sh <config_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -eq 1 ] || cfg_die "usage: resolve-config.sh <config_dir>"
cfg_resolve "$1"
