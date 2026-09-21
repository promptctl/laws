#!/usr/bin/env bash
# Verify run-bundle capture against the ticket's acceptance criterion:
#
#   "a reviewer locates any run's PR review threads, ticket history, and token totals
#    without reading harness code, in the same place for every bundle."
#
# Which breaks into four things a machine can decide:
#
#   1. EVERY DECLARED PATH IS THERE. HORIZON_BUNDLE_LAYOUT is the one declaration of a
#      bundle's shape; a captured bundle holds every path it names, and the bundle's own
#      README describes every one of them - so "without reading harness code" is checked,
#      not asserted.
#   2. THE THREE THINGS ARE FINDABLE, and hold what they claim: review threads with their
#      resolution state, tickets with their history, token totals that are not zero for a
#      run that spent tokens.
#   3. THE SHAPE DOES NOT DEPEND ON HOW THE RUN ENDED. A run that died before it ever
#      seeded a project produces the same top-level keys and the same capture names as one
#      that finished - with `"ok": false` and a reason where a capture could not run. Two
#      bundles are comparable because they answer the same questions, not because they
#      happen to hold the same things.
#   4. A SHORT CAPTURE IS REFUSED. A pull request whose review threads ran past one API
#      page stops the capture rather than being written to disk looking complete.
#
# WHAT THIS DOES NOT DO: launch a run. That needs an authenticated config dir and hours,
# and it is promptctl-horizon-7ry.3's gate, not this one. `gh` is replaced on PATH by a
# fixture that serves canned API responses, so every line of the real capture path runs
# against a known remote instead of the network.
#
# [LAW:verifiable-goals] this script IS the machine-checkable "done" for the ticket; exit 0
# means every criterion held on this run, exit nonzero says which one did not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

# Checked before the first line that reaches for one, including the mktemp below.
# [LAW:single-enforcer] [LAW:no-ambient-temporal-coupling]
horizon_need_base
horizon_need git
horizon_need lit
horizon_need python3
# Not in HORIZON_BASE_TOOLS, and reached by this script alone: the bundle comparison, the
# fixture heredocs, and making the fixture `gh` executable. Declared here for the same
# reason the sibling verifiers declare theirs - a missing one should say so in this
# script's own voice, not as a bare "command not found" from partway through a check.
horizon_need diff
horizon_need cat
horizon_need chmod
horizon_need cut
horizon_need head

WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Usage: json_field <file> <python-expression over `d`>
#
# One reader for "what does this bundle file say", so a check that mistypes a key fails
# loudly here rather than comparing two empty strings and passing. [LAW:no-silent-failure]
json_field() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2]))' "$1" "$2" \
    || fail "could not read $2 from $1"
}

# ── The fixture remote ─────────────────────────────────────────────────────────────────
#
# A `gh` on PATH that answers from files instead of GitHub. It is deliberately not a
# general fake: it serves exactly the four calls the capture makes, and refuses anything
# else by name, so a capture that starts making a fifth call fails here instead of being
# silently tolerated by a mock that says yes to everything.
build_gh_fixture() {
  local bin="$WORK/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'GH_FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  # The watermark read at time zero.
  *"per_page=1&sort=created&direction=desc"*)
    printf '%s\n' "$HORIZON_FIXTURE_WATERMARK" ;;
  # Every PR the repository has ever had, one number per line.
  *"pulls?state=all&per_page=100"*)
    printf '%s\n' $HORIZON_FIXTURE_PR_NUMBERS ;;
  "api graphql"*)
    number=""
    for arg in "$@"; do case "$arg" in number=*) number="${arg#number=}" ;; esac; done
    cat "$HORIZON_FIXTURE_DIR/pr-$number.json" ;;
  *)
    printf 'gh fixture: unexpected call: %s\n' "$*" >&2; exit 1 ;;
esac
GH_FIXTURE
  chmod +x "$bin/gh"
  PATH="$bin:$PATH"
  export PATH
}

# Usage: write_pr_fixture <number> <resolved> <unresolved> [flaw]
#
# One captured pull request in the shape `gh api graphql` returns. `flaw` writes one that
# came back short, and which one matters: `truncated` overflows the review threads
# themselves, `thread-truncated` overflows the comments INSIDE one thread - a connection
# nested in a connection, and the likeliest of the two to happen for real.
write_pr_fixture() {
  python3 - "$HORIZON_FIXTURE_DIR" "$@" <<'PY'
import json, os, sys
out_dir, number, resolved, unresolved = sys.argv[1:5]
flaw = sys.argv[5] if len(sys.argv) > 5 else ""
truncated = flaw == "truncated"

def thread(is_resolved, n):
    return {"isResolved": is_resolved, "isOutdated": False, "path": "src/app.py", "line": n,
            "comments": {"pageInfo": {"hasNextPage": flaw == "thread-truncated"},
                         "nodes": [{"author": {"login": "copirate"},
                                    "createdAt": "2026-01-01T00:00:00Z",
                                    "body": "This branch is unreachable."}]}}

threads = ([thread(True, i) for i in range(int(resolved))]
           + [thread(False, 100 + i) for i in range(int(unresolved))])

document = {"data": {"repository": {"pullRequest": {
    "number": int(number),
    "title": "feat: the CLI boundary",
    "url": "https://github.com/promptctl/horizon-eval/pull/%s" % number,
    "state": "MERGED", "isDraft": False, "merged": True,
    "createdAt": "2026-01-01T00:00:00Z", "mergedAt": "2026-01-01T01:00:00Z",
    "closedAt": "2026-01-01T01:00:00Z",
    "baseRefName": "master", "headRefName": "mack-1", "headRefOid": "deadbeef",
    "body": "Closes mack-1.", "author": {"login": "claude"},
    "commits": {"totalCount": 2, "pageInfo": {"hasNextPage": False},
                "nodes": [{"commit": {"oid": "c1", "messageHeadline": "wire it up",
                                      "committedDate": "2026-01-01T00:30:00Z"}}]},
    "comments": {"pageInfo": {"hasNextPage": False}, "nodes": []},
    "reviews": {"pageInfo": {"hasNextPage": False},
                "nodes": [{"author": {"login": "copirate"}, "state": "CHANGES_REQUESTED",
                           "submittedAt": "2026-01-01T00:40:00Z", "body": "Two findings."}]},
    "reviewThreads": {"pageInfo": {"hasNextPage": bool(truncated)}, "nodes": threads},
}}}}
with open(os.path.join(out_dir, "pr-%s.json" % number), "w") as handle:
    json.dump(document, handle)
PY
}

