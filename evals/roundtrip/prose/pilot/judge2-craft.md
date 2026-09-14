# Verdict

## Fact fidelity (scored)

Task facts checked: what it prints (common lines, once each, first-file order); `brew install sift` on macOS; `cargo install sift-cli` anywhere Rust is installed; binary `sift` in both cases; usage `sift FILE...`; at least two files; one file gives exit 2 and `sift: need at least two files` on stderr; `-i`/`--ignore-case` with first file's spelling; `-w`/`--trim` with untrimmed original printed; `-0`/`--null` NUL separator for `xargs -0`; exit codes 0/1/2; read fully into memory; 4 GB file uses about 4 GB RAM; no streaming mode; repository URL; MIT.

### Response A

- Missing: none.
- Misstated:
  - "`-0`, `--null` | Ends each output line with NUL instead of a newline". The task says `-0` "separates output lines with NUL". "Ends each line" means a NUL terminator after the last line too, which is different behavior that the task does not give.
- Invented: none. The worked example (`a.txt` = apple/banana/cherry, `b.txt` = cherry/apple/date, output apple/cherry) follows directly from the stated behavior: common lines, printed once, in the first file's order.

`missing: 0, misstated: 1, invented: 0`

### Response B

- Missing: none.
- Misstated:
  - "`sift [OPTIONS] FILE...`". The task gives the usage line as `sift FILE...`.
- Invented:
  - "so `sift` is not suited to files larger than the RAM you can spare". This is a suitability judgment the task does not make.
  - "to delete every file listed in both `a.txt` and `b.txt`, even when names contain spaces: `sift -0 a.txt b.txt | xargs -0 rm`". The task names piping into `xargs -0` but gives no deletion use case and no claim about spaces.
  - "Because "no common lines" is exit code 1, a script can test the result directly: `if sift a.txt b.txt > common.txt; then ...`". This scripting use case is not given.
  - "Source and issues: https://github.com/example/sift". The task does not mention an issue tracker.
  - "reads every file fully into memory before comparing". The task does not say when the comparison happens.
- Not counted: "The crate is named `sift-cli`" follows from `cargo install sift-cli`. The `monday.log tuesday.log wednesday.log` example asserts only the stated behavior.

`missing: 0, misstated: 1, invented: 5`

### Response C

- Missing: none.
- Misstated:
  - "`sift [OPTIONS] FILE...`". The task gives the usage line as `sift FILE...`.
- Invented: none. `$ sift a.txt b.txt c.txt` and `sift -0 list1.txt list2.txt | xargs -0 ...` assert nothing beyond the given behavior.

`missing: 0, misstated: 1, invented: 0`

## Rubric

Rules the standard asks of the finished document:

1. The document is layered for its readers: value and quick-start where the newcomer lands, depth below.
2. Headings front-load their keywords, so a skimming reader can find their section.
3. Every load-bearing fact is kept; nothing the reader needs is cut for tidiness.
4. Detail that serves none of the document's goals is cut.
5. The document, and each section, opens with the point.
6. For a README: it says what the tool is and gets to the install command fast.
7. Plain words and active sentences, with the actor named.
8. Sentences put their weight at the end, not on trailing filler.
9. One idea per paragraph, and lists only for parallel, discrete items, with items grammatically parallel.
10. Concrete beats abstract: specifics and real examples, not gestures.
11. No fluent, sophisticated-sounding phrases that carry no checkable fact.
12. No throat-clearing, restatement of what was just said, empty hedges, or intensifiers.
13. No headers and sections where a few paragraphs would do.
14. No bold scattered mid-sentence for emphasis.
15. No symmetrical filler ("not only X but also Y").
16. Varied rhythm: paragraphs and sentences are not all the same length and shape.
17. No adjectives standing where evidence should be.

| # | A | B | C |
| --- | --- | --- | --- |
| 1 | met | met | met |
| 2 | met | met | met |
| 3 | met | met | met |
| 4 | met | not met | met |
| 5 | met | met | met |
| 6 | met | met | met |
| 7 | met | met | met |
| 8 | met | met | met |
| 9 | not met | not met | not met |
| 10 | met | met | not met |
| 11 | met | met | met |
| 12 | not met | not met | met |
| 13 | met | met | met |
| 14 | met | met | met |
| 15 | met | met | met |
| 16 | met | met | met |
| 17 | met | met | met |

Counts: A met 15, not met 2, n/a 0. B met 14, not met 3, n/a 0. C met 15, not met 2, n/a 0.

Failures:

- A, rule 9: the exit-code items are not parallel. Two are sentences and one is a fragment: "At least one common line was printed." / "The files have no lines in common." / "Usage error, or a file could not be read."
- A, rule 12: the opening paragraph restates the tagline right above it. "Print the lines that every file has in common." is followed by "`sift` reads two or more files and prints each line that appears in all of them."
- B, rule 4: this sentence repeats the exit-code table as a scripting tip that neither named reader needs: "Because "no common lines" is exit code 1, a script can test the result directly: `if sift a.txt b.txt > common.txt; then ...`."
- B, rule 9: the exit-code items are not parallel: "At least one common line was printed." / "The files have no line in common." / "Usage error, or a file could not be read."
- B, rule 12: this sentence restates the paragraph above the example: "That prints every line present in all three logs, in `monday.log`'s order."
- C, rule 9: the exit-code items are not parallel: "At least one common line was printed." / "No common lines." / "Usage error, or a file could not be read."
- C, rule 10: the examples show nothing concrete. "`$ sift a.txt b.txt c.txt`" is shown with no output, and "`sift -0 list1.txt list2.txt | xargs -0 ...`" ends in a placeholder instead of a real command.

## Ranking

1. **A**: Its worked example, with input files and output, lets the thirty-second reader see exactly what `sift` does, it invents nothing, and its only flaw is the "ends each output line" wording for `-0`.
2. **C**: It is equally faithful and just as easy for the `-w` reader to scan, but its output-less example and `xargs -0 ...` placeholder give the newcomer less to decide on.
3. **B**: It helpfully puts the memory limit up front, but it adds five claims and use cases the task does not give, including the `rm` pipeline and the scripting tip, and it pads the opening with a restatement.

## Totals

- A: missing 0, misstated 1, invented 0; rubric met 15, not met 2, n/a 0
- B: missing 0, misstated 1, invented 5; rubric met 14, not met 3, n/a 0
- C: missing 0, misstated 1, invented 0; rubric met 15, not met 2, n/a 0
