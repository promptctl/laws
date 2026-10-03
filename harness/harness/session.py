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
import threading
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
        if "work_dir" not in data:
            raise HarnessError("spec", "a session spec needs a work_dir")
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


def check_prompt(prompt: object) -> str:
    """A prompt the TUI submits as typed text and records byte for byte. A leading "/",
    "!" or "#" would run a command, a shell line or a memory edit, and the input box trims
    surrounding whitespace, so each is refused rather than sent and found changed."""
    if not isinstance(prompt, str) or not prompt.strip():
        raise HarnessError("spec", f"a prompt is non-empty text, not {prompt!r}")
    if prompt != prompt.strip():
        raise HarnessError("spec", f"a prompt cannot start or end with whitespace: {prompt[:60]!r}")
    if prompt[0] in "/!#":
        raise HarnessError("spec", f"a prompt cannot start with {prompt[0]!r}, which the TUI reads as a command: {prompt[:60]!r}")
    return prompt


def shown(pane: str, text: str) -> int:
    """How many times the pane shows `text`. The TUI wraps a long line onto indented rows of
    its own, so whitespace, line breaks included, is dropped from both before counting."""
    return "".join(pane.split()).count("".join(text.split()))


def launch_env(spec: Spec, editor: Path) -> dict[str, str]:
    # Subagents run on the requested model too, so every response can be held to it.
    return claude.session_env(home.CONFIG_DIR, {"EDITOR": str(editor), "VISUAL": str(editor),
                                                "CLAUDE_CODE_SUBAGENT_MODEL": spec.model})


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _wait(what: str, stage: str, timeout: float, probe: Callable[[], object], pane: Callable[[], str],
          stop: threading.Event) -> object:
    """Poll `probe` until it returns something truthy; on timeout, say what the pane showed."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        _check_stop(stop)
        found = probe()
        if found:
            return found
        stop.wait(POLL_SECS)
    raise HarnessError(stage, f"{what} did not happen within {timeout:.0f}s. The pane showed:\n{pane()}")


def _check_stop(stop: threading.Event) -> None:
    if stop.is_set():
        raise HarnessError("interrupted", "the caller stopped the run")


class Session:
    """Use as a context manager. Leaving the block, by any path, ends the tmux session and
    moves the transcript into the run dir."""

    def __init__(self, spec: Spec, run_dir: Path, run_id: str, stop: threading.Event | None = None):
        """Setting `stop` ends the run at its next poll, at any stage, as an `interrupted`
        failure: Ctrl-C reaches only a caller's main thread, never the one running this."""
        self.spec, self.run_dir, self.run_id = spec, run_dir, run_id
        self._stop = stop if stop is not None else threading.Event()
        self.session_id = str(uuid.uuid4())
        self.tmux_name = f"harness-{run_id}"
        self.started_at = datetime.now(timezone.utc)
        self.binary: claude.Binary | None = None
        self.auth: claude.Auth | None = None
        self.pinned: list[plugins.Pinned] = []
        # What the caller admitted, read once at launch: the session runs with permissions
        # skipped and can rewrite its own work dir, so nothing is read from it afterwards.
        self.admitted: dict | None = None
        self.project_defs = transcript.ProjectDefs()
        self._live_path: Path | None = None
        self._live_offset = 0
        self._live_records: list[dict] = []
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
                except HarnessError as error:
                    # The failure that stopped the session is the one to report; why its
                    # transcript could not be captured rides along on it.
                    if exc is None:
                        raise
                    exc.add_note(str(error))
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
        if len(set(spec.plugins)) != len(spec.plugins):
            raise HarnessError("spec", f"a plugin is admitted twice: {list(spec.plugins)}")
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
        self.project_defs = project_defs(spec.work_dir)
        editor = control / "editor.sh"
        editor.write_text(f"#!/bin/sh\ncp {shlex.quote(str(control / 'prompt.txt'))} \"$1\" && touch {shlex.quote(str(control / 'editor.done'))}\n")
        editor.chmod(0o755)

        argv = ["/usr/bin/env", "-i"]
        argv += [f"{k}={v}" for k, v in launch_env(spec, editor).items()]
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

        _check_stop(self._stop)
        tmux.new_session(self.tmux_name, PANE_WIDTH, PANE_HEIGHT, str(spec.work_dir), argv)
        self._launched = True
        # env execs claude, so the pane process is claude itself.
        self._pid = tmux.pane_pid(self.tmux_name)
        self._await_ready()

    def _admit(self, guidance: Path | None) -> dict:
        spec = self.spec
        claude.refuse_credential_settings(spec.settings, "the spec's settings")
        project_hooks: set[str] = set()
        if spec.project_settings:
            # settings.local.json is the "local" setting source, which never loads.
            f = spec.work_dir / ".claude" / "settings.json"
            if f.is_file():
                try:
                    project = json.loads(f.read_text())
                except json.JSONDecodeError as error:
                    raise HarnessError("spec", f"{f} is not JSON: {error}") from None
                claude.refuse_credential_settings(project, str(f))
                project_hooks |= set(project.get("hooks", {}))
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
            _check_stop(self._stop)
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
            self._stop.wait(POLL_SECS)
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
        if self._live_path is None:
            self._live_path = self._live_transcript()
            if self._live_path is None:
                return []
        # claude only appends, so each read parses just the lines added since the last. A
        # last line without its newline is a record mid-write, left for the next read.
        with self._live_path.open("rb") as f:
            f.seek(self._live_offset)
            added = f.read()
        complete = added[:added.rfind(b"\n") + 1]
        self._live_records += transcript.parse(complete.decode())
        self._live_offset += len(complete)
        return self._live_records

    def turn(self, prompt: str, timeout: float = TURN_TIMEOUT_SECS) -> transcript.Turn:
        check_prompt(prompt)
        name = self.tmux_name
        pane = lambda: tmux.capture(name)  # noqa: E731
        records = self.records()
        prompts_before, turns_before = len(transcript.prompts(records)), len(transcript.turns(records))
        control = self.run_dir / "control"
        done = control / "editor.done"
        done.unlink(missing_ok=True)
        (control / "prompt.txt").write_text(prompt)
        # The prompt's last line is where the box's cursor sits, so it is on screen however
        # long the prompt is; it is in the box once the pane shows it once more than before.
        tail = prompt.splitlines()[-1][-60:]
        shown_before = shown(pane(), tail)
        tmux.send_keys(name, "C-g")
        _wait("the editor writing the prompt", "turn", EDITOR_TIMEOUT_SECS, done.exists, pane, self._stop)
        _wait("the prompt appearing in the input box", "turn", EDITOR_TIMEOUT_SECS,
              lambda: shown(pane(), tail) > shown_before, pane, self._stop)
        tmux.send_keys(name, "Enter")

        def submitted() -> bool:
            sent = transcript.prompts(self.records())
            if len(sent) <= prompts_before:
                return False
            if sent[prompts_before] != prompt:
                raise HarnessError("turn", f"the session recorded a different prompt than was sent "
                                           f"(sent sha256 {_sha256(prompt)}, recorded {sent[prompts_before][:200]!r})")
            return True

        _wait("the session recording the prompt", "turn", SUBMIT_TIMEOUT_SECS, submitted, pane, self._stop)

        def finished() -> transcript.Turn | None:
            if not tmux.alive(name):
                raise HarnessError("turn", f"claude exited mid-turn. The pane showed:\n{pane()}")
            done_turns = transcript.turns(self.records())
            return done_turns[turns_before] if len(done_turns) > turns_before else None

        return _wait("the turn finishing", "turn", timeout, finished, pane, self._stop)

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



