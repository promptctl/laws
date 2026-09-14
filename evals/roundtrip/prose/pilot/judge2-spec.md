# Verdict: sift README responses

## Fact fidelity (scored)

### Response A

Every task fact is present and stated correctly.

Invented:
- `sift [OPTIONS] FILE...`: the task gives the usage as `sift FILE...`. Adding `[OPTIONS]` before the file list claims an argument order that the task does not give.

The examples `sift a.txt b.txt c.txt` and `sift -0 list1.txt list2.txt | xargs -0 ...` claim nothing beyond the task's facts, so they are not counted.

`missing: 0, misstated: 0, invented: 1`

### Response B

Every task fact is present and stated correctly.

Invented:
- `sift [OPTIONS] FILE...`: same argument-order claim as in A.
- "so `sift` is not suited to files larger than the RAM you can spare": a suitability judgment the task does not make. The task gives only the 4 GB = about 4 GB figure.
- "to delete every file listed in both `a.txt` and `b.txt`, even when names contain spaces: `sift -0 a.txt b.txt | xargs -0 rm`": the task names no such use case and says nothing about names containing spaces.
- "Because 'no common lines' is exit code 1, a script can test the result directly: `if sift a.txt b.txt > common.txt; then ...`": a scripting use case the task does not give.
- "reads every file fully into memory before comparing": the task does not say when comparison happens relative to reading.
- "Source and issues: https://github.com/example/sift": the task does not say issues are tracked at that repository.

`missing: 0, misstated: 0, invented: 6`

### Response C

Misstated:
- "`-0`, `--null` | Ends each output line with NUL instead of a newline": the task says `-0` "separates output lines with NUL". Ending each line with NUL means a NUL after the last line too. A separator does not imply that, so C changes the output format.

Every other task fact is present and correct. The worked example (`a.txt` = apple/banana/cherry, `b.txt` = cherry/apple/date, output apple/cherry) matches the stated behavior: common lines, printed once, in first-file order. It is not an invention.

`missing: 0, misstated: 1, invented: 0`

## Rubric

| # | A | B | C |
| --- | --- | --- | --- |
| 1 | n/a | n/a | n/a |
| 2 | n/a | n/a | n/a |
| 3 | met | met | met |
| 4 | met | met | met |
| 5 | met | met | met |
| 6 | not met | not met | met |
| 7 | met | met | met |
| 8 | n/a | n/a | n/a |
| 9 | n/a | n/a | n/a |
| 10 | n/a | n/a | n/a |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |
| 14 | met | met | met |
| 15 | met | met | met |
| 16 | met | met | met |
| 17 | met | met | met |
| 18 | met | met | met |
| 19 | met | not met | not met |
| 20 | met | met | met |
| 21 | met | met | met |
| 22 | met | met | met |
| 23 | met | met | met |
| 24 | n/a | n/a | n/a |
| 25 | n/a | n/a | n/a |
| 26 | n/a | n/a | n/a |
| **Counts** | met 17, not met 1, n/a 8 | met 16, not met 2, n/a 8 | met 17, not met 1, n/a 8 |

Failures:
- A, #6: the example block `$ sift a.txt b.txt c.txt` shows no output, so it tells the newcomer nothing that Usage does not already say. `sift -0 list1.txt list2.txt | xargs -0 ...` ends in a literal `...` placeholder, so it adds no fact beyond the table row above it. Both are elements that carry nothing load-bearing.
- B, #6: the memory limit appears twice. It is at the top ("Files are read fully into memory, so `sift` is not suited to files larger than the RAM you can spare. See [Memory use](#memory-use).") and again in its own section ("`sift` reads every file fully into memory before comparing, and there is no streaming mode.").
- B, #19: the "Memory use" section repeats a point the reader already met in the opening: "Files are read fully into memory" followed later by "`sift` reads every file fully into memory before comparing".
- C, #19: the next sentence restates the tagline "Print the lines that every file has in common." immediately: "`sift` reads two or more files and prints each line that appears in all of them."

## Ranking

1. C: its worked example with real output lets the thirty-second reader see exactly what `sift` does, and its option table answers the `-w` question in one row. Its only fidelity slip is calling NUL a line terminator rather than a separator.
2. A: it is accurate and easy to scan for both readers, with a single small invention (`[OPTIONS]`). Its examples show no output, so the newcomer gets less than C gives.
3. B: it helps the newcomer by putting the memory limit up front, but it invents six claims and use cases the task forbids. Its `: ` definition-list syntax also does not render as a list on GitHub, which makes the `-w` lookup harder than a table.

## Totals

- A: missing 0, misstated 0, invented 1; rubric met 17, not met 1, n/a 8
- B: missing 0, misstated 0, invented 6; rubric met 16, not met 2, n/a 8
- C: missing 0, misstated 1, invented 0; rubric met 17, not met 1, n/a 8
