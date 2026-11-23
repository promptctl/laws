#!/bin/bash
# Tests for install.sh. Pure bash, the same dependency stance as the script.
#
# The installer is all effect, so each case runs it against a real directory tree: a throwaway
# home, or a throwaway copy of the skill, never the machine's own lit config. A case asserts what
# lit would find afterwards - which definitions are in its global layer and what they say - and
# nothing about how the installer put them there.
#
# The last case asks lit itself. It runs only where lit is on PATH and this checkout is a lit
# workspace, and says so when it does not run.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
INSTALL="$HERE/install.sh"
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

# skill_with <root> <definition-file>... -> a copy of the skill at <root> with one definition per
# name. Each body names the tree it came from, so a case can tell which copy lit would be reading.
skill_with() {
  local root=$1 name
  shift
  mkdir -p "$root/definitions"
  cp "$INSTALL" "$root/"
  for name in "$@"; do
    printf -- '---\nid: %s\n---\nfrom %s\n' "${name%.md}" "$root" > "$root/definitions/$name"
  done
}

# 1. A fresh home: every definition the skill ships is in lit's global layer as a file of its own
#    with its text unchanged, the run succeeds, and it says what it wrote.
home="$scratch/fresh"
mkdir -p "$home"
out=$(install "$INSTALL" "$home"); status=$?
[ "$status" -eq 0 ] && ok "a fresh home installs with exit 0" || bad "a fresh home installs with exit 0 (got $status: $(cat "$scratch/stderr"))"
shipped=0
wrong=""
reported=""
for definition in "$HERE"/definitions/*.md; do
  shipped=$((shipped+1))
  target="$home/.config/$LAYER/${definition##*/}"
  { [ ! -L "$target" ] && cmp -s "$definition" "$target"; } || wrong="$wrong ${definition##*/}"
  case "$out" in *"installed $target"*) ;; *) reported="$reported ${definition##*/}";; esac
done
[ "$shipped" -gt 0 ] && [ -z "$wrong" ] \
  && ok "all $shipped shipped definitions are in lit's global layer as files with the same text" \
  || bad "all shipped definitions are in lit's global layer as files with the same text (shipped: $shipped, wrong or missing:$wrong)"
[ -z "$reported" ] && ok "the output names every definition it wrote" || bad "the output names every definition it wrote (not named:$reported; output: $out)"

# 2. Installing again changes nothing and still succeeds.
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

# 4. The installed definitions outlive the skill's own directory. An update moves or removes the
#    directory it was installed from, and lit must keep reading what it was given.
skill_with "$scratch/v1" shim.md
home="$scratch/outlive-home"
mkdir -p "$home"
install "$scratch/v1/install.sh" "$home" >/dev/null
rm -rf "$scratch/v1"
case "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" in
  *"from $scratch/v1") ok "after the skill's directory is gone, the installed definition still reads";;
  *) bad "after the skill's directory is gone, the installed definition still reads (got: $(cat "$home/.config/$LAYER/shim.md" 2>&1))";;
esac

# 5. Running it again brings the global layer up to date with the skill that is there now.
skill_with "$scratch/v2" shim.md
install "$scratch/v2/install.sh" "$home" >/dev/null
case "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" in
  *"from $scratch/v2") ok "a second run from a newer copy of the skill replaces the definition";;
  *) bad "a second run from a newer copy of the skill replaces the definition (got: $(cat "$home/.config/$LAYER/shim.md" 2>&1))";;
esac

# 6. The directory ends up holding exactly what the skill ships: a definition it stopped shipping
#    is gone, one it still ships stays, and a link left by an earlier version of the installer is
#    replaced by a file - without writing through the link into the file it points at.
skill_with "$scratch/pruned" kept.md dropped.md
home="$scratch/pruned-home"
mkdir -p "$home"
install "$scratch/pruned/install.sh" "$home" >/dev/null
rm "$scratch/pruned/definitions/dropped.md"
ln -sf "$scratch/pruned/definitions/kept.md" "$home/.config/$LAYER/kept.md"
before=$(cat "$scratch/pruned/definitions/kept.md")
install "$scratch/pruned/install.sh" "$home" >/dev/null; status=$?
[ "$status" -eq 0 ] && [ ! -e "$home/.config/$LAYER/dropped.md" ] && [ ! -L "$home/.config/$LAYER/dropped.md" ] \
  && ok "a definition the skill no longer ships is gone from the global layer" \
  || bad "a definition the skill no longer ships is gone from the global layer (exit $status)"
