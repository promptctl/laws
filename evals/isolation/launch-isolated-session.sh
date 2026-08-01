#!/usr/bin/env bash
# Launch a ready isolated interactive Claude Code session on subscription Opus and leave it
# idle at a prompt in tmux, for a human to attach to or a script to drive.
#
# Assumes the persistent config dir has already been set up (setup-isolated-session.sh). If
# it has not been logged into, iso_launch aborts and points you at setup — it never falls
# back to the owner's global config.
# [LAW:cli] Exit codes: 0 = launched and idle; nonzero = did not.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

ISO_CONFIG_DIR="${ISO_CONFIG_DIR:-$HOME/.claude-laws-eval}"
ISO_WORK_DIR="${ISO_WORK_DIR:-$HOME/.claude-laws-eval-workdir}"
ISO_SESSION="${ISO_SESSION:-iso-claude-$$}"

iso_config_require "$ISO_CONFIG_DIR"
iso_launch "$ISO_SESSION" "$ISO_CONFIG_DIR" "$ISO_WORK_DIR"

# Handles a caller needs, on stdout (the machine-readable channel); progress went to stderr.
printf 'ISO_SESSION=%s\n' "$ISO_SESSION"
printf 'ISO_CONFIG_DIR=%s\n' "$ISO_CONFIG_DIR"
printf 'ISO_WORK_DIR=%s\n' "$ISO_WORK_DIR"
iso_log "attach with: tmux attach -t $ISO_SESSION   (detach: Ctrl-b d)"
iso_log "teardown with: tmux kill-session -t $ISO_SESSION   (the config dir stays — it holds your login)"
