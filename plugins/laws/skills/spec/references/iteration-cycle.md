# Iteration cycle

1. A user request arrives or a test produces a finding. Update the **PRD** with a validation log entry and with new or revised requirements.
2. Update the **FSD**: mark the affected requirements as validated, draft, or deprecated.
3. Update the **Spec**: promote, add, or schedule removal of components, and set the implementation plan.
4. Update the **traceability matrix** and run its coverage checks, so a specified-but-unbuilt requirement lands in the implementation plan before the build starts.
5. Build the plan, then test it with a person or an agent using the FSD's test cases as real tasks. Record what was observed, and return to step 1.
