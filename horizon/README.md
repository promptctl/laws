# horizon: the controlled-inclusion instrument

Part of the long-horizon eval (epic `promptctl-horizon-7ry`): an agent builds a real
project from scratch, autonomously, across many sessions, and a human reads the
resulting run bundle. This directory is the instrument's pinned, reproducible
environment - the piece that makes a run's controlled variables checkable instead of
assumed.

## The one command

```sh
horizon/pin-instrument.sh <run-dir> [memento-ref] [reviewer-sha] [goal-ref] [lit-ref]
```

An empty argument means that argument's default, so a caller can pass a later argument
without inventing values for the ones before it.

Builds `<run-dir>` from nothing:

- `pinned/` - a `git archive` snapshot of each of the run's two plugins, fetched from
  the repository that owns it: memento at `memento-ref` from
  `https://github.com/promptctl/memento`, extracted to `pinned/memento/`, and lit's
  Claude plugin (the one that ships `/next`, in its `claude-plugin/` directory) at
  `lit-ref` from `https://github.com/promptctl/links-issue-tracker`, extracted to
  `pinned/lit/`. Each ref names a ref in *that* repository and defaults to its default
  branch, which git asks the remote for at fetch time rather than reading a branch name
  copied into this codebase to go stale. Beside them sits
  `pinned/.claude-plugin/marketplace.json`, which declares those two plugins and
  *nothing else*.
  Each snapshot is its owner's whole tree, not just the plugin directory: memento keeps
  one copy of each skill at its repo root and symlinks it into every plugin that ships
  it, so archiving the plugin directory alone extracts dangling links. Snapshotting the
  closure is what makes the pin self-contained - `claude plugin install` then
  materialises those links into real files in its cache.
- `manifest.json` - canonical JSON (`schema_version: 4`, sorted keys, no timestamps)
  recording every pinned identity: the repository URL, commit and tree sha of memento
  and of lit's plugin (`lit_plugin`); the path and sha256 of the `lit` binary currently
  on `PATH`; the commit the reviewer action's `v1` tag resolves to plus the sha256 of its
  prompt file; the commit and sha256 of `horizon/GOAL_PROMPT.md`; and the harness the run
  executes on (`claude`) - the resolved path and version of the Claude Code binary, the
  campaign's version pin or `null`, and the model its sessions run.
- `bin/claude` - a symlink to that exact executable, and the thing `run-loop.sh` execs.

  memento's fields are a pure function of `memento-ref`, and `lit_plugin`'s of
  `lit-ref`, so two runs at the same refs are byte-identical there by construction.
  `goal_wording` is resolved separately, against `[goal-ref]` in this repo:
  `GOAL_PROMPT.md` lives here, and once memento moved to its own repository one sha
  could no longer honestly stand for both, so the commit it was read at is recorded as
  `goal_wording.ref`. The `lit` binary is resolved outside all of that, from whatever
  binary is on `PATH` (see below).

  Four of those identities hang off refs that move on their own: `memento-ref` and
  `lit-ref` default to their repositories' default branches, `goal-ref` to this
  checkout's `HEAD` - which advances whenever anything commits here - and the reviewer
  is resolved live against a moving tag (`v1`). Left to their defaults, two runs made
  minutes apart can legitimately disagree because one of the four moved between them. A
  campaign that wants its manifests byte-identical across runs passes all four
  explicitly - `memento-ref`, `reviewer-sha`, `goal-ref`, `lit-ref` - and the only field
  that can still drift afterwards is `lit`, if the binary on `PATH` changed in the
  meantime.
  `reviewer.resolved_from` records whether this run resolved the tag live
  (`tag`) or was handed the sha (`override`), so the manifest never implies a check
  that did not happen.

`pin-instrument.sh` touches nothing outside `<run-dir>`: `pinned/` and `manifest.json`
are all it produces, and because it shares no state with anything, two pins can run at
the same time safely. The run's `CLAUDE_CONFIG_DIR` lives at `$HORIZON_CONFIG_DIR` -
outside `<run-dir>`, at one fixed path, because Claude Code keys the stored credential to
that path. `run-loop.sh` rebuilds it right after the pin, while it holds the run lock,
through `horizon_provision_config_dir` and the real `claude plugin` CLI, from the pin's
`pinned/` snapshot. The result has every plugin the pinned marketplace lists - memento
and lit - installed and enabled, and nothing beyond those two even installable: the
marketplace never lists anything else. The path is not recorded in `manifest.json`; it
is a property of the machine, not of the pinned instrument.

