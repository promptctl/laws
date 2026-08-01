# Task specs (a real repo, a commit, the task text, and a machine-checked criterion)

A **task** is a self-contained, reusable spec: a real repository owned by the owner, the commit
to begin the work at, the text handed to the agent, and a programmatic success criterion a
machine evaluates against the real repo at the end. A task knows **nothing** about which skill
version or arm it runs under — that orthogonality is what lets the same task run honestly across
arms. If the task knew the arm, task and configuration would tangle and the comparison would be a
lie.

## The format

A task is a directory:

```
<task>/
  manifest.sh   # DATA ONLY: TASK_REPO, TASK_COMMIT, TASK_SUMMARY. No skill field, no arm field.
  prompt.md     # the task text handed to the agent
  check.sh      # THE CRITERION: runs with CWD = the checkout; exit 0 = success, nonzero = not
  setup.sh      # OPTIONAL: runs in the checkout to establish the STARTING state (e.g. the
                #   regression the agent must fix — where check.sh is expected to fail)
```

**The criterion is a command, not a menu choice.** `check.sh` exits 0 or nonzero, and that one
shape expresses every kind of ground truth — a test suite passing, a mechanical detector of a
defect class, an assertion on a produced artifact — so a new criterion *type* is a new `check.sh`,
never a change to the format. The criterion must be ground-truth / programmatic and must **not**
grade the output against any skill, law, or rubric derived from the guidance under test: success
is decided independent of the guidance's own vocabulary.

**Orthogonality is structural.** The manifest has no field for a skill or an arm, and no code that
consumes a task ever reads one — the arm is supplied entirely separately (the configuration
format). `manifest.sh` setting an arm-shaped variable is rejected by the validator as a smell that
the two concerns got confused.

## The two tasks here (deliberately different shapes)

| Task | Repo | Criterion type |
|------|------|----------------|
| `go-template-add-fix` | `promptctl/go-template-js` | the repo's **test suite** (`pnpm test`) |
| `laws-scripts-parse`  | `promptctl/laws`          | a **mechanical detector** (`bash -n` every eval script) |

Different repos *and* different criterion types — both validate against the same format with no
edit to the format, which is the proof that the format is not shaped around one task.

## Use it

```sh
evals/tasks/validate-task.sh evals/tasks/go-template-add-fix        # is it a well-formed spec?
evals/tasks/check-task.sh   evals/tasks/go-template-add-fix <dir>   # run its criterion vs a state
evals/tasks/verify-tasks.sh                                          # prove every task (below)
```

`verify-tasks.sh` is the done-claim proof. For **every** task directory it: validates the spec;
clones the pinned commit and runs the criterion against that clean state (must **PASS** — the
known-good reference); then clones again, runs `setup.sh` to establish the defect, and runs the
criterion against that state (must **FAIL**). Exit 0 iff every task validates and its criterion
discriminates good from defect. The loop is data-driven over whatever task dirs exist, so a new
task is proven by adding its directory — nothing here changes.

## Exit-code contract

Three distinct outcomes, so a consumer can never mistake "the harness could not run" for "the
work failed" — a fabricated verdict is the one thing this harness must not produce:

- `0` = criterion **passed**.
- `1` = criterion **failed** — a real verdict about the work.
- `2` (or any code `> 1`) = the criterion **could not run** (missing tool, absent tree, unresolvable
  commit) — a harness error, not a verdict.

This holds end to end: each `check.sh` exits `2` from its infra guards and `1` only on a genuine
failure; `task_check` translates those, aborting on `≥2` rather than reporting a FAIL; the machinery's
own `task_die` exits `2`; and `check-task.sh` surfaces `0`/`1`/`2` unchanged. `validate-task.sh`:
`0` = valid, `2` = the first violation, named on stderr.

## Files

- `lib.sh` — the format and machinery: `task_validate` (parse the spec into validated fields),
  `task_prepare` (clone + checkout the pinned commit), `task_setup` (establish the starting state),
  `task_check` (run the criterion, return its verdict).
- `validate-task.sh`, `check-task.sh` — the CLIs.
- `verify-tasks.sh` — the done-claim proof over every task.
- `<task>/` — one directory per task.

## Environment

`git` for all tasks; a task's `check.sh` may need its own tools (`go-template-add-fix` needs
`pnpm` + `node`). A criterion whose tools are missing exits `2` (a harness/infra error), never a
fabricated pass and never a fabricated FAIL.
