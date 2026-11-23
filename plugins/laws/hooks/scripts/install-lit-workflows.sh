#!/bin/bash
# Puts this plugin's lit workflow definitions into lit's global workflow layer. Runs at every
# session start (hooks.json), injects nothing, and prints nothing when it succeeds: at
# SessionStart a hook's plain stdout becomes context.
#
# lit prints the body of every workflow definition that matches a ticket's lifecycle moment. It
# reads definitions from the project, from workflows/ under its config directory, and from its
# own binary. The definitions in lit-workflows/ each tell the agent to run one of this plugin's
# skills at the moment that review is due. In the global layer they reach every project on the
# machine that lit tracks, and a machine without lit never reads them.
#
# A definition is installed as a symlink to the plugin's file, never a copy, so the plugin's file
# stays the only text there is [LAW:one-source-of-truth]. The link is per file because lit's walk
# reads a symlinked file and does not descend into a symlinked directory. The plugin's own path
# changes between sessions (a marketplace install lives in a directory named for its version), so
# the links are redrawn at every session start, not once.
#
# laws/ under the global layer belongs to this script: it holds a link for each definition the
# plugin ships and no link for one it has stopped shipping. A file there that is not a symlink is
# someone else's. It is never removed, and one that sits on a shipped definition's name stops the
# install instead of being replaced.
#
# No external dependencies - pure bash (3.2+), the same stance as skill-router.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFINITIONS="$(cd "$SCRIPT_DIR/../.." && pwd)/lit-workflows"

# lit's rule for where its config directory is: XDG_CONFIG_HOME when that is set and not empty,
# .config in the home directory otherwise. lit owns the rule and has no command that prints the
# result. [LAW:one-source-of-truth] exception: a second spelling of lit's rule, which changes
# only if lit moves its config directory.
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/links-issue-tracker/workflows/laws"

# Exit 2 shows the reason to the user at session start. A review that is never asked for looks
# exactly like a review that found nothing, so a failed install is not left to be noticed.
# [LAW:no-silent-failure]
fail() {
  echo "laws: lit workflows not installed: $1" >&2
  exit 2
}

mkdir -p "$INSTALL_DIR" || fail "cannot create $INSTALL_DIR"

# Each link is made under a name lit does not read, then renamed over its final name. A rename
# replaces in one step, so sessions that start together neither catch a definition missing nor
# fail on a name the other has just written. [LAW:no-ambient-temporal-coupling]
for definition in "$DEFINITIONS"/*.md; do
  [ -e "$definition" ] || fail "cannot read definition $definition"
  name=${definition##*/}
  link="$INSTALL_DIR/$name"
  [ -L "$link" ] || [ ! -e "$link" ] || fail "$link is not a link, so it is not this plugin's to replace"
  staged="$INSTALL_DIR/.$name.$$"
  ln -sfn "$definition" "$staged" && mv -f "$staged" "$link" || fail "cannot link $link"
done

for link in "$INSTALL_DIR"/*.md; do
  [ -L "$link" ] || continue
  [ -e "$DEFINITIONS/${link##*/}" ] || rm -f "$link" || fail "cannot remove $link"
done
