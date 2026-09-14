# Round-trip eval: results

Each craft was distilled into a spec, and a session that never saw the original
recompiled the spec into a craft, except in the prompt medium, where that was impossible. Then three agents did one small task per medium: one
with no guidance, one with the current craft, and one with the recompiled craft. Two
blind judges scored each set, one against the spec and one against the current craft.
Every agent ran on Opus 5, with one output per arm. Each medium's `results.md` has the
detail.

## Rankings

| Medium | Rubric | 1st | 2nd | 3rd | Added or misstated: control / current / roundtrip | Not met: control / current / roundtrip |
|---|---|---|---|---|---|---|
| application-spec | spec | roundtrip | current | control | 0 / 0 / 1 | 19 / 9 / 4 |
| application-spec | guidance | current | roundtrip | control | 0 / 0 / 1 | 9 / 1 / 1 |
| backlog | spec | roundtrip | current | control | 6 / 14 / 8 | 10 / 3 / 2 |
| backlog | guidance | roundtrip | current | control | 7 / 16 / 11 | 8 / 2 / 1 |
| chat | spec | roundtrip | current | control | 0 / 1 / 1 | 3 / 2 / 2 |
| chat | guidance | current | roundtrip | control | 0 / 0 / 1 | 2 / 1 / 1 |
| code | spec | roundtrip | current | control | 3 / 4 / 2 | 8 / 1 / 0 |
| code | guidance | roundtrip | current | control | 1 / 1 / 1 | 4 / 0 / 0 |
| prompt | spec | roundtrip | current | control | 3 / 4 / 1 | 10 / 5 / 0 |
| prompt | guidance | roundtrip | control | current | 2 / 3 / 1 | 2 / 3 / 1 |
| prose | spec | current | roundtrip | control | 0 / 0 / 0 | 0 / 0 / 1 |
| prose | guidance | current | roundtrip | control | 0 / 0 / 0 | 0 / 0 / 0 |
| ticket | spec | current | roundtrip | control | 2 / 4 / 3 | 7 / 0 / 1 |
| ticket | guidance | roundtrip | current | control | 1 / 3 / 2 | 5 / 1 / 1 |

"Added or misstated" and "not met" give counts per arm, in the order control, current,
round trip. Rubric sizes differ between judges, so compare counts within a row.

## Findings

- **A craft beat no craft.** The control never placed first, and it placed last in 13
  of 14 judgments. The control's outputs were usually accurate. They lost on what the crafts exist for.
  The backlog had no checkpoints. The ticket had no why and no completion signal. The
  chat reply never labelled which claims were verified. The clean-room spec had a
  man-page layout. The code had guards in the function body. The subagent prompt was
  written for a single turn.
- **The one exception is the prompt medium.** Its guidance judge ranked the current
  craft last. That arm paraphrased the user's requirements, and it used long-session
  devices on a prompt that only had to hold for one run.
- **The recompiled crafts performed on par with the current ones.** The round trip took
  first place in 9 of 14 judgments and the current craft in 5. On these tasks the spec
  carried enough to rebuild a craft that steers about as well as the original.
- **The compile fix removed the pilot's inventions.** In the pilot, the round-trip arm
  invented five or six claims on the prose task. The compile step was then forbidden to
  add anything the spec lacks, and the same task drew none. Round-trip arms added or
  misstated at most one claim in chat, prose, application-spec and prompt, and at most
  two in code. In ticket and backlog every arm added claims, for reasons their task flaws
  explain.
- **One loss traces to a gap in a craft.** The application-spec craft never says
  whether rule-token citations belong in the delivered spec. The distiller reported the
  gap, the spec kept it, and the recompiled craft put tokens and an audit record into
  the deliverable. The two judges then scored that choice in opposite directions.

## What this eval cannot show

- **It does not test the long hold.** The active form's redundancy, imagery and
  rehearsed temptations exist to keep guidance steering late in a long session. Every
  task here is a single shot, where a terse form is expected to do as well. A loss of
  late-session steering would not show up in these numbers.
- **Each arm ran once.** The judges disagreed on first place in three of seven media:
  application-spec, chat, ticket. A one-place difference is noise until it repeats across runs.
- **Several tasks have flaws, recorded in each `results.md`.** Prose is too easy to
  separate the crafts. The ticket task lists facts the ticket craft forbids using. The
  backlog task gives the founding document no path, and counts necessary planning
  detail as invention. The code rubric fails the control for not citing laws it never
  saw.
- **The prompt medium's recompile is not blind.** The compiler's craft is that medium's
  guidance, so it had to read the original.
- **Only the pilot measured the round trip as a description.** Distilling a recompiled
  craft again and diffing the two specs was done only for the pilot's prose craft.

## Follow-up tickets

- `promptctl-appspec-cal`: say in the application-spec craft whether citations belong in
  the deliverable.
- `promptctl-roundtrip-q0w`: remove the task flaws, diff every medium's specs, and repeat
  runs.
- `promptctl-roundtrip-dw1`: add a long-hold arm that tests late-session steering.
