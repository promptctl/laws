#!/usr/bin/env bash
# The turn driver: exchange turns with a live, isolated, interactive Claude Code TUI over
# tmux, and REFUSE to emit a bad turn. This is the general multi-turn driver the isolation
# ticket deferred; it builds ON isolation's primitives (capture, idle classification, launch)
# and never reaches around them.
#
# THE CONTRACT (read before changing anything):
# drive_turn sends one message and returns the session's reply to THAT message - or it aborts
# nonzero. It never returns a partial read, a stale reply, or an empty string dressed as an
# answer. The whole harness is a loop over this function; one unvalidated bad turn becomes N
# corrupt datapoints and a confidently wrong verdict, so a turn that cannot be completed
# cleanly stops the line here rather than passing rubble downstream.
#
# [LAW:one-way-deps] Dependencies flow driver -> isolation, never back. Isolation stays
#   independently verifiable without this layer; this layer reuses iso_capture / iso_launch /
#   iso_teardown and does not duplicate them.
# [LAW:parse-dont-validate] "The turn is done" is a PARSED state - a non-empty reply block
#   sitting below the prompt we just submitted, on an idle, settled screen - not a transient
#   we race to catch. The completion detector returns the reply text (the stamp), so no caller
#   downstream re-derives it from a raw pane.
# [LAW:no-silent-failure] Every failure arm - dead session, no reply within the bound, an
#   empty capture - aborts nonzero with a located message. None of them returns a string.
# [LAW:effects-at-boundaries] Every tmux read/write and every sleep is gathered in this file
#   and isolation's; the parsers above are pure functions of a captured screen.

set -o pipefail

DRV_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../isolation/lib.sh
source "$DRV_HERE/../isolation/lib.sh"

# ── Configuration knobs (data, not modes) ───────────────────────────────────────────────
# [LAW:dataflow-not-control-flow] Timing varies as values, never as branches.
DRV_TURN_TIMEOUT_SECS="${DRV_TURN_TIMEOUT_SECS:-600}"  # per-turn generation ceiling
DRV_POLL_SECS="${DRV_POLL_SECS:-2}"                    # idle-poll cadence
DRV_SETTLE_POLLS="${DRV_SETTLE_POLLS:-2}"              # consecutive stable reads => rendered
DRV_SEND_SETTLE_SECS="${DRV_SEND_SETTLE_SECS:-1}"      # let a pasted prompt register before submit

# The self-owned "session is working" token. spinnerVerbs.replace pins the active spinner to a
# string WE choose, so working-detection keys off a token we own rather than Anthropic's
# version-dependent verb list. Injected at launch via --settings (see drv_launch).
# [LAW:one-source-of-truth] The sentinel is defined once, here, and both the launch setting and
# the working-detector read it from this one place.
DRV_SPINNER_SENTINEL="${DRV_SPINNER_SENTINEL:-EVALBUSY}"

drv_die() { printf 'ERROR [driver]: %s\n' "$*" >&2; exit 1; }
drv_log() { printf '[driver] %s\n' "$*" >&2; }

# ── History-inclusive capture ───────────────────────────────────────────────────────────
# iso_capture reads only the visible pane; a reply longer than the pane scrolls its head - the
# prompt line the reply parser anchors on - out of view, and the parser then finds nothing and
# the turn times out. This captures the full retained scrollback (`-S -`), so the whole reply,
# head included, is present regardless of length. Retention is bounded by the session's
# history-limit, set generously at launch (ISO_HISTORY_LIMIT).
# The footer/idle-detection tokens still sit at the live bottom of this capture, and the TUI
# redraws the footer in place rather than scrolling it, so no stale "working" footer accumulates
# in history - idle/working classification reads the same on a full capture as on a visible one.
# [LAW:effects-at-boundaries] the one place the driver reads the screen for a turn.
# Usage: drv_capture <session>
drv_capture() {
  tmux capture-pane -t "$1" -p -S - 2>/dev/null
}

# ── Frame classification (pure functions of a captured screen) ──────────────────────────
# WORKING: the interrupt affordance is on screen, or our spinner sentinel is. The interrupt
# line is present on every generating frame; the sentinel flickers with tips, so it is an
# OR-companion, not the sole signal. Either one present => the session is mid-turn.
# [LAW:types-are-the-program] working-ness is derived from on-screen state, never elapsed time.
drv_frame_working() {
  case "$1" in
    *"esc to interrupt"*|*"Esc to interrupt"*|*"${DRV_SPINNER_SENTINEL}…"*) return 0 ;;
  esac
  return 1
}

