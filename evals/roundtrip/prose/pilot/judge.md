## Fact check

**Response A**

- Missing: none. Every fact in the task appears.
- Invented or beyond the task:
  - "The crate is named `sift-cli`": the task gives only the install command, not the crate name.
  - "`sift [OPTIONS] FILE...`": the task's usage line is `sift FILE...`.
  - "so `sift` is not suited to files larger than the RAM you can spare": a conclusion drawn from the memory fact, not stated in the task.
  - "`sift -0 a.txt b.txt | xargs -0 rm`" with "even when names contain spaces": the use case and the claim about spaces are not in the task.
  - "`if sift a.txt b.txt > common.txt; then ...`": the scripting pattern is not in the task (it follows from the exit codes).
  - "reads every file fully into memory before comparing": "before comparing" is not in the task.
  - "Source and issues": the task does not mention an issue tracker.

**Response B**

- Missing: none. Every fact in the task appears.
- Invented or beyond the task:
  - The worked example files and output (`apple`, `banana`, `cherry`, `date`). It is illustrative and matches the stated behavior.
  - "Ends each output line with NUL instead of a newline": the task says `-0` "separates output lines with NUL". A terminator and a separator are different behaviors, so this misstates the fact.

**Response C**

- Missing: none. Every fact in the task appears.
- Invented or beyond the task:
  - "`sift [OPTIONS] FILE...`": the task's usage line is `sift FILE...`.
  - "`sift -0 list1.txt list2.txt | xargs -0 ...`": the example is not in the task, and its `...` is a placeholder.

## Requirements

| # | A | B | C |
| --- | --- | --- | --- |
| 1 | met | met | met |
| 2 | met | met | met |
| 3 | met | met | met |
| 4 | met | met | met |
| 5 | met | met | not met |
| 6 | met | not met | met |
| 7 | met | met | not met |
| 8 | met | met | met |
| 9 | met | met | met |
| 10 | n/a | n/a | n/a |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |
| 14 | met | met | met |
| 15 | met | met | met |
| 16 | met | met | met |
| 17 | met | met | met |
| 18 | met | met | met |
| 19 | met | met | met |
| 20 | met | met | met |
| 21 | met | met | met |
| 22 | met | met | met |
| 23 | met | met | met |
| 24 | met | met | met |
| 25 | n/a | n/a | n/a |
| 26 | met | met | met |

Requirements 10 and 25 are marked n/a because they govern how the writer works (when to apply rules 11-19, and drafting several versions). They leave nothing on the page to judge. Page-level defects that 24 and 26 would catch are counted under 5, 6 and 7 instead, so they are not scored twice.

- B, requirement 6 (never trade accuracy for tidiness): "`-0`, `--null` | Ends each output line with NUL instead of a newline". The fact is that `-0` *separates* lines. The shorter wording changes the behavior a user piping into `xargs -0` would expect.
- C, requirement 5 (picture the named reader stuck): "```console\n$ sift a.txt b.txt c.txt\n```". The example shows a command with no output and no sentence saying what it prints, so the 30-second reader never sees a result.
- C, requirement 7 (cut what is irrelevant to the point at hand): "Example with `-0`:\n\n```sh\nsift -0 list1.txt list2.txt | xargs -0 ...\n```". The example repeats the table row, and its `...` placeholder adds nothing concrete.

## Ranking

1. **A**: its opening example says what it prints and it flags the memory limit before Install, where the 30-second reader decides. `-w` sits under a clear Options heading for the returning user. It also carries the most invented extras of the three (see Fact check).
2. **B**: the worked example with real output is the best 30-second demonstration, and the options table makes `-w` easy to find. But it misstates `-0`, and the memory gotcha sits at the bottom.
3. **C**: it is accurate and easy to scan, but its opening example shows no output and its `-0` example is a placeholder.

Requirement 6 separates first from second: B's "Ends each output line with NUL" misstates the fact, and A has no equivalent error.

## Totals

A: 24 met, 0 not met. B: 23 met, 1 not met. C: 22 met, 2 not met.
