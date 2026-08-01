#!/usr/bin/env bash
# ONE-TIME setup: provision the persistent isolated CLAUDE_CONFIG_DIR by logging in.
#
# This is the human step. It launches a real interactive Claude Code TUI in a tmux session
# pointed at the persistent config dir, then hands off to you: you attach, pick the
# subscription login, complete the OAuth in your browser, accept the trust dialog, and
# decline the fullscreen renderer. After that the token lives in your macOS keychain and the
# config dir keeps the account link - reused for weeks. You only do this again if the login
# expires.
#
# Nothing is copied or exported. Auth is obtained the real way: you log in.
# [LAW:cli] Exit codes: 0 = config dir is ready (already set up, or session launched for you
# to complete login); nonzero = the config dir could not be prepared.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

ISO_CONFIG_DIR="${ISO_CONFIG_DIR:-$HOME/.claude-laws-eval}"
ISO_WORK_DIR="${ISO_WORK_DIR:-$HOME/.claude-laws-eval-workdir}"
ISO_SESSION="${ISO_SESSION:-iso-setup}"

iso_config_require "$ISO_CONFIG_DIR"

if iso_config_is_setup "$ISO_CONFIG_DIR"; then
  iso_log "config dir already logged in: $ISO_CONFIG_DIR - nothing to do."
  iso_log "verify it with: $HERE/verify-isolation.sh"
  exit 0
fi

mkdir -p "$ISO_WORK_DIR"
[ -e "$ISO_WORK_DIR/CLAUDE.md" ] && iso_die "working dir has a CLAUDE.md: $ISO_WORK_DIR (would defeat isolation)"

iso_need tmux
iso_need claude
tmux kill-session -t "$ISO_SESSION" 2>/dev/null || true
tmux new-session -d -s "$ISO_SESSION" -x "$ISO_PANE_WIDTH" -y "$ISO_PANE_HEIGHT" \
  || iso_die "tmux could not create session: $ISO_SESSION"

cmd=$(printf 'cd %q && CLAUDE_CONFIG_DIR=%q claude --model opus --setting-sources '"'"''"'"'' "$ISO_WORK_DIR" "$ISO_CONFIG_DIR")
tmux send-keys -t "$ISO_SESSION" "$cmd" C-m

cat >&2 <<EOF

[isolation] one-time login required. A live Claude Code session is running in tmux.
  1. Attach:   tmux attach -t $ISO_SESSION
  2. Choose "Claude account with subscription" and complete the login in your browser.
  3. Accept the trust dialog ("Yes, I trust this folder"); decline the fullscreen renderer.
  4. Detach when you see the prompt:  Ctrl-b d
  5. Confirm:  $HERE/verify-isolation.sh

  config dir: $ISO_CONFIG_DIR   (this is what gets provisioned; leave it in place)
EOF