# Writes the helper that makes a transcript report two different usages for one message -
# the shape that turns billing-once-per-message-id from a count into a floor. Written to a
# file rather than inlined at the check, because it appends to a real captured transcript
# and wants the entry shape that transcript already uses.
write_clash_script() {
  cat > "$WORK/clash.py" <<'CLASH_PY'
import json, os, sys

root = sys.argv[1]
target = next(os.path.join(base, name)
              for base, _, names in os.walk(root)
              for name in names if name.endswith(".jsonl"))
with open(target) as handle:
    first = json.loads(handle.readline())


def block(output):
    return {"type": "assistant", "sessionId": first["sessionId"], "cwd": first["cwd"],
            "timestamp": first["timestamp"], "entrypoint": "cli",
            "message": {"role": "assistant", "id": "clash",
                        "content": [{"type": "text", "text": "."}],
                        "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0,
                                  "cache_read_input_tokens": 0, "output_tokens": output}}}


with open(target, "a") as handle:
    for output in (10, 99):
        handle.write(json.dumps(block(output)) + "\n")
CLASH_PY
}

# Usage: build_bundle <bundle_dir> <config_dir>
#
# Everything a run leaves behind before the close-out runs: a seeded project with real git
# history and a real lit store, a seed manifest naming it, the goal wording, and session
# transcripts sitting where Claude Code puts them. Real tools, not stubs - the point of
# this gate is that the capture path works against what a run actually produces.
build_bundle() {
  local bundle_dir="$1" config_dir="$2"
  local project_dir="$bundle_dir/seed/macklebox"

  mkdir -p "$project_dir"
  git -C "$project_dir" init --quiet --initial-branch=master
  git -C "$project_dir" config user.name "horizon verify"
  git -C "$project_dir" config user.email "horizon@promptctl.invalid"
  printf 'print("hi")\n' > "$project_dir/app.py"
  git -C "$project_dir" add -A
  git -C "$project_dir" -c commit.gpgsign=false commit --quiet -m "seed"
  printf 'print("hello")\n' > "$project_dir/app.py"
  git -C "$project_dir" add -A
  git -C "$project_dir" -c commit.gpgsign=false commit --quiet -m "the CLI boundary"

  # lit BEFORE the remote, and that ordering is the whole reason this fixture is built by
  # hand rather than cloned from a run: `lit init` adopts a backlog from any remote it
  # finds, so a project that already had an origin would start from that remote's backlog
  # instead of this fixture's - somebody else's tickets in the middle of a check about
  # this run's.
  ( cd "$project_dir" && lit init >/dev/null )
  ( cd "$project_dir" && lit new --title "Build the CLI boundary" --type feature \
      --topic cli >/dev/null )
  # A REAL GitHub origin, so the capture path reads a real `owner/name` - and a transport
  # that cannot leave this machine, so that is hermetic by construction rather than by
  # luck. `lit export` syncs against origin when it cannot settle the backlog from what is
  # on disk: measured 2026-09-21, an empty local backlog with this origin spent 5.9
  # seconds on the network and printed a blocking error, while the same project holding
  # one ticket spent 0.09 and stayed offline. This fixture makes a ticket, so the gate was
  # hermetic only for as long as that stayed true of both lit and this function. Pointing
  # `core.sshCommand` at /bin/false removes the question: any sync lit attempts fails
  # locally and instantly, and the fake `gh` on PATH refuses calls nobody expected, so
  # both routes off this machine are closed. [LAW:no-ambient-temporal-coupling]
  git -C "$project_dir" config core.sshCommand /bin/false
  git -C "$project_dir" remote add origin "git@github.com:promptctl/horizon-eval.git"

  printf '{\n  "project": {\n    "name": "macklebox"\n  }\n}\n' \
    > "$bundle_dir/seed/seed-manifest.json"
  printf 'Work the backlog to done.\n' > "$bundle_dir/goal.md"

  # What pin-instrument.sh leaves behind. Stood in for rather than pinned for real: a pin
  # fetches two repositories over the network and is promptctl-horizon-7ry.1's gate, not
  # this one. What this gate needs from it is that the path is part of a captured bundle
  # and the record accounts for it.
  mkdir -p "$bundle_dir/instrument/pinned"
  printf '{\n  "schema_version": 3\n}\n' > "$bundle_dir/instrument/manifest.json"

  # Two sessions, both in the project's cwd, each spending tokens - and one headless
  # `claude -p` a tool inside a session spawned, which is real spend and not a session.
  python3 - "$config_dir/projects/proj" "$project_dir" \
           "$(git -C "$project_dir" log -1 --format=%cI)" <<'PY'
import json, os, sys
directory, project_dir, commit_time = sys.argv[1:4]
os.makedirs(directory, exist_ok=True)

def block(message_id, output):
    return {"type": "assistant", "isSidechain": False,
            "message": {"role": "assistant", "id": message_id,
                        "content": [{"type": "text", "text": "."}],
                        "usage": {"input_tokens": 1, "cache_creation_input_tokens": 10,
                                  "cache_read_input_tokens": 100, "output_tokens": output}}}

def session(session_id, entrypoint, start, end, output, goal=True):
    lines = [{"sessionId": session_id, "cwd": project_dir, "timestamp": start,
              "type": "assistant", "entrypoint": entrypoint}]
    if goal:
        lines.append({"sessionId": session_id, "cwd": project_dir, "timestamp": start,
                      "type": "user", "entrypoint": entrypoint,
                      "message": {"role": "user", "content":
                                  "<command-name>/goal</command-name>\n"
                                  "<command-args>Work the backlog to done.</command-args>"}})
    # Three entries, one message: the shape that makes a naive token sum lie.
    for _ in range(3):
        lines.append(dict(block("m-%s" % session_id, output), sessionId=session_id,
                          cwd=project_dir, timestamp=start, entrypoint=entrypoint))
    lines.append({"sessionId": session_id, "cwd": project_dir, "timestamp": end,
                  "type": "assistant", "entrypoint": entrypoint})
    with open(os.path.join(directory, "%s.jsonl" % session_id), "w") as handle:
        for line in lines:
            handle.write(json.dumps(line) + "\n")

session("s1", "cli", "2026-01-01T00:00:00+00:00", commit_time, 1000)
session("s2", "cli", commit_time, "2099-01-01T00:00:00+00:00", 2000)
session("rev", "sdk-cli", "2026-01-01T00:10:00+00:00", "2026-01-01T00:20:00+00:00",
        500, goal=False)
PY
}