# IDLE: the shortcuts footer is present and nothing signals active work.
drv_frame_idle() {
  drv_frame_working "$1" && return 1
  case "$1" in
    *"? for shortcuts"*) return 0 ;;
  esac
  return 1
}

# The transcript is everything ABOVE the input box. The input box is a "❯ " line sandwiched
# between the last two horizontal rule lines near the bottom; its own "❯" must not be read as
# a submitted prompt, and any ghost-suggestion text inside it must not be read as a reply.
# This trims the pane to the transcript so the reply parser cannot see the input box.
# [LAW:parse-dont-validate] one place turns a raw pane into the transcript region.
drv_transcript() {
  printf '%s' "$1" | awk '
    /^────+/ { rule[++nr] = NR }               # remember every rule-line position
    { line[NR] = $0; last = NR }
    END {
      # The input box sits between the last two rule lines. Cut just above the first of them.
      cut = last
      if (nr >= 2) cut = rule[nr-1] - 1
      for (i = 1; i <= cut; i++) print line[i]
    }
  '
}

# The reply to the CURRENT turn: the assistant block (leading "⏺") that follows the LAST
# prompt line (leading "❯") in the transcript, with the trailing completion stamp
# ("✻ <verb> for <N>s") and blank padding removed. Empty while generation has not yet produced
# a reply below our prompt - which is exactly how pre-work idle is told apart from done.
# The previous turn's reply sits ABOVE our prompt and is structurally excluded.
# [LAW:one-source-of-truth] the sole reader of "what did the model just answer".
drv_reply_below_prompt() {
  drv_transcript "$1" | awk '
    { line[NR] = $0 }
    /^❯/ { lastprompt = NR }
    END {
      if (!lastprompt) exit
      # find the first "⏺" strictly after the last prompt
      rs = 0
      for (i = lastprompt + 1; i <= NR; i++) if (line[i] ~ /^⏺/) { rs = i; break }
      if (!rs) exit
      for (i = rs; i <= NR; i++) {
        l = line[i]
        if (l ~ /^✻ .* for [0-9]/) break   # completion stamp => reply ended
        if (l ~ /^❯/) break                # next prompt => reply ended
        sub(/^⏺[[:space:]]*/, "", l)
        out[++n] = l
      }
      # trim trailing blank lines
      while (n > 0 && out[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print out[i]
    }
  '
}

# ── Session launch with the sentinel injected ───────────────────────────────────────────
# Reuse isolation's launch (the single owner of the launch command) and add ONE setting: the
# pinned spinner sentinel, passed as a --settings JSON string. This does not reintroduce the
# config dir's settings, plugins, hooks, or CLAUDE.md - --settings is an explicit, additive
# JSON blob independent of --setting-sources, so ticket .1's isolation holds.
# [LAW:one-source-of-truth] iso_launch stays the only place that builds the claude command; we
# hand it the extra setting as its 4th positional argument (no ambient env that could leak into
# a later launch).
# Usage: drv_launch <session> <config_dir> <work_dir>
drv_launch() {
  local sess="$1" cfg="$2" wd="$3"
  # [LAW:parse-dont-validate] The sentinel is interpolated into a JSON string; a value carrying
  # a quote or backslash would corrupt it and claude would reject --settings, silently leaving
  # the session with no working token. Reject anything but a plain alphanumeric token here, at
  # the boundary where the env value enters.
  case "$DRV_SPINNER_SENTINEL" in
    ''|*[!A-Za-z0-9]*) drv_die "DRV_SPINNER_SENTINEL must be a non-empty alphanumeric token: got [$DRV_SPINNER_SENTINEL]" ;;
  esac
  iso_launch "$sess" "$cfg" "$wd" \
    "{\"spinnerVerbs\":{\"mode\":\"replace\",\"verbs\":[\"${DRV_SPINNER_SENTINEL}\"]}}"
}

# ── Send one prompt (bracketed paste, then explicit submit) ─────────────────────────────
# Bracketed paste keeps a multi-line prompt intact in the input box; embedded newlines do NOT
# submit it. Submission is a single, separate Enter. We confirm the paste registered (the box
# reflects a distinctive head of the prompt) before submitting, so a send that silently failed
# aborts here instead of Entering an empty prompt.
# [LAW:no-ambient-temporal-coupling] submit is an explicit owned event, not a newline artifact.
# Usage: drv_send <session> <prompt>
drv_send() {
  local sess="$1" prompt="$2"
  [ -n "$sess" ] && [ -n "$prompt" ] || drv_die "drv_send: missing session or prompt"

  # Capture the screen BEFORE the paste so we can prove the paste landed - a paste that
  # registered nothing leaves the screen unchanged, and we must not then submit stale/empty
  # input as if it were the prompt. [LAW:no-silent-failure] the confirm is the whole point.
  local before
  before="$(iso_capture "$sess")"

  printf '%s' "$prompt" | tmux load-buffer - 2>/dev/null \
    || drv_die "drv_send: could not load prompt into a tmux buffer"
  tmux paste-buffer -t "$sess" -p 2>/dev/null \
    || drv_die "drv_send: paste-buffer failed on $sess (session gone?)"
  sleep "$DRV_SEND_SETTLE_SECS"

  local after
  after="$(iso_capture "$sess")"
  # Universal confirm: the paste must have changed the screen. Holds for ANY prompt, including
  # ones that begin with a symbol or emoji (where a leading-alnum needle would be empty).
  [ "$after" != "$before" ] \
    || drv_die "drv_send: paste did not register on $sess (screen unchanged - send failed)"
  # Stronger confirm when a safe needle exists: the input box actually shows our text, not some
  # unrelated redraw. Use the first non-blank line's leading run of word/space chars.
  local head
  head="$(printf '%s' "$prompt" | sed -n '1p' | grep -oE '^[[:alnum:] ]+' | head -c 40)"
  if [ -n "$head" ]; then
    case "$after" in
      *"$head"*) : ;;
      *) drv_die "drv_send: prompt did not register in the input box on $sess (send failed)" ;;
    esac
  fi

  tmux send-keys -t "$sess" C-m 2>/dev/null \
    || drv_die "drv_send: submit (Enter) failed on $sess (session gone?)"
}

