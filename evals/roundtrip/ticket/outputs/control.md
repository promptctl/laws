# CSV export silently drops expenses whose description contains a comma

## Problem

In `tally`, the CSV export leaves out any expense whose description contains a comma. The expense is still in the app and still correct in the database. Only the exported file is wrong. Nothing is logged when a row is dropped, so the user gets no sign that the file is incomplete.

User report, verbatim:

> "I exported March and three of my expenses are just gone from the CSV. They're still in the app."

## Reproduction

1. Create an expense with a comma in its description, for example `Dinner, drinks`.
2. Export a CSV covering that expense.
3. The expense is missing from the file. Expenses without commas in their descriptions export correctly.

## Cause

The export is built in `internal/export/csv.go`. Line 88 splits each row with `strings.Split(row, ",")`. A comma inside a description produces more fields than the header has, and rows like that are skipped without logging anything.

The import path already uses `encoding/csv` and handles commas correctly.

## Affected versions

Every release since 1.4.0, up to and including the current release, 1.6.2.

## Expected behavior

- Every expense in the selected range appears in the export, including ones whose descriptions contain commas.
- A row is never dropped without a trace.

## Open question

Nobody has tested whether descriptions containing quotes or newlines also break the export. Check those cases as part of this work.

## Notes

- The database is correct. No data repair is needed. The fix is in the export only.
- The import path's use of `encoding/csv` is working code in the same repository to compare against.