A session launched with `CLAUDE_CONFIG_DIR=$HORIZON_CONFIG_DIR` sees memento's and lit's
skills and nothing of the owner's live laws plugin, `CLAUDE.md`, or memory. Two distinct
mechanisms produce that, and they are worth keeping straight: no *plugin* but those two
can be installed because the pinned marketplace never declares one - controlled
inclusion, not a launch-time filter over the owner's live config. The instrument writes
that marketplace itself, and it *is* the admitted set: `horizon_provision_config_dir`
installs every plugin it lists, and the verifier requires the installed set to equal
that list. memento's own marketplace.json, which declares memento and auto-bottle,
arrives with the whole-tree archive but sits inside `pinned/memento/`, where nothing
registers it. `CLAUDE.md` and memory are absent for the unrelated reason that
`horizon_provision_config_dir` builds the config dir from nothing (`rm -rf` then
`mkdir`), so anything that later seeds or templates that directory reintroduces the
leak the marketplace guarantee does not cover.

The loop's pickup step, `/next`, ships in lit's Claude plugin, so it is pinned the way
memento is: by commit, from lit's own repository. `lit init` does not write it into a
project. It is not pinned from the lit binary's build commit either, because the only
place the binary reports that is `lit version`, whose output lit's own source marks as
human-readable and not for parsing. memento supplies the loop's other two skills,
`address-pr-reviews` and `message-in-a-bottle`.

The binary still needs an identity of its own, since a run shells out to it, and with no
parseable version to read, the manifest records the path and sha256 of whatever binary
`command -v lit` resolves to. A later run whose `lit` hash disagrees with an earlier
manifest is a real config drift, not noise.

### The harness: the model, and Claude Code itself

Two controlled variables are properties of *this machine* rather than of anything the
pin fetches: the model the run's sessions think with, and the version of Claude Code
they run on. Neither has a repo or a ref, so `manifest.json` carries a `claude` block
holding a resolved path, an observed version, the campaign's pin, and the model.

**The model is set, not observed.** Launching bare `claude` takes whatever default the
installed CLI ships, so a manifest that only *recorded* a model would be naming a
control nothing applied. `horizon_write_model` writes `model` into the run config dir's
`settings.json` - Claude Code's own key for it - as the last step of provisioning. That
reaches every session of the run, including ones `finalize-session` relaunches, which
never see the driver's command line; a `--model` flag would reach only the first. It is
a full model id and never an alias, because `opus` resolves to a different model as new
ones ship, which is precisely the drift a five-run campaign must not absorb. Override it
with `HORIZON_CLAUDE_MODEL`.

**The version is pinned by resolving a symlink.** The native installer keeps versions
side by side as immutable executables (`~/.local/share/claude/versions/2.1.278`), and
auto-update *repoints* the `claude` on `PATH` at a new one rather than rewriting the file
behind it. So the name moves and its resolved target does not, and `pin-instrument.sh`
resolves it once and writes `<run-dir>/bin/claude` pointing at that exact executable.
`run-loop.sh` execs *that*, which is what makes an update landing mid-campaign unable to
reach a run. The symlink is named `claude` because `horizon_assert_transport` identifies
the pane process by that basename, and the resolved target's own filename is a version
string.

Pinning the first session pins them all: `horizon_assert_transport` guarantees the
in-place handoff, so every later session is that same process reset rather than a fresh
launch.

Two smaller guards sit behind that. `DISABLE_AUTOUPDATER=1` goes into the run's tmux
session so the run's own sessions cannot repoint the installation underneath it - it
cannot stop another session on the machine from doing so, and nothing repo-scoped could,
but the pinned symlink turns that case from silent version drift into a loud missing
binary. And after boot, `horizon_assert_booted_version` reads the version off the
session's own banner and requires it to equal the recorded one: every other field
describes a file the driver resolved, and this is the single reading taken from the
process that is actually running.

