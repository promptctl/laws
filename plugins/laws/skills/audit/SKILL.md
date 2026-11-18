---
name: audit
description: Audit an entire codebase against the laws of code. Splits the codebase into many overlapping areas, runs laws:law-review on every area in parallel, dedups across the reviews, and ranks the findings into three buckets - root causes first (biggest and most architectural), then every other finding attributed to its root cause, then build and non-architectural performance issues. Files one ticket per root cause, each with its research, fix, and test tickets, in the project's ticketing system; without one, it returns the buckets as markdown lists.
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

**Bucket 1 - root causes.** A root cause is the decision, the missing type, the missing
seam, or the second source of truth that makes a set of findings possible. Read the
pooled findings as one set and name every root cause behind them, across areas: the
per-area reviews each saw only their own area. Each root cause gets its fix, stated as
the change the laws ask for, and the findings it explains. Order bucket 1 biggest and
most architectural first: the fix that reaches across the most modules and explains the
most findings leads. If fifteen findings share one root cause, its fix comes before any
of the fifteen.

**Bucket 2 - every other finding.** Correctness bugs and law violations, each attributed
to its root cause in bucket 1 by name. A finding with no root cause in bucket 1 means
bucket 1 is incomplete: name the decision that made it possible and add that to bucket
1. A finding that truly stands alone is its own root cause and goes there.

**Bucket 3 - build and non-architectural performance issues.**

## Phase 5 - Tickets, or lists

Use the ticketing system the project defines - the one its CLAUDE.md or the user's
CLAUDE.md names, or the tracker the repository is set up with (for lit, run
`lit quickstart` first and follow it).

**With a ticketing system:**

1. Create one epic, or the system's container, for this audit's results.
2. File tickets for bucket 1 only. Root causes are what gets fixed; bucket 2 and bucket
   3 get no tickets of their own.
3. For each root cause, file a ticket under the epic: the root cause, its fix, and every
   bucket 2 finding attributed to it with file and line. Under it, file three tickets:
   1. **Research and plan.** Research the root cause and plan its fix, including the
      deletion of every test for the bucket 2 findings attributed to it. The plan for the
      fix and the deletions is written onto ticket 2; the plan for new tests is written
      onto ticket 3. This ticket produces plans only, so it gets no plan or review
      cycle of its own.
   2. **Fix.** Implement the fix for the root cause. Every test for a finding
      attributed to this root cause is deleted, not fixed. Blocked by ticket 1.
   3. **Tests.** A placeholder that ticket 1 fills in with the plan for new tests. Every
      test must conform to `laws:testing`. Blocked by tickets 1 and 2.

**Without a ticketing system:** write one markdown list per bucket. Each bucket 1 item
carries the root cause, its fix, the bucket 2 findings attributed to it, and the same
three steps - research and plan, fix with the attributable tests deleted, tests that
conform to `laws:testing`. Each bucket 2 item names its root cause. Bucket 3 is a plain
list.

## Report

Return to the user:

- the areas reviewed, and any area that could not be reviewed;
- bucket 1, in order: each root cause, its fix, how many findings it explains, and its
  ticket ID when filed;
- bucket 2 grouped under its root causes, then bucket 3 - each finding with file, line,
  and summary;
- the epic's ID, or the markdown lists themselves.
