# Verdict

## Fidelity (scored)

### Response A
- Missing: none found. Every behavior of the source is there: the option grammar, `-f` consuming the next argument, the unknown-option and usage errors (exit 2), the file-open error (exit 1), the uncaught decode failure, `STAMP_FORMAT` including the empty-value case, the built-in default, UTC vs local time, the timestamp sampled once after reading, the line-splitting terminators, the `PREFIX + " " + L + "\n"` format, empty-file behavior, and the absence of state, network and file writes.
- Misstated: none found.
- Added: none. Platform-dependent claims such as "`UNVERIFIED`: the exit status may be 1 or 120" and "`UNVERIFIED`: on Windows the terminator is expected to be CR LF" are marked as hypotheses and fit the source's runtime behavior. They do not assert new behavior.

`missing: 0, misstated: 0, added: 0`

### Response B
- Missing: B never says the program writes no files and keeps no state between runs. Only "No configuration files are read." is stated.
- Missing: B never says the program makes no network requests or other outbound interactions.
- Missing: B does not cover a failure while writing stdout (stdout closed early, or a character that cannot be encoded), which can leave partial output and exit 1. B covers only input errors: "Because the whole file is read before output starts, no input-related error ever leaves partial output on stdout."
- Misstated: none found.
- Added: none. The directive table and the worked examples are illustrations that fit the given facts.

`missing: 3, misstated: 0, added: 0`

### Response C
- Missing: none found.
- Misstated: C says standard input can never be read: "There is no way to make `stamp` read standard input." (3.2), "Standard input is never read." (5.3), and "It does not read standard input" (1). The source opens any path, so `/dev/stdin` reads standard input. C's own 5.1 admits "a readable special file such as a named pipe or `/dev/stdin`-style device node".
- Added: none. Hypotheses are marked `UNVERIFIED`, and the audit record describes the writing process, not program behavior.

`missing: 0, misstated: 1, added: 0`

## Rubric

| # | A | B | C |
|---|---|---|---|
| 1 | not met | met | not met |
| 2 | met | not met | met |
| 3 | not met | met | not met |
| 4 | n/a | n/a | n/a |
| 5 | not met | met | not met |
| 6 | met | not met | met |
| 7 | met | not met | met |
| 8 | met | n/a | met |
| 9 | not met | not met | met |
| 10 | not met | not met | met |
| 11 | met | not met | met |
| 12 | not met | met | met |
| 13 | met | not met | met |
| 14 | met | not met | met |
| 15 | met | not met | met |
| 16 | met | not met | met |
| 17 | met | not met | met |
| 18 | met | not met | met |
| 19 | met | not met | met |
| 20 | n/a | n/a | n/a |
| 21 | met | met | met |
| 22 | met | met | met |
| 23 | met | not met | met |
| 24 | n/a | n/a | n/a |
| 25 | not met | not met | met |
| 26 | met | met | met |
| 27 | n/a | n/a | n/a |
| 28 | met | not met | met |
| 29 | met | not met | met |
| 30 | met | met | met |
| 31 | met | met | met |
| 32 | not met | not met | met |
| 33 | n/a | n/a | met |
| 34 | n/a | n/a | not met |
| 35 | not met | not met | met |

Counts: A: 20 met, 9 not met, 6 n/a. B: 9 met, 19 not met, 7 n/a. C: 27 met, 4 not met, 4 n/a.

### Failures

**A**
- 1, 3: A states an internal mechanism instead of an observable effect: "**Signals:** the program installs no signal handling of its own."
- 5: A hedges in ways that are neither sharp nor a single stated hypothesis: "behavior for invalid or incomplete conversions ... depends on the host. It may copy the text through, drop it, or fail." It also says "the exit status may be 1 or 120, and the stderr text varies."
- 9: A records absent surfaces without saying how absence was verified: "## 7. Persistent state / None. The program creates, modifies and deletes no files..." and "## 10. External-system interactions / None."
- 10: A's surfaces are out of order: "## 8. Error behavior", "## 9. Lifecycle", "## 10. External-system interactions". The required order is external interactions, then lifecycle, then error behavior.
- 12: A records a resource behavior that it admits is not contractual: "Memory use grows with file size, because the whole file is read before any output. This is not a contractual requirement."
- 25: A's `UNVERIFIED` items never say what was tried, for example "`UNVERIFIED`: not observed." A also asserts source-derived runtime behavior as fact, for example "If the content is not valid UTF-8, the program writes a multi-line diagnostic to stderr".
- 32, 35: A has no record of either audit pass and cites no `[APPSPEC:...]` tokens anywhere.

**B**
- 2: B omits the absence of persistent state and outbound interactions, and omits stdout write failures (see Fidelity).
- 6, 7, 10, 11: B uses a CLI man-page layout instead of the nine surfaces: "## 1. Purpose", "## 2. Invocation", "## 3. Configuration", "## 4. Behavior", "## 5. Errors", "## 6. Examples".
- 9: Absent surfaces are never recorded. Persistent state, external interactions and lifecycle do not appear.
- 13: B covers partial failure for input errors only: "no input-related error ever leaves partial output on stdout". Failure while writing output is not specified.
- 14-18: B has no lifecycle section. Start requirements, readiness, signals, shutdown and crash residue are not addressed.
- 19: B never states outbound interactions, not even their absence.
- 23: B transcribes human-readable text: "The usage line is exactly: `usage: stamp [-u] [-f FORMAT] FILE`". It also transcribes "`stamp: unknown option ARG`" and "e.g. `No such file or directory`, `Permission denied`, `Is a directory`".
- 25: B asserts unobserved runtime behavior with no `UNVERIFIED` marking: "On a UTF-8 locale, output is UTF-8."
- 28, 29: B opens with "## 1. Purpose" and has no provenance section.
- 32, 35: B has no audit passes and no tokens.

**C**
- 1, 3: C makes a false claim that an observer could refute: "There is no way to make `stamp` read standard input." C also states internal mechanism: "the program installs no signal handlers. Signals get the runtime's default handling."
- 5: C hedges inside a hypothesis: "on common Linux and macOS systems the sequence is emitted more or less literally".
- 34: C's purity reread left failing sentences in place, including "the program installs no signal handlers" and "Standard input is never read."

## Ranking

1. **C**: C sweeps all nine surfaces in order, records how absence was established, and carries provenance and an audit record. Its one misstatement, about standard input, contradicts its own 5.1 and costs the rebuilding team little.
2. **A**: A is the most exact spec, with no fidelity errors and thorough edge cases. It loses ground on surface order, absence verification, audit passes and tokens.
3. **B**: B is accurate and easy to read, but it is a man-page layout with no provenance and no lifecycle. It omits the state, network and output-failure behavior, and it transcribes human-readable messages.

## Totals

- A: missing 0, misstated 0, added 0; rubric 20 met, 9 not met, 6 n/a
- B: missing 3, misstated 0, added 0; rubric 9 met, 19 not met, 7 n/a
- C: missing 0, misstated 1, added 0; rubric 27 met, 4 not met, 4 n/a
