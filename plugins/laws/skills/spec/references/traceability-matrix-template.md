# Requirements Traceability Matrix: [Product or Feature Name]

**Version:** · **Synced to:** PRD iteration N, FSD version, Spec version · **Owner:** · **Updated:**

## 1. Purpose
A single table that links every user request to the functional requirements, components, and test cases that serve it. It is used to confirm that everything built was requested, that everything requested is covered, and that everything deprecated has been removed.

## 2. Matrix

| REQ | Requirement (short) | Source | Priority | UC | FR / NFR | Component | TC | REQ status | Validated in |
|---|---|---|---|---|---|---|---|---|---|
| REQ-1 | Track which invoices have been sent | J. Smith, 2026-09-02 | must | UC-1 | FR-1, FR-2 | Invoice status service | TC-1, TC-2 | validated | Iteration 3 |
| REQ-2 | Find unsent invoices quickly | J. Smith, 2026-09-02 | should | UC-1 | FR-3, NFR-1 | Invoice list view | TC-3 | open | — |
| REQ-3 | Email reminder for unsent invoices | A. Lee, 2026-09-10 | could | UC-2 | FR-4 | Notification module | TC-4 | rejected | Iteration 4 |

The rows shown are examples. Each row is one product requirement.

## 3. Column definitions

| Column | Content | Drawn from |
|---|---|---|
| REQ | Product requirement ID | PRD section 3 |
| Requirement (short) | A summary of a few words, not the full text | PRD section 3 |
| Source | The person who made the request, and the date | PRD section 3 |
| Priority | must / should / could | PRD section 3 |
| UC | Related use cases | PRD section 4 |
| FR / NFR | Functional and non-functional requirements that implement it | FSD sections 3 and 7 |
| Component | Components that implement those requirements, by name | Spec section 4 |
| TC | Test cases that verify them | FSD section 8 |
| REQ status | open / validated / rejected | PRD section 3 |
| Validated in | The iteration in which the status was set | PRD section 9 |

The matrix holds IDs and short labels only. The full text stays in the source document, so that nothing is maintained in two places.

## 4. Coverage checks
Run these after every iteration.

| Check | Finding | Action |
|---|---|---|
| A requirement with no FR | The request is not yet specified | Specify it, or move it out of scope |
| An FR with no requirement | The behavior was never requested | Remove the FR |
| An FR with no component | It is specified but not built | Add it to the implementation plan |
| A component with no FR | The code serves no requirement | Schedule it for removal |
| An FR with no TC | The behavior cannot be verified | Write the test case, or rewrite the FR |
| A rejected requirement whose FRs, components, or TCs are still active | The cleanup is incomplete | Deprecate them, and add the code to Spec section 12 |
| A validated requirement with a prototype component | Hardening is overdue | Promote the component to production maturity |

## 5. Maintenance
- Update the matrix as the last step of each iteration, after the PRD, FSD, and Spec.
- An ID is never reused or renumbered. Rejected and deprecated rows remain in the matrix with their status.
- A change to any of the three documents that adds, removes, or re-links an ID requires a matching update here.
- If the matrix and a source document disagree, the source document is correct and the matrix is fixed.

## 6. Change history

| Iteration | Date | Rows added | Rows changed | Changed by |
|---|---|---|---|---|

---

**Document rules**
- One row per product requirement. Put multiple FRs, components, or TCs in the same cell, separated by commas.
- Every cell is filled. Use a dash where there is nothing yet, which makes the gaps visible for the coverage checks.
- Keep the matrix as a spreadsheet or a table that can be sorted and filtered, since the coverage checks depend on filtering by blank cells and by status.
