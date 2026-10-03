"""The Claude Code binary a run executes, the login it runs on, and the environment it sees."""
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from . import HarnessError

# One spelling of a version for every reader that compares two of them (the binary's
# --version, and the version each transcript record carries). A suffix such as -rc.1 is
# part of the version.
VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+[^\s]*")

# The only variables a session inherits from the caller. Everything else in the caller's
# shell, an ANTHROPIC_API_KEY above all, never reaches it: the session starts from an
# empty environment (env -i) plus these. HOME stays real because the macOS login keychain
# that holds the subscription credential is found through it.
PASSED_ENV = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR")

# What `claude auth status --json` reports for a subscription login. Anything else, an
# API key above all, is refused before a session starts.
SUBSCRIPTION_AUTH_METHODS = ("claude.ai",)


# Settings that would authenticate a session some other way than the subscription login
# `claude auth status` vouched for, or send it to another provider or endpoint. A session's
# settings are refused if they carry any of them.
CREDENTIAL_SETTINGS = ("apiKeyHelper", "awsAuthRefresh", "awsCredentialExport", "gcpAuthRefresh")
CREDENTIAL_ENV = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_BASE_URL",
                  "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
                  "CLAUDE_CODE_USE_GATEWAY", "CLAUDE_CODE_USE_MANTLE", "CLAUDE_CODE_USE_ANTHROPIC_AWS",
                  "CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD")


def refuse_credential_settings(settings: dict, where: str) -> None:
    found = [k for k in CREDENTIAL_SETTINGS if k in settings]
    found += [f"env.{k}" for k in CREDENTIAL_ENV if k in (settings.get("env") or {})]
    if found:
        raise HarnessError("auth", f"{where} sets {found}; runs use the subscription login only")


@dataclass(frozen=True)
class Binary:
    path: Path  # resolved through the installer's moving symlink to the immutable versioned file
    version: str


def resolve_binary(pinned_version: str | None) -> Binary:
    """Resolve `claude` once. The native installer repoints the `claude` on PATH at each
    update but never rewrites a versioned file, so the resolved path holds the version for
    the whole run."""
    found = subprocess.run(["/bin/sh", "-c", "command -v claude"], capture_output=True, text=True)
    if found.returncode != 0 or not found.stdout.strip():
        raise HarnessError("binary", "claude is not on PATH")
    path = Path(os.path.realpath(found.stdout.strip()))
    out = subprocess.run([str(path), "--version"], capture_output=True, text=True, env=_probe_env())
    if out.returncode != 0:
        raise HarnessError("binary", f"{path} --version exited {out.returncode}: {out.stderr.strip()}")
    match = VERSION_RE.search(out.stdout)
    if not match:
        raise HarnessError("binary", f"{path} --version printed no version: {out.stdout!r}")
    version = match.group(0)
    if pinned_version is not None and version != pinned_version:
        raise HarnessError("binary", f"the run pins Claude Code {pinned_version}, but claude on PATH is {version} ({path})")
    return Binary(path, version)


def _probe_env() -> dict[str, str]:
    return {k: os.environ[k] for k in PASSED_ENV if k in os.environ} | {"DISABLE_AUTOUPDATER": "1"}


def session_env(config_dir: Path, extra: dict[str, str]) -> dict[str, str]:
    return _probe_env() | {"CLAUDE_CONFIG_DIR": str(config_dir)} | extra


@dataclass(frozen=True)
class Auth:
    method: str
    provider: str


def auth(binary: Binary, config_dir: Path) -> Auth:
    """The login this config dir runs on, read from Claude Code's own status command:
    no model call, nothing billed. A logged-out dir or any non-subscription method is
    refused, so no run can reach the API on a key."""
    out = subprocess.run([str(binary.path), "auth", "status", "--json"], capture_output=True, text=True,
                         env=session_env(config_dir, {}), stdin=subprocess.DEVNULL)
    try:
        status = json.loads(out.stdout)
    except json.JSONDecodeError:
        raise HarnessError("auth", f"`claude auth status --json` printed no JSON (exit {out.returncode}): {out.stdout!r} {out.stderr.strip()}") from None
    if Path(status.get("configDirectory", "")).resolve() != config_dir.resolve():
        raise HarnessError("auth", f"auth status describes {status.get('configDirectory')!r}, not {config_dir}")
    if status.get("loggedIn") is not True:
        raise HarnessError("auth", f"{config_dir} is not logged in; run `harness login` (it needs a browser)")
    method, provider = str(status.get("authMethod")), str(status.get("apiProvider"))
    if method not in SUBSCRIPTION_AUTH_METHODS or provider != "firstParty":
        raise HarnessError("auth", f"{config_dir} authenticates with {method!r} via {provider!r}; runs use the subscription login only")
    return Auth(method, provider)
