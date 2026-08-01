# The single scored run (task × configuration → one ground-truth outcome)

A **run** is the atomic unit the whole comparison is built from. It takes **one task** and **one
configuration**, binds them only at run time, and produces exactly one outcome record — or aborts
loudly with none:

1. resolve the arm's skill body from git (or none, for control);
2. clone the task's repo at its commit and establish the starting (defect) state;
3. launch an isolated **Opus** session in that checkout, with the skill body loaded via
   `--append-system-prompt` and permissions bypassed so the agent can work autonomously;
4. drive the agent through the task as **genuinely multi-turn** work (the task prompt plus
   follow-ups), so the loaded guidance is observed deep into the session, not right after it was
   read — a single-turn run is invalid;
5. score the produced state with the task's **own programmatic criterion** — never a judgment
   against the laws or any skill-derived rubric;
6. emit the outcome record **last**, only once a real verdict exists.

## Use it

```sh
evals/run/run.sh evals/tasks/go-template-add-fix evals/configs/code-ref-a /tmp/out
cat /tmp/out/outcome.json
```

The outcome record:

```json
{ "task": "...", "config": "...", "skill_ref": "8f6d15b", "verdict": "pass",
  "turns": 3, "artifact": ".../repo", "transcript": ".../transcript.txt" }
```

`skill_ref` is the arm's git ref (or `none` for control); `verdict` is the criterion's real
pass/fail against the produced repo; `turns` is how many exchanges the run drove; `artifact` is the
worked checkout and `transcript` the full turn-by-turn log.

## Verify it

```sh
evals/run/verify-run.sh
```

Exits 0 iff, against a **live Opus session**: one real run (`go-template-add-fix` × `code-ref-a`)
produces exactly one outcome record whose `skill_ref` equals the arm's git ref, whose `verdict` is
the criterion's real **pass** on this task+config known to pass, and whose transcript shows **more
than one turn**; and forcing a driven turn to fail (a 1-second turn bound) yields a **nonzero exit
and zero outcome records** — never a fabricated or partial one.

## Why it aborts rather than fudges

The whole comparison is a loop over this run; one bad datapoint becomes a confidently wrong
verdict. So a failed, empty, or partial driven turn, a dead session, or a criterion that could not
run **aborts nonzero and writes no record**. The record is written last, after a real verdict
exists, so a partial run can never leave one behind. The session is torn down on every exit path,
including aborts.

## The guidance is the only variable

Before launch the run strips any `CLAUDE.md` from the checkout, so the **only** guidance in the
session is the arm's skill body (loaded as a system prompt). The task repo's own project guidance
is not a confound, and the isolation (custom `CLAUDE_CONFIG_DIR`, no global `CLAUDE.md`, no router
hooks) from the isolation module holds — the arm is the sole thing that differs between runs.

## Files

- `lib.sh` — `run_scored` (the orchestration) and `run_emit_outcome`. Sources the driver, task,
  and config modules; adds no capability beyond binding them.
- `run.sh` — the CLI.
- `verify-run.sh` — the live done-claim proof.

## Environment

Everything the driver, task, and config modules need (`git`, `tmux`, a logged-in isolated config
dir, a task's own tools such as `pnpm`). Knobs: `RUN_TURN_TIMEOUT_SECS` (per-turn ceiling, default
900), plus the isolation/driver/task/config knobs.
