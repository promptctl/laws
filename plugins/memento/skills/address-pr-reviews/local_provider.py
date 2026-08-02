#!/usr/bin/env python3
"""Local PR review provider — stub for a locally-running review agent.

This module satisfies the provider contract interface and raises
NotImplementedError on every method until the local agent is implemented.

To implement:
1. Decide how the local agent is invoked (binary, Python script, claude -p, etc.)
2. Implement `wait` (or make it a synchronous no-op if `fetch` blocks)
3. Implement `fetch` to run the agent and emit canonical findings JSON
4. If the agent can mark findings as done, implement `resolve`
5. Add a `setup_check` that verifies the binary / model is available
6. Update CAPABILITIES to reflect what's actually implemented
7. Set provider.json to {"provider": "local"}

See PROVIDER_CONTRACT.md for the full interface spec.
"""

from __future__ import annotations

CAPABILITIES = {
    "resolve":        False,  # local agent findings have no GitHub thread to resolve
    "trigger":        True,   # local agent must be explicitly invoked
    "setup_check":    True,   # can check whether the agent binary is available
    "dismiss_review": False,  # no formal GitHub review to dismiss
}


def setup_check(owner: str, repo: str) -> dict:
    raise NotImplementedError(
        "local_provider.setup_check is not yet implemented. "
        "Add a check that verifies the local review agent binary is on PATH "
        "and any required model/API credentials are configured."
    )


def trigger(pr_url: str) -> dict:
    raise NotImplementedError(
        "local_provider.trigger is not yet implemented. "
        "Invoke the local review agent on the PR diff and return "
        '{"triggered": True} when the agent has been successfully started.'
    )


def wait(pr_url: str) -> dict:
    raise NotImplementedError(
        "local_provider.wait is not yet implemented. "
        "If the local agent runs synchronously inside trigger(), implement wait "
        "as a no-op returning {\"status\": \"completed\", \"conclusion\": \"success\", "
        '"sha\": \"\", \"url\": None}. If it runs asynchronously, poll for completion.'
    )


def fetch(pr_url: str) -> dict:
    raise NotImplementedError(
        "local_provider.fetch is not yet implemented. "
        "Run the local review agent on the PR and return its findings in "
        "canonical form: {\"findings\": [{...}]}. See PROVIDER_CONTRACT.md "
        "for the Finding schema."
    )
