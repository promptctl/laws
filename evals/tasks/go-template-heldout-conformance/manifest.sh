# Task manifest - DATA ONLY, no logic. The headroom task: seven string helpers are gutted and
# must be reimplemented to byte-match the Go original on a HELD-OUT conformance corpus the agent
# never sees - a criterion the agent cannot iterate against, unlike the sibling tasks' visible
# gates. The corpus lives in this task dir (heldout-fixtures/) and is injected at check time.
TASK_REPO="https://github.com/promptctl/go-template-js"
TASK_COMMIT="db35fb8cb5f78bcf75eefbfb46a57665584c6e06"
TASK_SUMMARY="Reimplement seven gutted string helpers to byte-match Go sprig on a held-out conformance corpus"
