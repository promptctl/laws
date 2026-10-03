"""One live, interactive Claude Code session driven over tmux.

Turns are typed through the TUI's external-editor key: the session's $EDITOR is a
harness script that writes the next prompt into the input box, so a prompt of any size
reaches the model exactly as written. (A bracketed paste above a size threshold reaches
it wrapped in <pasted_content> tags, which tells the model the text is untrusted.) Every
turn is confirmed from the transcript, not the screen: the session recorded our prompt
byte for byte, and a turn_duration record closed the turn.
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import shutil
import signal
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from . import HarnessError, boot, claude, home, plugins, tmux, transcript

PANE_WIDTH, PANE_HEIGHT = 200, 50
POLL_SECS = 1.0
BOOT_TIMEOUT_SECS = 120
EDITOR_TIMEOUT_SECS = 30
SUBMIT_TIMEOUT_SECS = 60
TURN_TIMEOUT_SECS = 1800
EXIT_TIMEOUT_SECS = 30
KILL_TIMEOUT_SECS = 5


@dataclass(frozen=True)
class Spec:
    """Everything a caller admits into a session. Nothing else loads."""
    work_dir: Path
    model: str  # a full model id; the session must be served by exactly this model
    plugins: tuple[plugins.GitPlugin | plugins.DirPlugin, ...] = ()
    append_system_prompt: Path | None = None
    claude_version: str | None = None  # None records the version found without holding it
    settings: dict = field(default_factory=dict)  # extra --settings; hook events in it are admitted
    mcp_config: dict | None = None  # MCP servers admitted by name
    # The work dir's own CLAUDE.md and .claude/settings.json load (setting source
    # "project"). Off, no settings file and no CLAUDE.md loads at all.
    project_settings: bool = False

    @staticmethod
    def from_json(data: dict) -> "Spec":
        allowed = {"work_dir", "model", "plugins", "append_system_prompt", "claude_version", "settings", "mcp_config",
                   "project_settings"}
        unknown = set(data) - allowed
        if unknown:
            raise HarnessError("spec", f"unknown spec fields {sorted(unknown)}")
        if not str(data.get("model", "")).startswith("claude-"):
            raise HarnessError("spec", f"model must be a full model id (claude-...), not {data.get('model')!r}")
        return Spec(
            work_dir=Path(data["work_dir"]).resolve(),
            model=data["model"],
            plugins=tuple(plugins.parse_spec(p) for p in data.get("plugins", [])),
            append_system_prompt=Path(data["append_system_prompt"]).resolve() if data.get("append_system_prompt") else None,
            claude_version=data.get("claude_version"),
            settings=data.get("settings", {}),
            mcp_config=data.get("mcp_config"),
            project_settings=bool(data.get("project_settings", False)),
        )


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _wait(what: str, stage: str, timeout: float, probe: Callable[[], object], pane: Callable[[], str]) -> object:
    """Poll `probe` until it returns something truthy; on timeout, say what the pane showed."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = probe()
        if found:
            return found
        time.sleep(POLL_SECS)
    raise HarnessError(stage, f"{what} did not happen within {timeout:.0f}s. The pane showed:\n{pane()}")


