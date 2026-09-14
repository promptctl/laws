# Verdict: pocketlog backlog seed

## Fidelity (scored)

Given facts: (1) a CLI notebook for one person on one machine; (2) `add "text"` appends a timestamped entry to `~/.pocketlog/YYYY-MM-DD.md`; (3) `today` prints today's entries; (4) `search WORD` prints every entry from any day containing WORD, newest first; (5) tags are written `#tag`, and `tags` lists every tag with its count; (6) no network access, ever; (7) Rust, single binary; (8) sync is "maybe later", has no known design, and is not in the first release; (9) the first release is done when all four commands work and a test suite covers them.

Counting convention, applied the same way to all three: a ticket that leaves a choice open ("decide and document") adds nothing. A ticket that commits to a specific behavior the document does not give is an addition. Ordinary implementation plumbing is not an addition: a crate, a test harness, directory creation on append, round-trip correctness, a README, a dependency audit.

### Response A
Missing: none. All nine facts appear, quoted verbatim in the preamble.
Misstated: none.
Added:
1. The `--help` flag, and every choice stated in it: "`pocketlog --help` lists the four commands", "state it in the command's `--help` text".
2. Behavior for no subcommand, an unknown subcommand, or a stub: "An unknown subcommand, or no subcommand, prints usage to stderr and exits non-zero."
3. "**\"Today\" is the local calendar date** of the machine running the command."
4. A date override in the binary: "Use an environment variable read in exactly one place (the function that answers \"what is today\")".
5. "If `HOME` is unset, return an error the commands report."
6. Empty text is an error: "Make both an error with a non-zero exit, since an entry with no text carries nothing."
7. Order for `today`: "prints today's entries in the order they were written".
8. Empty results exit 0: "No directory or no file for today prints nothing and exits 0" (the same for `search` and `tags`).
9. Undecodable files are errors: "returns an error naming the file. Do not silently skip it."
10. "Implement plain, case-sensitive containment of WORD as a substring of the entry text."
11. "Each result shows its date and time".
12. "No WORD is a usage error with a non-zero exit."
13. Non-day files are ignored: "Files and directories whose names are not day files are skipped."
14. Tag grammar: "A tag is `#` immediately followed by one or more letters, digits, `_`, or `-` ... Tags are case-sensitive as written."
15. "The count is the number of times the tag appears across all entries."
16. "Output is sorted by tag name".

`missing: 0, misstated: 0, added: 16`

### Response B
Missing: none.
Misstated: none.
Added:
1. "Running with no subcommand or an unknown subcommand prints usage and exits non-zero."
2. "Make the directory overridable for tests (for example, by an environment variable or a function parameter)".
3. "Missing text (no argument) prints usage and exits non-zero without writing anything."
4. Order for `today`: "Prints today's entries, in the order they were added."
5. Empty results succeed: "prints nothing or a short message (decide and document) and exits successfully" (for `today`, `search` and `tags`).
6. "A missing WORD prints usage and exits non-zero."
7. "Each printed entry should show enough to tell which day and time it came from."

B leaves case sensitivity, tag grammar, count semantics and output order open, so those are not counted.

`missing: 0, misstated: 0, added: 7`

### Response C
Missing: none. The facts appear across the preamble, E1-1's list, and the command tickets.
Misstated: none.
Added:
1. "No subcommand or an unknown one prints usage and exits non-zero."
2. "Make the home directory and the current time injectable".
3. A claim about the repository's state: "Start from an empty repository (apart from `docs/`)."
4. "that `#` in text is stored untouched (tags are extracted at read time, Epic E2)."
5. Order for `today`: "Print today's entries, with their timestamps, in file order."
6. "Implement the literal reading - the entry text contains WORD as a case-sensitive substring".
7. Search output shows the date: "with enough of the date shown to tell days apart".
8. "Missing WORD prints usage and exits non-zero."
9. Non-day files are ignored: "Files with any other name are skipped."
10. "A missing store directory yields an empty list, not an error."
11. Tag output order must be deterministic: "choose one that is deterministic (so tests can assert it)".

