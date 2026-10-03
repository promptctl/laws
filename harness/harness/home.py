"""The harness's one persistent place on this machine: its login config dir and its lock.

The config dir's PATH is load-bearing. Claude Code names the keychain item holding the
login after a hash of the config dir's path, so the login survives wiping the directory
and is lost by moving it. One fixed path, logged into once, serves every run.
"""
from __future__ import annotations

import contextlib
import fcntl
import json
import os
from collections.abc import Iterator
from pathlib import Path

from . import HarnessError

HOME = Path(os.environ.get("CLAUDE_HARNESS_HOME", str(Path.home() / ".claude-harness")))
CONFIG_DIR = HOME / "config"
LOCK_FILE = HOME / "lock"

# Claude Code reads these from a config dir's settings or global state and would load
# guidance or tools from them. The harness's config dir carries none; check_config_dir
# refuses one that grew any.
FOREIGN_ENTRIES = ("CLAUDE.md", "skills", "commands", "agents", "hooks", "output-styles")
# plugins/ itself is not foreign: Claude Code registers the official marketplace catalog
# there on its own. An install is what would load, and installs are listed here.
INSTALLED_PLUGINS = Path("plugins") / "installed_plugins.json"


@contextlib.contextmanager
def lock(exclusive: bool) -> Iterator[None]:
    """Runs hold the lock shared, so any number run at once. `harness login` holds it
    exclusive, so a login can never rotate the credential under a live run."""
    HOME.mkdir(parents=True, exist_ok=True)
    with open(LOCK_FILE, "a") as handle:
        try:
            fcntl.flock(handle, (fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH) | fcntl.LOCK_NB)
        except BlockingIOError:
            what = "a run is live" if exclusive else "`harness login` is running"
            raise HarnessError("lock", f"{what} (lock {LOCK_FILE})") from None
        yield


def provision() -> None:
    """Write the first-run state no unattended session can answer (onboarding, theme) into
    the config dir's global state, merging into whatever Claude Code keeps there. Called
    under the exclusive lock, so no live session is writing the same file."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    state_path = CONFIG_DIR / ".claude.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    state |= {"hasCompletedOnboarding": True, "theme": "dark"}
    state_path.write_text(json.dumps(state, indent=2) + "\n")


def check_config_dir() -> None:
    """Structural isolation: the config dir is not the owner's, holds no guidance, and its
    settings enable nothing. Runs also pass --setting-sources '' so its settings are not
    read at all; this check is what makes that second latch unnecessary, not the reverse."""
    if not CONFIG_DIR.is_dir():
        raise HarnessError("config", f"{CONFIG_DIR} does not exist; run `harness login`")
    if CONFIG_DIR.resolve() == (Path.home() / ".claude").resolve():
        raise HarnessError("config", f"{CONFIG_DIR} is the owner's own config dir")
    present = [name for name in FOREIGN_ENTRIES if (CONFIG_DIR / name).exists()]
    if present:
        raise HarnessError("config", f"{CONFIG_DIR} carries {present}; the harness config dir holds no guidance or plugins")
    installed = CONFIG_DIR / INSTALLED_PLUGINS
    if installed.exists() and json.loads(installed.read_text()).get("plugins"):
        raise HarnessError("config", f"{installed} lists installed plugins; the harness admits plugins only per run")
    settings = CONFIG_DIR / "settings.json"
    if settings.exists():
        enabled = [k for k in ("enabledPlugins", "hooks", "mcpServers") if json.loads(settings.read_text()).get(k)]
        if enabled:
            raise HarnessError("config", f"{settings} sets {enabled}")
