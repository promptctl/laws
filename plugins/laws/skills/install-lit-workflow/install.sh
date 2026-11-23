#!/bin/bash
# Puts this plugin's lit workflow definitions into lit's global workflow layer. Run by the
# install-lit-workflow skill, when a person asks for it.
#
# lit prints the body of every workflow definition that matches a ticket's lifecycle moment. It
# reads definitions from the project, from workflows/ under its config directory, and from its
# own binary. The definitions beside this script each tell the agent to run one of this plugin's
# skills at the moment that review is due. In the global layer they reach every project on the
# machine that lit tracks.
#
# A definition is installed as a copy. A link would point into the plugin's own directory, and
# that directory is named for the plugin's version in a marketplace install, so an update would
# leave every link pointing at nothing - and lit says nothing about a link that points at
# nothing, so the reviews would stop being asked for without a word. A copy keeps working, and
# running the skill again is how it is brought up to date.
#
# laws/ under the global layer belongs to this script. After it runs, that directory holds the
# definitions the plugin ships and nothing else.
#
# No external dependencies - pure bash (3.2+), the same stance as skill-router.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFINITIONS="$SCRIPT_DIR/definitions"

# lit's rule for where its config directory is: XDG_CONFIG_HOME when that is set and not empty,
# .config in the home directory otherwise. lit owns the rule and has no command that prints the
# result. [LAW:one-source-of-truth] exception: a second spelling of lit's rule, which changes
# only if lit moves its config directory.
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/links-issue-tracker/workflows/laws"

# Exit 2, the convention skill-router.sh uses, with the reason on stderr. A review that is never
# asked for looks exactly like a review that found nothing, so a failed install says so.
# [LAW:no-silent-failure]
fail() {
  echo "laws: lit workflows not installed: $1" >&2
  exit 2
}

mkdir -p "$INSTALL_DIR" || fail "cannot create $INSTALL_DIR"

# Each copy is made under a name lit does not read, then renamed over its final name. A rename
# replaces in one step, so lit never reads a half-written definition, and it replaces a link left
# by an earlier version of this script instead of writing through it.
# [LAW:no-ambient-temporal-coupling]
for definition in "$DEFINITIONS"/*.md; do
  [ -e "$definition" ] || fail "cannot read definition $definition"
  name=${definition##*/}
  staged="$INSTALL_DIR/.$name.$$"
  cp "$definition" "$staged" && mv -f "$staged" "$INSTALL_DIR/$name" || fail "cannot write $INSTALL_DIR/$name"
  echo "installed $INSTALL_DIR/$name"
done

for installed in "$INSTALL_DIR"/*.md; do
  [ -e "$installed" ] || [ -L "$installed" ] || continue
  [ -e "$DEFINITIONS/${installed##*/}" ] && continue
  rm -f "$installed" || fail "cannot remove $installed"
  echo "removed $installed"
done
