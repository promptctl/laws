#!/bin/bash
# Tests for install-lit-workflows.sh. Pure bash, the same dependency stance as the script.
#
# The installer is all effect, so each case runs it against a real directory tree: a throwaway
# home, or a throwaway copy of the plugin, never the machine's own lit config. A case asserts what
# lit would find afterwards - which definitions are in its global layer and what they say - and
# nothing about how the installer put them there.
#
# The last case asks lit itself. It runs only where lit is on PATH and this checkout is a lit
# workspace, and says so when it does not run.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
INSTALL="$HERE/install-lit-workflows.sh"
PLUGIN=$(cd "$HERE/../.." && pwd)
LAYER=links-issue-tracker/workflows/laws

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

pass=0
fail=0
skipped=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail+1)); }
skip() { printf 'skip - %s\n' "$1"; skipped=$((skipped+1)); }

# install <installer> <home> -> the installer's stdout; its exit status is the function's.
# XDG_CONFIG_HOME is removed so the home directory decides where lit's config is.
install() { env -u XDG_CONFIG_HOME HOME="$2" "$1" 2>"$scratch/stderr"; }

# plugin_with <root> <definition-file>... -> a plugin tree at <root> with the installer under test
# and one definition per name. Each body names the tree it came from, so a case can tell which
# copy of the plugin lit would be reading.
plugin_with() {
  local root=$1 name
  shift
  mkdir -p "$root/hooks/scripts" "$root/lit-workflows"
  cp "$INSTALL" "$root/hooks/scripts/"
  for name in "$@"; do
    printf -- '---\nid: %s\n---\nfrom %s\n' "${name%.md}" "$root" > "$root/lit-workflows/$name"
  done
}

# 1. A fresh home: every definition the plugin ships is in lit's global layer with its text
#    unchanged, the run succeeds, and it prints nothing (at SessionStart, stdout is context).
home="$scratch/fresh"
mkdir -p "$home"
out=$(install "$INSTALL" "$home"); status=$?
[ "$status" -eq 0 ] && ok "a fresh home installs with exit 0" || bad "a fresh home installs with exit 0 (got $status: $(cat "$scratch/stderr"))"
[ -z "$out" ] && ok "a successful install prints nothing on stdout" || bad "a successful install prints nothing on stdout (got: $out)"
shipped=0
unreadable=""
for definition in "$PLUGIN"/lit-workflows/*.md; do
  shipped=$((shipped+1))
  cmp -s "$definition" "$home/.config/$LAYER/${definition##*/}" || unreadable="$unreadable ${definition##*/}"
done
[ "$shipped" -gt 0 ] && [ -z "$unreadable" ] \
  && ok "all $shipped shipped definitions read the same from lit's global layer" \
  || bad "all shipped definitions read the same from lit's global layer (shipped: $shipped, wrong or missing:$unreadable)"

# 2. Installing again changes nothing and still succeeds: it runs at every session start.
install "$INSTALL" "$home" >/dev/null; status=$?
again=$(ls "$home/.config/$LAYER" | wc -l | tr -d ' ')
[ "$status" -eq 0 ] && [ "$again" -eq "$shipped" ] \
  && ok "a second install succeeds and leaves the same $shipped definitions" \
  || bad "a second install succeeds and leaves the same definitions (exit $status, $again entries, shipped $shipped)"

# 3. lit's config directory follows XDG_CONFIG_HOME when it is set, so the install does too, and
#    nothing lands under the home directory.
home="$scratch/xdg-home"
mkdir -p "$home"
HOME="$home" XDG_CONFIG_HOME="$scratch/xdg" "$INSTALL" >/dev/null 2>&1
[ -e "$scratch/xdg/$LAYER/plan-review.md" ] && [ ! -e "$home/.config" ] \
  && ok "XDG_CONFIG_HOME decides where the definitions go" \
  || bad "XDG_CONFIG_HOME decides where the definitions go"

# 4. There is one text. A change to the plugin's definition is what lit reads next, with no
#    install in between - a copy would still say the old thing.
plugin_with "$scratch/one-text" shim.md
home="$scratch/one-text-home"
mkdir -p "$home"
install "$scratch/one-text/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null
echo "reworded" > "$scratch/one-text/lit-workflows/shim.md"
[ "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" = "reworded" ] \
  && ok "an edit to the plugin's definition is what the global layer reads, with no reinstall" \
  || bad "an edit to the plugin's definition is what the global layer reads, with no reinstall"

# 5. The plugin moved (an update installs it under a new version's directory). The next session
#    start reads the definitions from where the plugin is now.
plugin_with "$scratch/v1" shim.md
plugin_with "$scratch/v2" shim.md
home="$scratch/moved-home"
mkdir -p "$home"
install "$scratch/v1/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null
install "$scratch/v2/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null
case "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" in
  *"from $scratch/v2") ok "after the plugin moves, the global layer reads the new location's definitions";;
  *) bad "after the plugin moves, the global layer reads the new location's definitions (got: $(cat "$home/.config/$LAYER/shim.md" 2>&1))";;
