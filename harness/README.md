# harness

Runs live, interactive Claude Code sessions for evals: on the owner's subscription login,
isolated from the owner's own Claude setup, driven for one or more turns, and leaving a
transcript plus a schema-conforming run record. It imports nothing from any eval; this
directory can be moved out of the repo whole.

`claude -p --bare` is banned (owner, 2026-10-03), and so is API-key auth. Every session is
the interactive TUI on the subscription login.

## Use

```sh
harness/bin/harness login     # once, by a person with a browser
harness/bin/harness status    # the binary, the login and the config dir a run would use
harness/bin/harness verify    # prove all of this against two live sessions
harness/bin/harness run spec.json --out DIR [--run-id ID]
```

Needs `uv`, `tmux`, `git` and `claude` on PATH. A spec:

```json
{
  "session": {
    "work_dir": "/abs/path/the/agent/works/in",
    "model": "claude-opus-5-5",
    "plugins": [{"repo": "/path/or/url", "ref": "HEAD", "subdir": "plugins/laws"}, {"dir": "/abs/plugin"}],
    "append_system_prompt": "/abs/guidance.md",
    "claude_version": "2.1.288",
    "settings": {},
    "mcp_config": null,
    "project_settings": false
  },
  "prompts": ["first turn", "second turn"]
}
```

Only `work_dir` and `model` are required. `project_settings` lets the work dir's own
`CLAUDE.md`, `.claude/settings.json`, skills and agents load; off, any of them that loads
fails the run. A parent directory's are never admitted. What is admitted is read once at
launch, because the session can rewrite its own work dir. Settings that bring another
credential or provider (`apiKeyHelper`, `env.ANTHROPIC_API_KEY`, ...) are refused. A prompt
is sent exactly as written, so one with surrounding whitespace or a leading `/`, `!` or `#`
is refused. A run whose arguments are accepted leaves `DIR/run.json`
(`schema/run-record.schema.json`) or `DIR/failure.json` (`schema/failure.schema.json`),
never both and never neither, plus `DIR/transcript/<session>.jsonl`; arguments that are not
accepted raise before anything is written. From Python, an eval
calls `harness.run.run(Spec(...), prompts, run_dir, run_id)`.

Tests: `uv run --with jsonschema python -m unittest discover -s harness/tests`.

## Where each concern came from

The sources were the single-session harness restored from `cf5a570^` (`evals/isolation`,
`evals/driver`, `evals/run`), `horizon/` and `evals/law` on PR #86.

| concern | choice | source |
|---|---|---|
| login and auth | one persistent config dir at a fixed path, logged in once with `claude auth login --claudeai`; every run checks `claude auth status --json` and refuses anything but the subscription login | horizon `login.sh` (fixed path, login command); the status probe is new because horizon's probe used `claude -p` |
| keeping the API out | the session's environment is built from an allowlist under `env -i`, so no `ANTHROPIC_API_KEY` or token reaches it | evals/law `PASSED_ENV` |
| config-dir isolation | a dedicated config dir that holds no CLAUDE.md, skills, plugins or hooks, checked before every run, plus `--setting-sources ''` and `--strict-mcp-config` | evals/isolation (structural isolation, the config-dir checks) |
| proving isolation | read from the session's own transcript records (`instructions`, `hook_*`, `skill_listing`, `agent_listing_delta`, MCP deltas), checked against what the caller admitted; `verify` runs a positive control for each kind of load so an empty reading cannot pass by accident. A hook that prints nothing leaves no transcript record; the config-dir check and `--setting-sources` keep those out | evals/law (read what the session reports loading, never ask the model); the transcript records replace the `-p` init message, which an interactive session does not print |
| plugin admission and pinning | each admitted plugin is snapshotted (`git archive` of the whole tree at one commit, or a copy of a directory pinned by its digest) and loaded with `--plugin-dir`; nothing is installed into the config dir. A plugin's hooks are admitted from `hooks/hooks.json` and the manifest's `hooks`; its MCP servers do not load under `--strict-mcp-config` | horizon (`git archive` snapshot of the whole tree, admitted set is exactly what the caller lists) |
| claude version pinning | `claude` resolved once through the installer's symlink, launched by that resolved path, an optional exact pin, and every transcript record's `version` checked against it; `DISABLE_AUTOUPDATER=1` | horizon (`horizon_claude_path`, version pin, autoupdater off) |
| model verification | the caller names a full model id; subagents are launched on it too (`CLAUDE_CODE_SUBAGENT_MODEL`), and every assistant message in the transcript and its subagents' transcripts must carry exactly that model, and a session that showed an API error in place of a reply fails as `api` | evals/law (refuse a run whose session reports another model), read from the API responses rather than the init message |
| driving turns | tmux, the pane process launched with no shell; each prompt is typed through the TUI's external-editor key (`$EDITOR` is a harness script), confirmed by the transcript recording it byte for byte, and the turn is done when the transcript records `turn_duration` | evals/driver (tmux, confirm the send, never return a partial turn); the editor route is new because a large bracketed paste reaches the model wrapped in `<pasted_content>` tags |
| boot gates | the pane classified by a pure function, banner first, the login notice read only from the status row; onboarding written once at login; the trust dialog answered "yes" only once the cursor is seen on it (in bypass mode its default is "No, exit") | horizon `horizon_boot_state`; trust handling from evals/isolation |
| transcript capture | the session's transcript (and its subagent directory) moved out of the config dir into the run dir when the session ends, on every exit path | horizon `horizon_capture_transcripts` |
| run record and schema | one record per run, built from the transcript and launch inputs and validated against the schema before it is written | evals/law (record, schema, validation before write) |
| failure reporting | every failure is a `HarnessError` naming its stage; a run that fails writes `failure.json`, and a defect in the harness itself is recorded the same way | evals/law `failed-runs.json`; horizon (die with what the pane showed) |
| concurrency and locking | runs hold a shared `flock` and login holds it exclusive, so runs go in parallel and a login never rotates the credential under one; each run's tmux session has a unique name that tmux refuses to reuse | horizon (tmux name as the atomic claim, login under the run lock) |

Defects found in the restored sources and not carried over: tmux targets that prefix-match
(every target here is `=name` or `=name:`); a launch failure that leaked its tmux session
(the session is ended on every exit path); idle and reply detection read off the screen
(both come from the transcript); a paste check that cut a multibyte character (the
transcript compares the whole prompt).