**`version_pin` states which control was applied.** It is `null` when
`HORIZON_CLAUDE_VERSION_PIN` is unset, and that null is the honest statement that the
version was *recorded but not held* - the run took whatever was installed. Set it to a
version string and `pin-instrument.sh` refuses any run on a different one, during the
pin, before the config dir is rebuilt and hours before a session would have made the
mismatch visible. There is deliberately no second `enforcement` field saying the same
thing in words: two spellings of one fact are two things that can disagree, and a reader
trusting the wrong one would credit a campaign with a control it never had.

## Verify

```sh
horizon/verify-instrument.sh
```

Resolves all four moving refs once - memento's default branch, lit's default branch,
the reviewer's `v1` tag, and this checkout's own `HEAD` - and hands the same shas to
both `pin-instrument.sh` runs, so a push, a tag move, or a commit landing here between
the two calls cannot turn into test flakiness, then checks the manifests are
byte-identical.

It then builds a config dir of its own from the second run's `pinned/` snapshot, through
`horizon_provision_config_dir`, at a throwaway path under its scratch dir; the machine's
real, authenticated `$HORIZON_CONFIG_DIR` is never touched. That dir must have exactly
the plugins the pinned marketplace lists installed, all enabled, and that list must
include memento and lit. It must carry no `CLAUDE.md` and no memory content under
`projects/*/memory/`, and expose memento's `address-pr-reviews` and
`message-in-a-bottle` and lit's `next` at their actual installed locations (verified to
fall under the config dir, not merely to exist somewhere) with contents equal, byte for
byte, to the snapshot they were pinned from. Equality rather than existence, because
existence is what let this verifier once go green against an instrument whose skills
were all pointer stubs: the directories were there, holding nothing an agent could
follow. The pin now refuses such a snapshot outright, so "the
same bytes the snapshot carried" is the whole remaining question.

One more check follows the byte comparison: the installed `finalize-session`, memento's
relaunch binary, must be executable. `diff` compares bytes, not mode bits, and `claude
plugin install` materialises symlinked files into real ones, which can drop the
executable bit; a relaunch binary without it breaks the session handoff silently.

It then checks the `lit` binary on `PATH` against the manifest's hash of it.

Finally it **boots a real session** against the config dir it just produced. Everything
above this point runs `claude plugin list`, which needs neither a credential nor a
terminal, and that is how the verifier twice went green against a config dir no
unattended run could actually launch a session in — once stopped at first-run
onboarding, once at the workspace trust dialog.

The launched session is required to reach `logged-out`, not `ready`, and the difference
is the check rather than a weakening of it. Claude Code keys its stored credential to
the config dir's **path**, so a throwaway dir under the verifier's scratch space is
unauthenticated by construction and nothing this script may do would change that. But
`logged-out` is reachable only by a session that has drawn its banner and its input box,
which means onboarding and the trust dialog are both settled — so the check proves
exactly the instrument's half of booting and claims nothing about the operator's. The
run asserts `ready`, against its own authenticated dir.

The project it launches in is reached through a **symlink** on purpose. Claude Code
records a workspace under its resolved path, so the
`projects[<dir>].hasTrustDialogAccepted` key that settles the trust dialog has to be
resolved too — written under an unresolved path it never matches, and the value sits in
`.claude.json` looking correct while the dialog still appears. On this platform that
needs no mistake by anyone: `/tmp` is `/private/tmp`, and `HORIZON_WORK_DIR` is an
operator override. The symlink makes that difference exist on every machine instead of
only where the work dir happens to sit under one.

Both live checks read the pane through one classifier, which turns it into exactly one
of six states:

| state | what the pane shows | what it means |
| --- | --- | --- |
| `ready` | banner **and** a painted status line with no login notice **on that line** | up and accepting input |
| `logged-out` | banner **and** `Not logged in` / `Login expired` | drew everything, authenticates nothing |
| `onboarding` | the theme picker, before any banner | boot state never reached this config dir |
| `untrusted` | the workspace trust dialog | the trust key was written under a path the CLI does not look itself up under |
| `bypass-disclaimer` | the bypass-permissions warning | the acceptance was written to a key this CLI version does not read |
| `forming` | nothing recognised yet, **or** a banner whose status line has not painted | still starting — no evidence either way |

`ready` is the only state that turns on something *not* being present, so it is the only
one that could be reached by looking too early. It requires the status line to have been
painted before it will read anything into that line being quiet: the mode indicator and
the login notice share it, so a pane showing the indicator has already had its chance to
show a notice. A poll landing between the banner and the status line gets `forming` and
tries again — never `ready` on the strength of evidence that had not arrived yet.

