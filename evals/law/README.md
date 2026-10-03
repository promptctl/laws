# Per-law evals

Each case puts an agent at the one decision a law names, in one request, and reads
mechanically which way it went. Run under arms with and without the law, the cases say
whether the law's text moves the agent there. They do not score whether the task got
done (see `design-docs/no-single-session-evals.md`).

## Run

```sh
evals/law/run.py no-silent-failure            # arms none + skill:HEAD, 5 repeats each
evals/law/run.py no-silent-failure --arm none --arm skill:my-branch --repeats 3
evals/law/sensitivity.py <results-dir>        # re-read a results dir's records
```

Runs go through `harness/` (see `harness/README.md`), so they need what it needs: `uv`,
`tmux`, `git`, `claude` on PATH and its config dir logged in once with
`harness/bin/harness login`. Results go to `evals/law/results/<law>/<UTC time>/` unless
`--out` names a directory.

## Arms and isolation

- `none`: Claude Code's own system prompt, nothing else.
- `skill:<git-ref>`: `plugins/laws/skills/code/SKILL.md` as of that ref, appended to the
  system prompt with `--append-system-prompt-file`. The record keeps the resolved commit
  and the text's sha256.

Every run is one `harness/` session in a fresh copy of the fixture: the interactive TUI on
the subscription login, sent `request.md` as its one turn. The harness admits nothing but
the arm's guidance and refuses any run that loaded something else or was served by another
model than the one requested.

## A case

`cases/<law>/<scenario>/` holds:

- `fixture/`: the agent's working directory at the start.
- `request.md`: the one message the agent receives.
- `oracle.py <workdir>`: prints `{"verdict", "detail", ...}` for the agent's finished
  working directory. The verdict is `held`, `violated`, `off_fork` (the run never reached
  the decision, for instance because it did not do the job), or `inconclusive` (the
  oracle could not read the run).
- `references/<verdict>-<name>/`: files that overlay the fixture to make one known
  answer. `test_law_evals.py` requires the oracle to read each one as the verdict its
  name starts with, and to read the untouched fixture as `off_fork`.

A scenario must not be one the law's text uses as an example. Otherwise editing the text
teaches it to its own test.

The no-silent-failure cases use `differential.py`. It runs the agent's program once with
its dependency healthy and once with the dependency failing. If the two runs match on
exit code, stdout, stderr and files written, the failure was swallowed. A third, healthy
run checks that the program is deterministic. If it isn't, any difference is noise and
the verdict is `inconclusive`.

## Records

- `runs/<run>/`: the harness's run dir: `run.json` (`harness/schema/run-record.schema.json`:
  login, model served, Claude Code version, what loaded, tokens) or `failure.json`, and the
  session's transcript. The transcript is never committed: Claude Code writes the login's
  account email into it.
- `records/<run>.json`: one per run, conforming to `schema/run-record.schema.json`. It
  holds the case and a digest of the case and oracle code that judged it, the law, arm,
  skill ref and model, the oracle verdict, and paths to the harness record and the agent's
  diff.
- `summaries/<scenario>.json`: the case's sensitivity record, conforming to
  `schema/case-summary.schema.json`. It is derived from `records/` and `failed-runs.json`
  every time, never edited, and refuses records of one case judged by two versions of its
  code, or of one arm run on two guidance texts.
- `failed-runs.json`: present only when some runs ended without a record (a session the
  harness failed, an oracle crash). A summary counts them as runs that did not reach the
  decision.

A summary reads each arm against `none`, counting only the runs that reached the
decision:

| reading | when |
|---|---|
| `unmeasurable` | fewer than half of either arm's runs reached the decision |
| `separate` | the arm held more often than `none`, at p < 0.05 (two-sided Fisher exact on held/violated) |
| `regressed` | the arm violated more often than `none`, at p < 0.05 |
| `saturated` | no run of either arm violated: the law adds text and changes nothing here |
| `indistinguishable` | anything else |

A saturated reading is a finding about the law and gets reported as one. Don't tune a
case until the control fails.

## Tests

```sh
uv run --with jsonschema python -m unittest discover evals/law
```
