#!/usr/bin/env bash
# Isolation primitives for driving a real, live, interactive Claude Code TUI over tmux.
#
# THE MODEL (read this before changing anything):
# A single PERSISTENT CLAUDE_CONFIG_DIR that the owner logs into ONCE - an ordinary
# interactive subscription OAuth login. The token then lives in the macOS keychain and is
# reused for weeks; the config dir keeps the account link and a theme. That is all setup-
# isolated-session.sh does. Nothing here copies an identity file or exports a keychain
# token; auth is obtained the real way, by the owner logging in.
#
# Isolation is STRUCTURAL, not something we interrogate the agent to discover. The owner's
# global ~/.claude/CLAUDE.md, settings.json, and the laws-plugin router hooks live under the
# DEFAULT ~/.claude directory. This config dir is a different directory, so those files are
# not on its search path and cannot load. To see the isolation you read the dir, you do not
# quiz the model. (--setting-sources '' is kept as an explicit second latch so no project/
# local settings from the working dir load either.)
#
# [LAW:no-shared-mutable-globals] The tmux session and working dir are shared mutable state;
# this file is their single owner with an explicit API. The persistent config dir is owned
# by the one-time setup, not by any run.
# [LAW:effects-at-boundaries] Every effect - tmux I/O, file reads, sleeps - is gathered here.
# [LAW:no-silent-failure] Every external call is validated; a bad config dir, or a session
# that never reaches an idle prompt, aborts nonzero - it never falls back to ~/.claude.

set -o pipefail

# ── Configuration knobs (data, not modes) ──────────────────────────────────────────────
# [LAW:dataflow-not-control-flow] Timing/geometry vary as values, never as branches.
# [LAW:one-source-of-truth] The persistent config dir and the clean working dir have ONE set
# of defaults, here, in the file every isolation and driver script sources. Callers may
# override via env, but no script redefines the fallback - divergent copies could silently
# drift and point two scripts at two different dirs.
: "${ISO_CONFIG_DIR:=$HOME/.claude-laws-eval}"
: "${ISO_WORK_DIR:=$HOME/.claude-laws-eval-workdir}"
ISO_PANE_WIDTH="${ISO_PANE_WIDTH:-200}"
ISO_PANE_HEIGHT="${ISO_PANE_HEIGHT:-50}"
# Scrollback retention. A reply longer than the visible pane scrolls its head - including the
# prompt line a reader anchors on - out of the visible frame; tmux keeps it in history up to
# this many lines. Must exceed the longest single turn's line count, or that head is lost.
ISO_HISTORY_LIMIT="${ISO_HISTORY_LIMIT:-100000}"
ISO_LAUNCH_TIMEOUT_SECS="${ISO_LAUNCH_TIMEOUT_SECS:-40}"  # boot + trust dialog to settle
ISO_POLL_SECS="${ISO_POLL_SECS:-2}"                       # idle-poll cadence

# ── Small utilities ─────────────────────────────────────────────────────────────────────
iso_die() { printf 'ERROR [isolation]: %s\n' "$*" >&2; exit 1; }
iso_log() { printf '[isolation] %s\n' "$*" >&2; }

iso_need() {
  # Assert a command exists on PATH. [LAW:no-silent-failure]
  command -v "$1" >/dev/null 2>&1 || iso_die "required command not found: $1"
}

# ── Config-dir requirement ──────────────────────────────────────────────────────────────
# Ensure the persistent CLAUDE_CONFIG_DIR exists and is writable, or abort. There is no
# credential handling here by design: the dir is provisioned once by setup-isolated-
# session.sh (the owner logs in), and every run thereafter just uses it.
# [LAW:no-silent-failure] A missing/unwritable dir aborts - it never silently falls back to
# the owner's global ~/.claude, which would defeat the isolation entirely.
# Usage: iso_config_require <config_dir>
iso_config_require() {
  local cfg="$1"
  [ -n "$cfg" ] || iso_die "iso_config_require: config dir path is empty"
  if ! mkdir -p "$cfg" 2>/dev/null; then
    iso_die "CLAUDE_CONFIG_DIR could not be created: $cfg (refusing to fall back to global config)"
  fi
  [ -w "$cfg" ] || iso_die "CLAUDE_CONFIG_DIR is not writable: $cfg (refusing to fall back to global config)"
}

# Has this config dir completed the one-time login? Reads the account link the login writes.
# This is a readiness check on our own throwaway dir, not a probe of the owner's global data.
# Usage: iso_config_is_setup <config_dir>  -> exit 0 if logged in
iso_config_is_setup() {
  local cfg="$1"
  [ -f "$cfg/.claude.json" ] || return 1
  iso_need python3
  python3 - "$cfg/.claude.json" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get("oauthAccount") else 1)
PY
}

# ── Screen capture & frame classification ───────────────────────────────────────────────
# [LAW:effects-at-boundaries] the one place we read the screen.
iso_capture() {
  local sess="$1"
  tmux capture-pane -t "$sess" -p 2>/dev/null
}

# A screen that unambiguously means "this config dir is NOT set up" - first-run onboarding
# or a login prompt. If we see any of these on a run that expected a ready dir, we abort and
# tell the owner to run setup, rather than drive a half-provisioned session.
iso_screen_needs_setup() {
  case "$1" in
    *"Select login method"*|*"Paste code here"*|*"Log in with"*|*"Not logged in"* \
      |*"Choose the text style"*|*"sign in"*) return 0 ;;
  esac
  return 1
}

# A dismissable "press Enter to move on" interstitial (trust dialog, login-success notice,
# security notice). These are expected and we clear them with Enter.
iso_screen_is_enter_gate() {
  case "$1" in
    *"trust this folder"*|*"Press Enter to continue"*|*"Yes, I trust this folder"*) return 0 ;;
  esac
  return 1
}