**Where the classifier looks matters as much as what it looks for.** The pane it reads is
not a static splash: `run-loop.sh` launches session one with the `/goal` wording as its
prompt, so by the time the run's own wait polls, *an agent is writing into this pane*. A
pattern matched anywhere in the capture is therefore a pattern the run itself can print —
an agent checking `gh auth status` and printing `Not logged in`, a grep echoing
`Accessing workspace:` out of `lib.sh`. Matched loosely, those turn the wait into a fatal
*false failure*: it dies on any settled state it did not want, so a healthy campaign run
is killed mid-flight with a confident wrong diagnosis.

Two anchors keep it reading the chrome rather than the content. The banner is tested
first and the gates only below it, because a pane showing the banner is past onboarding
and the trust dialog by construction — each of those replaces the whole screen. And the
login notice is required *on the status line itself*, the row carrying the mode
indicator, where the two sit left- and right-aligned; an agent would have to print both
markers on one row to forge it. A window of the last few rows is not enough, which is not
a guess: a pane holding a `Not logged in` tool result directly above the status line was
classified `logged-out` by exactly that rule.

`bypass-disclaimer` is the third gate `horizon_write_boot_state` settles, and it is the
one most likely to come back: the CLI has already moved that acceptance once — from
`bypassPermissionsModeAccepted` in `.claude.json` to `skipDangerousModePermissionPrompt`
in `settings.json` — and is expected to move it again. When it does, the key lands where
nothing reads it and the session stops on that dialog. Without a state of its own that
stop looked like `forming`: a run burning the full boot timeout and then reporting that
the pane "drew nothing this script recognises", about a dialog that was on screen the
whole time and was never going to clear.

A login wording that ever appeared somewhere other than the status line would read as
`ready` here, and that is the direction to fail in. The run proceeds to
`horizon_wait_goal_in_force`, which reads the **transcript** rather than the pane and
refuses within the same timeout with a report of what the session actually did. The cost
is a worse diagnosis; the cost the other way is a healthy run killed.

`logged-out` exists because readiness used to be a boolean and the boolean was wrong: a
session whose credential has died draws the banner *and* an input box, so grepping the
pane for the banner answered "ready" for a run that could never move — a driver then
watched a login prompt for a whole turn, unable to tell it from an agent thinking hard.
The banner is still necessary and is no longer sufficient.

`forming` is deliberately kept apart from the three failures rather than folded in with
them. A pane that has drawn nothing yet is a session still starting, not a broken one,
and that distinction is what lets the wait refuse a settled gate on the first poll — a
trust dialog does not clear itself, and a retired credential does not come back —
without also refusing a slow machine. It is the same rule the transcript classification
in `sessions.py` follows: a state that claims something needs evidence for it, and the
absence of evidence is its own state.

Every pattern the classifier matches was read off a real pane captured from a session
put deliberately into that state, and each state is checked against one of those
captured panes on every run — a live boot can only ever exhibit one state, so the other
branches would otherwise never execute.

## Seeding a run's time zero

```sh
horizon/seed-run.sh <run-dir> <seed-dir> [project-name]
```

Where `pin-instrument.sh` pins the environment, this builds the starting state inside
it. A **seed bundle** is the entire definition of time zero, and has exactly two parts:

- `repo/` — the tree copied verbatim into the project (for the reference seed: the
  appspec, `LICENSE`, `README.md`).
- `backlog.json` — a `lit import` spec: every ticket, its `parent`, and the
  cross-epic `blocks` edges declared as `depends_on`. It is lit's own format rather
  than a private one, so lit validates and wires the whole backlog in one transaction
  and there is no second schema here to drift from it.

`horizon/seeds/macklebox` is the reference seed, recovered from the reference run
itself — see its `PROVENANCE.md` for how time zero was identified and why the bundle is
vendored rather than fetched.

Seeding produces, under `<run-dir>`: the project (fresh history, no remote, spec
committed, `lit` initialised, backlog loaded), a `backlog-shape.json`, and a canonical
`seed-manifest.json` recording the seed's digest, the committed tree and HEAD, the
backlog's shape hash, and the identity of the `lit` that rendered `AGENTS.md`/`CLAUDE.md`.

