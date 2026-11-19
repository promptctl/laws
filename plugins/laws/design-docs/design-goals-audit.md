# Design goals: the `audit` skill

This skill audits a whole codebase against the laws by running `laws:law-review` over many overlapping areas in parallel, then turning the pooled findings into work that fixes causes rather than symptoms. It runs forked on Opus; each area review runs on its own fork, which sends its angles to Haiku.

## What it's optimizing for

**Coverage of the whole codebase, including what lives between modules.** One review cannot read a whole repository, so the audit splits it. Many small areas mean every file is read by a reviewer that holds all of it; overlapping areas (seams, end-to-end units of work, shared state) catch the violations that only show to a reviewer holding both sides.

**Root causes fixed first, symptoms solved through them.** The owner's ranking (2026-11-18): the biggest, most architectural root causes lead; every other bug - and a law violation is a bug - is attributed to one of them; build, non-architectural performance, and other cleanup come last. Fifteen findings with one root cause are fifteen findings, not duplicates, and their root cause comes before any of them.

**A root cause stated, not solved.** The auditing agent names what law is broken, how, and where, from the findings in hand. It does no further research, proposes no fix, and writes no instructions: each root cause is significant, possibly wide-ranging work, and the agent that pulls its ticket needs room to decide how. That agent files the research-and-plan, fix, and test tickets, each a few lines saying where to start.

**Only tickets that change code.** Tickets are filed for root causes and one for cleanup. Every ticket ends in code changed, bugs fixed, or further tickets that carry its results into implementation - never in a measurement or a research result alone. The tests for bugs attributed to a root cause are deleted with the fix, not repaired, because they pin the shape the fix removes; the new tests conform to `laws:testing`.
