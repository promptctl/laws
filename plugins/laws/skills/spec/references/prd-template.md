# PRD: [Product or Feature Name]

**Version:** · **Iteration:** N · **Status:** draft / in validation / validated · **Owner:** · **Updated:**

## 1. Summary
One paragraph covering who requested this, the problem, the proposed solution, and the current validation status.

## 2. Problem statement
What is broken, for whom, and what it costs them. The requesting user should be able to read this and confirm it is accurate.

## 3. Requirements

| ID | Requirement | Source (who, date, their words) | Priority | Status |
|---|---|---|---|---|
| REQ-1 | | "..." | must / should / could | open / validated / rejected |

- Every requirement has a source, and a requirement without one is removed.
- Write requirements as user needs, not as features.
- The source shows that the need exists. The PRD makes no claim about how many users share it.

## 4. Use cases

| ID | Actor | Goal | Trigger | Related requirements |
|---|---|---|---|---|
| UC-1 | | | | REQ-1 |

Each use case gets one to three sentences describing the actor's real task. Detailed flows belong in the FSD.

## 5. Technical context and constraints
- What the available technology does well and cheaply.
- What it does poorly.
- The hard constraints: cost, latency, reliability, and platform.

The proposed solution should fit these. Note any place where it works against them, along with the cost of doing so.

## 6. Proposed solution
- **Approach:** the solution concept in a short paragraph, with a sketch or mockup if one helps.
- **Rationale:** why this approach addresses the requirements.
- **Assumptions:** what must be true for it to work. Each assumption has an observable result that would show it is false.
- **Alternatives considered:** what was rejected, and why.
- **Status:** proposed / validated / rejected

The user supplies the need. Design is the team's responsibility.

## 7. Success criteria
Observable user behavior, not opinion:
- The requesting user stops raising the issue.
- Their existing workaround is no longer used.
- They use the feature again without being prompted.
- A second user completes the task without having it explained.

## 8. Out of scope
- **This iteration:**
- **Permanently:**

## 9. Validation log
One entry per iteration, including the iterations that failed.

**Iteration N: [date]**
- **Built:**
- **Tested by:** [person or agent], performing [a real task]
- **Observed:** actions taken, points of hesitation, workarounds, and features ignored
- **Changes made:**
- **Effect on requirements and solution:** status updates

For agent testers, assign tasks and record what they did. Do not ask them for opinions.

## 10. Risks and open issues

| Item | Type (risk / question) | Owner | Due |
|---|---|---|---|

## 11. Handoff to FSD
List the validated requirements and the use cases that are ready for functional specification. Items that are still open remain in this document.

---

**Document rules**
- Record observed behavior in preference to stated opinion.
- Make no quantitative claims that the sample cannot support.
- Keep sections 1 through 8 to one page. The validation log is the only section that grows.
- Rejected items remain in the document, marked with their status and the iteration in which they were rejected.
