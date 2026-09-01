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
tested rather than trusted. It also ships a `post-commit` file inside a seed and requires
that seeding succeed while the file never runs: content a seed carries is content, never
something the instrument executes.

## What this does not do

Driving the unattended multi-session loop and capturing the run bundle are separate
tickets (`promptctl-horizon-7ry.3/.4`). This directory pins the environment and builds
the starting state those later pieces run inside.
