#!/usr/bin/env bash
# Authenticate the config directory horizon runs use. Run once, by a human, with a
# browser to hand; every run afterwards is unattended.
#
# WHY THIS EXISTS AS ITS OWN COMMAND: Claude Code keys its stored credential to the
# config directory's PATH, so "is this run logged in" is a question about WHERE the
# config dir is, not what is in it. Wiping the directory keeps the login; building the
# run somewhere new loses it. That is the whole reason runs are built at one fixed path
# instead of a fresh directory per run, and it is worth a command that says so rather
# than a step someone has to remember.
#
# It is also the one place a human is required. An unauthenticated config dir does not
# fail loudly when a run starts - it boots to a login prompt and waits forever, which in
# an unattended run looks exactly like an agent thinking hard. run-loop.sh therefore
# refuses to launch until this has been done. [LAW:no-silent-failure]
#
# Usage:
#   horizon/login.sh
#
# The directory is HORIZON_CONFIG_DIR, defined once in lib.sh and read from there by
# this script and by run-loop.sh alike - the credential is bound to a path, so two
# scripts holding their own idea of that path is the one disagreement that must be
# impossible. [LAW:one-source-of-truth]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

main() {
  horizon_need claude
  horizon_need mkdir
  horizon_need python3

  # Created if it does not exist yet: the credential is bound to this path, so it has to
  # be logged in BEFORE the first run rather than discovered missing halfway through one.
  local config_dir="$HORIZON_CONFIG_DIR"
  mkdir -p "$config_dir" || horizon_die "could not create $config_dir"
  config_dir="$(cd "$config_dir" && pwd)"

  horizon_log "authenticating the horizon run config dir:"
  horizon_log "  $config_dir"

  if CLAUDE_CONFIG_DIR="$config_dir" claude auth status 2>/dev/null \
      | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("loggedIn") is True else 1)'; then
    horizon_log "already authenticated - nothing to do"
    return 0
  fi

  horizon_log "opening the sign-in flow; complete it in the browser"
  CLAUDE_CONFIG_DIR="$config_dir" claude auth login --claudeai \
    || horizon_die "login did not complete"

  # Asserted through the same function run-loop.sh gates on, so "login.sh said it worked"
  # and "run-loop.sh agrees" cannot come apart. [LAW:single-enforcer]
  horizon_assert_authenticated "$config_dir"
  horizon_log "authenticated; runs at this work dir can now start unattended"
}

main "$@"