def _named(path: Path) -> str:
    """A skill or agent file's `name:` frontmatter, else its file name."""
    lines = path.read_text().splitlines()
    if lines and lines[0].strip() == "---":
        for line in lines[1:]:
            if line.strip() == "---":
                break
            if line.startswith("name:") and line[5:].strip():
                return line[5:].strip().strip("'\"")
    return path.parent.name if path.name == "SKILL.md" else path.stem


def _defined(claude_dir: Path) -> tuple[set[str], set[str]]:
    """The skill and agent names one .claude directory defines. A command in a
    subdirectory is listed as `dir:name`."""
    skills = {_named(d / "SKILL.md") for d in (claude_dir / "skills").glob("*") if (d / "SKILL.md").is_file()}
    commands = claude_dir / "commands"
    skills |= {":".join(f.relative_to(commands).with_suffix("").parts) for f in commands.rglob("*.md")}
    agents = {_named(f) for f in (claude_dir / "agents").glob("*.md")}
    return skills, agents


def project_defs(work_dir: Path) -> transcript.ProjectDefs:
    """What the work dir and its parent directories define. Parents reach the owner's home,
    whose .claude is the owner's own setup; those names are listed too, and none of them
    may load."""
    work_skills, work_agents = _defined(work_dir / ".claude")
    parent_skills: set[str] = set()
    parent_agents: set[str] = set()
    for parent in work_dir.parents:
        skills, agents = _defined(parent / ".claude")
        parent_skills |= skills
        parent_agents |= agents
    return transcript.ProjectDefs(frozenset(work_skills), frozenset(work_agents),
                                  frozenset(parent_skills), frozenset(parent_agents))
