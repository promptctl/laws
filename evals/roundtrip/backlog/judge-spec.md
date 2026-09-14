# Verdict

## Fidelity (scored)

Given facts: one person, one machine; `add "text"` appends a timestamped entry to `~/.pocketlog/YYYY-MM-DD.md`; `today` prints today's entries; `search WORD` prints every entry from any day containing WORD, newest first; `#tag` tags, `tags` lists every tag with its count; no network ever; Rust, single binary; syncing maybe later, not in first release; first release = four commands work + test suite covers them.

Not counted as additions: a decision left open for the implementer ("decide and document"), test-isolation mechanics, documentation files, and reading "newest first" as applying within a day too.

### Response A
Missing: none. Misstated: none.
Added:
1. "Running with no subcommand or an unknown subcommand prints usage and exits non-zero."
2. "Missing text (no argument) prints usage and exits non-zero without writing anything."
3. "A missing WORD prints usage and exits non-zero."
4. "Prints today's entries, in the order they were added." (the founding document gives no order for `today`)
5. "Each printed entry should show enough to tell which day and time it came from."
6. Empty cases "exits successfully" (today, search, tags). The founding document gives no exit status.

`missing: 0, misstated: 0, added: 6`

### Response B
Missing: none. Misstated: none.
Added:
1. "No subcommand or an unknown one prints usage and exits non-zero."
2. "Missing WORD prints usage and exits non-zero."
3. "the entry text contains WORD as a case-sensitive substring" (a fixed matching rule)
4. "Print today's entries, with their timestamps, in file order."
5. "with enough of the date shown to tell days apart"
6. "Files with any other name are skipped." / "A non-day file placed in `~/.pocketlog` ... ignored by both commands."
7. "A missing store directory yields an empty list, not an error."
8. "Add a check ... it fails if the dependency tree gains a crate whose purpose is networking (an explicit deny list in the repository ...)" (a build-enforcement requirement the document does not give)

`missing: 0, misstated: 0, added: 8`

### Response C
Missing: none. Misstated: none. (The founding text is quoted accurately.)
Added:
1. "An unknown subcommand, or no subcommand, prints usage to stderr and exits non-zero." plus a `--help` flag
2. "Make both an error with a non-zero exit" (empty or missing text for `add`)
3. "Implement plain, case-sensitive containment of WORD as a substring"
4. "A tag is `#` immediately followed by one or more letters, digits, `_`, or `-` ... A bare `#` and `##` alone are not tags. Tags are case-sensitive as written."
5. "The count is the number of times the tag appears across all entries."
6. "Output is sorted by tag name"
7. "If `HOME` is unset, return an error the commands report."
8. "Decoding a file a person has hand-edited into something the format cannot read returns an error naming the file." / "A day file the decoder rejects is an error with a non-zero exit."
9. "**'Today' is the local calendar date** of the machine running the command."
10. "prints today's entries in the order they were written, each with its time"
11. "No directory or no file for today prints nothing and exits 0." (and the same for search and tags)
12. "Files and directories whose names are not day files are skipped."
13. "Each result shows its date and time"
14. "No WORD is a usage error with a non-zero exit."

(C also says "Nothing further is invented", while fixing many of these behaviors itself.)

`missing: 0, misstated: 0, added: 14`

## Rubric

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | met | met | met |
| 3 | not met | met | not met |
| 4 | met | met | met |
| 5 | n/a | n/a | n/a |
| 6 | met | met | met |
| 7 | not met | met | not met |
| 8 | not met | met | met |
| 9 | not met | met | met |
| 10 | not met | met | met |
| 11 | not met | met | met |
| 12 | not met | met | met |
| 13 | not met | met | met |
| 14 | met | met | met |
| 15 | n/a | n/a | n/a |
| 16 | n/a | n/a | n/a |
| 17 | n/a | n/a | n/a |
| 18 | n/a | n/a | n/a |
| 19 | met | met | met |
| 20 | not met | met | met |
| 21 | met | not met | met |
| 22 | not met | met | not met |
| 23 | met | not met | met |

Counts: A: 8 met, 10 not met, 5 n/a. B: 16 met, 2 not met, 5 n/a. C: 15 met, 3 not met, 5 n/a.

Failures:

- A, 3: the whole of ticket 3.1 checks whether something is already true: "Run the full test suite and confirm every one of the four commands is covered ... Confirm the tool works with no network access ... Confirm the release build produces a single self-contained binary."
- A, 7: no foundational ticket states a one-sentence purpose, and the storage ticket joins several with "and": "### 1.2 Storage layer: locate, write, and read day files".
- A, 8: no foundational ticket names a second consumer. The only nod is "has a tested storage layer the commands can call."
- A, 9/10/11/12/13: no epic has a checkpoint. Epics end on tests alone: "Done when: all four commands work, the test suite covers them and passes".
- A, 20: Epic 2 says what it contains, not why it exists: "Each command from the founding document, built on the Epic 1 storage layer and covered by integration tests".
- A, 22: A restates the founding document instead of pointing to it by path: "`pocketlog` is a command-line notebook for one person on one machine, written in Rust and shipped as a single binary." It also cites "the founding document" with no path anywhere.
- B, 21: E1-1 asks the agent to "Add the founding text of `pocketlog` verbatim as `docs/founding.md`", but the reader has "the repository and nothing else". The ticket does not include that text, so the agent cannot start the work.
- B, 23: a person who cloned the repository this morning meets "The full statement of the project is in `docs/founding.md` (issue E1-1 puts it there)". That file does not exist, and nothing in the repository says what should go in it.
- C, 3: "### E3-2: Verify the single, offline binary ... Confirm `cargo build --release` yields one self-contained `pocketlog` executable ... Audit the full dependency tree". E3-1 is also framed as a check: "Read the tests for all four commands against the four command bullets".
- C, 7: E1-3 joins two units into one ticket: "Two foundational units that everything else reads through. Build them as one ticket". Unit B's purpose also needs an "and": "encode entries into day-file text and decode day-file text back into entries".
- C, 22: C restates the founding document: "Its terms are quoted here once so every ticket below can point at them". It never points to the document by path.

## Ranking

1. B: for an agent pulling one ticket at a time, B is the strongest. Every epic has a person-watched, edge-case-heavy checkpoint, foundational tickets have clean purposes and named second consumers, and open decisions go to one recorded document. Its only real gaps are the unsourceable E1-1 ticket and a moderate number of fixed behaviors.
2. C: nearly as strong on checkpoints, consumers and self-contained tickets. But it invents the most behavior (tag grammar, count semantics, sort order, error rules), bundles two foundational units into one ticket, and ends with verification tickets.
3. A: A adds the least, but it has no checkpoints, no foundational purpose or consumer statements, and epics without a stated reason, so an agent gets no way to know when an epic is truly done.

## Totals

- A: missing 0, misstated 0, added 6; rubric 8 met, 10 not met, 5 n/a
- B: missing 0, misstated 0, added 8; rubric 16 met, 2 not met, 5 n/a
- C: missing 0, misstated 0, added 14; rubric 15 met, 3 not met, 5 n/a
