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
| (A) live session is **Opus**          | launch the real session and ask it - model + auth are the one thing only the running session can confirm |

The first four are structural (read the config dir / the exit code). Only (A) is behavioral,
because whether the live session actually came up as Opus on the subscription is the one
property you genuinely cannot read off a file.

## Launch a session to poke at yourself

```sh
evals/isolation/launch-isolated-session.sh   # prints ISO_SESSION=...
tmux attach -t <ISO_SESSION>                 # Ctrl-b d to detach
```

Teardown: `tmux kill-session -t <ISO_SESSION>`. The config dir stays - it holds your login.

## Files

- `lib.sh` - isolation primitives: `iso_config_require`, `iso_launch`, `iso_turn`,
  `iso_wait`/`iso_answer`, `iso_teardown`. Single owner of the tmux session and launch
  lifecycle. No credential handling - auth comes from the one-time login in the keychain.
- `setup-isolated-session.sh` - one-time interactive login that provisions the config dir.
- `launch-isolated-session.sh` - steady-state launch (aborts if not set up), leaves it idle.
- `verify-isolation.sh` - the checks above, exit 0 iff all pass.

## Environment assumptions

macOS with `tmux`, `python3`, and a `claude` binary. The persistent config dir
(`~/.claude-laws-eval`) and working dir (`~/.claude-laws-eval-workdir`) live in `$HOME`, not
the repo. Knobs `ISO_CONFIG_DIR`, `ISO_WORK_DIR`, `ISO_LAUNCH_TIMEOUT_SECS`,
`ISO_TURN_TIMEOUT_SECS`, `ISO_POLL_SECS`, and the pane geometry are overridable via env.
