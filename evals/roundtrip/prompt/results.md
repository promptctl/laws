# Prompt: results

The task was to write the prompt for a subagent that renames a configuration key across
a repository, carrying five requirements the user gave verbatim. Every arm and both
judges ran on Opus 5, with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | round trip | current | control |
| current guidance | round trip | control | current |

| Arm | Claims added | Rules not met |
|---|---|---|
| control | 3 and 2 | 10 and 2 |
| current | 4 and 3 | 5 and 3 |
| round trip | 1 and 1 | 0 and 1 |

Each cell gives the spec judge's count, then the guidance judge's. No arm missed or
misstated a fact. The two rubrics differ in size, so compare counts within a judge.

## Findings

- **The round trip ranked first under both judges.** It quoted every requirement
  verbatim, gave stop conditions the subagent can check, put the exclusions at the
  opening and the close, and named the late temptation in one sentence. Its one
  addition stated as certain that a lookup will fail.
- **The current craft ranked last under the guidance judge.** This is the only
  judgment in the eval where a craft ranked below the control. The arm paraphrased four
  of the five requirements instead of quoting them. It gave a prompt for one run a
  multi-sentence temptation drill and heavy repetition, which the craft reserves for
  guidance that must hold a whole session. It also added a stop-and-report behavior
  nobody asked for.
- **The control quoted every requirement but wrote for a single turn.** Its exclusions
  sit in the middle of a list, it names no temptation, and its completion check runs a
  plain `git diff`, which cannot see an edit that was already committed. The spec judge
  ranked it last; the guidance judge put it second.
- **A reading worth testing.** The current craft's long-session devices may pull a
  writer past the hold a text needs. The recompiled craft, written from a spec that
  states each hold's treatment as a separate rule, did not do this here. One output per
  arm cannot tell that apart from chance.

## Limits specific to this medium

The compiler's own craft is this medium's current guidance, so the recompile had to
read it and is not blind. `craft-roundtrip-without-craft.md` is an earlier attempt that
obeyed the blindness rule and so never read the craft. It was not run as an arm.
