# Task: write the ticket for the CSV export bug

Write one ticket, in Markdown, for the bug below: a title line, then the body. Output
only the ticket. Use every fact below. Do not invent causes, numbers, file paths,
versions, or requirements that are not given.

## Facts

- Project: `tally`, a web app for tracking shared expenses. The backend is Go.
- A user reported, verbatim: "I exported March and three of my expenses are just gone
  from the CSV. They're still in the app."
- Reproduced: an expense whose description contains a comma, such as `Dinner, drinks`,
  is missing from the export. Expenses without commas export correctly.
- The export is built in `internal/export/csv.go`. Line 88 splits each row with
  `strings.Split(row, ",")`. Rows that split into more fields than the header has are
  skipped, and nothing is logged.
- The import path uses `encoding/csv` and handles commas correctly.
- Every release since 1.4.0 is affected. The current release is 1.6.2.
- The database is correct. Only the export file is wrong.
- Unknown: whether descriptions containing quotes or newlines also break the export.
  Nobody has tested it.

## Reader

The agent who picks up this ticket next. It has the repository and none of this
conversation.
