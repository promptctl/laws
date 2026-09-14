# Round-trip evals for the crafts

A craft (`plugins/laws/skills/<medium>/references/craft.md`) is the active form of a
writing standard: it steers an agent that holds it in context. Its spec is the
inactive form: the same rules stated once, plainly, with strength, condition and
exceptions, and nothing else. The `distill` skill turns a craft into a spec;
`laws:prompt` turns a spec back into a craft. This directory tests how much survives
the trip.

## Per craft

`evals/roundtrip/<medium>/` holds:

- `spec.md` - the craft distilled by a fresh session holding only `distill`.
- `craft-roundtrip.md` - the spec recompiled by a fresh session holding only
  `laws:prompt`, which never saw the original craft.
- `task.md` - one small single-shot goal in the medium. Fixed facts, named readers,
  nothing to invent, so a judge can check the output against the spec.
- `outputs/control.md` - the task with no guidance.
- `outputs/current.md` - the task with the current craft pasted as guidance.
- `outputs/roundtrip.md` - the task with `craft-roundtrip.md` pasted as guidance.
- `judge.md` - an LLM judge's verdict: each spec requirement marked met, not met, or
  not applicable for each output, with the outputs presented blind in a shuffled
  order. `judge-key.md` holds the letter-to-arm mapping the judge never saw.
- `spec-roundtrip.md` - `craft-roundtrip.md` distilled again, by a session that never
  saw `spec.md`. Diffing it against `spec.md` measures the trip as a description.

## Protocol

1. Distill: fresh subagent, `distill` only, craft to `spec.md`.
2. Recompile: fresh subagent, `laws:prompt` only, `spec.md` to `craft-roundtrip.md`.
   It must not read the original craft.
3. Run the three arms as fresh subagents from one prompt template that differs only
   in the guidance block. Arms load no skills.
4. Judge: fresh subagent, no skills, given `task.md`, `spec.md`, and the three
   outputs copied as `A.md`, `B.md`, `C.md` in a random order into a scratch directory
   outside the repo. No path or file the judge reads may name an arm or the experiment:
   `outputs/control.md` unblinds it whatever the letters say, and a directory called
   `roundtrip` tells it what is being tested. It scores each requirement per output
   and ranks the three. The verdict is copied back as `judge.md`; decode it with
   `judge-key.md`.

All arms and the judge run on one model, recorded in `judge-key.md`. Outputs from an
earlier model are kept under `outputs/<model>/` and are not judged against the
current set.

Every step is a fresh subagent because `distill` and `laws:prompt` are inverse
standards and a session that has held one cannot do the other, and because an arm
that has seen a craft is no longer a control.

## What the numbers mean

Two results per craft. The spec-level diff between `spec.md` and a distillation of
`craft-roundtrip.md` says how lossless the trip is as a description. The judge's
table says how much of the craft's steering power the recompiled version kept, with
the control arm as the floor. A large gap between current and roundtrip on a rule
means the spec under-specifies it, usually a missing condition or a lost observed
failure.
