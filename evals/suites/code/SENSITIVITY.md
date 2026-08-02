# Sensitivity record — laws:code suite

The suite is only useful if it can discriminate: a cross-arm difference is trusted only when it
exceeds an arm's own run-to-run spread. This record is the honest measurement of that, on live
runs, and it is updated whenever the suite's tasks or the measured arms change materially.

## Campaign of 2026-08-01

- **Harness/tasks at:** laws repo `7445e41` + this branch's suite work (the four tasks below).
- **Arms:** `code-ref-a` = laws:code body @ `8f6d15b` (the current body — no later commit
  touches it) vs `control` = no skill body.
- **Repetitions:** N=2 per task × arm. 16 scored runs total, sequential, each a fresh isolated
  subscription-Opus session driven multi-turn (3 turns each), scored by the task's own criterion.
- **Completion:** 16/16 runs completed with real verdicts; zero aborted repetitions.

### The grid (k/N passed)

| Task | code-ref-a (8f6d15b) | control (none) |
|------|----------------------|----------------|
| go-template-add-fix          | 2/2 | 2/2 |
| go-template-multi-regression | 2/2 | 2/2 |
| go-template-stub-reimpl      | 2/2 | 2/2 |
| laws-scripts-parse           | 2/2 | 2/2 |

### Reading

**No task discriminates between the arms: every cell is at the pass-rate ceiling.** An Opus
agent completes all four tasks reliably with or without the laws:code body loaded, so at N=2
the suite detects no effect of the skill in either direction.

Read this as a finding about the **suite**, not as proof the skill has no effect: a criterion
every arm saturates has no headroom to register a difference, whatever the difference is. The
tasks are real and their criteria discriminate good-from-defect states mechanically
(`verify-tasks.sh`), but "make the gates pass" sits below the difficulty where guidance would
change the pass rate.

Raising N on these tasks would sharpen an estimate of a gap this grid gives no evidence exists;
the productive next move is **headroom, not repetitions**: tasks hard enough that unguided runs
sometimes fail the gates — larger work surfaces, criteria that mechanically catch qualities
beyond test-greenness (artifact assertions, post-hoc detectors on the produced diff), or repos
where shortcut work fails hidden coverage.

### Reproduce

```sh
evals/suites/run-suite.sh evals/suites/code <out-dir> 2 \
  evals/configs/code-ref-a evals/configs/control
```

The grid above is derived from the per-repetition `outcome.json` records the campaign left under
its out-dir; the suite runner prints the same grid from the same records.

## Campaign of 2026-08-01 — headroom follow-up (`go-template-heldout-conformance` only)

- **Harness/tasks at:** laws repo `6613a26` (the new task's post-smoke-fix state). The four
  prior tasks and both arms are unchanged since the campaign above, so its cells for them stand;
  this campaign measured only the new task.
- **Arms:** `code-ref-a` = laws:code body @ `8f6d15b` (still the current body) vs `control` =
  no skill body.
- **Repetitions:** N=4 per task × arm, `RUN_TURN_TIMEOUT_SECS=1500`. 8 scored runs, sequential,
  each a fresh isolated subscription-Opus session driven 3 turns.
- **Completion:** 8/8 runs completed with real verdicts; zero aborted repetitions.

### The grid (k/N passed)

| Task | code-ref-a (8f6d15b) | control (none) |
|------|----------------------|----------------|
| go-template-heldout-conformance | 1/4 | 2/4 |

### Reading

**The suite's first below-ceiling cells: both arms fail this task in some repetitions.** The
control arm at 2/4 gives a cross-arm gap room to exist, which is what this task was built for.
The measured 1/4-vs-2/4 difference is one pass at N=4 — far inside an arm's own run-to-run
spread — so this campaign shows **no trusted separation between the arms, in either direction**.

**Failure anatomy — read before trusting movement on this task.** All five failures, in both
arms, are the *same single assertion*: the restored `initials` unit test (`"foo bar baz"` →
`"FBB"`, the doc-pinned uppercase divergence from Go's case-preserving `goutils.Initials`).
Every failing run scored 1442/1443 — each one reimplemented the xstrings case-conversion state
machine, wrapping, and abbreviation to byte-perfection, including the entire held-out corpus.
Transcripts show why: with `go`, network, and the in-checkout `conformance/gen` generator, runs
rebuilt a byte-oracle for the target semantics and iterated against it — so the held-out
corpus's corners discriminated nothing, re-creating at the reference level the visible-gate
saturation the task was designed to break. The one surviving discriminator is the documented
TS-vs-Go divergence: runs that followed the prompt's declared authority (the stub doc comment)
passed; runs that inferred "the corpus is Go-generated, so Go semantics must win" overrode the
doc and failed.

So the honest characterization: this task has real headroom at the recorded N, but its
discriminating signal is currently **one interpretation bit** (declared-authority vs.
inferred-grader), not a gradient of corner-case engineering quality. Treat cross-arm movement
on this task accordingly until the follow-up lands: removing the in-checkout oracle (or pricing
oracle reconstruction above the turn budget), widening the gutted surface against that budget,
and eliminating doc-vs-reference conflict bits so what remains measurable is semantic fidelity.

### Reproduce

```sh
RUN_TURN_TIMEOUT_SECS=1500 evals/compare/compare-repeated.sh \
  evals/tasks/go-template-heldout-conformance <out-dir> 4 \
  evals/configs/code-ref-a evals/configs/control
```

The grid is derived from the per-repetition `outcome.json` records under the campaign's
out-dir; failure anatomy from re-running each failed artifact's restored suite and reading the
run transcripts.
