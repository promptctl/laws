# Decision: no single-session eval work in this repo. Period.

**2026-08-09, owner decision.** This repo will not build, run, or maintain evals of
single coding tasks or single-session workflows. Not "deprioritized" — banned. Any
future ticket proposing one gets closed wontfix and pointed here.

## Why

Claude completing a bounded, single-session coding task is already established — it
does not need re-proving, and a harness that re-proves it burns tokens and owner
attention measuring a question nobody is asking.

The harness this repo built (evals/, deleted in the commit that adds this file; parts
restored since, see Salvage) confirmed the deeper problem empirically. Its own
sensitivity records, both campaigns:

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

Nothing yet. The long-horizon eval (an agent builds a real project from scratch across
many sessions; the `horizon` epic, closed) was the planned replacement, and the owner
dropped it on 2026-09-27: a five-run baseline was days of continuous Opus usage, too
much for what it returned. A cheaper method is still to be worked out. This decision
does not reopen single-session evals.

## Salvage

The deleted tree's `evals/isolation` (isolated logged-in profile) and `evals/driver`
(tmux session driver) were transport, not single-task apparatus. They are restored from
`cf5a570^` as source material for the harness epic (`promptctl-harness-4r0`), together
with `evals/run`, `evals/compare`, `evals/configs`, `evals/judge` and `evals/judges`. Those
five are the single-task scoring layer. They are restored only as reference for config,
run-record and judge shapes, and this decision still bans reviving them as evals. `evals/run`
and `evals/compare` source the deleted `evals/tasks/lib.sh`, so they do not run. `evals/tasks`
and `evals/suites`, the single-session cases, stay deleted. The long-horizon harness's
scripts are still in `horizon/`; its reference seed was deleted in the commit for PR #78
and is recoverable from `35effb3`.

## Transport

**2026-10-03, owner decision**, verbatim: "'-p --bare' is ACTUALLY banned, this is the
user saying this, right here, officially. It's banned." Harness runs use the owner's
Claude Code subscription login, never an API key.
