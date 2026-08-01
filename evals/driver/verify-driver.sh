#!/usr/bin/env bash
# Prove the turn driver's contract against a LIVE isolated Opus session. Exit 0 iff every
# claim holds. Each check is a deterministic assertion on drive_turn's stdout and exit code -
# no eyeballing, no "looks right".
#
# The claims (from the ticket's observable done-claim):
#   A. A throwaway prompt returns the session's reply text and exits 0.
#   B. Turns compose: a second turn on the same session returns THAT turn's reply, not the first.
#   C. A slow turn is waited out in full - the driver returns the complete reply (its final
#      end-token is present), never an early partial.
#   D. A turn that never reaches idle within its bound exits nonzero and emits NO reply.
#   E. Killing the session mid-turn exits nonzero and emits NO reply.
#
# [LAW:verifiable-goals] done has a shape and this script is that shape; it runs the checks
#   itself against the real session, it does not ask a human to look.
# [LAW:no-silent-failure] any failed check makes the whole script exit nonzero and say which.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

ISO_CONFIG_DIR="${ISO_CONFIG_DIR:-$HOME/.claude-laws-eval}"
ISO_WORK_DIR="${ISO_WORK_DIR:-$HOME/.claude-laws-eval-workdir}"

fails=0
pass() { printf '  PASS  %s\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

iso_config_require "$ISO_CONFIG_DIR"

# ── Session 1: the clean-completion claims A, B, C, then the timeout claim D ──────────────
S1="verify-drv-clean-$$"
trap 'iso_teardown "$S1"; iso_teardown "${S2:-}"' EXIT
drv_launch "$S1" "$ISO_CONFIG_DIR" "$ISO_WORK_DIR"

# A) throwaway prompt -> non-empty reply, exit 0
if replyA="$(drive_turn "$S1" 'Reply with exactly: banana-ok-4417')" && [ -n "$replyA" ]; then
  case "$replyA" in
    *banana-ok-4417*) pass "A: throwaway turn returned its reply, exit 0" ;;
    *) fail "A: turn returned a reply but not the expected content: [$replyA]" ;;
  esac
else
  fail "A: throwaway turn did not return a non-empty reply at exit 0"
fi

# B) a second turn on the SAME session returns THAT turn's answer (turns compose, no staleness)
if replyB="$(drive_turn "$S1" 'Reply with exactly: cherry-ok-8823')"; then
  case "$replyB" in
    *cherry-ok-8823*)
      case "$replyB" in
        *banana-ok-4417*) fail "B: second turn's reply still carried the first turn's content" ;;
        *) pass "B: second turn returned its own reply, not the first's" ;;
      esac ;;
    *) fail "B: second turn did not return the expected content: [$replyB]" ;;
  esac
else
  fail "B: second turn on the same session did not exit 0"
fi

# C) a slow turn is waited out in full - the end-token only exists at the very end of the reply
CPROMPT='Count from 1 to 25, one number per line, thinking briefly before each. On the very last line write exactly: SLOWDONE-A1B2C3'
if replyC="$(drive_turn "$S1" "$CPROMPT")"; then
  case "$replyC" in
    *SLOWDONE-A1B2C3*) pass "C: slow turn returned the COMPLETE reply (final end-token present)" ;;
    *) fail "C: slow turn returned but the final end-token is missing (returned a partial?): [$replyC]" ;;
  esac
else
  fail "C: slow turn did not exit 0"
fi

# D) a turn that cannot reach idle within its bound -> nonzero, and NOTHING on stdout
outD="$(DRV_TURN_TIMEOUT_SECS=4 drive_turn "$S1" 'Write a detailed 600-word essay about the history of typography. Take your time.' 2>/dev/null)"
rcD=$?
if [ "$rcD" -ne 0 ] && [ -z "$outD" ]; then
  pass "D: turn exceeding its bound exited nonzero ($rcD) and emitted no reply"
else
  fail "D: expected nonzero + empty stdout on a bound-exceeding turn; got rc=$rcD stdout=[$outD]"
fi
iso_teardown "$S1"

# ── Session 2: claim E - kill the session WHILE it is working ─────────────────────────────
S2="verify-drv-kill-$$"
drv_launch "$S2" "$ISO_CONFIG_DIR" "$ISO_WORK_DIR"

# Drive a long turn in the background; once it is genuinely working, kill the session and check
# the driver aborts nonzero with no reply on stdout.
outE_file="$(mktemp)"
( drive_turn "$S2" 'Write a long, careful 800-word essay about the history of the bicycle.' >"$outE_file" 2>/dev/null ) &
drvpid=$!

# Wait until the session is actually working (bounded), then kill it mid-turn.
killed=0 waited=0
while [ "$waited" -lt 60 ]; do
  if drv_frame_working "$(iso_capture "$S2")"; then
    tmux kill-session -t "$S2" 2>/dev/null; killed=1; break
  fi
  sleep 2; waited=$((waited + 2))
done

if [ "$killed" -ne 1 ]; then
  fail "E: session never reached a working state to kill within 60s (cannot test mid-turn kill)"
  kill "$drvpid" 2>/dev/null || true
else
  wait "$drvpid"; rcE=$?
  outE="$(cat "$outE_file")"
  if [ "$rcE" -ne 0 ] && [ -z "$outE" ]; then
    pass "E: session killed mid-turn made the driver exit nonzero ($rcE) with no reply"
  else
    fail "E: expected nonzero + empty stdout on a mid-turn kill; got rc=$rcE stdout=[$outE]"
  fi
fi
rm -f "$outE_file"

# ── Verdict ───────────────────────────────────────────────────────────────────────────────
if [ "$fails" -eq 0 ]; then
  printf '\nDRIVER OK - all checks passed\n' >&2
  exit 0
fi
printf '\nDRIVER FAILED - %d check(s) failed\n' "$fails" >&2
exit 1
