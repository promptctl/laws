"""Prove the harness against live sessions on the subscription login.

Two sessions. The clean one admits nothing and is driven for two turns, the second a
prompt large enough that a paste would arrive wrapped. The control one admits one of each
thing a session can load (a work-dir CLAUDE.md, a project skill and agent, a project
hook, a --settings hook, a plugin with a hook of its own, an MCP server) and
proves the transcript readers see each load: a reader that saw nothing would make the
clean session's empty reading worthless. The control session's loads are then checked
against an empty admission, which must refuse every one of them.
"""
from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

import jsonschema

from . import HarnessError, home, record, session, transcript
from .run import run
from .session import Spec
from .plugins import DirPlugin

HERE = Path(__file__).resolve().parent.parent
PROBE_PLUGIN = HERE / "tests" / "fixtures" / "probe-plugin"
GUIDANCE_MARKER = "HARNESS-VERIFY-GUIDANCE-3c91"
# Its last line is about 420 characters, so in a 200-column pane the input box wraps it
# twice, and the second wrap lands inside the 60-character tail the turn looks for.
LARGE_PROMPT = "\n".join(f"Line {i}: filler that makes this prompt larger than a paste may be." for i in range(80)) \
    + "\n" + "This last line runs past the width of the pane so that it wraps. " * 5 \
    + "Padding so the wrap lands in the tail. Reply with exactly the word BRAVO and nothing else."


class Checks:
    def __init__(self) -> None:
        self.failed = 0

    def check(self, label: str, ok: bool, detail: str) -> None:
        self.failed += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {label} - {detail}")


def verify(model: str, out: Path | None) -> int:
    root = out or Path(tempfile.mkdtemp(prefix="harness-verify-"))
    checks = Checks()

    print("== clean session: subscription, requested model, nothing loaded, two turns ==")
    clean_work = root / "clean-work"
    clean_work.mkdir(parents=True)
    try:
        clean = run(Spec(work_dir=clean_work.resolve(), model=model),
                    ["Reply with exactly the word ALPHA and nothing else.", LARGE_PROMPT], root / "clean", "verify-clean")
    except HarnessError as error:
        checks.check("clean session ran", False, str(error))
        return _finish(checks, root, out)
    checks.check("subscription login", clean["auth"]["method"] == "claude.ai", json.dumps(clean["auth"]))
    checks.check("served by the requested model", clean["model"]["served"] == [model], json.dumps(clean["model"]))
    checks.check("nothing loaded beyond builtins", not any(clean["loaded"].values()), json.dumps(clean["loaded"]))
    replies = [t["reply"].strip() for t in clean["turns"]]
    checks.check("driven for two turns", replies == ["ALPHA", "BRAVO"], f"replies {replies}")
    clean_transcript = root / "clean" / clean["transcript"]
    checks.check("transcript captured", clean_transcript.is_file(), str(clean_transcript))
    checks.check("nothing left in the config dir", not _left_behind(clean), clean["session_id"])
    jsonschema.validate(json.loads((root / "clean" / "run.json").read_text()), record.RUN_SCHEMA)
    checks.check("run record conforms to the schema", True, str(root / "clean" / "run.json"))

    print("== control session: each kind of load is seen, and refused when not admitted ==")
    control_work = root / "control-work"
    control_work.mkdir(parents=True)
    (control_work / "CLAUDE.md").write_text("This project is a harness verification fixture.\n")
    (control_work / ".claude").mkdir()
    (control_work / ".claude" / "skills" / "probe-skill").mkdir(parents=True)
    (control_work / ".claude" / "skills" / "probe-skill" / "SKILL.md").write_text(
        "---\nname: probe-skill\ndescription: Exists so verify can see a project skill load. Never use it.\n---\n\nNothing to do.\n")
    (control_work / ".claude" / "agents").mkdir()
    (control_work / ".claude" / "agents" / "probe-agent.md").write_text(
        "---\nname: probe-agent\ndescription: Exists so verify can see a project agent load. Never use it.\n---\n\nNothing to do.\n")
    (control_work / ".claude" / "settings.json").write_text(json.dumps(
        {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo harness verification hook"}]}]}}))
    guidance = root / "guidance.md"
    guidance.write_text(f"{GUIDANCE_MARKER}: this line exists so verify can find it in the system prompt.\n")
    control_spec = Spec(
        work_dir=control_work.resolve(), model=model, plugins=(DirPlugin(PROBE_PLUGIN),), project_settings=True,
        append_system_prompt=guidance.resolve(),
        settings={"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "true"}]}]}},
        mcp_config={"mcpServers": {"harness-probe": {"command": "/usr/bin/false"}}},
    )
    try:
        control = run(control_spec, ["Reply with exactly the word CHARLIE and nothing else."], root / "control", "verify-control")
    except HarnessError as error:
        checks.check("control session ran", False, str(error))
        return _finish(checks, root, out)
    seen = control["loaded"]
    checks.check("work-dir CLAUDE.md is seen", str(control_work.resolve() / "CLAUDE.md") in seen["claude_md"], json.dumps(seen["claude_md"]))
    checks.check("admitted hooks are seen", {"SessionStart", "Stop", "UserPromptSubmit"} <= set(seen["hooks"]), json.dumps(seen["hooks"]))
    checks.check("admitted plugin's skill is seen", "harness-probe:probe" in seen["plugin_skills"], json.dumps(seen["plugin_skills"]))
    checks.check("admitted MCP server is seen", "harness-probe" in seen["mcp_servers"], json.dumps(seen["mcp_servers"]))
    checks.check("project skill is seen", seen["project_skills"] == ["probe-skill"], json.dumps(seen["project_skills"]))
    checks.check("project agent is seen", seen["project_agents"] == ["probe-agent"], json.dumps(seen["project_agents"]))
    checks.check("nothing left in the config dir", not _left_behind(control), control["session_id"])
    control_records = transcript.load(root / "control" / control["transcript"])
    checks.check("appended guidance is in the system prompt", GUIDANCE_MARKER in transcript.system_prompt(control_records),
                 control["admitted"]["append_system_prompt"]["sha256"])
    loads = transcript.loaded(control_records, session.project_defs(control_work.resolve()))
    nothing = {"plugins": [], "hook_events": [], "mcp_servers": [], "project_settings": False}
    refused = record.isolation_violations(loads, nothing, control_work.resolve())
    kinds = {"CLAUDE.md", "hook", "plugin skill", "project skill", "project agent", "MCP server"}
    checks.check("an empty admission refuses every load", all(any(v.startswith(k) for v in refused) for k in kinds), json.dumps(refused))
    return _finish(checks, root, out)


def _left_behind(run_record: dict) -> list[Path]:
    """Any file of the session's still under the config dir after the run moved it out."""
    return list((home.CONFIG_DIR / "projects").glob(f"*/{run_record['session_id']}*"))


def _finish(checks: Checks, root: Path, out: Path | None) -> int:
    print(f"\nRESULT: {'PASS' if not checks.failed else f'FAIL ({checks.failed} failed)'}  runs in {root}")
    if not checks.failed and out is None:
        shutil.rmtree(root)
    return 1 if checks.failed else 0
