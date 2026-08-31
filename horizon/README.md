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

  Everything except the reviewer is a pure function of `memento-ref`, so two runs at
  the same `memento-ref` are byte-identical on those fields by construction. The
  reviewer is the one field resolved live against a moving tag (`v1`); left
  unpinned, two runs made minutes apart could legitimately disagree if the tag
  moved. Pass `[reviewer-sha]` explicitly - the same way a campaign already pins
  `memento-ref` for cross-run consistency - to get a fully byte-identical manifest
  across runs.

A session launched with `CLAUDE_CONFIG_DIR=<run-dir>/config` sees memento's skills
and nothing of the owner's live laws plugin, `CLAUDE.md`, or memory - controlled
inclusion, not exclusion: isolation comes from the pinned marketplace only ever
declaring memento, never from filtering the owner's live config out at launch time.
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

## What this does not do

Seeding a project (appspec + fresh repo + `lit init`), driving the unattended
multi-session loop, and capturing the run bundle are separate tickets
(`promptctl-horizon-7ry.2/.3/.4`). This directory only pins and records the
environment those later pieces run inside.