The project directory's **name is part of time zero**, not cosmetics: `lit init` derives
the issue prefix from it. It defaults to the seed bundle's name.

### Why "shape" and not "identical"

lit generates issue ids and offers no way to choose them — an `id:` in an import doc
selects an *update* — so two seedings of one bundle always differ in their id suffixes.
`backlog.py` is where "the same backlog" is given a checkable meaning: it reads a
`lit export` and replaces every generated id with the item's structural position in
rank order, leaving exactly the part of the backlog the seed determines. The files, by
contrast, *are* byte-identical: commit identity and timestamps are pinned, so two
seedings produce the same tree and the same HEAD commit sha.

### Verify

```sh
horizon/verify-seed.sh [seed-dir]
```

Seeds twice and checks the manifests and backlog shapes are byte-identical, then checks
the seeded backlog against the **seed bundle** — every ticket, its parent, and every
`blocks` edge, keyed by title rather than by position, so a bug shared with `backlog.py`
cannot hide. Reproducibility alone would not be worth much: a seeding that silently
dropped every dependency edge reproduces that damage perfectly.

It then checks the repo has fresh history and no remote — `lit init` adopts a backlog
from a git remote when it finds one, which is exactly how this seed was recovered in the
first place. After that it diffs every file under the seed's `repo/` against what was
committed, byte for byte — the only check that ties a committed tree back to the seed,
since two matching manifests would agree just as happily on the wrong bytes.

It then seeds once more under an environment that exports `GIT_AUTHOR_NAME`,
`GIT_COMMITTER_NAME` and their email twins, and requires the commit sha to be unchanged.
Seeding twice on one machine cannot show this: both runs read the same environment and
agree with each other whatever it says. But git ranks those variables above `user.name`
from every config source, `-c` included, so without this check an operator whose shell or
CI wrapper already sets them would author the seed commit themselves — and time zero
would quietly differ per operator.

