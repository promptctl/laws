# Per-law evals

Each case puts an agent at the one decision a law names, in one request, and reads
mechanically which way it went. Run under arms with and without the law, the cases say
whether the law's text moves the agent there. They do not score whether the task got
done (see `design-docs/no-single-session-evals.md`).

## Run

```sh
evals/law/run.py no-silent-failure            # the four default arms, 5 repeats each
evals/law/run.py no-silent-failure --arm none --arm skill:my-branch --repeats 3
evals/law/run.py no-silent-failure --split tuning   # leave the hold-out cases unread
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
- either one suffixed `+diluted`: the session first gets the fixed turns in `dilution/`
  (three stdlib modules pasted with a question about each), then the
  request. Measured on one run each, the context at the request grows from 31k tokens to
  92k, so the skill (28k) falls from about half of it to under a quarter, nearer its share
  in real use. The
  record keeps the turns' sha256.

The default arms are `none`, `skill:HEAD`, `none+diluted` and `skill:HEAD+diluted`. An arm
is read against the `none` arm in its own context, so a diluted arm needs `none+diluted`
in the same invocation, and `run.py` refuses one without it.

Every run is one `harness/` session in a fresh copy of the fixture: the interactive TUI on
the subscription login, sent `request.md` as its one turn. The harness admits nothing but
the arm's guidance and refuses any run that loaded something else or was served by another
model than the one requested.

## A case

`cases/<law>/<scenario>/` holds:

- `case.json` (`schema/case.schema.json`): its `kind` and `split`.
  - `fork`: the request puts the agent at the law's decision.
  - `over-firing`: the law does not apply. Held means the agent added no ceremony the
    request did not need, so a `regressed` reading is guidance that fires where it should not.
  - `tuning` or `holdout`: a hold-out case is kept out of the skill-edit loop. Edit
    against `--split tuning` and run the hold-out cases only to check that an edit
    generalizes. A loop that reads them teaches the text to them too.
- `fixture/`: the agent's working directory at the start.
- `request.md`: the one message the agent receives.
- `oracle.py <workdir>`: prints `{"verdict", "detail", ...}` for the agent's finished
  working directory. The verdict is `held`, `violated`, `off_fork` (the run never reached
  the decision, for instance because it did not do the job), or `inconclusive` (the
  oracle could not read the run).
- `references/<verdict>-<name>/`: files that overlay the fixture to make one known
  answer. `test_law_evals.py` requires the oracle to read each one as the verdict its
  name starts with, and to read the untouched fixture as `off_fork`.

Every law's case set has at least one over-firing case and one hold-out case.

A scenario must not be one the law's text uses as an example. Otherwise editing the text
teaches it to its own test.

Oracles share three helpers. Each is part of the digest of every case it could judge:

- `differential.py` (no-silent-failure): did a failure leave a trace?
- `calltrace.py` (parse-dont-validate): what type did each of the program's own
  functions receive? The program runs under a profiler on good input. A function inland
  of the boundary that still receives the raw `dict` or `str` was handed unchecked data.
- `identifiers.py` (domain-language): which names did the agent coin, and from which
  vocabulary? Each case holds the domain's or the project's term for the thing the
  request describes, and the plain words the request uses instead.

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
  holds the case, its kind and split, a digest of the case and oracle code that judged
  it, the law, arm, skill ref, context and model, the oracle verdict, and paths to the
  harness record and the agent's diff.
- `summaries/<scenario>.json`: the case's sensitivity record, conforming to
  `schema/case-summary.schema.json`. It is derived from `records/` and `failed-runs.json`
  every time, never edited, and refuses records of one case judged by two versions of its
  code, or of one arm run on two guidance texts.
- `failed-runs.json`: present only when some runs ended without a record (a session the
  harness failed, an oracle crash). A summary counts them as runs that did not reach the
  decision.

The three schemas are frozen as of promptctl-law-evals-qdn.3yt. A change to any of them
is its own ticket.

A summary reads each arm against the `none` arm in its context, counting only the runs
that reached the decision:

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
