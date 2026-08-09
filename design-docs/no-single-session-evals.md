# Decision: no single-session eval work in this repo. Period.

**2026-08-09, owner decision.** This repo will not build, run, or maintain evals of
single coding tasks or single-session workflows. Not "deprioritized" — banned. Any
future ticket proposing one gets closed wontfix and pointed here.

## Why

Claude completing a bounded, single-session coding task is already established — it
does not need re-proving, and a harness that re-proves it burns tokens and owner
attention measuring a question nobody is asking.

The harness this repo built (evals/, deleted in the commit that adds this file)
confirmed the deeper problem empirically. Its own sensitivity records, both
campaigns:

- 2026-07-31: every visible-gate task saturated — all arms passed everything.
- 2026-08-01: the one task with headroom produced no trusted separation between
  laws-on and laws-off arms; the surviving signal was a single spec-interpretation
  bit, not engineering quality.

A single session is too small a stage for the laws to differentiate on. The value
the laws claim — carrying-cost held down, seams that stay smooth, representations
that stay true — accrues across sessions, refactors, and a growing codebase. An
instrument scoped to one session structurally cannot see it, no matter how well
built.

## What replaces it

The long-horizon eval: an agent builds a real project from scratch, autonomously,
across many sessions, under the repo's actual workflow — and the artifact is judged
where the laws' value actually lives. See the `horizon` epic in the tracker.

## Salvage

The deleted tree's isolation layer (isolated logged-in profile) and tmux
session-driver were transport, not single-task apparatus. If the long-horizon
harness wants them, recover from git history at this file's introducing commit
rather than rebuilding blind.
