# Repeated comparison (the harness's own noise floor)

An Opus agent driven through a multi-turn task is **stochastic**: a one-shot A-beats-B read is as
likely to be noise as signal. So the comparison can run each task+arm pair **more than once** and
report each arm's outcome as a **distribution** — a pass rate over N repetitions — not a single
verdict. A reader trusts a cross-arm difference only when it exceeds an arm's own run-to-run
spread.

## Use it

```sh
evals/compare/compare-repeated.sh evals/tasks/go-template-add-fix /tmp/rep 3 \
  evals/configs/code-ref-a evals/configs/code-ref-b evals/configs/control
```

Per arm it prints every repetition's outcome and a `k of N passed` summary, then a pass-rate table:

```
ARM                    SKILL_REF    PASS RATE (k/N)
---------------------- ------------ ---------------
code-ref-a             8f6d15b      3/3
code-ref-b             58b573b      2/3
control                none         3/3

Read a cross-arm difference as real only if it exceeds an arm's own run-to-run spread over these 3 repetitions.
```

Each repetition's full record is under `/tmp/rep/<arm>/rep-NN/`.

## An aborted repetition is a failure, never a fabricated pass

Every repetition holds all the prior constraints (Opus, subscription-only via tmux, isolated, real
multi-turn work, ground-truth scoring). An aborted repetition is counted as a **FAILED run** in the
distribution — it never counts as a pass or a fabricated score — and any aborted repetition makes
the **overall exit nonzero**. Repetition is a run-count, not a new task or arm dimension: the
task/arm orthogonality is unchanged.

## Verify it

```sh
evals/compare/verify-repeated.sh
```

Exits 0 iff, against a **live Opus session**: a two-arm repeated comparison (a skill arm and an arm
whose runs are forced to abort, N=2 each) reports every repetition's outcome and a k/N summary; the
skill arm's two runs form a visible same-arm spread (2/2); and the aborting arm's repetitions are
counted as failures (0/2, aborted surfaced), never inflating the pass rate, with a nonzero overall
exit and no outcome records left behind.

## Note on N

The pass rate over a handful of repetitions is a **floor for seeing jitter**, not a significance
test — it lets the owner notice that an observed A-vs-B gap is (or isn't) larger than a single
arm's own variation. Larger N sharpens the picture at linear cost (each repetition is a full scored
run).

## Files

- `lib.sh` — `compare_repeated` (runs each arm N times via `run_scored`, tabulates the
  distribution), alongside the single-shot `compare_task`.
- `compare-repeated.sh` — the CLI.
- `verify-repeated.sh` — the live done-claim proof.
