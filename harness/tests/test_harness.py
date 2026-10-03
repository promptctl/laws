"""Offline tests: every pure reader against captured or constructed input, and every
refusal the harness promises. `harness verify` is the live counterpart.

    uv run --with jsonschema python -m unittest discover -s harness/tests -t harness
"""
from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from harness import HarnessError, boot, claude, home, plugins, record, tmux, transcript  # noqa: E402
from harness import cli  # noqa: E402
from harness import run as run_module  # noqa: E402
from harness import session as session_module  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
TWO_TURNS = transcript.load(FIXTURES / "two-turns.jsonl")


def attachment(kind: str, **fields) -> dict:
    return {"type": "attachment", "attachment": {"type": kind, **fields}}


class TranscriptReaders(unittest.TestCase):
    def test_turns_pair_each_prompt_with_its_reply(self):
        turns = transcript.turns(TWO_TURNS)
        self.assertEqual([t.reply for t in turns], ["PONG one", "PONG three"])
        self.assertTrue(turns[1].prompt.endswith("Final: reply with exactly PONG three."))

    def test_an_unclosed_prompt_is_not_a_turn(self):
        last_duration = max(i for i, r in enumerate(TWO_TURNS) if r.get("subtype") == "turn_duration")
        self.assertEqual(len(transcript.turns(TWO_TURNS[:last_duration])), 1)
        self.assertEqual(len(transcript.prompts(TWO_TURNS[:last_duration])), 2)

    def test_served_models_and_versions_come_from_the_records(self):
        self.assertEqual(transcript.served_models(TWO_TURNS), ["claude-haiku-4-5-20251001"])
        self.assertEqual(transcript.claude_versions(TWO_TURNS), ["2.1.288"])

    def test_a_compaction_summary_is_not_a_prompt(self):
        summary = {"type": "user", "isSidechain": False, "isCompactSummary": True, "isVisibleInTranscriptOnly": True,
                   "message": {"role": "user", "content": "This session is being continued from a previous conversation."}}
        last_duration = max(i for i, r in enumerate(TWO_TURNS) if r.get("subtype") == "turn_duration")
        records = TWO_TURNS[:last_duration] + [summary] + TWO_TURNS[last_duration:]
        self.assertEqual(transcript.prompts(records), transcript.prompts(TWO_TURNS))
        self.assertEqual(transcript.turns(records), transcript.turns(TWO_TURNS))

    def test_synthetic_messages_are_not_a_served_model_and_api_errors_are_read(self):
        def synthetic(text, error):
            return {"type": "assistant", "isApiErrorMessage": error,
                    "message": {"model": "<synthetic>", "content": [{"type": "text", "text": text}]}}
        records = TWO_TURNS + [synthetic("No response requested.", False), synthetic("API Error: 529 Overloaded.", True)]
        self.assertEqual(transcript.served_models(records), ["claude-haiku-4-5-20251001"])
        self.assertEqual(transcript.api_errors(records), ["API Error: 529 Overloaded."])
        self.assertEqual(transcript.api_errors(TWO_TURNS), [])

    def test_system_prompt_is_read_from_the_last_snapshot(self):
        records = [attachment("prompt_snapshot", systemPrompt=["a", "b"]), attachment("prompt_snapshot", systemPrompt=["c"])]
        self.assertEqual(transcript.system_prompt(records), "c")
        with self.assertRaisesRegex(HarnessError, "prompt_snapshot"):
            transcript.system_prompt([])

    def test_tokens_count_each_api_message_once(self):
        message = {"id": "msg_1", "model": "m", "content": [], "usage": {"input_tokens": 3, "output_tokens": 5}}
        records = [{"type": "assistant", "message": message}, {"type": "assistant", "message": message}]
        self.assertEqual(transcript.tokens(records), {"input": 3, "output": 5, "cache_read": 0, "cache_creation": 0})

    def test_clean_session_loads_nothing(self):
        self.assertFalse(any(transcript.loaded(TWO_TURNS).as_record().values()))

    def test_every_kind_of_load_is_read(self):
        records = TWO_TURNS + [
            attachment("instructions", files=[{"path": "/Users/x/.claude/CLAUDE.md", "type": "User", "content": "x"}]),
            attachment("hook_success", hookName="SessionStart:startup", hookEvent="SessionStart"),
            attachment("hook_some_outcome_never_seen", hookName="PreCompact", hookEvent="PreCompact"),
            {"type": "system", "subtype": "stop_hook_summary", "hookCount": 1},
            attachment("mcp_instructions_delta", addedNames=["docs"], addedBlocks=[], removedNames=[]),
            attachment("deferred_tools_delta", addedNames=["mcp__search__find"], surfacedNames=[],
                       failedMcpServers=["broken"], pendingMcpServers=[]),
            attachment("skill_listing", names=["simplify", "laws:code", "deploy", "grp:nested", "up"]),
            attachment("agent_listing_delta", addedTypes=["Plan", "laws:auditor", "reviewer", "stray"], builtInTypes=["Plan"]),
        ]
        defs = transcript.ProjectDefs(work_skills=frozenset({"deploy", "grp:nested"}), work_agents=frozenset({"reviewer"}),
                                      parent_skills=frozenset({"up"}), parent_agents=frozenset())
        loaded = transcript.loaded(records, defs)
        self.assertEqual(loaded.claude_md, ("/Users/x/.claude/CLAUDE.md",))
        self.assertEqual(loaded.hooks, ("PreCompact", "SessionStart", "Stop"))
        self.assertEqual(loaded.mcp_servers, ("broken", "docs", "search"))
        self.assertIn("laws:code", loaded.plugin_skills)
        self.assertEqual(loaded.plugin_agents, ("laws:auditor",))
        self.assertEqual(loaded.plugin_skills, ("laws:code",))
        self.assertEqual(loaded.project_skills, ("deploy", "grp:nested"))
        self.assertEqual(loaded.project_agents, ("reviewer",))
        self.assertEqual(loaded.other_skills, ("up",))
        self.assertEqual(loaded.other_agents, ("stray",))

    def test_a_missing_usage_or_duration_is_refused_not_read_as_zero(self):
        message = {"id": "msg_1", "model": "m", "content": [], "usage": {"output_tokens": 5}}
        with self.assertRaisesRegex(HarnessError, "token usage"):
            transcript.tokens([{"type": "assistant", "message": message}])
        stripped = [{k: v for k, v in r.items() if k != "durationMs"} for r in TWO_TURNS]
        with self.assertRaisesRegex(HarnessError, "durationMs"):
            transcript.turns(stripped)

    def test_a_transcript_without_its_listings_is_refused(self):
        stripped = [r for r in TWO_TURNS if r.get("attachment", {}).get("type") != "skill_listing"]
        with self.assertRaisesRegex(HarnessError, "skill_listing"):
            transcript.loaded(stripped)

    def test_a_hook_record_without_its_event_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "hookEvent"):
            transcript.loaded(TWO_TURNS + [attachment("hook_success", hookName="x")])

    def test_a_non_json_line_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "line 2"):
            transcript.parse('{"type": "user"}\nnot json\n')



