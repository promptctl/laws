# Application spec: results

The task was to write a clean-room behavioral specification of `stamp`, a 40-line
command-line program whose full source the task gives. Every arm and both judges ran on
Opus 5, with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | round trip | current | control |
| current guidance | current | round trip | control |

| Arm | Facts missing | Facts misstated | Rules not met |
|---|---|---|---|
| control | 3 and 0 | 0 and 0 | 19 and 9 |
| current | 0 and 0 | 0 and 0 | 9 and 1 |
| round trip | 0 and 0 | 1 and 1 | 4 and 1 |

Each cell gives the spec judge's count, then the guidance judge's. No arm added a claim.

## Findings

- **The control wrote a man page, not a clean-room spec.** It used a
  Purpose/Invocation/Errors layout, had no provenance section and no lifecycle, and
  never recorded that the program keeps no state and makes no network calls. It also
  transcribed the human-readable error messages, which the craft says to describe
  instead. Both judges ranked it last.
- **The current craft wrote the most exact spec.** Both judges found no fidelity
  errors in it. The spec judge marked it down for putting the surfaces out of order and
  for having no audit record and no rule tokens.
- **The round trip made one false claim.** It said standard input can never be read,
  though passing `/dev/stdin` as the file reads it, and its own section 5.1 says so.
  Both judges caught this.

## A loss the round trip introduced

The round-trip arm put `[APPSPEC:...]` rule tokens and an audit record inside the
delivered spec. The two judges scored this in opposite directions. The spec judge
counted the tokens and audit record as required. The guidance judge counted them as
process notes leaking into a document the clean team reads cold.

The current craft says to cite a rule's token "while writing spec sentences" but never
says whether citations belong in the deliverable. The session that distilled it
reported exactly this as a gap in the source. The spec kept the ambiguity, the
recompiled craft resolved it by putting tokens in the output, and the arm followed.
Resolving the gap in the craft itself would remove the divergence.
