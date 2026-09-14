## Fidelity (scored)

### Response A
Missing:
- The project description: "a web app for tracking shared expenses" (A only says "In `tally`").
- "The backend is Go."

Misstated: none.

Added:
- "Check those cases as part of this work." Adds a requirement. The task gives only that nobody has tested quotes or newlines.
- "A row is never dropped without a trace." Adds a requirement. The task says nothing is logged but never requires a trace.

`missing: 2, misstated: 0, added: 2`

### Response B
Missing:
- The project name `tally`.
- The project description: "a web app for tracking shared expenses".
- "The backend is Go."
- "Line 88". B says only "The export is built in `internal/export/csv.go`."
- The exact call `strings.Split(row, ",")`. B paraphrases it as "splits each row on raw commas instead of treating it as CSV".

Misstated: none.

Added:
- "No expense is left out of the file without anyone knowing." Adds a requirement that is not given.
- "they rely on the export matching what the app shows". Asserts a claim about users that is not given.
- "The end state above covers every description, so check those cases too." Adds a requirement about quotes and newlines. The task lists that only as untested.

`missing: 5, misstated: 0, added: 3`

### Response C
Missing:
- The project name `tally`.
- The project description: "a web app for tracking shared expenses".
- "The backend is Go."
- "Line 88". C says only "the export in `internal/export/csv.go` splits each row on raw commas".
- The exact call `strings.Split(row, ",")`, which C paraphrases as "splits each row on raw commas".

Misstated: none.

Added:
- "No expense is ever left out of an export without anyone knowing." Adds a requirement that is not given.
- "users rely on the export as a full copy of their expenses". Asserts a claim that is not given.
- "people only find out when they compare the file to the app". Asserts a claim that is not given.
- "The destination above covers them too, because an expense missing from the export is the bug whatever character causes it." Pulls quotes and newlines into scope. That is a requirement the task does not give.

`missing: 5, misstated: 0, added: 4`

## Rubric

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | not met | met | met |
| 3 | n/a | met | met |
| 4 | not met | met | met |
| 5 | met | met | met |
| 6 | not met | met | met |
| 7 | not met | met | met |
| 8 | met | met | met |
| 9 | not met | met | met |
| 10 | met | met | met |
| 11 | met | met | met |
| 12 | not met | met | met |
| 13 | met | met | met |
| 14 | n/a | n/a | n/a |
| 15 | met | n/a | n/a |
| 16 | not met | not met | met |
| 17 | met | met | met |
| 18 | n/a | n/a | n/a |
| 19 | n/a | n/a | n/a |
| 20 | n/a | n/a | n/a |
| 21 | met | met | met |
| 22 | met | met | met |
| 23 | n/a | n/a | n/a |
| 24 | n/a | n/a | n/a |
| 25 | n/a | n/a | n/a |
| 26 | n/a | n/a | n/a |
| 27 | n/a | n/a | n/a |
| 28 | met | met | met |
| 29 | met | met | met |
| 30 | met | met | met |
| 31 | n/a | n/a | n/a |
| 32 | n/a | n/a | n/a |
| 33 | n/a | n/a | n/a |
| 34 | n/a | n/a | n/a |
| 35 | n/a | n/a | n/a |
| 36 | n/a | n/a | n/a |
| 37 | n/a | n/a | n/a |
| 38 | n/a | n/a | n/a |
| 39 | n/a | n/a | n/a |

Counts: A: 13 met, 7 not met, 19 n/a. B: 19 met, 1 not met, 19 n/a. C: 20 met, 0 not met, 19 n/a.

Failures:
- A, 2: A has no why line and no completion signal. Its sections are "Problem", "Reproduction", "Cause", "Affected versions", "Expected behavior", "Open question" and "Notes".
- A, 4: A gives no observable completion signal anywhere. "Expected behavior" lists outcomes but no fact to check.
- A, 6: "Line 88 splits each row with `strings.Split(row, \",\")`." This copies code the repo already shows.
- A, 7: "Line 88 splits each row with `strings.Split(row, \",\")`." This is a line number plus a local call expression.
- A, 9: "The import path's use of `encoding/csv` is working code in the same repository to compare against." This points the implementer at a route.
- A, 12: "The import path's use of `encoding/csv` is working code in the same repository to compare against." This is a mechanism offered softly as a reference rather than stated as an outcome.
- A, 16: "Check those cases as part of this work." This sets the scope of verification in the ticket.
- B, 16: "The end state above covers every description, so check those cases too." This sets the scope of verification in the ticket.

## Ranking
1. C: It meets every applicable requirement and gives the next agent a clear end state, a one-line why and a checkable completion signal. Its fidelity costs are dropped code-level facts and a few added claims.
2. B: It has the same strong structure as C, with a slightly tighter why. But it tells the implementer to "check those cases too", which scopes verification.
3. A: It keeps the most facts. But it has no why and no completion signal, copies a line number and code, and hints at a mechanism, so the next agent gets a bug report rather than a ticket.

## Totals
- A: fidelity missing 2, misstated 0, added 2; rubric 13 met, 7 not met, 19 n/a
- B: fidelity missing 5, misstated 0, added 3; rubric 19 met, 1 not met, 19 n/a
- C: fidelity missing 5, misstated 0, added 4; rubric 20 met, 0 not met, 19 n/a