# ── Drive one turn ──────────────────────────────────────────────────────────────────────
# Send one message, wait until the session has produced a complete reply to it and settled to
# idle, and print that reply. Abort nonzero - emitting NO reply - on a dead session, a turn
# that never completes within the bound, or an empty result.
# [LAW:no-silent-failure] every arm below that is not the clean success prints to stderr and
#   exits nonzero; none returns a string.
# Usage: drive_turn <session> <prompt>   -> prints the reply on stdout, exit 0
drive_turn() {
  local sess="$1" prompt="$2"
  [ -n "$sess" ] && [ -n "$prompt" ] || drv_die "drive_turn: missing session or prompt"
  tmux has-session -t "$sess" 2>/dev/null || drv_die "drive_turn: session is not alive: $sess"

  drv_send "$sess" "$prompt"

  # Wait for completion: an idle, settled screen whose reply-below-our-prompt is non-empty and
  # unchanged across DRV_SETTLE_POLLS reads. Reset the settle counter whenever the screen is
  # working or the reply is still empty (pre-work idle), so neither can be mistaken for done.
  local waited=0 reply="" prev="" stable=0 cur curreply
  while [ "$waited" -lt "$DRV_TURN_TIMEOUT_SECS" ]; do
    tmux has-session -t "$sess" 2>/dev/null \
      || drv_die "drive_turn: session died mid-turn: $sess (no reply emitted)"
    # History-inclusive capture: a reply longer than the visible pane keeps its prompt anchor and
    # head in scrollback, so the parser can still find and return the whole reply.
    cur="$(drv_capture "$sess")"
    # A live session's pane always carries at least the footer, so an empty capture is a real
    # failure, not a slow turn. Surface it with the precise cause instead of spinning to a
    # misleading timeout. [LAW:no-silent-failure] (also closes the has-session/capture TOCTOU:
    # a session that died in between lands here and is reported as a death, not a capture fault.)
    if [ -z "$cur" ]; then
      tmux has-session -t "$sess" 2>/dev/null \
        || drv_die "drive_turn: session died mid-turn: $sess (no reply emitted)"
      drv_die "drive_turn: screen capture returned empty on a live session: $sess (tmux capture-pane failed) - aborting rather than spinning to a misleading timeout"
    fi
    if drv_frame_idle "$cur"; then
      curreply="$(drv_reply_below_prompt "$cur")"
      if [ -n "$curreply" ] && [ "$curreply" = "$prev" ]; then
        stable=$((stable + 1))
        if [ "$stable" -ge "$DRV_SETTLE_POLLS" ]; then reply="$curreply"; break; fi
      else
        stable=0
      fi
      prev="$curreply"
    else
      stable=0; prev=""
    fi
    sleep "$DRV_POLL_SECS"; waited=$((waited + DRV_POLL_SECS))
  done

  [ -n "$reply" ] \
    || drv_die "drive_turn: no complete reply within ${DRV_TURN_TIMEOUT_SECS}s on $sess (aborting rather than emitting a partial or empty datapoint)"
  printf '%s\n' "$reply"
}
