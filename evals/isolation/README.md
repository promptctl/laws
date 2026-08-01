# Isolated interactive Claude Code session (subscription Opus, no CLAUDE.md leak)

Launches a **real, live, interactive** Claude Code TUI - driven over tmux, never
`claude -p` / print mode / `--bare` / any API path - that runs on subscription **Opus**
while loading **none** of the machine owner's global guidance.

This is the isolation + verification only. The general multi-turn driver, task-spec format,
and scoring are separate later tickets.

## The model: a persistent config dir you log into once

Isolation is **structural**. The owner's global `~/.claude/CLAUDE.md`, `settings.json`, and
the laws-plugin router hooks live under the *default* `~/.claude` directory. Point
`CLAUDE_CONFIG_DIR` at a **different** directory and none of them are on the search path, so
none of them can load. That is a fact about the filesystem, not about the model's answers.

Auth is obtained the real way - you log in:

1. **One time:** `evals/isolation/setup-isolated-session.sh` launches a session against the
   persistent config dir (`~/.claude-laws-eval` by default). You attach, pick the
   subscription login, complete the OAuth in your browser, accept the trust dialog. The
   token then lives in your macOS keychain and the config dir keeps the account link.
2. **Every run after:** the token is reused for weeks. Nothing is copied from your global
   config; nothing is exported to disk.

## Run the verification

```sh
evals/isolation/verify-isolation.sh
```

Exits `0` only if every check passes:

| Check | How it's checked |
|-------|------------------|
| config dir is not `~/.claude`        | resolve both paths and compare - pointing at the global dir would load everything |
| no `CLAUDE.md` in the config dir      | `find` the dir - a dir with no guidance in it cannot serve guidance |
| loads no plugins/hooks                | read the config dir's `settings.json` - no `enabledPlugins`, no `hooks` (so the laws router can't fire) |
| (D) no silent fallback                | a nonexistent/unwritable `CLAUDE_CONFIG_DIR` makes the harness exit nonzero, never fall back to the global config |
| (A) live session is **Opus** on the subscription | launch the real session and **read the account banner** it paints (`<model> · Claude Max`) - the model it resolved to and the plan, taken from the left box column so a changelog naming another model can't fool it |

The first four are structural (read the config dir / the exit code). (A) launches the real
session - the model only resolves once it is running - but it is still read from state, not from
the model: we read the banner the TUI paints, never ask the model to name itself (models
misreport their identity). The banner also confirms the **Claude Max** subscription plan.

## Launch a session to poke at yourself

```sh
evals/isolation/launch-isolated-session.sh   # prints ISO_SESSION=...
tmux attach -t <ISO_SESSION>                 # Ctrl-b d to detach
```

Teardown: `tmux kill-session -t <ISO_SESSION>`. The config dir stays - it holds your login.

## Files

- `lib.sh` - isolation primitives: `iso_config_require`, `iso_launch`, `iso_capture`, the frame
  classifiers, `iso_teardown`. Single owner of the tmux session and launch lifecycle. No
  credential handling - auth comes from the one-time login in the keychain. Driving turns lives
  in `../driver`; isolation quizzes no model.
- `setup-isolated-session.sh` - one-time interactive login that provisions the config dir.
- `launch-isolated-session.sh` - steady-state launch (aborts if not set up), leaves it idle.
- `verify-isolation.sh` - the checks above, exit 0 iff all pass.

## Environment assumptions

macOS with `tmux`, `python3`, and a `claude` binary. The persistent config dir
(`~/.claude-laws-eval`) and working dir (`~/.claude-laws-eval-workdir`) live in `$HOME`, not
the repo. Knobs `ISO_CONFIG_DIR`, `ISO_WORK_DIR`, `ISO_LAUNCH_TIMEOUT_SECS`,
`ISO_POLL_SECS`, `ISO_HISTORY_LIMIT`, `ISO_PLAN_TOKEN` (the account-banner anchor, default
`Claude Max`), and the pane geometry are overridable via env.
