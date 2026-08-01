#!/usr/bin/env bash
# Verify the isolated session is what it claims: subscription Opus, with none of the owner's
# global guidance able to load, and no silent fallback to the global config. Exits 0 only if
# every check passes.
#
# How each property is actually checked - and why:
#   Isolation is STRUCTURAL. The owner's ~/.claude/CLAUDE.md, settings.json, and the laws-
#   plugin router hooks live under the DEFAULT ~/.claude dir. We point CLAUDE_CONFIG_DIR at a
#   DIFFERENT dir, so they are not on the search path. We prove that by reading the config
#   dir - it is not ~/.claude, it holds no CLAUDE.md, and its settings enable no plugins or
#   hooks. We do NOT quiz the model with trick questions to "discover" a leak: a config dir
#   with no guidance in it cannot serve guidance, and that is a fact about the filesystem,
#   not about the model's answers.
#   Model + auth ARE behavioral - whether the live session actually came up as Opus on the
#   subscription can only be seen by launching it and asking. That one check runs live.
#
# [LAW:no-silent-failure] A bad config dir aborts nonzero; the live turn aborts nonzero on a
# timeout/empty turn - no check can be faked into a pass.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

# ISO_CONFIG_DIR / ISO_WORK_DIR default in lib.sh (sourced above), its single owner.
ISO_SESSION="${ISO_SESSION:-iso-verify-$$}"
GLOBAL_CONFIG_DIR="${CLAUDE_CONFIG_DIR_DEFAULT:-$HOME/.claude}"

PASS=0 FAIL=0
report() {  # report <label> <ok|fail> <detail>
  if [ "$2" = ok ]; then PASS=$((PASS+1)); printf '  PASS  %s - %s\n' "$1" "$3"
  else FAIL=$((FAIL+1)); printf '  FAIL  %s - %s\n' "$1" "$3"; fi
}
cleanup() { iso_teardown "$ISO_SESSION"; }
trap cleanup EXIT

# ── (Structural) The config dir is distinct from the global one and carries no guidance ───
echo "== (isolation) config dir carries none of the global guidance =="

# Distinct from ~/.claude - pointing at the same dir would load everything.
if [ "$(cd "$ISO_CONFIG_DIR" 2>/dev/null && pwd -P)" = "$(cd "$GLOBAL_CONFIG_DIR" 2>/dev/null && pwd -P)" ]; then
  report "config dir is not the global one" fail "ISO_CONFIG_DIR resolves to the global $GLOBAL_CONFIG_DIR"
else
  report "config dir is not the global one" ok "$ISO_CONFIG_DIR (not $GLOBAL_CONFIG_DIR)"
fi

# No CLAUDE.md anywhere in the isolated config dir.
if [ -n "$(find "$ISO_CONFIG_DIR" -name CLAUDE.md -print -quit 2>/dev/null)" ]; then
  report "no CLAUDE.md in config dir" fail "found a CLAUDE.md under $ISO_CONFIG_DIR"
else
  report "no CLAUDE.md in config dir" ok "none under $ISO_CONFIG_DIR"
fi

# The config dir's own settings enable no plugins and register no hooks - so the laws-plugin
# router cannot fire. (A missing settings.json is trivially clean.)
SETTINGS="$ISO_CONFIG_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
  report "config dir loads no plugins/hooks" ok "no settings.json present"
else
  iso_need python3
  if python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit(f"settings.json unreadable: {e}")
bad = [k for k in ("enabledPlugins", "hooks") if d.get(k)]
sys.exit("has " + ", ".join(bad) if bad else 0)
PY
  then
    report "config dir loads no plugins/hooks" ok "settings.json enables no plugins and no hooks"
  else
    report "config dir loads no plugins/hooks" fail "settings.json enables plugins or hooks: $SETTINGS"
  fi
fi

# ── (D) A bad CLAUDE_CONFIG_DIR aborts nonzero - never a silent fallback to global ────────
echo "== (D) No silent fallback for a bad CLAUDE_CONFIG_DIR =="
DTMP="$(mktemp -d)"

RO_PARENT="$DTMP/readonly_parent"; mkdir -p "$RO_PARENT"; chmod 500 "$RO_PARENT"
if ( iso_config_require "$RO_PARENT/cfg" ) >"$DTMP/d1.out" 2>&1; then
  chmod 700 "$RO_PARENT"; report "(D) uncreatable dir" fail "iso_config_require SUCCEEDED on an uncreatable dir"
else
  d1=$?; chmod 700 "$RO_PARENT"; report "(D) uncreatable dir" ok "exited $d1: $(grep -m1 ERROR "$DTMP/d1.out")"
fi

UNWRITABLE="$DTMP/unwritable_cfg"; mkdir -p "$UNWRITABLE"; chmod 500 "$UNWRITABLE"
if ( iso_config_require "$UNWRITABLE" ) >"$DTMP/d2.out" 2>&1; then
  chmod 700 "$UNWRITABLE"; report "(D) unwritable dir" fail "iso_config_require SUCCEEDED on an unwritable dir"
else
  d2=$?; chmod 700 "$UNWRITABLE"; report "(D) unwritable dir" ok "exited $d2: $(grep -m1 ERROR "$DTMP/d2.out")"
fi
rm -rf "$DTMP"

# ── (A) The live session actually runs on Opus (behavioral - the one thing you must ask) ──
echo "== (A) launch the real session and confirm it is Opus =="
iso_config_require "$ISO_CONFIG_DIR"
iso_config_is_setup "$ISO_CONFIG_DIR" \
  || iso_die "config dir is not logged in: $ISO_CONFIG_DIR - run $HERE/setup-isolated-session.sh first"
iso_launch "$ISO_SESSION" "$ISO_CONFIG_DIR" "$ISO_WORK_DIR"

A_SCREEN="$(iso_turn "$ISO_SESSION" \
  "Reply with exactly one line: MODELCHECK then the model family and version you are.")"
A_ANS="$(iso_answer "$A_SCREEN")"
if printf '%s' "$A_ANS" | grep -qi 'opus'; then
  report "(A) model is Opus" ok "session answered: $(printf '%s' "$A_ANS" | grep -i opus | head -1)"
else
  report "(A) model is Opus" fail "model answer did not say Opus. Answer: [$A_ANS]"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: PASS - isolated config dir carries no global guidance; bad dir aborts; live session is Opus"
  exit 0
else
  echo "RESULT: FAIL"
  exit 1
fi
