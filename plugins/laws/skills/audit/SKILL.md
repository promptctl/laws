---
name: audit
description: Audit an entire codebase against the laws of code. Splits the codebase into many overlapping areas, runs laws:law-review on every area in parallel, dedups across the reviews, and ranks the findings into three buckets - root causes first (biggest and most architectural), then every other bug attributed to its root cause, then cleanup. In the project's ticketing system it files one ticket per root cause plus one cleanup ticket; without one, it returns the buckets as markdown lists.
argument-hint: "[<path>]"
context: fork
model: opus
---

`audit -> map areas -> law-review per area, in parallel -> dedup -> three buckets -> tickets or lists -> report`

Scope (empty means the whole repository): `$ARGUMENTS`

## Phase 1 - Map the areas

List the tracked files (`git ls-files`) in scope and read enough of the tree to know
its modules, its layers, and its main units of work. Leave out generated and vendored
code.

Split the code into **areas**. More is better: each area is small enough that one
reviewer reads every file in it. Overlap is better still, because a violation that
lives between two modules shows only to a reviewer who holds both sides:

- one area per module, package, or directory of real code;
- one area per seam between modules - both sides of it together;
- one area per main unit of work, end to end - its entry point, through the code it
  calls, to its effects;
- one area for the types, config, and state every module shares.

Every file in scope belongs to at least one area. Write the area list down: a name and
its paths for each.

## Phase 2 - Review every area in parallel

Run `laws:law-review` once per area, every call in the same message so they run in
parallel - the Skill tool, skill `laws:law-review`, args: the area's paths, followed by
`Review this code as it stands; there is no diff.` Wait until every review has
returned. A review that fails is rerun; an area left unreviewed is reported as a gap,
never dropped in silence.

## Phase 3 - Dedup across the reviews

Pool every finding. Overlapping areas report the same defect more than once: the same
defect at the same location is one finding - keep the copy with the sharper failure
scenario. The same cause at different locations is **not** a duplicate. Those are
separate findings, and Phase 4 ties them to one root cause.

## Phase 4 - Rank into three buckets

**Bucket 1 - root causes.** A root cause is what makes a set of findings possible:
the law it breaks, how the code breaks it, and where. Read the pooled findings as one
set and name every root cause behind them, across areas: each per-area review saw only
its own area. State each one from the findings in hand - no further research, no fix,
no instructions. Working out the fix belongs to whoever pulls its ticket. Order bucket 1
biggest and most architectural first: the root cause that reaches across the most
modules and explains the most findings leads. Fifteen findings with one root cause are
fifteen findings, and their root cause comes before all of them.

**Bucket 2 - every other bug.** Correctness bugs and law violations - a law violation is
a bug. Each is attributed by name to its root cause in bucket 1. A bug with no root
cause there means bucket 1 is incomplete: add the root cause that made it possible. A
bug that truly stands alone is its own root cause and goes in bucket 1.

**Bucket 3 - cleanup.** Build issues, non-architectural performance issues, and the
reuse, simplification, and conventions findings.

## Phase 5 - Tickets, or lists

Use the ticketing system the project defines - the one its CLAUDE.md or the user's
CLAUDE.md names, or the tracker the repository is set up with (for lit, run
`lit quickstart` first and follow it).

Every ticket is minimal and carries concrete work. It says what is wrong and where to
start, never how to fix it - the agent that works it decides that. Its done-when is
code changed, bugs fixed, or further tickets filed that carry its results into
implementation; never a measurement or a research result alone.

**With a ticketing system:**

1. Create one epic, or the system's container, for this audit's results.
2. File one ticket per root cause under the epic, in bucket 1 order. Bucket 2 gets no
   tickets of its own: its bugs are the symptoms their root cause's ticket solves. Each
   root cause ticket carries:
   - the root cause: the law, how the code breaks it, and where;
   - every bucket 2 bug attributed to it, with file and line;
   - done when those bugs can no longer happen - refactored away, or otherwise solved
     by fixing the root cause rather than each symptom;
   - this instruction, verbatim:

     > When you pull this ticket, file three tickets under it, each a few lines saying
     > where to start, not the work itself:
     > 1. Research and plan the fix for the root cause, and the deletion of every test
     >    for the bugs listed here. Write the fix-and-deletion plan onto ticket 2 and
     >    the plan for new tests onto ticket 3. This ticket gets no plan or review cycle.
     > 2. Implement the fix. Every test for a bug listed here is deleted, not fixed.
     >    Blocked by ticket 1.
     > 3. Write the new tests from the plan ticket 1 puts here. Every test conforms to
     >    `laws:testing`. Blocked by tickets 1 and 2.
3. File one cleanup ticket under the epic: every bucket 3 item with file and line, done
   when each is fixed.

**Without a ticketing system:** write one markdown list per bucket. Each bucket 1 item
carries what its ticket would. Each bucket 2 item names its root cause. Bucket 3 is the
cleanup list.

## Report

Return to the user:

- the areas reviewed, and any area that could not be reviewed;
- bucket 1, in order: each root cause, how many bugs it explains, and its ticket ID
  when filed;
- bucket 2 grouped under its root causes, then bucket 3 - each with file, line, and
  summary;
- the epic's ID, or the markdown lists themselves.
