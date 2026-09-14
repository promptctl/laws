# Judge verdict

## Fidelity (scored)

Facts given: (1) project `tally`, a web app for tracking shared expenses, Go backend; (2) verbatim user report; (3) reproduction with `Dinner, drinks`, non-comma expenses export fine; (4) built in `internal/export/csv.go`, line 88 splits with `strings.Split(row, ",")`, over-long rows skipped, nothing logged; (5) import path uses `encoding/csv` and handles commas; (6) every release since 1.4.0, current 1.6.2; (7) database correct, only export file wrong; (8) unknown whether quotes/newlines break it, untested.

### Response A

Missing:
- The project is never described as "a web app for tracking shared expenses". It is only named: "In `tally`, the CSV export leaves out...".
- "The backend is Go" appears nowhere.

Misstated: none.

Added:
- "Check those cases as part of this work." This is a requirement the task does not give. The task only says the quotes/newlines behavior is unknown.

Not counted: "No data repair is needed" (follows from "the database is correct"), "working code in the same repository to compare against" (consistent with fact 5), and "A row is never dropped without a trace" (the inverse of the given bug).

`missing: 2, misstated: 0, added: 1`

### Response B

Missing:
- The project name `tally` appears nowhere.
- "a web app for tracking shared expenses" is absent.
- "The backend is Go" is absent.
- "Line 88" is absent.
- `strings.Split(row, ",")` is absent. It is paraphrased only as "splits each row on raw commas".

Misstated: none.

Added:
- "users rely on the export as a full copy of their expenses". This claim about users is not given.
- "people only find out when they compare the file to the app". This generalizes one report into a claim about how users find the bug.
- "The destination above covers them too, because an expense missing from the export is the bug whatever character causes it." This widens the required scope to quotes and newlines, which the task leaves as untested unknowns.

Not counted: "So the two paths currently disagree about what a valid row is" (an inference from facts 4 and 5).

`missing: 5, misstated: 0, added: 3`

### Response C

Missing:
- The project name `tally` appears nowhere.
- "a web app for tracking shared expenses" is absent.
- "The backend is Go" is absent.
- "Line 88" is absent.
- `strings.Split(row, ",")` is absent. It is paraphrased as "splits each row on raw commas instead of treating it as CSV".

Misstated: none.

Added:
- "they rely on the export matching what the app shows". This claim about users is not given.
- "The end state above covers every description, so check those cases too." This adds a requirement to test quotes and newlines.

Not counted: "A spreadsheet or any standard CSV parser reads `Dinner, drinks` back as `Dinner, drinks`" (an illustration consistent with the given facts) and "That's how expenses disappear without a trace" (restates fact 4).

`missing: 5, misstated: 0, added: 2`

## Rubric

Rules the standard asks of a finished ticket:

1. States a destination: the end state that must be true, not the steps to get there.
2. Gives one line of why.
3. Gives a done-claim: one observable signal someone could go and check.
4. Carries the context that won't survive the trip (the bug report, decisions, and facts not recoverable from the repo).
5. Does not restate what the repo already shows (points at code without transcribing its behavior).
6. Code pointers are no more precise than a filename: no line numbers, no local function or variable names.
7. Carries no author-invented mechanism, including one hedged with a "compare against" or "one option" sticker.
8. Keeps requester-imposed constraints verbatim.
9. The done-claim is a claim, not a statement that the work was verified.
10. The deliverable is a change to the system, not a document about it.
11. Sized as one coherent push: neither lumped nor split below the floor.
12. Invents no handoff, status, or session-continuity apparatus.
13. Uses no dependency links ("blocks" / "depends on").

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | not met | met | met |
| 3 | not met | met | met |
| 4 | met | met | met |
| 5 | not met | not met | not met |
| 6 | not met | met | met |
| 7 | not met | met | met |
| 8 | n/a | n/a | n/a |
| 9 | met | met | met |
| 10 | met | met | met |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |

Counts: A met 7, not met 5, n/a 1. B met 11, not met 1, n/a 1. C met 11, not met 1, n/a 1.

Failures:

- A, rule 2: there is no why line anywhere. The sections are Problem, Reproduction, Cause, Affected versions, Expected behavior, Open question and Notes.
- A, rule 3: there is no done-claim. The nearest is "Every expense in the selected range appears in the export, including ones whose descriptions contain commas.", which restates the destination and gives no concrete signal to check.
- A, rule 5: "Line 88 splits each row with `strings.Split(row, ",")`. A comma inside a description produces more fields than the header has, and rows like that are skipped without logging anything." This transcribes the current code's behavior.
- A, rule 6: "Line 88 splits each row with `strings.Split(row, ",")`" gives a line number and a call expression as coordinates.
- A, rule 7: "The import path's use of `encoding/csv` is working code in the same repository to compare against." This steers the implementer toward a particular fix.
- B, rule 5: "Cause: the export in `internal/export/csv.go` splits each row on raw commas. A row that splits into more fields than the header has is skipped, and nothing is logged." This restates code behavior the repo shows.
- C, rule 5: "It splits each row on raw commas instead of treating it as CSV. A row that splits into more fields than the header has gets skipped, and nothing is logged." This restates code behavior the repo shows.

## Ranking

1. **C:** it gives a clear end state, a one-line why, and a parseable done-claim with a filename-only pointer, and it has the fewest unallowed additions of the two rubric-strong responses.
2. **B:** it is as strong as C against the rubric, but it adds more unsupported claims (a two-part why about user behavior, and scope widened to quotes and newlines).
3. **A:** it carries the most given facts, but it has no why, no done-claim, a line-number coordinate, and a steer toward the fix, so the next agent gets a bug report rather than a pullable ticket.

## Totals

- A: fidelity missing 2, misstated 0, added 1; rubric met 7, not met 5, n/a 1
- B: fidelity missing 5, misstated 0, added 3; rubric met 11, not met 1, n/a 1
- C: fidelity missing 5, misstated 0, added 2; rubric met 11, not met 1, n/a 1