# ── 1. A complete run: every declared path lands, and holds what it claims ─────────────

BUNDLE="$WORK/run"
CONFIG="$WORK/config"
HORIZON_FIXTURE_DIR="$WORK/fixtures"
mkdir -p "$HORIZON_FIXTURE_DIR"
export HORIZON_FIXTURE_DIR

build_gh_fixture
write_clash_script
build_bundle "$BUNDLE" "$CONFIG"

# Both spellings git accepts for a GitHub remote reduce to the one `gh` wants - and
# anything else is refused rather than handed on as a slug. What made this worth checking
# head-on: the old fallback returned whatever it was given, so a path remote came back as
# `/tmp/x/remote` and went into `gh api repos/.../pulls` looking like a repository.
URL_PROBE="$WORK/url-probe"
mkdir -p "$URL_PROBE"
git -C "$URL_PROBE" init --quiet --initial-branch=master
git -C "$URL_PROBE" remote add origin "git@github.com:promptctl/horizon-eval.git"
[ "$(horizon_project_remote_repo "$URL_PROBE")" = "promptctl/horizon-eval" ] \
  || fail "an ssh remote did not read back as owner/name"
git -C "$URL_PROBE" remote set-url origin "https://github.com/promptctl/horizon-eval.git"
[ "$(horizon_project_remote_repo "$URL_PROBE")" = "promptctl/horizon-eval" ] \
  || fail "an https remote did not read back as owner/name"
git -C "$URL_PROBE" remote set-url origin "$WORK/not-github.git"
if ( horizon_project_remote_repo "$URL_PROBE" ) >/dev/null 2>&1; then
  fail "a remote that is not a GitHub repository was read back as one anyway"
fi
pass "a GitHub remote reads back as owner/name in both spellings, and anything else is refused"

# PR #7 is a LEFTOVER from an earlier run of this shared repository; #8 and #9 are this
# run's. A capture that ignored the watermark would adopt #7 as this run's work.
HORIZON_FIXTURE_WATERMARK=7
HORIZON_FIXTURE_PR_NUMBERS="7 8 9"
export HORIZON_FIXTURE_WATERMARK HORIZON_FIXTURE_PR_NUMBERS
write_pr_fixture 7 1 0
write_pr_fixture 8 2 0
write_pr_fixture 9 1 1

horizon_record_remote_time_zero "$BUNDLE" "promptctl/horizon-eval" >/dev/null
horizon_capture_bundle "$CONFIG" "$BUNDLE" "2026-01-01T00:00:00Z" \
  || fail "capturing a complete run's bundle failed:
$(json_field "$BUNDLE/run.json" 'json.dumps(d["captured"], indent=2)')"

while read -r path; do
  [ -e "$BUNDLE/$path" ] || fail "the layout declares '$path' and the captured bundle has no such thing"
  grep -qF -- "\`$path\`" "$BUNDLE/README.md" \
    || fail "the layout declares '$path' and the bundle's README never mentions it"
done < <(horizon_bundle_layout_paths)
pass "every declared path is in the bundle and described by its README"

# The README's map must not name paths the bundle does not have either - a front page
# describing a file that was never captured sends a reviewer looking for nothing.
while read -r described; do
  [ -e "$BUNDLE/$described" ] \
    || fail "the bundle's README describes '$described', which is not in the bundle"
done < <(grep -oE '^- `[^`]+`' "$BUNDLE/README.md" | tr -d '`' | sed 's/^- //')
pass "the README describes nothing the bundle does not hold"