Finally it builds seeds that are deliberately wrong and requires each to be refused: a
dangling `parent`, a dangling `depends_on`, a repeated `local_id`, and a `repo/` tree
carrying its own `.git` (which would otherwise be merge-copied over the project's). The
first three are the references `verify-seed.sh` follows without checking them itself, on
the grounds that `lit import` rejects them first — this is where that assumption gets
tested rather than trusted, each case required to be refused for its own stated reason
rather than merely to fail. Finally it seeds under an operator global config whose
`core.hooksPath` points at a hostile `post-commit`, and requires that seeding succeed
while the hook never fires: no hook of the operator's runs against a seed commit.

## Driving a run unattended

```sh
horizon/run-loop.sh [seed-dir] [memento-ref] [lit-ref]
```

Builds time zero with the two commands above, launches session one with the pinned
`/goal` wording as claude's prompt, waits until that session's transcript records the
goal executed, and then only observes. `seed-dir` defaults to `horizon/seeds/macklebox`;
`memento-ref` and `lit-ref` go straight to `pin-instrument.sh`, and the reviewer and goal
refs are left to their defaults.
Every session after the first is produced by memento's own relaunch.

The goal is the launch prompt because a `/goal` typed or pasted into the input box does
not reliably run. Pasted at the pinned wording's size, Claude Code collapses it into a
`[Pasted text #n]` placeholder and submits it as a plain message, so the session reads
the wording with no goal in force (acceptance attempt 3, Claude Code v2.1.263). The same
text given as the launch prompt executes.

The driver does not repair, and that is the central design point. memento's goal-carry
and its in-place relaunch are the controlled variables this eval measures. A driver that
re-issued a lost goal, or restarted a dead session, would be measuring itself: the run
would look healthiest exactly where the instrument is broken. So a lost carry stops the
run, loudly.

### The shared run repository

Every run drives one repository that already exists: **`promptctl/horizon-eval`**. The
driver never creates a repository and never deletes one, so nothing in this eval needs a
credential that could destroy either. At the start of a run it resets that repo to the
seed — closes every open PR, deletes every branch but `master`, force-pushes the seeded
history — and points the project's `origin` at it.

The goal wording drives the agent to carry every unit of work to a merged PR, so it needs
somewhere to push and a place for the reviewer Action to run. Public, not private:
Actions minutes are unmetered on public repositories.

**Why shared rather than one repo per run.** A per-run repo has to answer "when is it
safe to create this?", and every answer is a claim about a moment in the driver's
execution order rather than a fact about the domain — create it before the session boots
and each boot failure mints a repo no run ever used; create it after the goal is issued
and the agent racing to its first push decides whether `origin` exists. A position
between the two works only until someone reorders the lines, and it leaves the eval
wanting the power to delete repositories to clean up after itself. A repository that
always exists has no such moment to get wrong.

**Why the reset runs at the start and not at the end.** A run that crashes never reaches
its own cleanup, so tidying afterwards leaves the next run to begin from wreckage — and
"usually clean" is not a time zero. Resetting on the way in makes the starting state a
function of that one call, whatever the previous run did or how it died.

**What survives a reset**, stated because it is a real divergence rather than an
oversight: pull requests can be closed but never deleted, so closed PRs accumulate and PR
numbers keep climbing. Run five does not start at `#1`. Nothing else carries over, and
`horizon_assert_remote_at_time_zero` checks the rest against GitHub rather than trusting
the commands that just ran.

**The repo is scratch space, not a record.** A run's PRs and review threads are captured
onto disk into the run bundle (see "The run bundle" below). Leaving them to live in a
GitHub repo would make the bundle depend on that repo surviving untouched forever, which
is the fragility capture exists to remove.

### Two paths, opposite lifetimes, one login

A run touches two directories and one tmux session; the directories are deliberately
not nested:

- `~/.horizon/config` (override `HORIZON_CONFIG_DIR`) — the `CLAUDE_CONFIG_DIR` every
  run launches against. **Permanent, and its exact path is load-bearing.** Claude Code
  keys its stored credential to that path, so wiping the directory keeps the login while
  building it somewhere new loses it — established empirically. Each run rebuilds it in
  place; only a move would break it.
- `~/.horizon/run` (override `HORIZON_WORK_DIR`) — one run's output. **Must not exist
  when a run starts**, so the last run's transcripts and commits can never be mistaken
  for this one's. Archiving it is the operator's job: copy the finished run wherever runs
  are kept, then remove it. `run-loop.sh` refuses to start while the directory exists,
  and its error message says exactly that.
- The tmux session `horizon-run` (not overridable) — the lock. `run-loop.sh` creates it
  before it creates the work dir, rebuilds the config dir, or resets the shared remote,
  and tmux refuses a duplicate session name atomically, so a second invocation dies at
  once and leaves nothing behind. **Held for the run's whole life:** claude is launched
  into that session's pane, and the driver's exit handler kills the session on every exit
  path — success, a failed assertion, the wall-clock ceiling — before it moves the
  transcripts out of the config dir, so after `run-loop.sh` exits nothing is still
  running and the next run starts against an idle machine. A driver killed without
  exiting (`kill -9`, a crashed terminal) leaves the session behind, and the next run
  refuses to start until `tmux kill-session -t horizon-run` clears it — only do that
  when no run is actually live.

Nesting them is a mistake this code made once: with the config dir living inside the run
dir, the work dir's freshness guard had to refuse the very directory the credential was
bound to, and no run could start after a login had happened.

Which is why the login is its own command, run once:

```sh
horizon/login.sh
```

A human with a browser does that once; every run afterwards is unattended. An
unauthenticated config dir does not fail loudly on its own. It boots to a login prompt
and waits forever, which in an unattended run is indistinguishable from an agent
thinking hard, so `run-loop.sh` refuses to launch until login has happened.
That refusal rests on a real request, not on a read of the stored credential: a refresh
token the server has retired still reads as logged in until a session tries to use it,
so after a long gap between runs `login.sh` can be needed again with nothing moved.

`login.sh` takes the same `horizon-run` tmux session as its lock for as long as the login
lasts, so a login cannot rotate the credential underneath a live run; while one is live
it refuses with the same "a run is live" message `run-loop.sh` gives.

### Why the run lives in tmux

The run is launched inside a detached tmux session, and that single fact decides whether
the run stays isolated. finalize-session chooses its handoff transport by walking process
ancestry: under a live tmux pane it resets *that* process in place, so
`CLAUDE_CONFIG_DIR`, `PATH` and flags survive, because nothing is relaunched. Launched
any other way it spawns a *new* tmux session, which inherits the tmux server's
environment rather than the caller's — the successor would silently read the operator's
real config while every log line still reported success. `run-loop.sh` asserts this
precondition before trusting a run.

The `/goal` wording is issued from the commit `manifest.json` names, never from the
working tree, so the bytes a run used and the `goal_wording.sha256` it reports cannot
diverge.

The work dir holds two subdirectories, `instrument/` and `seed/`, because
`pin-instrument.sh` and `seed-run.sh` each refuse a run-dir that already exists — a guard
worth keeping, so each gets its own directory rather than being loosened to share.

### What the run leaves behind

The work dir **is the run bundle** — see "The run bundle" below for its shape. `goal.md`
is the exact `/goal` wording the run issued, read from the commit `manifest.json` names.

The run's record is `loop.json`, produced by `sessions.py`. That program is pure
analysis over inputs it is handed — transcripts as files, commits on stdin — so the same
verdict can be recomputed from an archived run months later with nothing running.

Per session it reports the session id, its time window, whether a `/goal` was issued,
whether that goal matches the pinned wording rather than merely being some goal, and
which commits fall in its window. A goal counts only when the transcript records it
executed: the `/goal` command envelope, or the line announcing its Stop hook. A `/goal`
recorded as plain message text arrived without running, so it does not count. It also reports the longest run of *consecutive*
sessions that each committed something. Consecutive matters: three committing sessions
with a dead one between them is a loop that stalled and was restarted.

Two top-level fields count the carry. `goal_carries_expected` is the number of successor
sessions: those after the first that have shown evidence either way, a turn taken or a
goal recorded. Session one is excluded because the driver issued its goal directly, and
counting it would flatter the result. `goal_carries_intact` is how many of those
successors received the pinned wording exactly - their `goal_matches_pinned` is true.
`horizon_observe` in lib.sh reads both through `horizon_report_counts` and stops the run,
loudly, the moment they differ; that is the mechanism by which a lost carry stops the run.
`session_one_goal_in_force` says whether the driver's own launch put the pinned goal in
force. `horizon_wait_goal_in_force` requires it before the run is declared live.

Per session it also reports what that session **cost**, and `tokens` at the top level
totals the run: `sessions` for the agent's own spend, `subprocesses` for the headless
`claude` processes its tools spawned, `total` for the sum. The two are kept apart because
a configuration that leans on subagents and adversarial reviewers would otherwise look
free — on the one archived run this was checked against, the reviewer subprocesses
accounted for 39% of the run's output tokens.

The four usage figures are never added into a single "tokens used". A cached read and a
generated token differ in price by more than an order of magnitude, and this file is the
record a human quotes from.

Every transcript found under the run's config dir is one of four things, and `loop.json`
reports all four because they are not interchangeable. A **session** is the run's own, and
counts toward the acceptance. A **subprocess** matched the project but took no turns of
its own — a headless `claude -p` a tool spawned — so it is billed and counted
(`subprocess_transcripts`) without being a session. A **foreign** transcript
(`foreign_transcripts`) recorded a working directory and it was somebody else's; its spend
is not billed at all. A **forming** transcript (`forming_transcripts`) recorded no working
directory at any point, so nothing can say whose it is: Claude Code opens a transcript with
boot entries carrying neither `cwd` nor `entrypoint`, and some never acquire one. The
distinction between the last two is the whole point — absence of evidence is not evidence
of somebody else, and collapsing them once killed an unattended run at minute zero.

Two fields say the totals above cannot be trusted, and the close-out refuses a run that
reports either. `usage_disagreements` counts messages whose content blocks disagreed about
what the message cost; spend is billed once per message id, so a nonzero count means every
total is a floor rather than a count, and the larger figure is the one kept.
`tokens.unattributed` is spend found in a forming transcript, deliberately **not** folded
into `tokens.total` — `total` is what the analysis can stand behind, and a floor published
as a count is just a wrong number. `horizon_capture_loop` writes `loop.json` first and
refuses afterwards, because the record is not broken: it is complete, and what it says is
that the totals are unsafe.

Tests: `horizon/sessions.test.py`.

## The run bundle

```sh
horizon/verify-bundle.sh
```

The work dir a run leaves behind is the eval's **output**, not its scratch. There is no
scored layer anywhere here, so nothing downstream turns a run into a verdict — a person
opens one bundle beside another and reads them. That makes reviewability the product, and
it has to be two things at once:

- **Complete.** The record outlives the machine that made it. Transcripts live inside the
  config dir, which is a fixed path the next run wipes; a run's pull requests and review
  threads live on GitHub, in a repository the next run resets. Both are moved or copied
  into the bundle by the close-out, so nothing the bundle reports depends on anything
  outside it surviving untouched.
- **Identical in shape.** Two bundles are comparable because the same fact is in the same
  place in both.

`lib.sh` declares that shape once, in `HORIZON_BUNDLE_LAYOUT`. Three things read that one
declaration and nothing else: the close-out, which creates what it names; the bundle's own
`README.md`, rendered from it, so a reviewer never has to open this directory; and
`verify-bundle.sh`, which checks a captured bundle against it. A path spelled a second time
anywhere is a map that can drift from the tree it describes.

### A fixed record, not a fixed set of files

The part worth stating plainly, because it is what "identically structured" actually
buys: a run that finished the backlog and a run that died holding the lock produce
`run.json` with **the same keys and the same capture names**. A capture that could not run
is a *value* — `"ok": false` with the reason — never an absent file. An absent file makes
a reader guess between "this run had none" and "the recording broke", and those are
opposite findings.

That guarantee starts at the work dir, and the one case outside it is worth naming: a
run refused before it created one — the config dir failed to authenticate, the lock was
already held — leaves no bundle, and therefore no `run.json` at all. "A refused
invocation leaves nothing behind" is the older promise and it wins here, because the
alternative is a bundle directory conjured by the close-out for a run that never began,
which the next invocation then refuses to start on top of. No bundle, and a bundle that
answers every question, are both readable states; a bundle that exists because of how a
run *ended* is not.

A file in a bundle is whole or it is absent — never present and empty. Shell redirects
are opened before the command that fills them runs, so `> loop.json` on a failing path
left a zero-byte file the inventory then counted as present, which is the same
empty-`loop.json` shape acceptance attempt 1 produced. Both `loop.json` and each
`prs/pr-NNNN.json` are built outside the bundle and moved in, *outside* rather than
beside under a `.partial` name, because the analysis ends in a `die` and a die exits —
so a cleanup written after it never runs. For the same reason the close-out refuses a
bundle that already holds `transcripts/`: `mv` into an existing directory nests rather
than replaces, and `transcripts/projects/<slug>/` reads as a clean capture of a run that
did nothing.

The paths themselves are covered the same way rather than by a second promise. A run that
died before it was seeded genuinely has no `seed/`, so the close-out's last step
inventories the bundle against the layout and the `layout` capture *names* whatever is
missing. The guarantee is not that every bundle holds every file; it is that `run.json`
accounts for every file the layout declares, so absence is always read off the record
rather than inferred from a directory listing.

That is also why the close-out runs from the driver's exit handler on every path there is,
and why a failed capture fails the run. The run most worth reading is the one that died,
and it never reaches its own last line. Acceptance attempt 1 was stopped by hand four
minutes in and left an empty `loop.json` behind — a record that existed because of how the
run *ended* rather than because it ran — which is the shape this removes.

### Scoping a run's pull requests

Every run drives one shared repository, and closed pull requests are never deleted, so PR
numbers climb across runs. Immediately after the remote is reset — the one moment the fact
is true — the driver records the highest PR number as `prs/time-zero.json`. Everything
numbered above it is this run's work by construction, rather than by a creation timestamp
a slow clock or a long queue can put on the wrong side of the line.

Each pull request is captured in one GraphQL query, because a PR's body, its reviews and
its review threads are read together or they are read at inconsistent moments. GraphQL
rather than REST because `isResolved` exists nowhere else, and whether a review thread was
ever settled is the observation here, not decoration. The diff is deliberately not
captured: the produced repository is in the bundle with its whole history.

A connection that came back with `hasNextPage` stops the capture. A bundle holding most of
a review thread is worse than one holding none, because only the second announces itself.

### Reading a bundle again later

`loop.json` and `prs/index.json` both recompute from an archived bundle with nothing
running. The one field that makes it possible is `project.path` in `run.json`: transcripts
record the directory they were written in, so matching them up needs the path the run
*used*, which stops being where the bundle sits the moment anyone archives it. Passing the
wrong one used to report a run in which nothing happened; it now says so instead.
