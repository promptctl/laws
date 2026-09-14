# CSV export drops expenses whose description contains a comma

**End state:** A CSV export has one row for every expense in the exported range. Each description comes out intact, commas included. A spreadsheet or any standard CSV parser reads `Dinner, drinks` back as `Dinner, drinks`. No expense is left out of the file without anyone knowing.

**Why:** Users are losing expenses from their exports without any sign of it, and they rely on the export matching what the app shows.

**Completion signal:** Export a month that has an expense described as `Dinner, drinks` alongside expenses without commas. When the file is parsed as CSV, its row count matches the number of expenses the app shows for that month, and one row's description is exactly `Dinner, drinks`.

## Context

- User report, verbatim: "I exported March and three of my expenses are just gone from the CSV. They're still in the app."
- Reproduced: any expense whose description contains a comma (for example `Dinner, drinks`) is missing from the export. Expenses without commas export correctly.
- The export is built in `internal/export/csv.go`. It splits each row on raw commas instead of treating it as CSV. A row that splits into more fields than the header has gets skipped, and nothing is logged. That's how expenses disappear without a trace.
- The database is correct. Only the export file is wrong, so no data repair is needed.
- The import path uses `encoding/csv` and handles commas correctly.
- Affected: every release since 1.4.0. The current release is 1.6.2.
- Unknown: nobody has tested whether descriptions containing quotes or newlines also break the export. The end state above covers every description, so check those cases too.
