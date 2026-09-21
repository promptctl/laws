# Technical Spec: [Product or Feature Name]

**Version:** · **Synced to FSD version:** · **Status:** prototype / hardening / production · **Owner:** · **Updated:**

## 1. Summary
One paragraph covering the main components, how they connect, and where the technical difficulty lies.

## 2. Constraints
- The non-functional requirements from FSD section 7, as measurable targets.
- The technical constraints from PRD section 5: cost, latency, reliability, and platform.
- The team's own constraints: stack, infrastructure, budget, and any systems that must not be modified.

## 3. Architecture
The components and how they connect, shown in one diagram. Mark each component as prototype or production.

## 4. Components

**[Component name]**
- **Implements:** FR-1, FR-3
- **Responsibility:** one sentence
- **Inputs and outputs:**
- **Dependencies:**
- **Maturity:** prototype (implements draft requirements) / production (implements validated requirements)
- **Removal impact:** what is deleted, and what else is affected, if its requirements are deprecated

A component that implements no functional requirement is removed.

## 5. Data design
The schema, the storage, and the migration approach, with the FSD's data entities mapped to the schema.

Flag every choice that is irreversible or costly to reverse. These choices get full rigor even at prototype stage, because stored data persists across every iteration.

## 6. Interfaces
APIs, events, and external integrations. Each interface has a contract covering inputs, outputs, errors, and versioning. Any interface that another team or system depends on is treated as production from its first day.

## 7. Architecture decision records

| ID | Decision | Alternatives | Rationale | Reversible? | Cost to reverse |
|---|---|---|---|---|---|
| ADR-1 | | | | | |

Reversible decisions are made quickly. Irreversible decisions get a full written record and a review.

## 8. Modularity and feature flags
Where the draft requirements are implemented, and how that code is isolated through modules, flags, and boundaries. For each draft requirement, state what is removed if it is deprecated. Deprecating a requirement should lead to a deletion, not a rewrite.

## 9. Error handling and observability
- How each case in FSD section 5 is implemented.
- Logging and instrumentation: event logs, agent transcripts, and the points where users hesitate or abandon a task. The validation process depends on observing users, so the system must capture these observations cheaply.

## 10. Testing

| Requirement status | Test coverage |
|---|---|
| Validated | Automated tests, plus agent-run test cases from FSD section 8, gating every build |
| Draft | Smoke test only |

Heavy test coverage on draft requirements slows the changes that are expected to follow.

## 11. Implementation plan
The smallest build that allows the next validation iteration: what is built, in what order, and what is stubbed or simulated. List every stub here, so that none is mistaken for finished work.

## 12. Deprecation and cleanup

| Code or component | Deprecated requirement | Owner | Due |
|---|---|---|---|

Track code removal with the same discipline as new work.

## 13. Open issues

| Item | Owner | Due |
|---|---|---|

---

**Document rules**
- Describe what is built now, not what is planned for some later date.
- Scale rigor to validation status and to reversibility. Prototype quality is acceptable for draft requirements. It is never acceptable for data, security, or external interfaces.
- Do not build for hypothetical future users. Build for the requirements in the PRD.
- When a requirement is validated, promote its components to production maturity and give them full tests and hardening.
