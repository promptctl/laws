# Requirements traceability matrix

This matrix spans all three documents.

| REQ | Source | UC | FR | Component | TC | Status |
|---|---|---|---|---|---|---|
| REQ-1 | [who, date] | UC-1 | FR-1, FR-2 | [name] | TC-1, TC-2 | |

- Any row can be read backward from a component to the user who made the request.
- When a requirement is rejected or deprecated, its row lists every functional requirement, component, and test case to be removed.
- An item that appears in no row is removed.

# Iteration cycle

1. A user request arrives or a test produces a finding. Update the **PRD** with a validation log entry and with new or revised requirements.
2. Update the **FSD**: mark the affected requirements as validated, draft, or deprecated.
3. Update the **Spec**: promote, add, or schedule removal of components, and set the implementation plan.
4. Build the plan, then test it with a person or an agent using the FSD's test cases as real tasks. Record what was observed, and return to step 1.
