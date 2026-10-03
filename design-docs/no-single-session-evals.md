# Decision: no single-session project-outcome evals in this repo

**2026-08-09, owner decision; narrowed 2026-10-01.** This repo will not build, run, or
maintain evals that score whether an agent completes a single coding task or
single-session workflow. Any ticket proposing one gets closed wontfix and pointed here.

**What is not banned: per-law fork tests** (epic `promptctl-law-evals-qdn`, harness in
`evals/law/`). On 2026-10-01 the owner asked for evals that "test each individual law,
or capability, within a single turn"; "for the most part we should be able to test
individual pieces of guidance within a small amount of turns"; "some stuff like 'does
this activate reliably' might need to happen a bunch of turns in"; "our goal will be
LOW VARIANCE so we don't need to run 100x tests to get reliable data." A fork test does
not ask whether the task got done. It puts the agent at the one decision a law names,
where the unguided move is the violation, and reads mechanically which way it went. A
ticket for one of those is in scope; do not close it against this document.

## Why the outcome evals stay banned

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

An outcome ("make the gates pass") is reached by any competent model with or without
the laws, so it cannot see what the laws change. The laws' cumulative value — carrying-
cost held down, seams that stay smooth, representations that stay true — accrues across
sessions, refactors, and a growing codebase. A fork test sidesteps both problems by
measuring the mechanism instead of the outcome: whether this text moves the agent at the
decision it names.

## The long-horizon eval

The long-horizon eval (an agent builds a real project from scratch across many
sessions; the `horizon` epic, closed) measured the cumulative value directly, and the
owner dropped it on 2026-09-27: a five-run baseline was days of continuous Opus usage,
too much for what it returned. Its scripts are still in `horizon/`; its reference seed
was deleted in the commit for PR #78 and is recoverable from `35effb3`.

## Salvage

The deleted tree's isolation layer (isolated logged-in profile) and tmux session-driver
drove a live interactive session on the subscription. `evals/law/` uses `claude -p
--bare` on an API key instead; if a run ever needs the interactive transport, recover
them from git history at `cf5a570^` rather than rebuilding blind.