[ -f "$home/.config/$LAYER/kept.md" ] && [ ! -L "$home/.config/$LAYER/kept.md" ] \
  && ok "a definition the skill still ships stays, as a file" \
  || bad "a definition the skill still ships stays, as a file"
[ "$(cat "$scratch/pruned/definitions/kept.md")" = "$before" ] \
  && ok "replacing a link does not write through it into the skill's own definition" \
  || bad "replacing a link does not write through it into the skill's own definition"

# 7. Two installs run together. The interleaving is forced, not hoped for: a stand-in for mv runs
#    a whole second install at the moment the first has written its copy and not yet moved it into
#    place, then lets the first carry on. Both must succeed and the definition must be there.
skill_with "$scratch/together" shim.md
home="$scratch/together-home"
mkdir -p "$home" "$scratch/gate"
cat > "$scratch/gate/mv" <<EOF
#!/bin/bash
PATH="$PATH" HOME="$home" "$scratch/together/install.sh" >/dev/null || exit 1
PATH="$PATH" exec mv "\$@"
EOF
chmod +x "$scratch/gate/mv"
env -u XDG_CONFIG_HOME HOME="$home" PATH="$scratch/gate:$PATH" "$scratch/together/install.sh" >/dev/null 2>"$scratch/stderr"; status=$?
case "$(cat "$home/.config/$LAYER/shim.md" 2>&1)" in
  *"from $scratch/together") together=yes;;
  *) together=no;;
esac
[ "$status" -eq 0 ] && [ "$together" = yes ] && [ "$(ls -A "$home/.config/$LAYER" | wc -l | tr -d ' ')" -eq 1 ] \
  && ok "a second install in the middle of the first leaves both successful and one definition in place" \
  || bad "a second install in the middle of the first leaves both successful and one definition in place (exit $status: $(cat "$scratch/stderr"); directory: $(ls -A "$home/.config/$LAYER" 2>&1 | tr '\n' ' '))"

# 8. A failed install is loud: exit 2 with the path it could not write. The home here is a
#    regular file, so nothing can be created under it.
echo "not a directory" > "$scratch/a-file"
out=$(install "$INSTALL" "$scratch/a-file"); status=$?
case "$(cat "$scratch/stderr")" in
  *"lit workflows not installed"*"$scratch/a-file/.config/$LAYER"*) named=yes;;
  *) named=no;;
esac
[ "$status" -eq 2 ] && [ "$named" = yes ] && [ -z "$out" ] \
  && ok "an install that cannot write exits 2 and names the directory on stderr" \
  || bad "an install that cannot write exits 2 and names the directory on stderr (exit $status, stderr: $(cat "$scratch/stderr"), stdout: $out)"

# 9. A skill with no definitions is a broken skill, not an empty install.
skill_with "$scratch/empty"
home="$scratch/empty-home"
mkdir -p "$home"
install "$scratch/empty/install.sh" "$home" >/dev/null; status=$?
case "$(cat "$scratch/stderr")" in
  *"$scratch/empty/definitions"*) named=yes;;
  *) named=no;;
esac
[ "$status" -eq 2 ] && [ "$named" = yes ] \
  && ok "a skill with no definitions exits 2 and names where they should be" \
  || bad "a skill with no definitions exits 2 and names where they should be (exit $status, stderr: $(cat "$scratch/stderr"))"

# 10. A definition exists to name a skill. Every shipped one names a skill of this plugin that is
#     really here, so a renamed or moved skill fails this before an agent is sent to nothing.
for definition in "$HERE"/definitions/*.md; do
  named=$(grep -o -E '/laws:[a-z-]+' "$definition" | sort -u)
  missing=""
  for skill in $named; do
    [ -f "$HERE/../${skill#/laws:}/SKILL.md" ] || missing="$missing $skill"
  done
  [ -n "$named" ] && [ -z "$missing" ] \
    && ok "${definition##*/} names a skill this plugin ships ($(echo $named))" \
    || bad "${definition##*/} names a skill this plugin ships (named: $(echo $named); not found:$missing)"
done

# 11. lit's side of the contract: installed where lit looks, each definition fires at its moment,
#     with the ticket's id filled in, and stays quiet at the moment beside it.
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
