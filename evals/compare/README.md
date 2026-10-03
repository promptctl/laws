# The comparison (same task across arms → which did better)

One command runs the **identical task** under two or more configurations, collects the
ground-truth outcomes, and prints a per-arm table plus which arm did better **by the task's own
criterion**. This is the epic's payoff made runnable in one step — B vs A vs no-skill on the same
task, decided by ground truth, never by how well output matches the skill.

## Use it

```sh
evals/compare/compare.sh evals/tasks/go-template-add-fix /tmp/cmp \
  evals/configs/code-ref-a evals/configs/code-ref-b evals/configs/control
```

Prints, per arm, its skill ref (or `none`) and the criterion's verdict, then a which-arm line:

```
CONFIGURATION          SKILL_REF    VERDICT
---------------------- ------------ -------
code-ref-a             8f6d15b      pass
code-ref-b             58b573b      pass
control                none         pass

Better by the criterion: tie - these arms passed: code-ref-a (8f6d15b), code-ref-b (58b573b), control (none)
```

Each arm's full record and transcript are under `/tmp/cmp/<arm>/`.

## An aborted arm is FAILED, never fabricated

Every arm runs the same task; arms differ only in configuration. A run that **aborts** (broken
config, dead session, forced bad turn) is reported as `FAILED` in the table — never dropped and
never given a made-up score — and any FAILED arm makes the **overall exit nonzero**. A run that
completes with a real `fail` verdict is a valid outcome, not an abort. "Which did better" is
computed **only** from the criterion's verdicts (`pass` > `fail` > `FAILED`), never from any
comparison of output against the skill.

## Verify it

```sh
evals/compare/verify-compare.sh
```

Exits 0 iff, against a **live Opus session**: a three-arm comparison (a skill arm, the no-skill
control, and an arm forced to abort) prints one row per arm labelled by ref/`none`, the two
completing arms reproduce a real **pass**, a which-arm-did-better line is derived from the
verdicts, and the aborting arm shows as **FAILED** with a **nonzero overall exit** and no outcome
record left behind.

## Files

- `lib.sh` — `compare_task` (run each arm via `run_scored`, catch aborts, tabulate) and
  `cmp_report`. Sources the run module; adds no scoring of its own.
- `compare.sh` — the CLI.
- `verify-compare.sh` — the live done-claim proof.

## Environment

Everything a run needs (the isolated Opus session, `git`, the task's own tools). Runs execute
sequentially — each arm is a full scored run.
