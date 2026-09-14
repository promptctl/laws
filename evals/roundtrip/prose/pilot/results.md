# Prose pilot: results

One single-shot task (write the `sift` README from fixed facts), three arms on Opus 5,
three blind judges. One sample per arm, so these are signals, not measurements.

## Rankings

| Judge | Rubric | Scores fact fidelity | 1st | 2nd | 3rd |
|---|---|---|---|---|---|
| `judge.md` | spec | no | round trip | current | control |
| `judge2-spec.md` | spec | yes | current | control | round trip |
| `judge2-craft.md` | original craft | yes | current | control | round trip |

| Arm | Invented claims, spec judge | Invented claims, craft judge | Misstated |
|---|---|---|---|
| control | 1 | 0 | 0 or 1 |
| current | 0 | 0 | 1 |
| round trip | 6 | 5 | 0 or 1 |

## Findings

- **Rubric scores barely separate the arms.** Every arm met all but one to three
  rules under every judge. On a task this small the craft's rules are mostly met with
  no craft at all.
- **Fact fidelity separates them.** The task forbade inventing anything. The
  round-trip arm added use cases, a scripting tip, a suitability judgment and an
  issue tracker. The first judge did not score fidelity and ranked it first; both
  judges that did ranked it last.
- **The current craft beat the control on one visible point.** Its worked example
  shows real input and output, and every judge that ranked it first named that
  example. It also misstated `-0` as a terminator instead of a separator.
- **The round trip lost no rules but added about a dozen.** See `spec-diff.md`. A
  likely cause of the inventions, not yet tested, is the added rules that push the
  writer to supply whatever the reader might need, such as writing the obvious
  sentence "including when leaving it out feels like respecting the reader".

## What changed because of this

- The distill skill now records a failure clause where the source names a mistake,
  so the compile step can harden exactly those rules and no others.
- The compile step may not add temptations, permissions or methods the spec lacks.
- Every judge scores fact fidelity against the task, and a second judge uses the
  original craft as rubric so the spec cannot favour the round-trip arm.
- Judges see outputs as `A.md`, `B.md`, `C.md` in a neutral directory. The first
  attempt named files after their arms, and the second sat under a directory named
  for the experiment.

## Limits

- One output per arm. Run-to-run variance is unknown, so a one-rule gap is noise
  until repeated.
- Fable-era control and current outputs in `outputs/fable/` were not judged.
