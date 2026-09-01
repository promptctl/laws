# horizon: the controlled-inclusion instrument

Part of the long-horizon eval (epic `promptctl-horizon-7ry`): an agent builds a real
project from scratch, autonomously, across many sessions, and a human reads the
resulting run bundle. This directory is the instrument's pinned, reproducible
environment - the piece that makes a run's controlled variables checkable instead of
assumed.

## The one command

```sh
horizon/pin-instrument.sh <run-dir> [memento-ref] [reviewer-sha]
```

Builds `<run-dir>` from nothing:

- `pinned/` - a `git archive` snapshot of `plugins/memento` at the resolved
  `memento-ref` (default: this repo's current `HEAD`), plus a marketplace.json that
  declares that snapshot and *nothing else*.
- `config/` - a fresh `CLAUDE_CONFIG_DIR`, provisioned through the real `claude
  plugin` CLI, with memento installed and enabled and no other plugin even
  installable - the pinned marketplace never lists one.
- `manifest.json` - canonical JSON (sorted keys, no timestamps) recording every
  pinned identity: memento's commit and tree sha, the sha256 of the `lit` binary
  currently on `PATH`, the commit the reviewer action's `v1` tag resolves to plus the
  sha256 of its prompt file, and the sha256 of `horizon/GOAL_PROMPT.md`.

  `memento` and `goal_wording` are pure functions of `memento-ref`, so two runs at
  the same `memento-ref` are byte-identical on those fields by construction. The
  other two are resolved outside it: `lit` from whatever binary is on `PATH` (see
  below), and the reviewer live against a moving tag (`v1`) - left unpinned, two runs
  made minutes apart could legitimately disagree if the tag moved. Pass
  `[reviewer-sha]` explicitly - the same way a campaign already pins `memento-ref`
  for cross-run consistency - and the manifest is byte-identical across runs on every
  pinned field, provided the `lit` binary on `PATH` did not change between them.
  `reviewer.resolved_from` records whether this run resolved the tag live (`tag`) or
  was handed the sha (`override`), so the manifest never implies a check that did not
  happen.

A session launched with `CLAUDE_CONFIG_DIR=<run-dir>/config` sees memento's skills and
nothing of the owner's live laws plugin, `CLAUDE.md`, or memory. Two distinct
mechanisms produce that, and they are worth keeping straight: no *plugin* but memento
can be installed because the pinned marketplace never declares one - controlled
inclusion, not a launch-time filter over the owner's live config. `CLAUDE.md` and
memory are absent for the unrelated reason that `horizon_provision_config_dir` builds
the config dir from nothing (`rm -rf` then `mkdir`), so anything that later seeds or
templates that directory reintroduces the leak the marketplace guarantee does not
cover.
`lit` itself has no version string to pin (see lib.sh's comment on `horizon_lit_path`
for what `lit doctor` actually reports), so its identity is recorded as the sha256 of
whatever binary `command -v lit` resolves to; a later run whose `lit` hash disagrees
with an earlier manifest is a real config drift, not noise.

## Verify

```sh
horizon/verify-instrument.sh
```

Resolves the reviewer's pinned commit once (so a moving tag can't turn into test
flakiness) and runs `pin-instrument.sh` twice with it, checks the manifests are
byte-identical, then checks the isolated config dir has exactly memento installed
and enabled, carries no `CLAUDE.md` and no memory content under `projects/*/memory/`,
exposes the standard memento skills at its actual installed location (verified to
fall under the config dir, not merely to exist somewhere), and that the `lit` on
`PATH` matches what the manifest recorded.

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
horizon/run-loop.sh [seed-dir] [memento-ref]
```

Builds time zero with the two commands above, issues the pinned `/goal` wording once,
and then only observes. `seed-dir` defaults to `horizon/seeds/macklebox`. Every session
after the first is produced by memento's own relaunch.

The driver does not repair, and that is the central design point. memento's goal-carry
and its in-place relaunch are the controlled variables this eval measures. A driver that
re-issued a lost goal, or restarted a dead session, would be measuring itself: the run
would look healthiest exactly where the instrument is broken. So a lost carry stops the
run, loudly.

### One fixed working path, one login

Runs are built at one fixed working path (`~/.horizon/run`, override
`HORIZON_WORK_DIR`), and the finished run is copied to wherever runs are being kept.
That is not a convenience. Claude Code keys its stored credential to the config
directory's path, so wiping that directory keeps the login while building the run
somewhere new loses it — all of it established empirically.

Which is why the login is its own command, run once:

```sh
horizon/login.sh
```

A human with a browser does that once; every run afterwards is unattended. An
unauthenticated config dir does not fail loudly on its own. It boots to a login prompt
and waits forever, which in an unattended run is indistinguishable from an agent
thinking hard, so `run-loop.sh` refuses to launch until login has happened.

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

The run's record is `loop.json` in the work dir, produced by `sessions.py`. That program
is pure analysis over inputs it is handed — transcripts as files, commits on stdin — so
the same verdict can be recomputed from an archived run months later with nothing
running.

Per session it reports the session id, its time window, whether a `/goal` was issued,
whether that goal matches the pinned wording rather than merely being some goal, and
which commits fall in its window. It also reports the longest run of *consecutive*
sessions that each committed something. Consecutive matters: three committing sessions
with a dead one between them is a loop that stalled and was restarted.

Tests: `horizon/sessions.test.py`.

## What this does not do

Capturing the run bundle is a separate ticket (`promptctl-horizon-7ry.4`). This directory
pins the environment, builds the starting state, and drives the run that later piece
records.