esac

# 6. A definition the plugin stopped shipping leaves the global layer at the next install; one it
#    still ships stays; a file somebody else put beside them is not the plugin's to remove.
plugin_with "$scratch/pruned" kept.md dropped.md
home="$scratch/pruned-home"
mkdir -p "$home"
install "$scratch/pruned/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null
echo "someone else's definition" > "$home/.config/$LAYER/theirs.md"
rm "$scratch/pruned/lit-workflows/dropped.md"
install "$scratch/pruned/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null; status=$?
[ "$status" -eq 0 ] && [ ! -e "$home/.config/$LAYER/dropped.md" ] && [ ! -L "$home/.config/$LAYER/dropped.md" ] \
  && ok "a definition the plugin no longer ships is gone from the global layer" \
  || bad "a definition the plugin no longer ships is gone from the global layer (exit $status)"
[ -e "$home/.config/$LAYER/kept.md" ] \
  && ok "a definition the plugin still ships stays" \
  || bad "a definition the plugin still ships stays"
[ "$(cat "$home/.config/$LAYER/theirs.md" 2>&1)" = "someone else's definition" ] \
  && ok "a file somebody else put in the directory is left as it was" \
  || bad "a file somebody else put in the directory is left as it was"

# 6b. A file that is not a link, sitting on the name of a shipped definition: somebody's own copy.
#     The install does not replace it and does not pass over it quietly. It stops and names it.
plugin_with "$scratch/occupied" shim.md
home="$scratch/occupied-home"
mkdir -p "$home/.config/$LAYER"
echo "somebody's own copy" > "$home/.config/$LAYER/shim.md"
install "$scratch/occupied/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null; status=$?
case "$(cat "$scratch/stderr")" in
  *"$home/.config/$LAYER/shim.md"*) named=yes;;
  *) named=no;;
esac
[ "$status" -eq 2 ] && [ "$named" = yes ] && [ "$(cat "$home/.config/$LAYER/shim.md")" = "somebody's own copy" ] \
  && ok "a file that is not a link on a shipped name is kept, and the install exits 2 naming it" \
  || bad "a file that is not a link on a shipped name is kept, and the install exits 2 naming it (exit $status, stderr: $(cat "$scratch/stderr"), file: $(cat "$home/.config/$LAYER/shim.md" 2>&1))"

# 7. Two sessions start together. The interleaving is forced, not hoped for: a stand-in for mv
#    runs a whole second install at the moment the first has made its link and not yet moved it
#    into place, then lets the first carry on. Both must succeed and the definition must be there.
plugin_with "$scratch/together" shim.md
home="$scratch/together-home"
mkdir -p "$home" "$scratch/gate"
cat > "$scratch/gate/mv" <<EOF
#!/bin/bash
PATH="$PATH" HOME="$home" "$scratch/together/hooks/scripts/install-lit-workflows.sh" || exit 1
PATH="$PATH" exec mv "\$@"
EOF
chmod +x "$scratch/gate/mv"
out=$(env -u XDG_CONFIG_HOME HOME="$home" PATH="$scratch/gate:$PATH" "$scratch/together/hooks/scripts/install-lit-workflows.sh" 2>"$scratch/stderr"); status=$?
case "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" in
  *"from $scratch/together") together=yes;;
  *) together=no;;
esac
[ "$status" -eq 0 ] && [ "$together" = yes ] && [ "$(ls -A "$home/.config/$LAYER" | wc -l | tr -d ' ')" -eq 1 ] \
  && ok "a second install in the middle of the first leaves both successful and one definition in place" \
  || bad "a second install in the middle of the first leaves both successful and one definition in place (exit $status: $(cat "$scratch/stderr"); directory: $(ls -A "$home/.config/$LAYER" 2>&1 | tr '\n' ' '))"

