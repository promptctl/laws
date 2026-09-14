# Verdict

## Fidelity (scored)

Given facts checked: what `sift` does (lines in every file, once each, first-file order); both install commands; the binary is `sift` either way; `sift FILE...`, at least two files; the one-file error (exit 2, `sift: need at least two files` to stderr); `-i`/`--ignore-case` with first-file spelling; `-w`/`--trim` with the untrimmed first-file text; `-0`/`--null` for `xargs -0`; exit codes 0/1/2 including unreadable file; read fully into memory, 4 GB log ~ 4 GB RAM, no streaming mode; repository URL; MIT license.

### Response A
- Missing: none. Every fact above is present.
- Misstated: none.
- Added: none. `sift [OPTIONS] FILE...` and the example `sift a.txt b.txt c.txt` illustrate the given usage and flags and assert nothing new.

`missing: 0, misstated: 0, added: 0`

### Response B
- Missing: none.
- Misstated: none. "The output is the first file's original line, whitespace included" matches "untrimmed". "The files have no lines in common" matches exit 1.
- Added: none. The `monday.txt`/`tuesday.txt` example is an illustration: it prints `alice` and `carol` in first-file order, which agrees with the given behavior.

`missing: 0, misstated: 0, added: 0`

### Response C
- Missing: none.
- Misstated: none. "with its whitespace intact" matches "untrimmed".
- Added: none counted. "The crate is named `sift-cli`" follows from the given `cargo install sift-cli` command and does not assert a new behavior. `sift -0 a.txt b.txt | xargs -0 echo` illustrates the given `xargs -0` use.

`missing: 0, misstated: 0, added: 0`

## Rubric

| # | A | B | C |
|---|---|---|---|
| 1 | n/a | n/a | n/a |
| 2 | met | met | met |
| 3 | met | met | met |
| 4 | met | met | met |
| 5 | met | met | met |
| 6 | met | met | met |
| 7 | met | met | not met |
| 8 | met | met | met |
| 9 | n/a | n/a | n/a |
| 10 | n/a | n/a | n/a |
| 11 | met | met | met |
| 12 | n/a | n/a | n/a |
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
| 25 | met | met | met |
| 26 | met | met | met |
| 27 | met | met | met |
| 28 | met | met | met |
| 29 | n/a | n/a | n/a |
| 30 | n/a | n/a | n/a |
| 31 | n/a | n/a | n/a |

Counts:
- A: met 24, not met 0, n/a 7
- B: met 24, not met 0, n/a 7
- C: met 23, not met 1, n/a 7

Failures:
- C, requirement 7: the options use definition-list syntax, which GitHub-flavored Markdown does not render. The colons will show up literally on the repository page the task names: "`-w`, `--trim`\n: Ignore leading and trailing whitespace when comparing lines." A table or plain list would carry the same facts with a simpler element that renders.

Notes on close calls, not failures:
- A, requirement 6: the heading "## Options" is a reasonable keyword for reader 2, but B's and C's "## Options: -i, -w, -0" put the exact flag that reader is scanning for into the heading.
- A, requirement 3: the example `sift a.txt b.txt c.txt` shows no output. Reader 1 has to work out what "in the order they first appear in the first file" looks like. B's example shows it.

## Ranking

1. **B** - its worked example lets the thirty-second reader see exactly what the tool outputs and in what order, and its "Options: -i, -w, -0" heading takes the returning user straight to `-w`, with no fidelity errors.
2. **C** - it puts the memory limit right under the description, where a reader deciding whether the tool fits will see it, and it also has the flag-keyword heading, but its definition-list markup will render badly on GitHub.
3. **A** - it is accurate and clean, but its example has no output and its generic "Options" heading makes both readers do slightly more work than B or C.

## Totals

- A: missing 0, misstated 0, added 0; rubric met 24, not met 0, n/a 7
- B: missing 0, misstated 0, added 0; rubric met 24, not met 0, n/a 7
- C: missing 0, misstated 0, added 0; rubric met 23, not met 1, n/a 7
