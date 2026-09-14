# CSV export silently drops expenses whose description contains a comma

## Destination

A CSV export has one row for every expense in the exported range, and each row's description is exactly what the app shows. That includes descriptions with commas, like `Dinner, drinks`. No expense is ever left out of an export without anyone knowing.

**Why:** users rely on the export as a full copy of their expenses. Right now it loses data without any warning, and people only find out when they compare the file to the app.

## Done when

Export a range with an expense described as `Dinner, drinks`. The CSV has that expense as a single row with the description `Dinner, drinks`, and the file has as many expense rows as the app shows for that range.

## Context

- User report, verbatim: "I exported March and three of my expenses are just gone from the CSV. They're still in the app."
- Reproduced: an expense whose description has a comma is missing from the export. Expenses without commas export correctly.
- Cause: the export in `internal/export/csv.go` splits each row on raw commas. A row that splits into more fields than the header has is skipped, and nothing is logged.
- The import path uses `encoding/csv` and handles commas correctly. So the two paths currently disagree about what a valid row is.
- The database is correct. Only the export file is wrong, so no stored data needs repair.
- Affected: every release since 1.4.0. The current release is 1.6.2.
- Unknown: nobody has tested descriptions that contain quotes or newlines. The destination above covers them too, because an expense missing from the export is the bug whatever character causes it.