[ "$(json_field "$BUNDLE/prs/index.json" 'd["count"]')" = 2 ] \
  || fail "the capture did not take exactly this run's two pull requests"
[ "$(json_field "$BUNDLE/prs/index.json" 'min(p["number"] for p in d["pull_requests"])')" = 8 ] \
  || fail "the capture adopted a pull request from an earlier run of the shared repository"
pass "pull requests are scoped to this run by the time-zero watermark"

[ "$(json_field "$BUNDLE/prs/index.json" 'd["unresolved_review_threads"]')" = 1 ] \
  || fail "the index does not surface the unresolved review thread"
[ "$(json_field "$BUNDLE/prs/pr-0009.json" \
     'sum(1 for t in d["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"] if not t["isResolved"])')" = 1 ] \
  || fail "a captured pull request does not carry its review threads with resolution state"
pass "review threads are captured with their resolution state, and counted in the index"

[ "$(json_field "$BUNDLE/backlog/export.json" 'len(d["issues"])')" -ge 1 ] \
  || fail "the captured backlog holds no tickets"
[ "$(json_field "$BUNDLE/backlog/export.json" 'len(d["events"])')" -ge 1 ] \
  || fail "the captured backlog holds no ticket history"
pass "ticket history is in the backlog export, as issues and their events"

# 1000 + 2000 output tokens across the two sessions, each written as three entries of one
# message. A reader that summed entries would report 9000 here.
[ "$(json_field "$BUNDLE/loop.json" 'd["tokens"]["sessions"]["output_tokens"]')" = 3000 ] \
  || fail "session token totals are wrong - a message billed across blocks is being counted more than once"
[ "$(json_field "$BUNDLE/loop.json" 'd["tokens"]["subprocesses"]["output_tokens"]')" = 500 ] \
  || fail "the headless subprocess's tokens are missing from the run's totals"
[ "$(json_field "$BUNDLE/loop.json" 'd["tokens"]["total"]["output_tokens"]')" = 3500 ] \
  || fail "the run's token total is not the sum of its parts"
pass "token totals are in loop.json, deduplicated, with subprocess spend counted apart"

[ "$(json_field "$BUNDLE/run.json" 'd["project"]["path"]')" = "$BUNDLE/seed/macklebox" ] \
  || fail "run.json does not record the path the project ran at - a moved bundle cannot be re-read"
[ "$(json_field "$BUNDLE/run.json" 'all(s["ok"] for s in d["captured"].values())')" = True ] \
  || fail "a complete run reports a capture that did not land: $(json_field "$BUNDLE/run.json" 'd["captured"]')"
# The inventory reports both numbers because they differ by one on purpose: run.json is
# written FROM this step's result, so it is the one declared path that cannot be checked.
# A bare "8 present" against a nine-line layout reads as a bundle short of a file.
LAYOUT_DETAIL="$(json_field "$BUNDLE/run.json" 'd["captured"]["layout"]["detail"]')"
DECLARED="$(horizon_bundle_layout_paths | wc -l | tr -d ' ')"
case "$LAYOUT_DETAIL" in
  "$((DECLARED - 1)) of $DECLARED declared path(s) present;"*) : ;;
  *) fail "the inventory does not say how many of how many paths it found: $LAYOUT_DETAIL" ;;
esac
pass "run.json records the run-time project path, that every capture landed, and the inventory's own arithmetic"

# The claim the README makes to the next reader, executed rather than trusted: loop.json is
# recomputable from the bundle alone, using the path run.json records.
RECOMPUTED="$WORK/recomputed.json"
# Read into a variable FIRST, the way every other call in this file does. `json_field`
# refuses by calling `fail`, which exits - but only the subshell the substitution forked,
# and bash does not check an embedded substitution's status when it is merely one word of
# a command line. Inlined here, a run.json that had stopped recording `project.path` would
# hand sessions.py an empty argument, and the diff below would fail somewhere else
# entirely. The assignment is what makes the refusal reach this script. [LAW:no-silent-failure]
RECORDED_PROJECT="$(json_field "$BUNDLE/run.json" 'd["project"]["path"]')"
( cd "$BUNDLE/seed/macklebox" && git log --reverse --format='%H%x09%cI' ) \
  | python3 "$SCRIPT_DIR/sessions.py" "$BUNDLE/transcripts" \
      "$RECORDED_PROJECT" "$BUNDLE/goal.md" \
  > "$RECOMPUTED" || fail "loop.json could not be recomputed from the bundle"
diff "$BUNDLE/loop.json" "$RECOMPUTED" >/dev/null \
  || fail "recomputing loop.json from the bundle gives a different answer than the run recorded"
pass "loop.json recomputes from the bundle alone, byte for byte"

# ── 2. The shape does not depend on how the run ended ──────────────────────────────────

DIED="$WORK/died"
mkdir -p "$DIED"
# Its OWN config dir, not section 1's. Reusing $CONFIG produced the intended "no
# transcripts" bundle only because the capture above had already moved $CONFIG/projects
# into that bundle - a side effect of a different section, nowhere stated, and the kind
# of coupling that survives until somebody reorders the file and then silently tests the
# opposite scenario from the one the heading claims.
# [LAW:no-ambient-temporal-coupling] the scenario builds what it needs.
# With no projects/ inside it, which is what a config dir looks like when the run died
# before a session ever booted - and is exactly the state section 1 left $CONFIG in by
# accident. Built on purpose here, it is the scenario rather than a leftover.
DIED_CONFIG="$WORK/died-config"
mkdir -p "$DIED_CONFIG"
horizon_capture_bundle "$DIED_CONFIG" "$DIED" "2026-01-01T00:00:00Z" >/dev/null 2>&1 \
  && fail "a run that died before seeding reported a successful capture"

