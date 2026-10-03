"""Run live, isolated Claude Code sessions on the owner's subscription login.

The package imports nothing from any eval. An eval imports `harness.session` and
`harness.record`; nothing flows the other way.
"""


class HarnessError(Exception):
    """A run that cannot be trusted. Raised, never logged and continued past.

    `stage` names where the run was when it stopped, so a failure record can say which
    step to look at without the reader opening a traceback.
    """

    def __init__(self, stage: str, message: str):
        super().__init__(f"[{stage}] {message}")
        self.stage = stage
        self.message = message