class Isolation(unittest.TestCase):
    WORK = Path("/work/case")
    NOTHING = {"plugins": [], "hook_events": [], "mcp_servers": [], "project_settings": False}
    PROJECT = NOTHING | {"project_settings": True}

    def loaded(self, **fields) -> transcript.Loaded:
        base = {"claude_md": (), "hooks": (), "plugin_skills": (), "plugin_agents": (), "project_skills": (),
                "project_agents": (), "other_skills": (), "other_agents": (), "mcp_servers": ()}
        return transcript.Loaded(**(base | fields))

    def test_nothing_loaded_is_clean(self):
        self.assertEqual(record.isolation_violations(self.loaded(), self.NOTHING, self.WORK), [])

    def test_claude_md_outside_the_work_dir_is_foreign(self):
        found = record.isolation_violations(
            self.loaded(claude_md=("/work/case/CLAUDE.md", "/work/CLAUDE.md", "/Users/x/.claude/CLAUDE.md")), self.PROJECT, self.WORK)
        self.assertEqual(found, ["CLAUDE.md /work/CLAUDE.md", "CLAUDE.md /Users/x/.claude/CLAUDE.md"])

    def test_project_loads_are_foreign_unless_project_settings_are_admitted(self):
        loaded = self.loaded(claude_md=("/work/case/sub/CLAUDE.md",), project_skills=("deploy",), project_agents=("reviewer",))
        self.assertEqual(record.isolation_violations(loaded, self.NOTHING, self.WORK),
                         ["CLAUDE.md /work/case/sub/CLAUDE.md", "project skill deploy", "project agent reviewer"])
        self.assertEqual(record.isolation_violations(loaded, self.PROJECT, self.WORK), [])

    def test_loads_from_outside_the_work_dir_are_always_foreign(self):
        loaded = self.loaded(other_skills=("up",), other_agents=("stray",))
        self.assertEqual(record.isolation_violations(loaded, self.PROJECT, self.WORK),
                         ["parent-directory skill up", "agent stray from outside the work dir"])

    def test_unadmitted_hooks_plugins_and_servers_are_foreign(self):
        loaded = self.loaded(hooks=("Stop",), plugin_skills=("laws:code",), plugin_agents=("memento:x",), mcp_servers=("docs",))
        self.assertEqual(len(record.isolation_violations(loaded, self.NOTHING, self.WORK)), 4)
        admitted = self.NOTHING | {"plugins": [{"name": "laws"}, {"name": "memento"}], "hook_events": ["Stop"],
                                   "mcp_servers": ["docs"]}
        self.assertEqual(record.isolation_violations(loaded, admitted, self.WORK), [])