[ -f "$DIED/run.json" ] || fail "a run that died before seeding left no run.json"
[ -f "$DIED/README.md" ] || fail "a run that died before seeding left no README"

COMPLETE_KEYS="$(json_field "$BUNDLE/run.json" 'sorted(d)')"
DIED_KEYS="$(json_field "$DIED/run.json" 'sorted(d)')"
[ "$COMPLETE_KEYS" = "$DIED_KEYS" ] \
  || fail "run.json keys differ by how the run ended: $COMPLETE_KEYS vs $DIED_KEYS"
COMPLETE_STEPS="$(json_field "$BUNDLE/run.json" 'sorted(d["captured"])')"
DIED_STEPS="$(json_field "$DIED/run.json" 'sorted(d["captured"])')"
[ "$COMPLETE_STEPS" = "$DIED_STEPS" ] \
  || fail "the captures reported differ by how the run ended: $COMPLETE_STEPS vs $DIED_STEPS"
pass "a run that died before seeding answers the same questions as one that finished"

[ "$(json_field "$DIED/run.json" 'd["captured"]["backlog"]["ok"]')" = False ] \
  || fail "a bundle with no project claims it captured a backlog"
json_field "$DIED/run.json" 'd["captured"]["backlog"]["detail"]' | grep -q 'seeding' \
  || fail "a capture that could not run does not say why"
pass "a capture that could not run records that it did not, and why"

# ── 3. A short capture is refused ──────────────────────────────────────────────────────

SHORT="$WORK/short"
mkdir -p "$SHORT/prs"
# #88, not #8. The numbers in HORIZON_FIXTURE_PR_NUMBERS are served by the fake `gh` to
# the real capture further down, so overwriting one of those with a deliberately broken
# document would leave a later check passing for a reason nobody wrote it to test.
write_pr_fixture 88 2 0 truncated
cp "$HORIZON_FIXTURE_DIR/pr-88.json" "$SHORT/prs/pr-0088.json"
if python3 "$SCRIPT_DIR/prs.py" "$SHORT/prs" 2>"$WORK/short.err"; then
  fail "a pull request whose review threads ran past one page was accepted as complete"
fi
grep -q 'reviewThreads' "$WORK/short.err" \
  || fail "the refusal does not name what came back short: $(cat "$WORK/short.err")"
[ ! -e "$SHORT/prs/index.json" ] \
  || fail "a refused capture still wrote an index, which reads as a complete one"
pass "a capture that came back short is refused, by name, and writes no index"

# ── 4. Each capture works on its own, not only from inside the close-out ───────────────
#
# bash is dynamically scoped: a `local` in horizon_capture_bundle is visible to everything
# it calls, so a capture that read the caller's variable instead of its own argument worked
# from there and nowhere else. horizon_capture_backlog did exactly that, and wrote to
# `/backlog/export.json` the moment anything else called it. Called here from a shell
# holding no such variable, which is the only place that mistake is visible.
STANDALONE="$WORK/standalone"
mkdir -p "$STANDALONE"
horizon_capture_backlog "$STANDALONE" "$BUNDLE/seed/macklebox" >/dev/null \
  || fail "capturing the backlog outside the close-out failed"
[ -f "$STANDALONE/backlog/export.json" ] \
  || fail "the backlog capture wrote somewhere other than the bundle it was handed"
pass "a capture writes to the bundle it is handed, not to one its caller happened to name"

# ── 5. A capture that could not read its subject refuses, rather than reporting zero ──
#
# Each of these produces a file or a number that looks exactly like a real, quiet, empty
# result. That resemblance is the whole hazard: a reader has no way to tell a run that
# created nothing from a recording that broke, and they are opposite findings.

# `lit export` exits 0 on a sync it cannot settle and writes an empty document. Every run
# is seeded with a backlog, so no tickets at all is that failure and never a thin backlog.
EMPTY_PROJECT="$WORK/empty-backlog"
mkdir -p "$EMPTY_PROJECT"
git -C "$EMPTY_PROJECT" init --quiet --initial-branch=master
git -C "$EMPTY_PROJECT" config user.name "horizon verify"
git -C "$EMPTY_PROJECT" config user.email "horizon@promptctl.invalid"
printf 'print("hi")\n' > "$EMPTY_PROJECT/app.py"
git -C "$EMPTY_PROJECT" add -A
git -C "$EMPTY_PROJECT" -c commit.gpgsign=false commit --quiet -m "seed"
( cd "$EMPTY_PROJECT" && lit init >/dev/null )
git -C "$EMPTY_PROJECT" config core.sshCommand /bin/false
git -C "$EMPTY_PROJECT" remote add origin "git@github.com:promptctl/horizon-eval.git"
EMPTY_BUNDLE="$WORK/empty-backlog-bundle"
mkdir -p "$EMPTY_BUNDLE"
if ( horizon_capture_backlog "$EMPTY_BUNDLE" "$EMPTY_PROJECT" ) >"$WORK/empty.out" 2>&1; then
  fail "a backlog export holding no tickets was recorded as a captured backlog"
fi
grep -q 'no tickets' "$WORK/empty.out" \
  || fail "the refusal does not say what was wrong: $(cat "$WORK/empty.out")"
