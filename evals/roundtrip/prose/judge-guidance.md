## Fidelity (scored)

Given facts checked in every response: what `sift` prints (every file, once each, first-file order); both install commands and the `sift` binary name; the `sift FILE...` usage with at least two files, and the one-file case (exit 2, the stderr message); `-i`/`--ignore-case` with first-file spelling; `-w`/`--trim` with the original untrimmed text; `-0`/`--null` for `xargs -0`; exit codes 0/1/2 including the unreadable-file case; the full-read memory gotcha with the 4 GB example and no streaming mode; the repository URL; MIT license.

**Response A**
- Missing: none.
- Misstated: none.
- Added: none. `sift [OPTIONS] FILE...` and the example `sift a.txt b.txt c.txt` are illustrations that fit the given facts.

`missing: 0, misstated: 0, added: 0`

**Response B**
- Missing: none.
- Misstated: none. "The output is the first file's original line, whitespace included" says the same thing as "original text, untrimmed". "The files have no lines in common" says the same thing as exit 1 "when there were none".
- Added: none. The `monday.txt`/`tuesday.txt` session is an illustration that fits the facts: the output `alice`, `carol` is correct and in first-file order.

`missing: 0, misstated: 0, added: 0`

**Response C**
- Missing: none.
- Misstated: none.
- Added: none. "The crate is named `sift-cli`" follows directly from `cargo install sift-cli`. `sift -0 a.txt b.txt | xargs -0 echo` is an illustration of the given `xargs -0` use.

`missing: 0, misstated: 0, added: 0`

## Rubric

Rules the standard asks of the finished response:

1. Lead with the point: the first sentence says what the thing is, with no warm-up.
2. Serve the named readers: the newcomer gets the value and a quick start early, and the returning user can reach their answer fast.
3. Layer the document under headings that front-load their keywords, so a skimmer can find their section.
4. Plain words and active sentences that name the actor.
5. Concrete beats abstract: specifics and numbers, not generic claims.
6. No fluent phrases that sound sophisticated but carry no checkable fact.
7. No throat-clearing, restatement, empty hedges, or intensifiers.
8. Use lists or tables only for parallel, discrete items, and keep the items grammatically parallel.
9. Paragraphs over fragments, one idea per paragraph.
10. No bold scattered mid-sentence for emphasis.
11. No symmetrical filler ("not only X but also Y").
12. No adjectives standing in for evidence.
13. Sentences end on the important or new thing (stress position), not on trailing filler.
14. Keep every load-bearing fact and trade no accuracy for tidiness.
15. No headers and sections where a few paragraphs would do.
16. Varied rhythm, not every sentence and paragraph the same shape.

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | met | met | met |
| 3 | met | met | met |
| 4 | met | met | met |
| 5 | met | met | met |
| 6 | met | met | met |
| 7 | met | met | met |
| 8 | met | met | met |
| 9 | met | met | met |
| 10 | met | met | met |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |
| 14 | met | met | met |
| 15 | met | met | met |
| 16 | met | met | met |

Counts: A met 16, not met 0, n/a 0. B met 16, not met 0, n/a 0. C met 16, not met 0, n/a 0.

Failures: none.

These differences did not cross into a failure:
- Rule 3: A's heading is just "Options". B and C use "Options: -i, -w, -0", which puts the flag a returning user is looking for in the heading.
- Rule 5: B is the only response that shows input and output, so a newcomer can see the result and the ordering. A and C show only the command.
- Rule 2: C puts the memory gotcha right after the opening example, where the thirty-second reader will see it. A and B put it near the bottom.

## Ranking

1. B: the input/output example lets the thirty-second reader see exactly what `sift` does, including the first-file ordering, and its options heading names `-w` for the returning user.
2. C: it puts the memory limit where the deciding reader will see it and names the flags in the heading, but its opening example shows no output.
3. A: it is accurate and clean, but it shows no output, puts the memory limit last, and its plain "Options" heading does the least for the reader looking for `-w`.

## Totals

- A: missing 0, misstated 0, added 0; rubric met 16, not met 0, n/a 0
- B: missing 0, misstated 0, added 0; rubric met 16, not met 0, n/a 0
- C: missing 0, misstated 0, added 0; rubric met 16, not met 0, n/a 0
