#!/usr/bin/env bash
# Drive one isolated Claude Code session through one or more turns and print each reply.
# This is the thin CLI over drive_turn: it launches an isolated subscription-Opus session,
# exchanges the given turns with it, prints the reply to each on stdout, and tears the session
# down. Multi-turn is the point - each argument is a full turn, driven in order on ONE session,
# so the loaded context accumulates the way a real task's does.
#
# [LAW:cli] Exit codes are a contract: 0 = every turn completed and its reply was printed;
#   nonzero = a turn could not be completed cleanly (dead session, timeout, empty), and drive_turn
#   already said where on stderr. Replies go to stdout (machine channel); progress to stderr.
# [LAW:no-silent-failure] A failed turn aborts the whole run nonzero; we never print a partial
#   or empty reply as if the turn had succeeded.
#
# Usage:
#   drive.sh "first turn" "second turn" ...   # each arg is one turn
#   echo "a single prompt" | drive.sh          # no args => read one prompt from stdin

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

ISO_CONFIG_DIR="${ISO_CONFIG_DIR:-$HOME/.claude-laws-eval}"
ISO_WORK_DIR="${ISO_WORK_DIR:-$HOME/.claude-laws-eval-workdir}"
ISO_SESSION="${ISO_SESSION:-drv-claude-$$}"

# Turns are data: from the argument vector, or one prompt slurped from stdin.
# [LAW:dataflow-not-control-flow] the turn list is a value; the same loop runs for one or many.
declare -a turns=()
if [ "$#" -gt 0 ]; then
  turns=("$@")
else
  turns=("$(cat)")
fi
[ -n "${turns[0]:-}" ] || drv_die "no prompt given (pass turns as arguments or one prompt on stdin)"

iso_config_require "$ISO_CONFIG_DIR"
# Tear the session down however we exit - the config dir is left intact (it holds the login).
trap 'iso_teardown "$ISO_SESSION"' EXIT
drv_launch "$ISO_SESSION" "$ISO_CONFIG_DIR" "$ISO_WORK_DIR"

for i in "${!turns[@]}"; do
  drv_log "turn $((i + 1))/${#turns[@]} ->"
  reply="$(drive_turn "$ISO_SESSION" "${turns[$i]}")"   # aborts nonzero on a bad turn
  printf '%s\n' "$reply"
done