# And it leaves nothing behind. A refused export written in place is a well-formed
# `{"issues": []}` sitting under the name the bundle README sends a reviewer to, saying
# the run created no tickets - which is the opposite of what happened.
[ ! -e "$EMPTY_BUNDLE/backlog/export.json" ] \
  || fail "a refused backlog export was left in the bundle, reading as an empty backlog"
pass "an export with no tickets is refused, not counted as an empty backlog, and not left behind"

# The transcripts capture MOVES the directory in, so its absence means that step did not
# land. Analysing that as a run of zero sessions writes a clean, entirely fabricated
# loop.json - and the README sends readers to loop.json on its own.
NO_TRANSCRIPTS="$WORK/no-transcripts"
mkdir -p "$NO_TRANSCRIPTS"
cp -R "$BUNDLE/seed" "$NO_TRANSCRIPTS/seed"
cp "$BUNDLE/goal.md" "$NO_TRANSCRIPTS/goal.md"
if ( horizon_capture_loop "$NO_TRANSCRIPTS" "$NO_TRANSCRIPTS/seed/macklebox" ) \
     >"$WORK/noloop.out" 2>&1; then
  fail "the loop capture reported a run from a bundle whose transcripts never landed"
fi
[ ! -e "$NO_TRANSCRIPTS/loop.json" ] \
  || fail "the loop capture wrote a record of a run it could not read"
pass "a bundle whose transcripts did not land is refused, not reported as zero sessions"

# ── 6. run.json stays readable whatever a step printed ────────────────────────────────

CHATTY="$(horizon_capture_step chatty python3 -c 'print("x" * 5000)')"
CHATTY_DETAIL="$(printf '%s' "$CHATTY" | cut -f3)"
[ "${#CHATTY_DETAIL}" -lt 5000 ] \
  || fail "a step that printed 5000 characters put all of them in run.json"
case "$CHATTY_DETAIL" in
  *"(truncated)") : ;;
  *) fail "a detail was cut without saying so: $CHATTY_DETAIL" ;;
esac
TERSE="$(horizon_capture_step terse printf 'two tickets\n')"
[ "$(printf '%s' "$TERSE" | cut -f3)" = "two tickets" ] \
  || fail "a detail short enough to keep was altered anyway"
pass "a long capture detail is bounded and says it was cut; a short one is left alone"

# ── 7. The record's own failure paths ─────────────────────────────────────────────────

mkdir -p "$WORK/malformed"
if printf 'this row has no tabs\n' \
     | python3 "$SCRIPT_DIR/bundle.py" "$WORK/malformed" run.json \
         "2026-01-01T00:00:00Z" "2026-01-01T01:00:00Z" "$BUNDLE/seed/macklebox" \
         2>"$WORK/malformed.err"; then
  fail "a malformed capture row was written into run.json instead of refused"
fi
grep -q 'malformed capture row' "$WORK/malformed.err" \
  || fail "the refusal does not name the problem: $(cat "$WORK/malformed.err")"

# Two rows under one name would collapse into one entry, leaving run.json holding fewer
# captures than the close-out ran - in the file whose whole contract is that every
# capture has an entry.
mkdir -p "$WORK/doubled"
if printf 'backlog\t1\tone\nbacklog\t0\tanother\n' \
     | python3 "$SCRIPT_DIR/bundle.py" "$WORK/doubled" run.json \
         "2026-01-01T00:00:00Z" "2026-01-01T01:00:00Z" "$BUNDLE/seed/macklebox" \
         2>"$WORK/doubled.err"; then
  fail "two capture rows sharing a name collapsed into one entry without complaint"
fi
grep -q 'both named' "$WORK/doubled.err" \
  || fail "the refusal does not name the collision: $(cat "$WORK/doubled.err")"

# An unreadable clock must read back as null, never as a duration of zero: one is a claim
# about the record and the other is a claim about the run.
mkdir -p "$WORK/clockless"
printf 'transcripts\t1\t3 transcript(s)\n' \
  | python3 "$SCRIPT_DIR/bundle.py" "$WORK/clockless" run.json "not-a-time" "nor-this" \
      "$BUNDLE/seed/macklebox" \
  || fail "an unreadable clock took down the whole record"
[ "$(json_field "$WORK/clockless/run.json" 'd["duration_seconds"]')" = None ] \
  || fail "an unreadable clock became a duration instead of null"

# And a clock that ran BACKWARDS is the same kind of record. Both stamps parse here, so
# the guard above lets this through; what comes out the other side without a second guard
# is a negative number that reads like a duration and gets averaged like one.
mkdir -p "$WORK/backwards"
printf 'transcripts\t1\t3 transcript(s)\n' \
  | python3 "$SCRIPT_DIR/bundle.py" "$WORK/backwards" run.json \
      "2026-01-01T09:00:00Z" "2026-01-01T08:00:00Z" "$BUNDLE/seed/macklebox" \
  || fail "a backwards clock took down the whole record"
[ "$(json_field "$WORK/backwards/run.json" 'd["duration_seconds"]')" = None ] \
  || fail "a run whose end precedes its start reported a duration: $(json_field "$WORK/backwards/run.json" 'd["duration_seconds"]')"
pass "run.json refuses a malformed row and a duplicated one, and records an unreadable and a backwards clock as null"

