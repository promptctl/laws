#!/usr/bin/env bash
# Isolation primitives for driving a real, live, interactive Claude Code TUI over tmux.
#
# THE MODEL (read this before changing anything):
# A single PERSISTENT CLAUDE_CONFIG_DIR that the owner logs into ONCE — an ordinary
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
# [LAW:effects-at-boundaries] Every effect — tmux I/O, file reads, sleeps — is gathered here.
# [LAW:no-silent-failure] Every external call is validated; a bad config dir, or a session
# that never reaches an idle prompt, aborts nonzero — it never falls back to ~/.claude.

set -o pipefail

# ── Configuration knobs (data, not modes) ──────────────────────────────────────────────
# [LAW:dataflow-not-control-flow] Timing/geometry vary as values, never as branches.
ISO_PANE_WIDTH="${ISO_PANE_WIDTH:-200}"
ISO_PANE_HEIGHT="${ISO_PANE_HEIGHT:-50}"
ISO_LAUNCH_TIMEOUT_SECS="${ISO_LAUNCH_TIMEOUT_SECS:-40}"  # boot + trust dialog to settle
ISO_TURN_TIMEOUT_SECS="${ISO_TURN_TIMEOUT_SECS:-90}"      # per-turn generation ceiling
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
# [LAW:no-silent-failure] A missing/unwritable dir aborts — it never silently falls back to
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

# A screen that unambiguously means "this config dir is NOT set up" — first-run onboarding
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
# provisioned isolated config dir, and settle to an idle prompt — clearing the per-directory
# trust dialog on the way. If the screen shows first-run onboarding or a login prompt, the
# dir is not set up: abort loudly pointing at setup, never limp forward.
#
# [LAW:no-ambient-temporal-coupling] "Idle at a prompt" is a state we poll for, not a hoped-
# for consequence of a fixed sleep.
#
# Usage: iso_launch <session_name> <config_dir> <work_dir>
iso_launch() {
  local sess="$1" cfg="$2" wd="$3"
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

  # [LAW:effects-at-boundaries] the launch command is data handed to tmux; %q keeps paths
  # intact. --setting-sources '' is the explicit second latch (see file header).
  local cmd
  printf -v cmd 'cd %q && CLAUDE_CONFIG_DIR=%q claude --model opus --setting-sources '"'"''"'"'' "$wd" "$cfg"
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

# ── Drive one turn ──────────────────────────────────────────────────────────────────────
# Send one prompt, wait for the session to return to idle, and echo the full pane. A one-
# shot probe turn — the simple question/answer this ticket needs, not the general multi-turn
# driver (a later ticket).
#
# [LAW:no-silent-failure] A turn that never begins, never returns to idle within the timeout,
# or comes back with an empty/unchanged screen ABORTS nonzero — it never returns a partial
# capture a caller could mistake for a pass. This is the amplifier guard: one bad turn stops
# the line rather than emitting a corrupt datapoint.
#
# Usage: iso_turn <session> <prompt>   -> prints post-turn pane on stdout
iso_turn() {
  local sess="$1" prompt="$2"
  [ -n "$sess" ] && [ -n "$prompt" ] || iso_die "iso_turn: missing session or prompt"

  local before
  before="$(iso_capture "$sess")"

  tmux send-keys -t "$sess" -l -- "$prompt" || iso_die "iso_turn: send-keys (prompt) failed on $sess"
  sleep 1  # let the TUI register the full literal line before submit
  tmux send-keys -t "$sess" C-m || iso_die "iso_turn: send-keys (submit) failed on $sess"

  # Wait for the turn to actually START (a working indicator appears) before waiting for it
  # to finish — otherwise the previous turn's idle footer reads as instant completion.
  # [LAW:no-ambient-temporal-coupling] the started→idle transition is owned state, not luck.
  local waited=0 cur started=0
  while [ "$waited" -lt "$ISO_TURN_TIMEOUT_SECS" ]; do
    cur="$(iso_capture "$sess")"
    if ! iso_is_idle_frame "$cur"; then started=1; break; fi
    sleep "$ISO_POLL_SECS"; waited=$((waited + ISO_POLL_SECS))
  done
  [ "$started" -eq 1 ] \
    || iso_die "driven turn never began working within ${ISO_TURN_TIMEOUT_SECS}s (prompt did not take) — aborting"

  # Then wait for it to settle back to a stable idle frame.
  local prev=""
  waited=0
  while [ "$waited" -lt "$ISO_TURN_TIMEOUT_SECS" ]; do
    cur="$(iso_capture "$sess")"
    if iso_is_idle_frame "$cur" && [ "$cur" = "$prev" ]; then break; fi
    prev="$cur"
    sleep "$ISO_POLL_SECS"; waited=$((waited + ISO_POLL_SECS))
  done
  [ "$waited" -lt "$ISO_TURN_TIMEOUT_SECS" ] \
    || iso_die "driven turn TIMED OUT after ${ISO_TURN_TIMEOUT_SECS}s (never returned to idle) — aborting rather than emitting a partial datapoint"

  local screen
  screen="$(iso_capture "$sess")"
  [ -n "$screen" ] || iso_die "driven turn produced an EMPTY capture — aborting"
  [ "$screen" != "$before" ] || iso_die "driven turn left the screen unchanged — aborting"

  printf '%s\n' "$screen"
}

# Extract the model's LAST answer from a captured pane. The TUI marks the assistant's reply
# with a leading "⏺" and the user's prompt with "❯"; grade the reply, not the echoed prompt.
# [LAW:one-source-of-truth] the answer region is the one place to read the model's reply.
# Usage: iso_answer "<captured screen>"  -> prints the answer text
iso_answer() {
  printf '%s\n' "$1" | awk '
    { lines[NR] = $0 }
    /^⏺/ { last = NR }
    END {
      if (!last) exit
      for (i = last; i <= NR; i++) {
        if (i > last && lines[i] ~ /^[[:space:]]*❯/) break
        line = lines[i]
        sub(/^⏺[[:space:]]*/, "", line)
        sub(/^[[:space:]]+/, "", line)
        print line
      }
    }
  '
}

# ── Teardown ────────────────────────────────────────────────────────────────────────────
# Kill the tmux session. The persistent config dir is deliberately LEFT INTACT — it holds
# the one-time login and is reused by every future run. There is no materialized secret to
# scrub, because we never create one.
# Usage: iso_teardown <session>
iso_teardown() {
  local sess="$1"
  [ -n "$sess" ] && tmux kill-session -t "$sess" 2>/dev/null || true
  return 0
}
