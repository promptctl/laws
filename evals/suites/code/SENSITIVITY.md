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
