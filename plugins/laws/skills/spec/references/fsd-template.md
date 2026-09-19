# FSD: [Product or Feature Name]

**Version:** · **Synced to PRD iteration:** N · **Status:** draft / partially validated / validated · **Owner:** · **Updated:**

## 1. Summary
One paragraph on what the product does today, from the user's point of view. Leave out implementation details.

## 2. Actors and system context
The users, agents, and external systems that interact with the product, and what each one is trying to accomplish. Include a context diagram if it is clearer than prose.

## 3. Functional requirements

| ID | Requirement | Traces to | Status |
|---|---|---|---|
| FR-1 | When [condition], the user [action], and the system [response, including what the user sees]. | REQ-1, UC-1 | draft / validated / deprecated |

- Each requirement is atomic, observable from outside the system, and testable.
- **Draft** means specified but not yet tested with a user. **Validated** means a user was observed completing a real task with it.
- Every functional requirement traces to a PRD requirement. A requirement with no trace is removed.

## 4. User flows
The main paths through the functional requirements, in sequence, shown as a diagram where that is clearer than prose. Mark each flow as validated or draft.

## 5. Error handling and edge cases
For each functional requirement, specify the behavior on invalid input, on system failure, and when the user is interrupted midway. State what the user sees and how they recover.

Tag each case by origin: **observed** (from the validation log) or **anticipated**. Observed cases take priority.

## 6. Business rules and data
- Business rules, validation rules, and limits. Use a decision table for any rule with more than two conditions.
- Data entities as the user understands them, for example "a project contains tasks." The schema belongs in the Spec.

## 7. Non-functional requirements

| ID | Category | Requirement | Traces to |
|---|---|---|---|
| NFR-1 | performance / reliability / security / accessibility / capacity | A measurable target, e.g. "results display within 2 seconds" | REQ-n or PRD section 5 |

Set each target from the PRD's constraints and from what users were observed to notice. Do not optimize something that no user noticed.

## 8. Acceptance criteria and test cases

| ID | Tests | Task given to a person or agent | Pass condition |
|---|---|---|---|
| TC-1 | FR-1 | "Perform [real task]" | [observable result] |

- Every functional requirement has at least one test case.
- Write each test case as a task to perform, not as an assertion about the system.
- The test cases are the script for the next validation iteration. Once a requirement is validated, its test cases join the regression suite and run on every build.

## 9. Open issues

| Item | Owner | Due |
|---|---|---|

Include any behavior that is intentionally left to the implementer's judgment. Stating this prevents requirements from being invented later.

## 10. Deprecated requirements
List each one with the iteration in which it was deprecated and the reason. The Spec uses this list to schedule code removal.

## 11. Handoff to Spec
- The functional and non-functional requirements to implement, each with its status.
- A flag on every draft requirement, so it is implemented in a way that is cheap to change.

## 12. Glossary
Define each term once and use it the same way throughout.

---

**Document rules**
- Specify what the system does and never how. Class names, tables, and services belong in the Spec.
- A requirement's status changes only on the basis of a validation log entry in the PRD.
- If a test case cannot be written for a requirement, the requirement is too vague and must be rewritten.
- Do not use terms that cannot be measured, such as "fast," "intuitive," or "etc."
- Iteration history is kept in the PRD. This document states only the current behavior.