# The idle prompt frame: the shortcuts footer is present and no active-work indicator is.
# [LAW:types-are-the-program] idle-ness is derived from on-screen state, not elapsed time.
iso_is_idle_frame() {
  case "$1" in
    *"esc to interrupt"*|*"Esc to interrupt"*|*"to interrupt"*) return 1 ;;
  esac
  case "$1" in
    *"? for shortcuts"*) return 0 ;;
  esac
  return 1
}

# ── Session launch (steady state) ───────────────────────────────────────────────────────
# Launch the interactive Claude Code TUI on Opus, in a clean working dir, with the already-
# provisioned isolated config dir, and settle to an idle prompt - clearing the per-directory
# trust dialog on the way. If the screen shows first-run onboarding or a login prompt, the
# dir is not set up: abort loudly pointing at setup, never limp forward.
#
# [LAW:no-ambient-temporal-coupling] "Idle at a prompt" is a state we poll for, not a hoped-
# for consequence of a fixed sleep.
#
# The 4th argument (optional) is a JSON string appended as `--settings <json>`. --settings is
# an explicit, additive blob independent of --setting-sources, so it does NOT reintroduce the
# config dir's settings, plugins, hooks, or CLAUDE.md - the isolation holds. It is a positional
# parameter, not an ambient env var, so it cannot leak from one launch into the next.
# [LAW:no-ambient-temporal-coupling] the extra settings flow in as an argument each call; there
# is no shell state that a later plain launch could inherit.
#
# Usage: iso_launch <session_name> <config_dir> <work_dir> [extra_settings_json]
iso_launch() {
  local sess="$1" cfg="$2" wd="$3" extra="${4:-}"
  [ -n "$sess" ] && [ -n "$cfg" ] && [ -n "$wd" ] || iso_die "iso_launch: missing session/config/work dir"
  iso_need tmux
  iso_need claude

  mkdir -p "$wd" 2>/dev/null || iso_die "could not create working dir: $wd"
  # A clean working dir must carry no project CLAUDE.md, or a project-scoped router hook
  # could fire from it and defeat the isolation.
  [ -e "$wd/CLAUDE.md" ] && iso_die "working dir already has a CLAUDE.md: $wd (would defeat isolation)"

  # A prior session under this name is irrelevant; new-session below fails if the name is
  # still taken, which is the only condition that matters. [LAW:no-silent-failure] exception.
  tmux kill-session -t "$sess" 2>/dev/null || true
  tmux new-session -d -s "$sess" -x "$ISO_PANE_WIDTH" -y "$ISO_PANE_HEIGHT" \
    || iso_die "tmux could not create session: $sess"
  # Set scrollback retention before the TUI produces any output, so a long reply's scrolled-off
  # head stays in history and a full-history capture can recover it. [LAW:no-silent-failure]
  tmux set-option -t "$sess" history-limit "$ISO_HISTORY_LIMIT" \
    || iso_die "tmux could not set history-limit on session: $sess"

  # [LAW:effects-at-boundaries] the launch command is data handed to tmux; %q keeps paths and
  # the settings JSON intact. --setting-sources '' is the explicit second latch (see header);
  # --settings is appended only when a caller provided one.
  local cmd
  printf -v cmd 'cd %q && CLAUDE_CONFIG_DIR=%q claude --model opus --setting-sources '"'"''"'"'' "$wd" "$cfg"
  [ -n "$extra" ] && printf -v cmd '%s --settings %q' "$cmd" "$extra"
  tmux send-keys -t "$sess" "$cmd" C-m

  # Settle loop: clear Enter-gates, refuse if setup is needed, return on a stable idle frame.
  local waited=0 screen prev=""
  while [ "$waited" -lt "$ISO_LAUNCH_TIMEOUT_SECS" ]; do
    screen="$(iso_capture "$sess")"
    if iso_screen_needs_setup "$screen"; then
      iso_die "isolated config dir is not logged in / not fully set up: $cfg
  run the one-time setup and log in:  $(dirname "${BASH_SOURCE[0]}")/setup-isolated-session.sh
  (refusing to drive a half-provisioned session)"
    fi
    if iso_screen_is_enter_gate "$screen"; then
      tmux send-keys -t "$sess" C-m
      prev=""; sleep "$ISO_POLL_SECS"; waited=$((waited + ISO_POLL_SECS)); continue
    fi
    if iso_is_idle_frame "$screen" && [ "$screen" = "$prev" ]; then
      iso_log "session launched and idle at prompt: $sess"
      return 0
    fi
    prev="$screen"
    sleep "$ISO_POLL_SECS"; waited=$((waited + ISO_POLL_SECS))
  done
  iso_die "session never reached an idle prompt within ${ISO_LAUNCH_TIMEOUT_SECS}s: $sess"
}

# Driving turns is the driver layer's job (evals/driver, drive_turn). Isolation deliberately
# holds no turn-driver of its own: nothing here needs to quiz the model. The one behavioral
# property - which model the session runs - is read from the account banner the TUI paints
# (see verify-isolation.sh), because a model's own answer about its identity is exactly the
# thing it can misstate.

# ── Teardown ────────────────────────────────────────────────────────────────────────────
# Kill the tmux session. The persistent config dir is deliberately LEFT INTACT - it holds
# the one-time login and is reused by every future run. There is no materialized secret to
# scrub, because we never create one.
# Usage: iso_teardown <session>
iso_teardown() {
  local sess="$1"
  [ -n "$sess" ] && tmux kill-session -t "$sess" 2>/dev/null || true
  return 0
}
