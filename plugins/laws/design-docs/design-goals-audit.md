# Design goals: the `audit` skill

This skill audits a whole codebase against the laws by running `laws:law-review` over many overlapping areas in parallel, then turning the pooled findings into work that fixes causes rather than symptoms. It runs forked on Opus; each area review runs on its own fork, which sends its angles to Haiku.

## What it's optimizing for

**Coverage of the whole codebase, including what lives between modules.** One review cannot read a whole repository, so the audit splits it. Many small areas mean every file is read by a reviewer that holds all of it; overlapping areas (seams, end-to-end units of work, shared state) catch the violations that only show to a reviewer holding both sides.

**Root causes fixed first, symptoms never patched.** The owner's ranking (2026-11-18): the biggest, most architectural root causes lead; every other finding is attributed to one of them; build and non-architectural performance issues come last. Fifteen findings with one root cause are fifteen findings, not duplicates, and the root cause's fix comes before any of them.

**Tickets only for root causes, with the symptoms' tests deleted.** Each root cause becomes research-and-plan, fix, and test tickets. The tests for findings attributable to a root cause are deleted with the fix, not repaired, because they pin the shape the fix removes; the new tests conform to `laws:testing`.