# 8. A failed install is loud: exit 2, which shows stderr to the user at session start, with the
#    path it could not write. The home here is a regular file, so nothing can be created under it.
echo "not a directory" > "$scratch/a-file"
out=$(install "$INSTALL" "$scratch/a-file"); status=$?
case "$(cat "$scratch/stderr")" in
  *"lit workflows not installed"*"$scratch/a-file/.config/$LAYER"*) named=yes;;
  *) named=no;;
esac
[ "$status" -eq 2 ] && [ "$named" = yes ] && [ -z "$out" ] \
  && ok "an install that cannot write exits 2 and names the directory on stderr" \
  || bad "an install that cannot write exits 2 and names the directory on stderr (exit $status, stderr: $(cat "$scratch/stderr"), stdout: $out)"

# 9. A plugin with no definitions is a broken plugin, not an empty install.
plugin_with "$scratch/empty"
home="$scratch/empty-home"
mkdir -p "$home"
install "$scratch/empty/hooks/scripts/install-lit-workflows.sh" "$home" >/dev/null; status=$?
case "$(cat "$scratch/stderr")" in
  *"$scratch/empty/lit-workflows"*) named=yes;;
  *) named=no;;
esac
[ "$status" -eq 2 ] && [ "$named" = yes ] \
  && ok "a plugin with no definitions exits 2 and names where they should be" \
  || bad "a plugin with no definitions exits 2 and names where they should be (exit $status, stderr: $(cat "$scratch/stderr"))"

# 10. A definition exists to name a skill. Every shipped one names a skill of this plugin that is
#     really here, so a renamed or moved skill fails this before an agent is sent to nothing.
for definition in "$PLUGIN"/lit-workflows/*.md; do
  named=$(grep -o -E '/laws:[a-z-]+' "$definition" | sort -u)
  missing=""
  for skill in $named; do
    [ -f "$PLUGIN/skills/${skill#/laws:}/SKILL.md" ] || missing="$missing $skill"
  done
  [ -n "$named" ] && [ -z "$missing" ] \
    && ok "${definition##*/} names a skill this plugin ships ($(echo $named))" \
    || bad "${definition##*/} names a skill this plugin ships (named: $(echo $named); not found:$missing)"
done

# 11. lit's side of the contract: installed where lit looks, each definition fires at its moment,
#     with the ticket's id filled in, and stays quiet at the moment before it.
#     fired <dry-run arguments> -> what lit would print at that moment, under a scratch config.
home="$scratch/lit-home"
mkdir -p "$home"
HOME="$home" XDG_CONFIG_HOME="$scratch/lit-config" "$INSTALL" >/dev/null 2>&1
fired() { ( cd "$HERE" && XDG_CONFIG_HOME="$scratch/lit-config" lit workflows dry-run --issue demo-1 "$@" 2>&1 ); }
if ! command -v lit >/dev/null 2>&1; then
  skip "lit fires each definition at its moment (lit is not on PATH)"
elif ! fired --enter review >/dev/null; then
  skip "lit fires each definition at its moment (lit cannot run here: $(fired --enter review | head -1))"
else
  case "$(fired --exit plan --enter impl)" in
    *laws-plan-review*'/laws:plan-review demo-1'*) ok "lit asks for the plan review when a ticket leaves plan";;
    *) bad "lit asks for the plan review when a ticket leaves plan (lit printed: $(fired --exit plan --enter impl))";;
  esac
  case "$(fired --enter in_progress --enter plan)" in
    *laws-plan-review*) bad "lit does not ask for the plan review when a ticket enters plan";;
    *) ok "lit does not ask for the plan review when a ticket enters plan";;
  esac
  case "$(fired --enter review)" in
    *laws-law-review*'/laws:law-review <pr> <pass>'*) ok "lit asks for the law review when a ticket enters review";;
    *) bad "lit asks for the law review when a ticket enters review (lit printed: $(fired --enter review))";;
  esac
  case "$(fired --exit review --enter merge)" in
    *laws-law-review*) bad "lit does not ask for the law review when a ticket leaves review";;
    *) ok "lit does not ask for the law review when a ticket leaves review";;
  esac
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