class Session:
    """Use as a context manager. Leaving the block, by any path, ends the tmux session and
    moves the transcript into the run dir."""

    def __init__(self, spec: Spec, run_dir: Path, run_id: str):
        self.spec, self.run_dir, self.run_id = spec, run_dir, run_id
        self.session_id = str(uuid.uuid4())
        self.tmux_name = f"harness-{run_id}"
        self.started_at = datetime.now(timezone.utc)
        self.binary: claude.Binary | None = None
        self.auth: claude.Auth | None = None
        self.pinned: list[plugins.Pinned] = []
        # What the caller admitted, read once at launch: the session runs with permissions
        # skipped and can rewrite its own work dir, so nothing is read from it afterwards.
        self.admitted: dict | None = None
        self.work_dir_skills: frozenset[str] = frozenset()
        self.transcript_path: Path | None = None  # set once the session is closed and the file moved
        self._lock = None
        self._launched = False
        self._pid: int | None = None

    # ── lifecycle ──────────────────────────────────────────────────────────────────────
    def __enter__(self) -> "Session":
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self._lock = home.lock(exclusive=False)
        self._lock.__enter__()
        try:
            self._start()
        except BaseException as error:
            self.__exit__(type(error), error, error.__traceback__)
            raise
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        try:
            if self._launched:
                tmux.kill(self.tmux_name)
                try:
                    forced = self._await_exit()
                except HarnessError as error:
                    if exc is None:
                        raise
                    exc.add_note(str(error))
                    return
                try:
                    self._capture_transcript()
                except HarnessError:
                    # A session that failed before it wrote a transcript has nothing to
                    # capture; the failure that stopped it is the one to report.
                    if exc is None:
                        raise
                if forced is not None:
                    # A failure already in flight is the one to report; the forced exit
                    # rides along on it rather than replacing it.
                    if exc is None:
                        raise HarnessError("teardown", forced)
                    exc.add_note(f"[teardown] {forced}")
        finally:
            if self._lock is not None:
                self._lock.__exit__(None, None, None)
                self._lock = None

    def _start(self) -> None:
        spec = self.spec
        if not spec.work_dir.is_dir():
            raise HarnessError("spec", f"work dir does not exist: {spec.work_dir}")
        home.check_config_dir()
        self.binary = claude.resolve_binary(spec.claude_version)
        self.auth = claude.auth(self.binary, home.CONFIG_DIR)
        plugin_root = self.run_dir / "plugins"
        self.pinned = [plugins.pin(p, plugin_root) for p in spec.plugins]
        names = [p.name for p in self.pinned]
        if len(set(names)) != len(names):
            raise HarnessError("plugins", f"two admitted plugins share a name: {names}")

        control = self.run_dir / "control"
        control.mkdir(exist_ok=True)
        guidance = None
        if spec.append_system_prompt is not None:
            # Loaded from a copy, so the recorded digest is of what the session read.
            guidance = control / "append-system-prompt.md"
            shutil.copyfile(spec.append_system_prompt, guidance)
        self.admitted = self._admit(guidance)
        self.work_dir_skills = _work_dir_skills(spec.work_dir)
        editor = control / "editor.sh"
        editor.write_text(f"#!/bin/sh\ncp {shlex.quote(str(control / 'prompt.txt'))} \"$1\" && touch {shlex.quote(str(control / 'editor.done'))}\n")
        editor.chmod(0o755)

        argv = ["/usr/bin/env", "-i"]
        argv += [f"{k}={v}" for k, v in claude.session_env(home.CONFIG_DIR, {"EDITOR": str(editor), "VISUAL": str(editor)}).items()]
        # The resolved versioned file, launched under a symlink named `claude` so the process
        # is recognisable by name and cannot be repointed by an update mid-run.
        link = control / "claude"
        link.symlink_to(self.binary.path)
        settings = {"skipDangerousModePermissionPrompt": True} | spec.settings
        argv += [str(link), "--model", spec.model, "--session-id", self.session_id,
                 "--setting-sources", "project" if spec.project_settings else "", "--settings", json.dumps(settings),
                 "--strict-mcp-config", "--dangerously-skip-permissions"]
        if spec.mcp_config is not None:
            argv += ["--mcp-config", json.dumps(spec.mcp_config)]
        for p in self.pinned:
            argv += ["--plugin-dir", str(p.plugin_dir)]
        if guidance is not None:
            argv += ["--append-system-prompt-file", str(guidance)]

        tmux.new_session(self.tmux_name, PANE_WIDTH, PANE_HEIGHT, str(spec.work_dir), argv)
        self._launched = True
        # env execs claude, so the pane process is claude itself.
        self._pid = tmux.pane_pid(self.tmux_name)
        self._await_ready()

    def _admit(self, guidance: Path | None) -> dict:
        spec = self.spec
        project_hooks: set[str] = set()
        if spec.project_settings:
            # settings.local.json is the "local" setting source, which never loads.
            f = spec.work_dir / ".claude" / "settings.json"
            if f.is_file():
                try:
                    project_hooks |= set(json.loads(f.read_text()).get("hooks", {}))
                except json.JSONDecodeError as error:
                    raise HarnessError("spec", f"{f} is not JSON: {error}") from None
        return {
            "plugins": [{"name": p.name, **p.provenance} for p in self.pinned],
            "append_system_prompt": None if guidance is None else {
                "path": str(spec.append_system_prompt), "sha256": hashlib.sha256(guidance.read_bytes()).hexdigest()},
            "hook_events": sorted({e for p in self.pinned for e in p.hook_events} | set(spec.settings.get("hooks", {}))
                                  | project_hooks),
            "mcp_servers": sorted((spec.mcp_config or {}).get("mcpServers", {})),
            "project_settings": spec.project_settings,
        }

    def _await_ready(self) -> None:
        """Wait out `forming`; answer the trust dialog with yes (the work dir is the
        caller's); refuse every other gate at once."""
        deadline = time.monotonic() + BOOT_TIMEOUT_SECS
        pane = ""
        while time.monotonic() < deadline:
            if not tmux.alive(self.tmux_name):
                raise HarnessError("boot", f"claude exited during boot. The pane showed:\n{tmux.capture(self.tmux_name)}")
            pane = tmux.capture(self.tmux_name)
            current = boot.state(pane)
            if current == boot.READY:
                return
            if current == boot.UNTRUSTED:
                # Confirmed only once the cursor sits on the yes option: in bypass mode the
                # dialog's default is "No, exit", so a bare Enter would quit.
                tmux.send_keys(self.tmux_name, "Enter" if boot.trust_selected(pane) else "Down")
            elif current != boot.FORMING:
                raise HarnessError("boot", f"session booted to '{current}': {boot.MEANING[current]}. The pane showed:\n{pane}")
            time.sleep(POLL_SECS)
        raise HarnessError("boot", f"session never became ready within {BOOT_TIMEOUT_SECS}s. The pane showed:\n{pane}")

    # ── turns ──────────────────────────────────────────────────────────────────────────
    def _live_transcript(self) -> Path | None:
        found = list((home.CONFIG_DIR / "projects").glob(f"*/{self.session_id}.jsonl"))
        if len(found) > 1:
            raise HarnessError("transcript", f"session {self.session_id} has {len(found)} transcripts: {found}")
        return found[0] if found else None

    def records(self) -> list[dict]:
        if self.transcript_path is not None:
            return transcript.load(self.transcript_path)
        live = self._live_transcript()
        # claude is still appending: a last line without its newline is a record mid-write.
        return transcript.parse(live.read_text(), complete=False) if live is not None else []

    def turn(self, prompt: str, timeout: float = TURN_TIMEOUT_SECS) -> transcript.Turn:
        if not prompt:
            raise HarnessError("turn", "an empty prompt")
        name = self.tmux_name
        pane = lambda: tmux.capture(name)  # noqa: E731
        records = self.records()
        prompts_before, turns_before = len(transcript.prompts(records)), len(transcript.turns(records))
        control = self.run_dir / "control"
        done = control / "editor.done"
        done.unlink(missing_ok=True)
        (control / "prompt.txt").write_text(prompt)
        empty_box = pane()
        tmux.send_keys(name, "C-g")
        _wait("the editor writing the prompt", "turn", EDITOR_TIMEOUT_SECS, done.exists, pane)
        _wait("the prompt appearing in the input box", "turn", EDITOR_TIMEOUT_SECS, lambda: pane() != empty_box, pane)
        tmux.send_keys(name, "Enter")

        def submitted() -> bool:
            sent = transcript.prompts(self.records())
            if len(sent) <= prompts_before:
                return False
            if sent[prompts_before] != prompt:
                raise HarnessError("turn", f"the session recorded a different prompt than was sent "
                                           f"(sent sha256 {_sha256(prompt)}, recorded {sent[prompts_before][:200]!r})")
            return True

        _wait("the session recording the prompt", "turn", SUBMIT_TIMEOUT_SECS, submitted, pane)

        def finished() -> transcript.Turn | None:
            if not tmux.alive(name):
                raise HarnessError("turn", f"claude exited mid-turn. The pane showed:\n{pane()}")
            done_turns = transcript.turns(self.records())
            return done_turns[turns_before] if len(done_turns) > turns_before else None

        return _wait("the turn finishing", "turn", timeout, finished, pane)

    # ── close-out ──────────────────────────────────────────────────────────────────────
    def _exited_within(self, seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                os.kill(self._pid, 0)
            except ProcessLookupError:
                return True
            time.sleep(0.2)
        return False

    def _await_exit(self) -> str | None:
        """claude writes its last transcript records while it shuts down, after the tmux
        session is gone. Moving the file before the process has exited strands that tail
        in a new file at the old path. One that will not exit is killed, so it cannot go on
        writing to the shared config dir; the return says that happened."""
        if self._pid is None or self._exited_within(EXIT_TIMEOUT_SECS):
            return None
        os.kill(self._pid, signal.SIGKILL)
        if not self._exited_within(KILL_TIMEOUT_SECS):
            raise HarnessError("teardown", f"claude (pid {self._pid}) survived SIGKILL; its transcript was left in place")
        return f"claude (pid {self._pid}) was still running {EXIT_TIMEOUT_SECS}s after its session ended and was killed"

    def _capture_transcript(self) -> None:
        """Move, not copy: the config dir then never accumulates runs' records, and what a
        later run finds there is only its own. A session's subagent transcripts live in a
        directory named after it and move with it."""
        live = self._live_transcript()
        if live is None:
            raise HarnessError("transcript", f"session {self.session_id} left no transcript under {home.CONFIG_DIR / 'projects'}")
        target = self.run_dir / "transcript"
        target.mkdir(exist_ok=False)
        shutil.move(str(live), target / live.name)
        sidecar = live.with_suffix("")
        if sidecar.is_dir():
            shutil.move(str(sidecar), target / sidecar.name)
        self.transcript_path = target / live.name


def _work_dir_skills(work_dir: Path) -> frozenset[str]:
    """The skills and commands the work dir defines, which load as project skills."""
    claude_dir = work_dir / ".claude"
    skills = {d.name for d in (claude_dir / "skills").glob("*") if (d / "SKILL.md").is_file()}
    commands = {f.stem for f in (claude_dir / "commands").glob("*.md")}
    return frozenset(skills | commands)