`missing: 0, misstated: 0, added: 11`

## Rubric

Rules the standard asks of a finished response:

1. Plan only work whose destination is known today. No speculative tickets and nothing past the edge of what is known (sync stays out).
2. No investigation tickets posing as build tickets.
3. Each foundational unit's purpose is one sentence with no "and". A ticket holding two units is cut.
4. Each foundational ticket names its second consumer.
5. Every epic carries a user-verifiable checkpoint, not just "tests pass".
6. Checkpoints are comprehensive: edge cases, empty input, boundaries.
7. Checkpoints are in vivo, run in the application itself.
8. Checkpoints come close enough together that the project is never far from one.
9. A demo, if present, is labelled, built to full quality, exercises more than the happy path, and says the project learns from it rather than building on it.
10. No dead references to the planning conversation ("as discussed", "per the plan").
11. Every epic states why it exists in terms of the project's goals.
12. Every ticket carries what a stranger needs to start.
13. The founding document is pointed at by path. It is not restated, and the text does not assume the reader has read it.

| Rule | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | met | met | met |
| 3 | not met | not met | not met |
| 4 | met | not met | met |
| 5 | met | not met | met |
| 6 | met | not met | met |
| 7 | met | not met | met |
| 8 | met | not met | met |
| 9 | n/a | n/a | n/a |
| 10 | met | met | met |
| 11 | met | not met | met |
| 12 | met | met | met |
| 13 | not met | not met | met |

Counts:
- A: met 10, not met 2, n/a 1
- B: met 4, not met 8, n/a 1
- C: met 11, not met 1, n/a 1

Failures:
- A, rule 3: one ticket holds two units, and one purpose has an "and". "Two foundational units that everything else reads through. Build them as one ticket" and "**Unit B. Purpose:** encode entries into day-file text and decode day-file text back into entries". E1-1 has no purpose sentence, and its title bundles three things: "Cargo project, single binary, and command dispatch".
- A, rule 13: A restates the founding document instead of pointing at it by path. "Its terms are quoted here once so every ticket below can point at them without a stranger having to find another file".
- B, rule 3: B has no one-sentence purposes, and the storage ticket bundles several units: "### 1.2 Storage layer: locate, write, and read day files".
- B, rule 4: no consumer is named for any foundational unit, only "a tested storage layer the commands can call."
- B, rules 5 to 8: no epic has a person-watched checkpoint. Epic 1 ends at "`cargo build` produces the binary, `cargo test` runs and passes". Epic 2 tickets end at "Done when: integration tests cover ...". Epic 3 ends at "the checks above are recorded in the issue's closing note."
- B, rule 11: Epic 2 describes what it contains, not why it exists. "Each command from the founding document, built on the Epic 1 storage layer and covered by integration tests".
- B, rule 13: B names no path for the founding document, yet assumes the reader has read it. "Where the founding document leaves a detail open" and "Each command from the founding document".
- C, rule 3: one ticket holds two units joined by "and". "### E1-4: Map a date to its day-file path and resolve \"today\"". Its purpose sentence names only the first unit.

## Ranking

1. **C.** It points at the founding document by path, names consumers, and gives every epic a comprehensive in vivo checkpoint. It is the only response that meets rule 13, with a moderate number of additions.
2. **A.** Its checkpoints and ticket detail are equally strong for a fresh agent. But it restates the founding document, bundles two units in one ticket, and commits to the most unsupported behaviors (16).
3. **B.** It has the fewest additions. But no epic has a person-watched checkpoint and no foundational unit names a consumer. It also refers to a founding document the pulling agent cannot locate.

## Totals

- A: fidelity missing 0, misstated 0, added 16; rubric met 10, not met 2, n/a 1
- B: fidelity missing 0, misstated 0, added 7; rubric met 4, not met 8, n/a 1
- C: fidelity missing 0, misstated 0, added 11; rubric met 11, not met 1, n/a 1