class BootStates(unittest.TestCase):
    READY = (" ▐▛███▜▌   Claude Code v2.1.288\n▝▜█████▛▘  Haiku 4.5 · Claude Max\n❯ \n"
             "──────\n  ⏵⏵ bypass permissions on (shift+tab to cycle)\n")

    def test_ready(self):
        self.assertEqual(boot.state(self.READY), boot.READY)

    def test_banner_without_status_line_is_still_forming(self):
        self.assertEqual(boot.state(" ▐▛███▜▌   Claude Code v2.1.288\n"), boot.FORMING)

    def test_login_notice_counts_only_on_the_status_row(self):
        printed = self.READY.replace("❯ \n", "⏺ Bash(gh auth status)\n  Not logged in\n❯ \n")
        self.assertEqual(boot.state(printed), boot.READY)
        on_status = self.READY.replace("(shift+tab to cycle)", "(shift+tab to cycle) · Not logged in")
        self.assertEqual(boot.state(on_status), boot.LOGGED_OUT)

    def test_gates(self):
        self.assertEqual(boot.state("Let's get started.\nChoose the text style"), boot.ONBOARDING)
        self.assertEqual(boot.state("Accessing workspace:\n/tmp/x\n❯ 1. Yes, I trust this folder"), boot.UNTRUSTED)
        self.assertEqual(boot.state("WARNING: Claude Code running in Bypass Permissions mode"), boot.BYPASS_DISCLAIMER)
        self.assertEqual(boot.state(""), boot.FORMING)

    def test_trust_is_confirmed_only_with_the_cursor_on_yes(self):
        dialog = "Accessing workspace:\n /tmp/x\n ❯ No, exit\n   Yes, I trust this folder\n"
        self.assertFalse(boot.trust_selected(dialog))
        self.assertTrue(boot.trust_selected(dialog.replace(" ❯ No", "   No").replace("   Yes", " ❯ Yes")))


def fake_claude(directory: Path, status: dict | None, version: str = "2.1.288 (Claude Code)") -> Path:
    script = directory / "claude"
    status_json = json.dumps(status) if status is not None else "not json"
    script.write_text(f"#!/bin/sh\nif [ \"$1\" = --version ]; then echo '{version}'; exit 0; fi\n"
                      f"printf '%s\\n' {json.dumps(status_json)}\n")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return script


