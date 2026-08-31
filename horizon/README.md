# horizon: the controlled-inclusion instrument

Part of the long-horizon eval (epic `promptctl-horizon-7ry`): an agent builds a real
project from scratch, autonomously, across many sessions, and a human reads the
resulting run bundle. This directory is the instrument's pinned, reproducible
environment - the piece that makes a run's controlled variables checkable instead of
assumed.

## The one command

```sh
horizon/pin-instrument.sh <run-dir> [memento-ref]
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
  sha256 of its prompt file, and the sha256 of `horizon/GOAL_PROMPT.md`. Because
  nothing time-varying goes into it, running the command twice with the same inputs
  produces a byte-identical manifest.

A session launched with `CLAUDE_CONFIG_DIR=<run-dir>/config` sees memento's skills
and nothing of the owner's live laws plugin, `CLAUDE.md`, or memory - controlled
inclusion, not exclusion: isolation comes from the pinned marketplace only ever
declaring memento, never from filtering the owner's live config out at launch time.
`lit` itself has no version string to pin (`lit doctor` reports "dev build, build
date unknown"), so its identity is recorded as the sha256 of whatever binary
`command -v lit` resolves to; a later run whose `lit` hash disagrees with an earlier
manifest is a real config drift, not noise.

## Verify

```sh
horizon/verify-instrument.sh
```

Resolves the reviewer's pinned commit once (so a moving tag can't turn into test
flakiness) and runs `pin-instrument.sh` twice with it, checks the manifests are
byte-identical, then checks the isolated config dir has exactly memento installed
and enabled, carries no `CLAUDE.md` and no `projects/` (where session memory would
live), exposes the standard memento skills at its actual installed location, and
that the `lit` on `PATH` matches what the manifest recorded.

## What this does not do

Seeding a project (appspec + fresh repo + `lit init`), driving the unattended
multi-session loop, and capturing the run bundle are separate tickets
(`promptctl-horizon-7ry.2/.3/.4`). This directory only pins and records the
environment those later pieces run inside.
