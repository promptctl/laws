# Backlog: results

Recorded against the craft as of v0.26.0. v0.29.0 inverted the planning rule (plan the
whole arc at the detail you have; unknowns get their own tickets), so `spec.md`,
`craft-roundtrip.md`, `judge-guidance.md`, and `task.md` here all encode the old rule.
A rerun regenerates every fixture, not just the distill.

The task was to write the first backlog for `pocketlog`, a small command-line notebook,
from a short founding document. Every arm and both judges ran on Opus 5, with one output
per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | round trip | current | control |
| current guidance | round trip | current | control |

| Arm | Claims added | Rules not met |
|---|---|---|
| control | 6 and 7 | 10 and 8 |
| current | 14 and 16 | 3 and 2 |
| round trip | 8 and 11 | 2 and 1 |

Each cell gives the spec judge's count, then the guidance judge's. No arm missed or
misstated a fact.

## Findings

- **Without a craft, the backlog has no way to tell when an epic is done.** The control
  gave no epic a checkpoint a person watches, named no second consumer for its
  foundational units, and said what each epic contains rather than why it exists. It
  also planned a whole ticket whose only job is to confirm things already true.
- **Both judges ranked the round trip first.** Its epics each end on a checkpoint a
  person watches, with edge cases, and its foundational tickets have one-sentence
  purposes and named second consumers. Its one real defect is a ticket that asks the
  agent to copy the founding document into the repository, which a fresh agent does not
  have.
- **The current craft pinned down the most behavior nobody gave.** It fixed a tag
  grammar, count semantics, a sort order and error rules. It also bundled two
  foundational units into one ticket and restated the founding document instead of
  pointing to it.

## Flaws in this task

- **The founding document has no path.** The backlog rules say to point to it by path,
  so every arm either invented a location or restated it. The task should place the
  document at a named path in the repository.
- **Planning forces detail that counts as an addition.** A ticket a fresh agent can pull
  needs decisions like how tags are written. The no-additions rule scores those as
  invented behavior, so the added-claims column mixes real inventions with necessary
  planning. A better task would say which details the backlog may decide.
