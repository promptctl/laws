"""Every tmux call the harness makes, against exact targets only.

A bare `-t name` prefix-matches, so a session named `run-1` answers to `-t run`. Session
targets here are `=name` and pane targets `=name:`, which match one session or nothing.
"""
from __future__ import annotations

import subprocess

from . import HarnessError


def _tmux(*args: str, input: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["tmux", *args], capture_output=True, text=True, input=input)


def _session(name: str) -> str:
    return f"={name}"


def _pane(name: str) -> str:
    return f"={name}:"


def new_session(name: str, width: int, height: int, cwd: str, argv: list[str]) -> None:
    """Start `argv` as the pane process itself, no shell in between. tmux refuses a name
    already in use, atomically, so two runs can never share a session. The session opens
    on a placeholder and the command replaces it only once the options are set, so even a
    command that exits at once leaves its pane, and its last words, on screen."""
    steps = [
        ("new-session", "-d", "-s", name, "-x", str(width), "-y", str(height), "sleep", "86400"),
        ("set-option", "-t", _pane(name), "remain-on-exit", "on"),
        ("respawn-pane", "-k", "-t", _pane(name), "-c", cwd, *argv),
    ]
    for step in steps:
        out = _tmux(*step)
        if out.returncode != 0:
            if step[0] != "new-session":
                _tmux("kill-session", "-t", _session(name))
            raise HarnessError("launch", f"tmux {step[0]} for session {name} failed: {out.stderr.strip()}")


def alive(name: str) -> bool:
    """The session exists and its pane process has not exited (remain-on-exit keeps a dead
    pane on screen so its last words can be read)."""
    out = _tmux("display-message", "-p", "-t", _pane(name), "#{pane_dead}")
    return out.returncode == 0 and out.stdout.strip() == "0"


def pane_pid(name: str) -> int:
    out = _tmux("display-message", "-p", "-t", _pane(name), "#{pane_pid}")
    if out.returncode != 0 or not out.stdout.strip().isdigit():
        raise HarnessError("launch", f"could not read the pane pid of {name}: {out.stderr.strip()}")
    return int(out.stdout.strip())


def capture(name: str) -> str:
    out = _tmux("capture-pane", "-p", "-t", _pane(name))
    if out.returncode != 0:
        raise HarnessError("tmux", f"could not read the pane of {name}: {out.stderr.strip()}")
    return out.stdout


def send_keys(name: str, *keys: str) -> None:
    out = _tmux("send-keys", "-t", _pane(name), *keys)
    if out.returncode != 0:
        raise HarnessError("tmux", f"send-keys {keys} to {name} failed: {out.stderr.strip()}")


def kill(name: str) -> None:
    """Judged on the postcondition: a session already gone is the goal reached."""
    out = _tmux("kill-session", "-t", _session(name))
    if out.returncode != 0 and _tmux("has-session", "-t", _session(name)).returncode == 0:
        raise HarnessError("teardown", f"could not end tmux session {name}: {out.stderr.strip()}")
