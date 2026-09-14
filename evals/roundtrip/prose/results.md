# Prose: results

The task was to write the README for `sift` from a fixed list of facts, the same task as
the pilot in `pilot/`. Every arm and both judges ran on Opus 5, with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | current | round trip | control |
| current guidance | current | round trip | control |

No arm had a missing, misstated or added fact under either judge. The spec judge found
one unmet rule, in the round trip. The guidance judge found none.

## Findings

- **The rubric could not separate the arms.** All three READMEs met every applicable
  rule. The ranking rests on small reader-facing choices, not on rule failures.
- **The current craft won on one concrete choice.** It was the only arm whose example
  shows input files and the output, so a reader sees the ordering rule work. Both judges
  named that example.
- **The round trip put the memory limit where a deciding reader sees it**, right under
  the description. It lost a point for definition-list markup that GitHub does not
  render.
- **The control was accurate and plain.** Its example shows no output, and its
  "Options" heading does not name the flag a returning user is looking for.

## Compared with the pilot

The pilot ran this same task with an earlier compile step, one that let the compiler
choose its own rehearsed temptations. That round-trip craft led its arm to invent five
or six claims, and both fidelity-scoring judges ranked it last. This run forbade the
compiler from adding anything the spec lacks, and the round-trip arm invented nothing.
One output per arm is not enough to call that settled, but it is the change the fix was
meant to produce.

## A flaw in this task

A README from a short fact list is easy enough that no guidance is needed to meet the
rules. A task with a harder reader problem, such as conflicting audiences or a fact
that has to be put near the top, would give the craft something to do.
