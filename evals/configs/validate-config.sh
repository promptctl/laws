#!/usr/bin/env bash
# Validate a configuration directory against the format. Exit 0 iff well-formed.
# [LAW:cli] exit code is the contract: 0 = valid, nonzero = the first violation (named on stderr).
# Usage: validate-config.sh <config_dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

[ "$#" -eq 1 ] || cfg_die "usage: validate-config.sh <config_dir>"
cfg_validate "$1"
printf 'VALID: %s\n' "$1"