# ── 7b. A seed manifest that exists and will not read is not "the run never seeded" ───
#
# Two different findings that used to produce one sentence in the record. The bundle has a
# seed/ with a project directory sitting in it, so a reader told "the run ended before
# seeding finished" is told something the bundle itself contradicts.
UNREADABLE="$WORK/unreadable-manifest"
mkdir -p "$UNREADABLE/seed/macklebox"
printf '{ this is not json' > "$UNREADABLE/seed/seed-manifest.json"
[ -z "$(horizon_bundle_project_dir "$UNREADABLE" 2>/dev/null)" ] \
  || fail "an unreadable seed manifest resolved to a project directory anyway"
# Resolving to empty is not enough and never was: that is what the masked version did too.
# What has to be true is that the reason was SAID. An unattended close-out has nobody
# reading a python traceback, and "could not read project.name" without this line leaves
# the reader to conclude from silence that there was simply no manifest.
UNREADABLE_LOG="$( ( horizon_bundle_project_dir "$UNREADABLE" >/dev/null ) 2>&1 )"
case "$UNREADABLE_LOG" in
  *"is present but records no readable project.name"*) : ;;
  *) fail "an unreadable seed manifest was masked as an absent one: $UNREADABLE_LOG" ;;
esac
UNREADABLE_REFUSAL="$( ( horizon_require_bundle_project "$(horizon_bundle_project_dir "$UNREADABLE")" ) 2>&1 )" \
  && fail "a bundle whose manifest will not read was accepted as having a project"
case "$UNREADABLE_REFUSAL" in
  *"cannot be read"*) : ;;
  *) fail "the refusal still asserts a cause it did not check: $UNREADABLE_REFUSAL" ;;
esac
pass "a seed manifest that exists and will not read is refused without inventing a cause"

# ── 8. Every way a PR capture can come back unusable is refused ───────────────────────
#
# Usage: refuses_capture <name> <document-file> <expected-text-in-the-refusal>
refuses_capture() {
  local name="$1" document="$2" expected="$3" dir="$WORK/refuse-$1"
  mkdir -p "$dir/prs"
  cp "$document" "$dir/prs/pr-0008.json"
  if python3 "$SCRIPT_DIR/prs.py" "$dir/prs" 2>"$dir/err"; then
    fail "a capture that $name was accepted as a complete pull request"
  fi
  grep -q "$expected" "$dir/err" \
    || fail "the refusal for '$name' does not name it: $(cat "$dir/err")"
  [ ! -e "$dir/prs/index.json" ] \
    || fail "a capture that $name still wrote an index, which reads as a complete one"
}

write_pr_fixture 89 2 0 thread-truncated
refuses_capture "overflowed one thread's comments" \
  "$HORIZON_FIXTURE_DIR/pr-89.json" 'more comments than one page'

printf '{"errors": [{"message": "Could not resolve to a Repository."}]}\n' \
  > "$WORK/graphql-error.json"
refuses_capture "came back a GraphQL error" "$WORK/graphql-error.json" 'GraphQL error'

printf '{"data": {"repository": {"pullRequest": null}}}\n' > "$WORK/no-such-pr.json"
refuses_capture "named a pull request that does not exist" \
  "$WORK/no-such-pr.json" 'captured no pull request'

printf '{"data": {"repository": {}}}\n' > "$WORK/shapeless.json"
refuses_capture "does not have the shape prs.py reads" \
  "$WORK/shapeless.json" 'disagree about the document'
pass "a short, errored, empty or drifted PR capture is refused by name and writes no index"

# ── 9. A file appears in a bundle only once it is whole ───────────────────────────────
#
# A redirect is opened before the command that fills it runs, so every `> file` on a
# failing path leaves a zero-byte file behind. The layout inventory then counts the path
# as present and a reader opening it gets nothing - the same empty-loop.json shape this
# capture was written to remove.

PARTIAL="$WORK/partial-loop"
mkdir -p "$PARTIAL"
cp -R "$BUNDLE/transcripts" "$PARTIAL/transcripts"
# The project is named at its original path, the way run.json records it, so the ONLY
# reason this analysis fails is the one being tested: there is no goal.md to compare a
# carried goal against.
if ( horizon_capture_loop "$PARTIAL" "$BUNDLE/seed/macklebox" ) >/dev/null 2>&1; then
  fail "the loop capture succeeded with no goal wording to compare against"
fi
[ ! -e "$PARTIAL/loop.json" ] \
  || fail "a failed analysis left an empty loop.json in the bundle"
# Nothing else appeared either - named by what the bundle HOLDS, not by what a leftover
# might be called. The check here used to glob for `*.partial`, which no code path has
# ever written: staging is a `mktemp` under $TMPDIR with a random suffix, and `.partial`
# was the rejected design. A check that cannot fail passes a regression through as
# readily as a fix, which is the one thing a gate may never do.
LEFT_BEHIND="$(cd "$PARTIAL" && find . -mindepth 1 -maxdepth 1 | sort | tr '\n' ' ')"
[ "$LEFT_BEHIND" = "./transcripts " ] \
  || fail "a failed capture left something in the bundle beyond what it was given: $LEFT_BEHIND"
pass "a failed analysis leaves no loop.json at all, whole or empty"

PR_PARTIAL="$WORK/pr-partial"
mkdir -p "$PR_PARTIAL/seed"
cp -R "$BUNDLE/seed/macklebox" "$PR_PARTIAL/seed/macklebox"
horizon_record_remote_time_zero "$PR_PARTIAL" "promptctl/horizon-eval" >/dev/null
# #10 is listed at the remote and has no fixture behind it, so its query fails.
HORIZON_FIXTURE_PR_NUMBERS="7 8 9 10"
if ( horizon_capture_prs "$PR_PARTIAL" "$PR_PARTIAL/seed/macklebox" ) >/dev/null 2>&1; then
  fail "a pull request whose query failed was captured anyway"
