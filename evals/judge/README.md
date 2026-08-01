# The optional, reference-anchored judge tier

Some real qualities resist a pure mechanical check. For those, a run **may** attach a **secondary**
judge that scores the produced artifact against a supplied **reference / ground truth**. But a
judge is worthless — and was the previous harness's fatal flaw — unless it is anchored to ground
truth rather than to the treatment, and calibrated against humans before anyone believes it. So:

- the **primary** verdict is always the programmatic / ground-truth criterion; the judge never
  decides the comparison on its own;
- the judge scores against a **reference**, never against the laws, a law's diagnostic, or any
  rubric derived from the skill under test — it is structurally handed only the artifact and the
  reference, never the skill;
- the judge's verdicts are **not trusted** until they are shown to agree with **human labels** on a
  held set. Until then they are tagged `unvalidated` and excluded from the decision.

## The judge format

```
<judge>/judge.sh    # scorer: judge.sh <artifact_dir> <reference_path>; exit 0 = judge-pass,
                    #   1 = judge-fail, 2 = could-not-run. Handed ONLY artifact + reference.
<judge>/reference   # the ground truth the artifact is scored against
<judge>/labels.tsv  # OPTIONAL held validation set: rows of <case_artifact_dir>\t<pass|fail>,
                    #   a human's label per artifact — used only to calibrate, never seen at scoring
```

## Use it

```sh
evals/judge/score-judge.sh    evals/judges/output-matches-reference <artifact_dir>   # pass|fail
evals/judge/validate-judge.sh evals/judges/output-matches-reference                  # agreement vs humans
```

`validate-judge.sh` scores every held case, compares to its human label, and prints the agreement
rate; it exits 0 only if agreement meets `JUDGE_AGREEMENT_BAR` (default 80%). A judge below the bar
stays `unvalidated` and may not contribute to a verdict.

The sample judge is **deliberately fallible**: on `cases/case-4` it passes an artifact a human
labelled `fail`, which drops its agreement to 4/5 = 80% — exactly the kind of blind spot the
human-agreement gate exists to expose.

## Verify it

```sh
evals/judge/verify-judge.sh
```

Mechanical (no live session — the tier is about structure). Exits 0 iff: the judge scores an
artifact against the reference; without human labels its verdict is `unvalidated` and does not
decide (the programmatic verdict does); with labels the agreement rate is reported and gated by the
bar (validates at 80%, not at 90%); a validated judge is still secondary; and the scorer is blind
to the skill.

## Files

- `lib.sh` — `judge_score` (artifact vs reference), `judge_validate` (agreement vs human labels
  against the bar), `judge_report` (primary programmatic verdict + tagged secondary judge verdict).
- `score-judge.sh`, `validate-judge.sh` — the CLIs.
- `verify-judge.sh` — the done-claim proof.
- `../judges/output-matches-reference/` — a sample judge with a reference and a labelled held set.
