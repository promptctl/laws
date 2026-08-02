# Suites (a named set of tasks, runnable across arms in one command)

A **suite** is the per-skill eval made concrete: a named set of task specs that one command runs
across two or more arms with repeats, ending in a task × arm pass-rate grid. A suite is **data**
— a manifest naming task directories under `evals/tasks` — and it inherits its tasks'
orthogonality: it knows nothing about which skill version or arm it runs under, and its manifest
has no field to say so.

## The format

A suite is a directory:

```
<suite>/manifest.sh   # DATA ONLY: SUITE_SUMMARY (one line), SUITE_TASKS (whitespace-separated
                      #   names of task dirs under evals/tasks). No skill field, no arm field.
```

Members are task **names**, not paths — a suite cannot reach outside the task set, and every
member is a validated task spec before any consumer sees it. Everything about a task (repo,
commit, criterion) lives in the task spec it names; the suite stores only the set.

## The suite here

`code/` — the **laws:code** suite: coding tasks scored by the target repos' own gates (tests,
typecheck, lint) and mechanical detectors. Its sensitivity record — which tasks separate a
skill arm from control, measured on live runs — lives in `code/SENSITIVITY.md`.

## Use it

```sh
evals/suites/run-suite.sh evals/suites/code /tmp/suite-out 2 \
  evals/configs/code-ref-a evals/configs/control
```

Runs every task in the suite through the repeated comparison (`compare-repeated`) across the
given arms, printing each task's per-arm distribution as it goes, then the suite grid:

```
TASK                            code-ref-a         control
------------------------------- ------------------ ------------------
go-template-add-fix             2/2                2/2
go-template-heldout-conformance 1/4                2/4
go-template-multi-regression    2/2                2/2
go-template-stub-reimpl         2/2                2/2
laws-scripts-parse              2/2                2/2
```

(These are the real cells from the 2026-08-01 campaigns — the four saturated tasks at N=2, the
held-out task at N=4 from its own follow-up campaign; see `code/SENSITIVITY.md` for the reading,
including why movement on the held-out task's cells must be read with care. An aborted cell
would additionally carry a `(n!)` marker.)

Every repetition holds all the harness constraints (subscription Opus, interactive tmux-driven
session, real multi-turn work, isolation, ground-truth scoring). The grid is **derived from the
per-repetition outcome records on disk** — never a second tally.

## An aborted repetition fails the suite run, never fabricates

A repetition that aborts is counted in its cell (marked `!`), the remaining tasks still run —
one broken task must not discard the others' datapoints — and the overall exit is nonzero. A
completed run with a real `fail` verdict is a valid outcome, not an abort.

## Verify it

```sh
evals/suites/verify-suites.sh
```

Static (no LLM runs): every suite here validates and resolves to ≥1 valid task, and the failure
arms — a missing member, an empty task list, a duplicate member, a smuggled arm field — each
abort nonzero. Exit 0 iff all hold.

## Exit-code contract

`run-suite.sh`: `0` = every repetition of every task completed with a real verdict; `1` = at
least one repetition aborted (cells marked `!`); `2` = the suite spec itself is malformed.
`verify-suites.sh`: `0` = all checks hold, `1` = at least one failed.

## Files

- `lib.sh` — the format and `suite_validate` (parse the manifest into validated task dirs).
- `run-suite.sh` — the CLI: suite × arms × reps → per-task tables + the suite grid.
- `verify-suites.sh` — the static proof.
- `<suite>/` — one directory per suite.

## Environment

Everything a scored run needs (the isolated Opus session, `git`, `tmux`, each task's own tools).
Runs execute sequentially; a suite run is `tasks × arms × reps` full scored runs — budget
accordingly.