class AuthAndBinary(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.config = self.tmp / "config"
        self.config.mkdir()

    def status(self, **fields) -> dict:
        return {"loggedIn": True, "authMethod": "claude.ai", "apiProvider": "firstParty",
                "configDirectory": str(self.config)} | fields

    def binary(self, status: dict | None) -> claude.Binary:
        return claude.Binary(fake_claude(self.tmp, status), "2.1.288")

    def test_subscription_login_is_accepted(self):
        self.assertEqual(claude.auth(self.binary(self.status()), self.config).method, "claude.ai")

    def test_api_key_auth_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "subscription login only"):
            claude.auth(self.binary(self.status(authMethod="api_key")), self.config)

    def test_third_party_provider_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "subscription login only"):
            claude.auth(self.binary(self.status(apiProvider="bedrock")), self.config)

    def test_logged_out_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "not logged in"):
            claude.auth(self.binary(self.status(loggedIn=False, authMethod="none")), self.config)

    def test_status_about_another_dir_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "describes"):
            claude.auth(self.binary(self.status(configDirectory="/elsewhere")), self.config)

    def test_unparseable_status_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "no JSON"):
            claude.auth(self.binary(None), self.config)

    def test_session_env_carries_no_credential_from_the_caller(self):
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-x", "CLAUDE_CODE_OAUTH_TOKEN": "t", "ANTHROPIC_BASE_URL": "u"}):
            env = claude.session_env(self.config, {})
        self.assertFalse([k for k in env if k.startswith(("ANTHROPIC", "CLAUDE_CODE"))])
        self.assertEqual(env["CLAUDE_CONFIG_DIR"], str(self.config))
        self.assertEqual(env["DISABLE_AUTOUPDATER"], "1")

    def test_version_pin_refuses_another_version(self):
        fake_claude(self.tmp, self.status(), "2.1.300 (Claude Code)")
        with mock.patch.dict(os.environ, {"PATH": f"{self.tmp}:{os.environ['PATH']}"}):
            self.assertEqual(claude.resolve_binary(None).version, "2.1.300")
            with self.assertRaisesRegex(HarnessError, "pins Claude Code 2.1.288"):
                claude.resolve_binary("2.1.288")


class ConfigDir(unittest.TestCase):
    def setUp(self):
        self.config = Path(tempfile.mkdtemp()) / "config"
        patcher = mock.patch.object(home, "CONFIG_DIR", self.config)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_missing_dir_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "does not exist"):
            home.check_config_dir()

    def test_guidance_in_the_config_dir_is_refused(self):
        self.config.mkdir()
        home.check_config_dir()
        (self.config / "CLAUDE.md").write_text("x")
        with self.assertRaisesRegex(HarnessError, "CLAUDE.md"):
            home.check_config_dir()

    def test_a_marketplace_catalog_is_not_an_install(self):
        (self.config / "plugins" / "marketplaces").mkdir(parents=True)
        home.check_config_dir()
        (self.config / home.INSTALLED_PLUGINS).write_text(json.dumps({"version": 2, "plugins": {"laws@x": [{}]}}))
        with self.assertRaisesRegex(HarnessError, "installed plugins"):
            home.check_config_dir()

    def test_enabled_plugins_in_settings_are_refused(self):
        self.config.mkdir()
        (self.config / "settings.json").write_text(json.dumps({"enabledPlugins": {"laws@x": True}}))
        with self.assertRaisesRegex(HarnessError, "enabledPlugins"):
            home.check_config_dir()

    def test_provision_merges_into_existing_state(self):
        self.config.mkdir()
        (self.config / ".claude.json").write_text(json.dumps({"oauthAccount": {"x": 1}}))
        home.provision()
        state = json.loads((self.config / ".claude.json").read_text())
        self.assertEqual(state["oauthAccount"], {"x": 1})
        self.assertTrue(state["hasCompletedOnboarding"])


