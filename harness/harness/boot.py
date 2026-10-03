"""What a booting pane means. Pure: pane text in, one state out, so every state is tested
against captured panes rather than only against whatever a live boot does today."""
from __future__ import annotations

import re

BANNER_RE = re.compile(r"Claude Code v[0-9]")
# The footer row the TUI paints under the input box once it accepts input. The harness
# always launches in bypass mode, whose footer carries this text.
STATUS_LINE_RE = re.compile(r"bypass permissions on")
LOGIN_NOTICE_RE = re.compile(r"Not logged in|Login expired")
ONBOARDING_RE = re.compile(r"Choose the text style|Let's get started[.]|Select login method")
UNTRUSTED_RE = re.compile(r"Is this a project you created or one you trust[?]|Accessing workspace:|trust this folder")
BYPASS_GATE_RE = re.compile(r"Bypass Permissions mode")

READY, LOGGED_OUT, ONBOARDING, UNTRUSTED, BYPASS_DISCLAIMER, FORMING = (
    "ready", "logged-out", "onboarding", "untrusted", "bypass-disclaimer", "forming")

MEANING = {
    READY: "the session is up and accepting input",
    LOGGED_OUT: "the session cannot authenticate; run `harness login` (it needs a browser)",
    ONBOARDING: "the session stopped at first-run onboarding; `harness login` writes the state that skips it",
    UNTRUSTED: "the session stopped at the workspace trust dialog",
    BYPASS_DISCLAIMER: "the session stopped at the bypass-permissions disclaimer",
    FORMING: "the session has drawn nothing recognisable yet",
}


def state(pane: str) -> str:
    """The banner is checked first and the gates only without it: onboarding and the trust
    dialog replace the whole screen, so a pane showing the banner is past them, and text a
    session prints about them cannot be mistaken for them. The login notice counts only on
    the status row itself, which content cannot forge."""
    lines = pane.splitlines()
    status = [line for line in lines if STATUS_LINE_RE.search(line)]
    if BANNER_RE.search(pane):
        if not status:
            return FORMING
        return LOGGED_OUT if LOGIN_NOTICE_RE.search(status[-1]) else READY
    if ONBOARDING_RE.search(pane):
        return ONBOARDING
    if UNTRUSTED_RE.search(pane):
        return UNTRUSTED
    if BYPASS_GATE_RE.search(pane):
        return BYPASS_DISCLAIMER
    return FORMING



def trust_selected(pane: str) -> bool:
    """The trust dialog's cursor is on the yes option."""
    return any(line.lstrip().startswith("❯") and "Yes, I trust this folder" in line for line in pane.splitlines())
