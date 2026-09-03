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

- `pinned/` - a `git archive` snapshot of memento at the resolved `memento-ref`,
  fetched from the repository that owns it (`https://github.com/promptctl/memento`;
  `memento-ref` names a ref in *that* repository and defaults to its default branch,
  `master`), plus a marketplace.json that declares that snapshot and *nothing else*.
  The snapshot is memento's whole tree, not just its `memento/` plugin directory:
  memento keeps one copy of each skill at its repo root and symlinks it into every
  plugin that ships it, so archiving the plugin directory alone extracts dangling
  links. Snapshotting the closure is what makes the pin self-contained - `claude
  plugin install` then materialises those links into real files in its cache.
- `config/` - a fresh `CLAUDE_CONFIG_DIR`, provisioned through the real `claude
  plugin` CLI, with memento installed and enabled and no other plugin even
  installable - the pinned marketplace never lists one.
- `manifest.json` - canonical JSON (`schema_version: 2`, sorted keys, no timestamps)
  recording every pinned identity: memento's repository URL, commit and tree sha; the
  sha256 of the `lit` binary currently on `PATH` and of the `/next` procedure that
  binary writes; the commit the reviewer action's `v1` tag resolves to plus the sha256
  of its prompt file; and the commit and sha256 of `horizon/GOAL_PROMPT.md`.

  memento's fields are a pure function of `memento-ref`, so two runs at the same
  `memento-ref` are byte-identical there by construction. `goal_wording` is resolved
  separately, against this repo's own `HEAD`: `GOAL_PROMPT.md` lives here, and once
  memento moved to its own repository one sha could no longer honestly stand for both,
  so the commit it was read at is recorded as `goal_wording.ref`. The other two are
  resolved outside `memento-ref` entirely: `lit` from whatever binary is on `PATH` (see
  below), and the reviewer live against a moving tag (`v1`) - left unpinned, two runs
  made minutes apart could legitimately disagree if the tag moved. Pass
  `[reviewer-sha]` explicitly - the same way a campaign already pins `memento-ref`,
  whose default likewise tracks a moving branch - and the manifest is byte-identical
  across runs on every pinned field, provided the `lit` binary on `PATH` did not change
  between them. `reviewer.resolved_from` records whether this run resolved the tag live
  (`tag`) or was handed the sha (`override`), so the manifest never implies a check
  that did not happen.

A session launched with `CLAUDE_CONFIG_DIR=<run-dir>/config` sees memento's skills and
nothing of the owner's live laws plugin, `CLAUDE.md`, or memory. Two distinct
mechanisms produce that, and they are worth keeping straight: no *plugin* but memento
can be installed because the pinned marketplace never declares one - controlled
inclusion, not a launch-time filter over the owner's live config. That marketplace is
generated over the top of memento's own, which the whole-tree archive brings along and
which declares two plugins (memento and auto-bottle); the overwrite *is* the inclusion
control, because what a run can install is what the generated file lists, and it lists
one thing. `CLAUDE.md` and memory are absent for the unrelated reason that
`horizon_provision_config_dir` builds the config dir from nothing (`rm -rf` then
`mkdir`), so anything that later seeds or templates that directory reintroduces the
leak the marketplace guarantee does not cover.
`lit` itself has no version string to pin (see lib.sh's comment on `horizon_lit_path`
for what `lit doctor` actually reports), so its identity is recorded as the sha256 of
whatever binary `command -v lit` resolves to; a later run whose `lit` hash disagrees
with an earlier manifest is a real config drift, not noise. The loop's pickup step is
pinned the same way and for the same reason: `next` is not a plugin skill any more -
the procedure ships inside the lit binary, and `lit init` writes it into the project at
`.claude/skills/next/SKILL.md` - so the pin runs lit against a throwaway repo, hashes
what it wrote, and records that hash. A lit too old to write it fails the pin loudly,
naming the upgrade (it needs one newer than 0.11.0). memento supplies the loop's other
two skills, `address-pr-reviews` and `message-in-a-bottle`.

## Verify

```sh
horizon/verify-instrument.sh
```

Resolves both moving refs once - memento's default branch and the reviewer's `v1` tag -
and hands the same shas to both `pin-instrument.sh` runs, so a push or a tag move
landing between the two calls cannot turn into test flakiness, then checks the
manifests are byte-identical.

It then checks the isolated config dir has exactly memento installed and enabled,
carries no `CLAUDE.md` and no memory content under `projects/*/memory/`, and exposes
memento's skills at its actual installed location (verified to fall under the config
dir, not merely to exist somewhere) with contents equal, byte for byte, to the snapshot
they were pinned from. Equality rather than existence, because existence is what let
this verifier once go green against an instrument whose skills were all pointer stubs:
the directories were there, holding nothing an agent could follow. The pin now refuses
such a snapshot outright, so "the same bytes the snapshot carried" is the whole
remaining question.

Finally it checks both halves of `lit`'s recorded identity: the binary on `PATH`
against the manifest's hash of it, and the `/next` procedure that binary writes - run
into a throwaway repo again and re-hashed - against the manifest's hash of that.

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

## What this does not do

Driving the unattended multi-session loop and capturing the run bundle are separate
tickets (`promptctl-horizon-7ry.3/.4`). This directory pins the environment and builds
the starting state those later pieces run inside.