class Locking(unittest.TestCase):
    def setUp(self):
        root = Path(tempfile.mkdtemp())
        for name, value in (("HOME", root), ("LOCK_FILE", root / "lock")):
            patcher = mock.patch.object(home, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_runs_share_and_login_excludes(self):
        with home.lock(exclusive=False), home.lock(exclusive=False):
            with self.assertRaisesRegex(HarnessError, "a run is live"):
                with home.lock(exclusive=True):
                    pass
        with home.lock(exclusive=True):
            with self.assertRaisesRegex(HarnessError, "harness login"):
                with home.lock(exclusive=False):
                    pass


class Plugins(unittest.TestCase):
    def test_dir_plugin_is_loaded_from_a_copy_pinned_by_digest(self):
        source = Path(tempfile.mkdtemp()) / "probe"
        subprocess.run(["cp", "-R", str(FIXTURES / "probe-plugin"), str(source)], check=True)
        into = Path(tempfile.mkdtemp())
        pinned = plugins.pin(plugins.DirPlugin(source), into)
        self.assertEqual(pinned.name, "harness-probe")
        self.assertTrue(pinned.plugin_dir.is_relative_to(into))
        self.assertEqual(pinned.provenance["sha256"], plugins.tree_digest(source))
        (source / "skills" / "probe" / "SKILL.md").write_text("changed mid-run")
        self.assertEqual(plugins.tree_digest(pinned.plugin_dir), pinned.provenance["sha256"])

    def test_hook_events_come_from_every_place_a_plugin_declares_them(self):
        root = Path(tempfile.mkdtemp())
        (root / ".claude-plugin").mkdir()
        (root / "hooks").mkdir()
        (root / "cfg").mkdir()
        (root / "hooks" / "hooks.json").write_text(json.dumps({"hooks": {"Stop": []}}))
        (root / "cfg" / "more.json").write_text(json.dumps({"hooks": {"PreCompact": []}}))
        manifest = root / ".claude-plugin" / "plugin.json"
        manifest.write_text(json.dumps({"name": "p", "hooks": ["./cfg/more.json", {"SessionStart": []}]}))
        self.assertEqual(plugins.pin(plugins.DirPlugin(root), Path(tempfile.mkdtemp())).hook_events,
                         ("PreCompact", "SessionStart", "Stop"))
        self.assertEqual(plugins.pin(plugins.DirPlugin(FIXTURES / "probe-plugin"), Path(tempfile.mkdtemp())).hook_events,
                         ("UserPromptSubmit",))
        manifest.write_text(json.dumps({"name": "p", "hooks": "./cfg/missing.json"}))
        with self.assertRaisesRegex(HarnessError, "not a file"):
            plugins.pin(plugins.DirPlugin(root), Path(tempfile.mkdtemp()))

    def test_git_plugin_is_pinned_to_a_commit(self):
        repo = Path(tempfile.mkdtemp())
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["cp", "-R", str(FIXTURES / "probe-plugin"), str(repo / "plugin")], check=True)
        git = ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run([*git, "add", "."], check=True)
        subprocess.run([*git, "commit", "-qm", "x"], check=True)
        commit = subprocess.run([*git, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
        into = Path(tempfile.mkdtemp())
        pinned = plugins.pin(plugins.GitPlugin(str(repo), "HEAD", "plugin"), into)
        self.assertEqual((pinned.name, pinned.provenance["commit"]), ("harness-probe", commit))
        self.assertTrue((pinned.plugin_dir / "skills" / "probe" / "SKILL.md").is_file())
        # A second plugin from the same repo at the same commit shares the snapshot.
        again = plugins.pin(plugins.GitPlugin(str(repo), "HEAD", "plugin"), into)
        self.assertEqual(again.plugin_dir, pinned.plugin_dir)

    def test_a_relative_repo_path_is_resolved_against_the_caller(self):
        cwd = Path(tempfile.mkdtemp()).resolve()
        (cwd / "repo").mkdir()
        before = os.getcwd()
        os.chdir(cwd)
        try:
            parsed = plugins.parse_spec({"repo": "repo", "ref": "HEAD", "subdir": "p"})
        finally:
            os.chdir(before)
        self.assertEqual(parsed.repo, str(cwd / "repo"))
        self.assertEqual(plugins.parse_spec({"repo": "https://example.com/r.git", "ref": "HEAD", "subdir": "p"}).repo,
                         "https://example.com/r.git")

    def test_a_spec_must_be_one_shape_or_the_other(self):
        with self.assertRaisesRegex(HarnessError, "a plugin is"):
            plugins.parse_spec({"dir": "x", "ref": "y"})


class SessionLaunch(unittest.TestCase):
    def session(self, **spec_fields) -> session_module.Session:
        work = Path(tempfile.mkdtemp()).resolve()
        return session_module.Session(session_module.Spec(work_dir=work, model="claude-x", **spec_fields),
                                      Path(tempfile.mkdtemp()), "r1")

    def test_admission_reads_the_work_dir_at_launch(self):
        session = self.session(project_settings=True, settings={"hooks": {"Stop": []}})
        (session.spec.work_dir / ".claude").mkdir()
        settings = session.spec.work_dir / ".claude" / "settings.json"
        settings.write_text(json.dumps({"hooks": {"SessionStart": []}}))
        (session.spec.work_dir / ".claude" / "settings.local.json").write_text(json.dumps({"hooks": {"PreCompact": []}}))
        guidance = session.run_dir / "guidance.md"
        guidance.write_text("g")
        admitted = session._admit(guidance)
        self.assertEqual(admitted["hook_events"], ["SessionStart", "Stop"])
        settings.write_text("{not json")
        with self.assertRaisesRegex(HarnessError, "is not JSON"):
            session._admit(None)

    def test_a_work_dir_without_project_settings_admits_none_of_its_hooks(self):
        session = self.session()
        (session.spec.work_dir / ".claude").mkdir()
        (session.spec.work_dir / ".claude" / "settings.json").write_text(json.dumps({"hooks": {"SessionStart": []}}))
        self.assertEqual(session._admit(None)["hook_events"], [])

    def test_project_definitions_are_named_as_the_session_lists_them(self):
        root = Path(tempfile.mkdtemp())
        work = root / "repo" / "sub"
        (work / ".claude" / "skills" / "deploy").mkdir(parents=True)
        (work / ".claude" / "skills" / "deploy" / "SKILL.md").write_text("---\nname: deploy-it\ndescription: x\n---\n")
        (work / ".claude" / "skills" / "empty").mkdir()
        (work / ".claude" / "commands" / "grp").mkdir(parents=True)
        (work / ".claude" / "commands" / "ship.md").write_text("x")
        (work / ".claude" / "commands" / "grp" / "nested.md").write_text("x")
        (work / ".claude" / "agents").mkdir()
        (work / ".claude" / "agents" / "reviewer.md").write_text("x")
        (root / "repo" / ".claude" / "agents").mkdir(parents=True)
        (root / "repo" / ".claude" / "agents" / "file.md").write_text("---\nname: up-agent\n---\n")
        defs = session_module.project_defs(work)
        self.assertEqual(defs.work_skills, frozenset({"deploy-it", "ship", "grp:nested"}))
        self.assertEqual(defs.work_agents, frozenset({"reviewer"}))
        self.assertIn("up-agent", defs.parent_agents)

    def test_settings_that_bring_another_credential_are_refused(self):
        with self.assertRaisesRegex(HarnessError, "env.ANTHROPIC_API_KEY"):
            self.session(settings={"env": {"ANTHROPIC_API_KEY": "sk-x"}})._admit(None)
        session = self.session(project_settings=True)
        (session.spec.work_dir / ".claude").mkdir()
        (session.spec.work_dir / ".claude" / "settings.json").write_text(json.dumps({"apiKeyHelper": "echo k"}))
        with self.assertRaisesRegex(HarnessError, "apiKeyHelper"):
            session._admit(None)

    def test_the_live_transcript_is_read_incrementally_leaving_a_record_mid_write(self):
        session = self.session()
        live = session.run_dir / "live.jsonl"
        live.write_text('{"n": 1}\n{"n": 2')
        session._live_path = live
        self.assertEqual(session.records(), [{"n": 1}])
        with live.open("a") as f:
            f.write('}\n{"n": 3}\n')
        self.assertEqual(session.records(), [{"n": 1}, {"n": 2}, {"n": 3}])

    def test_a_prompt_line_the_tui_wrapped_is_still_found_in_the_pane(self):
        tail = "the end of a long line that the input box wrapped"
        pane = "❯ start of the line and the end of a long line\n  that the input box wrapped\n──────\n"
        self.assertEqual(session_module.shown(pane, tail), 1)
        self.assertEqual(session_module.shown("❯ \n──────\n", tail), 0)

    def test_a_plugin_admitted_twice_is_a_spec_error(self):
        probe = plugins.DirPlugin(FIXTURES / "probe-plugin")
        session = self.session(plugins=(probe, probe))
        with mock.patch.object(session_module.home, "check_config_dir"), \
                mock.patch.object(session_module.claude, "resolve_binary"), mock.patch.object(session_module.claude, "auth"):
            with self.assertRaisesRegex(HarnessError, "admitted twice"):
                session._start()

    def test_subagents_are_launched_on_the_requested_model(self):
        env = session_module.launch_env(self.session().spec, Path("/e"))
        self.assertEqual((env["CLAUDE_CODE_SUBAGENT_MODEL"], env["EDITOR"]), ("claude-x", "/e"))

    def test_a_failed_capture_rides_along_on_the_failure_in_flight(self):
        session = self.session()
        session._launched = True
        failure = HarnessError("turn", "timed out")
        with mock.patch.object(session_module.tmux, "kill"), \
                mock.patch.object(session, "_await_exit", return_value=None), \
                mock.patch.object(session, "_capture_transcript", side_effect=HarnessError("transcript", "2 transcripts")):
            session.__exit__(HarnessError, failure, None)
        self.assertEqual(failure.__notes__, ["[transcript] 2 transcripts"])

    def test_prompts_the_tui_would_not_submit_verbatim_are_refused(self):
        for bad in ["", "  ", "text\n", " text", "/clear", "!ls", "# note", 3]:
            with self.assertRaises(HarnessError, msg=repr(bad)):
                session_module.check_prompt(bad)
        self.assertEqual(session_module.check_prompt("line one\nline two"), "line one\nline two")

    def test_a_claude_that_will_not_exit_is_killed_and_said_so(self):
        session = self.session()
        # Detached, as claude is: tmux, not the harness, is its parent and reaps it.
        session._pid = int(subprocess.run(["sh", "-c", "sleep 60 >/dev/null 2>&1 & echo $!"],
                                          capture_output=True, text=True, check=True).stdout)
        with mock.patch.object(session_module, "EXIT_TIMEOUT_SECS", 0.3):
            said = session._await_exit()
        self.assertIn("was killed", said)
        with self.assertRaises(ProcessLookupError):
            os.kill(session._pid, 0)


class Runs(unittest.TestCase):
    def test_a_run_id_tmux_would_rename_is_refused(self):
        with self.assertRaisesRegex(HarnessError, "run id"):
            run_module.run(None, ["p"], Path(tempfile.mkdtemp()), "v1.2")

    def test_an_interrupted_run_leaves_a_failure_and_keeps_propagating(self):
        run_dir = Path(tempfile.mkdtemp())
        with mock.patch.object(run_module, "Session") as session:
            session.return_value.turn.side_effect = KeyboardInterrupt()
            session.return_value.transcript_path = None
            with self.assertRaises(KeyboardInterrupt):
                run_module.run(None, ["p"], run_dir, "r1")
        self.assertEqual(json.loads((run_dir / "failure.json").read_text())["stage"], "interrupted")

    def test_prompts_must_be_a_list_of_strings(self):
        spec = Path(tempfile.mkdtemp()) / "spec.json"
        spec.write_text(json.dumps({"session": {}, "prompts": "hello"}))
        args = argparse.Namespace(spec=str(spec), run_id=None, out=str(spec.parent / "out"))
        with self.assertRaisesRegex(HarnessError, "list of strings"):
            cli.run_command(args)


class Records(unittest.TestCase):
    def test_subagent_transcripts_are_held_to_the_same_checks(self):
        run_dir = Path(tempfile.mkdtemp())
        main = run_dir / "transcript" / "s.jsonl"
        (run_dir / "transcript" / "s" / "subagents").mkdir(parents=True)
        main.write_text((FIXTURES / "two-turns.jsonl").read_text())
        sub = {"type": "assistant", "isSidechain": True,
               "message": {"id": "msg_sub", "model": "claude-other", "content": [], "usage": {"input_tokens": 1, "output_tokens": 1}}}
        (run_dir / "transcript" / "s" / "subagents" / "agent-1.jsonl").write_text(json.dumps(sub) + "\n")
        session = mock.Mock(transcript_path=main, run_dir=run_dir)
        session.spec.model = "claude-haiku-4-5-20251001"
        with self.assertRaisesRegex(HarnessError, "claude-other"):
            record.build(session)


    def test_a_clean_session_builds_a_record_that_conforms(self):
        run_dir = Path(tempfile.mkdtemp())
        main = run_dir / "transcript" / "s.jsonl"
        main.parent.mkdir()
        main.write_text((FIXTURES / "two-turns.jsonl").read_text())
        session = mock.Mock(transcript_path=main, run_dir=run_dir, run_id="r1", session_id=str(uuid.uuid4()),
                            started_at=datetime.now(timezone.utc), project_defs=transcript.ProjectDefs(),
                            admitted={"plugins": [], "append_system_prompt": None, "hook_events": [], "mcp_servers": [],
                                      "project_settings": False})
        session.spec.model, session.spec.claude_version, session.spec.work_dir = "claude-haiku-4-5-20251001", None, Path("/w")
        session.binary = claude.Binary(Path("/bin/claude"), "2.1.288")
        session.auth = claude.Auth("claude.ai", "firstParty")
        built = record.build(session)
        self.assertEqual(len(built["turns"]), 2)


class Schemas(unittest.TestCase):
    def test_failure_record_conforms(self):
        failure = record.failure("r1", HarnessError("boot", "never ready"), None)
        self.assertEqual(failure["stage"], "boot")

    def test_a_failure_carries_the_notes_added_to_it(self):
        error = HarnessError("turn", "claude exited mid-turn")
        error.add_note("[teardown] claude (pid 1) was killed")
        self.assertEqual(record.failure("r1", error, None)["error"], "claude exited mid-turn\n[teardown] claude (pid 1) was killed")


@unittest.skipUnless(subprocess.run(["which", "tmux"], capture_output=True).returncode == 0, "tmux not installed")
class TmuxTargets(unittest.TestCase):
    def test_targets_match_exactly_never_by_prefix(self):
        long_name = f"harness-test-{uuid.uuid4().hex[:8]}-long"
        short_name = long_name.removesuffix("-long")
        tmux.new_session(long_name, 80, 24, "/", ["sleep", "30"])
        try:
            self.assertTrue(tmux.alive(long_name))
            self.assertFalse(tmux.alive(short_name))
            tmux.kill(short_name)  # a missing session is already the goal
            self.assertTrue(tmux.alive(long_name))
        finally:
            tmux.kill(long_name)
        self.assertFalse(tmux.alive(long_name))

    def test_a_dead_pane_is_not_alive(self):
        name = f"harness-test-{uuid.uuid4().hex[:8]}"
        tmux.new_session(name, 80, 24, "/", ["true"])
        try:
            for _ in range(50):
                if not tmux.alive(name):
                    break
                __import__("time").sleep(0.1)
            self.assertFalse(tmux.alive(name))
        finally:
            tmux.kill(name)


if __name__ == "__main__":
    unittest.main()