fi
HORIZON_FIXTURE_PR_NUMBERS="7 8 9"
[ ! -e "$PR_PARTIAL/prs/pr-0010.json" ] \
  || fail "a failed PR query left an empty pr-0010.json in the bundle"
# And prs/ holds exactly the queries that SUCCEEDED plus the watermark - no staging file
# under any name, including one a future change might invent.
PRS_LEFT="$(cd "$PR_PARTIAL/prs" && find . -mindepth 1 -maxdepth 1 | sort | tr '\n' ' ')"
# #7 is the watermark itself, so it belongs to an EARLIER run and is never captured.
[ "$PRS_LEFT" = "./pr-0008.json ./pr-0009.json ./time-zero.json " ] \
  || fail "a failed PR capture left prs/ holding something other than the queries that worked: $PRS_LEFT"
pass "a pull request whose query failed leaves no file behind, empty or otherwise"

# ── 10. A second close-out over one bundle is refused, not silently nested ────────────
#
# `mv` given an existing directory moves the source INSIDE it. transcripts/projects/<slug>
# reads as a successful capture - the count even comes out right - while sessions.py globs
# one level up, matches nothing, and reports a run of zero sessions that spent nothing.
RECAPTURE="$WORK/recapture"
mkdir -p "$RECAPTURE/transcripts" "$WORK/cfg2/projects/p"
printf '{}\n' > "$WORK/cfg2/projects/p/s.jsonl"
if ( horizon_capture_transcripts "$WORK/cfg2" "$RECAPTURE" ) >"$WORK/recapture.out" 2>&1; then
  fail "a second capture into a bundle that already had transcripts reported success"
fi
[ ! -e "$RECAPTURE/transcripts/projects" ] \
  || fail "a second capture nested the transcripts where nothing reads them"
pass "a bundle that already holds transcripts refuses a second capture rather than nesting it"

# ── 11. The close-out invents nothing for a run that never began ──────────────────────
#
# The exit handler is installed before the driver creates its work dir, so it also runs
# for failures that happened first - an unauthenticated config dir, most often. A bundle
# conjured there is refused by the NEXT run's "work dir already holds a run" guard, about
# a run that never started.
NEVER="$WORK/never-began"
( horizon_capture_bundle "$CONFIG" "$NEVER" "2026-01-01T00:00:00Z" ) >/dev/null 2>&1 \
  || fail "the close-out treated a run that never began as a failed capture"
[ ! -e "$NEVER" ] \
  || fail "the close-out created a work dir for a run that never began, which blocks the next run"
pass "a run that ended before it made a work dir leaves nothing behind"

# ── 12. Token totals that are a floor say so, and the close-out refuses them ──────────

DISAGREED="$WORK/disagreed"
mkdir -p "$DISAGREED"
cp -R "$BUNDLE/transcripts" "$DISAGREED/transcripts"
cp "$BUNDLE/goal.md" "$DISAGREED/goal.md"
python3 "$WORK/clash.py" "$DISAGREED/transcripts"
if ( horizon_capture_loop "$DISAGREED" "$BUNDLE/seed/macklebox" ) >"$WORK/disagreed.out" 2>&1; then
  fail "a run whose token totals are a floor was captured as if they were a count"
fi
grep -q 'usage_disagreements' "$WORK/disagreed.out" \
  || fail "the refusal does not say where to look: $(cat "$WORK/disagreed.out")"
[ "$(json_field "$DISAGREED/loop.json" 'd["usage_disagreements"]')" = 1 ] \
  || fail "the record does not count the disagreement it refused over"
pass "a disagreed token total is recorded, kept, and refused by the close-out"

# The other way a total stops being a count: a transcript that recorded no working
# directory and still spent tokens. Nothing can say whose that spend is, so it is kept
# out of the total - and a total that is a floor must not be published as a count.
ORPHANED="$WORK/orphaned"
mkdir -p "$ORPHANED"
cp -R "$BUNDLE/transcripts" "$ORPHANED/transcripts"
cp "$BUNDLE/goal.md" "$ORPHANED/goal.md"
ORPHAN_DIR="$(dirname "$(find "$ORPHANED/transcripts" -name '*.jsonl' | head -1)")"
printf '%s\n' \
  '{"type": "last-prompt", "sessionId": "orphan"}' \
  '{"type": "assistant", "message": {"role": "assistant", "id": "orphan-1", "content": [{"type": "text", "text": "."}], "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 4242}}}' \
  > "$ORPHAN_DIR/orphan.jsonl"
if ( horizon_capture_loop "$ORPHANED" "$BUNDLE/seed/macklebox" ) >"$WORK/orphaned.out" 2>&1; then
  fail "a run with spend nobody could attribute was captured as if the totals were complete"
fi
grep -q 'unattributed' "$WORK/orphaned.out" \
  || fail "the refusal does not say where to look: $(cat "$WORK/orphaned.out")"
[ "$(json_field "$ORPHANED/loop.json" 'd["tokens"]["unattributed"]["output_tokens"]')" = 4242 ] \
  || fail "the record does not carry the spend it refused over"
[ "$(json_field "$ORPHANED/loop.json" 'd["tokens"]["total"]["output_tokens"]')" = 3500 ] \
  || fail "unattributed spend was folded into the total the analysis stands behind"
pass "spend nothing can attribute is kept out of the total, recorded, and refused by the close-out"

printf '\nall checks passed\n'
