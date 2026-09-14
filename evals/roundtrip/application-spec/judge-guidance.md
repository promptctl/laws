# Verdict

## Fidelity (scored)

The source fixes these facts: the synopsis/usage text; `-u` selects UTC; `-f` consumes the next argument as FORMAT; `-f` with nothing after it prints the usage line and exits 2; any other argument starting with `-` in the option phase is an unknown option (stderr, exit 2); options stop at the first argument that does not start with `-`; anything other than exactly one operand prints the usage line and exits 2; `STAMP_FORMAT` overrides the default `%Y-%m-%dT%H:%M:%S` and `-f` overrides both; the file is read whole as UTF-8 and split into lines; an OS error on open or read prints `stamp: PATH: REASON` and exits 1; one timestamp (gmtime or localtime) is rendered through strftime; each line is printed as `prefix + " " + line`; the exit status is 0 on success.

I count behavior that follows from these calls on the runtime (the splitlines terminators, the BOM being kept, an undecodable file giving a traceback and exit 1) as behavior the source has, not as an addition. A claim hedged as `UNVERIFIED`/hypothesis is not counted as an asserted addition.

### Response A
- Missing: none. Every source fact is present, including empty-but-set `STAMP_FORMAT`, `-f` as the last argument, operand count, the OS-error line, the UTF-8 decode failure, and the single timestamp.
- Misstated: none.
- Added: none. The strftime directive table, the `%S` range and the example clock values are illustrations that agree with the given facts.

`missing: 0, misstated: 0, added: 0`

### Response B
- Missing: none.
- Misstated:
  - "There is no way to make `stamp` read standard input." (3.2) and "Standard input is never read." (5.3). Both contradict the response's own 5.1, "a readable special file such as a named pipe or `/dev/stdin`-style device node". Passing `/dev/stdin` as FILE does make the program read standard input.
- Added: none. The claims about write failure, signals, locale and encoding all carry `UNVERIFIED` with a hypothesis. The exit-status table's "a failure occurred while writing output (10.4)" points to that marked section.

`missing: 0, misstated: 1, added: 0`

### Response C
- Missing: none.
- Misstated: none. It gets standard input right: "does not read standard input (unless the named FILE happens to be a path to it, such as `/dev/stdin`)".
- Added: none. The Windows CR LF, `%f`, NUL-in-FORMAT, SIGINT/SIGPIPE and broken-pipe (1 or 120) claims are all marked `UNVERIFIED` or "expected".

`missing: 0, misstated: 0, added: 0`

## Rubric

The standard's rules for a finished response. Rules about process that leave nothing in the response are skipped: citing tokens while writing, and performing the two audit passes.

1. Include every outside-observable fact (the completeness direction of the boundary test).
2. Include no implementation internals: no algorithms, internal names, code, runtime or library mechanism, and no "how it works" narration.
3. Use the universal surface structure whatever the target's kind, and record each absent surface as absent together with how the absence was established.
4. Address all nine surfaces explicitly: invocation, configuration/environment with precedence, inputs accepted and rejected, outputs and streams, persistent state, external interactions, lifecycle, errors, observable guarantees.
5. State error behavior as API: exit codes, stream and shape of error output, malformed input, unreachable dependencies, and failure partway through.
6. State lifecycle as API: startup requirements and what happens when they are unmet, readiness, shutdown and signals, crash residue.
7. State external interactions at wire level, or record them as none.
8. Give timing and resource numbers only where contractual, and mark them as such.
9. Transcribe machine-read, boundary-crossing strings exactly: flags, env var names, exit codes, formats.
10. Describe human-facing text (error wording, usage/help prose) by function, never transcribed.
11. Never assert unobserved behavior as fact. Mark what could not be determined `UNVERIFIED` with what was tried and the hypothesis.
12. Write each sentence as condition → observable effect, sharp enough to become an acceptance test.
13. Stand alone, with no references into the source tree.
14. Open with an overview stating what the application is and where its boundary lies.
15. Include a provenance section: identity/version, available evidence channels, and observed versus derived.
16. Deliver as an `appspec/` directory. The task overrides this with "one Markdown file", so the rule is n/a.

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | met | not met | met |
| 3 | not met | met | not met |
| 4 | not met | met | met |
| 5 | not met | met | met |
| 6 | not met | met | met |
| 7 | not met | met | met |
| 8 | met | met | met |
| 9 | met | met | met |
| 10 | not met | met | met |
| 11 | not met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |
| 14 | not met | met | met |
| 15 | not met | met | met |
| 16 | n/a | n/a | n/a |

Counts: A: met 6, not met 9, n/a 1. B: met 14, not met 1, n/a 1. C: met 14, not met 1, n/a 1.

Failures:

- **A, rule 3.** The sections are "Purpose, Invocation, Configuration, Behavior, Errors, Examples", a CLI-shaped layout. Persistent state, external interactions and lifecycle get no section and are never recorded as absent. The only absence stated is "No configuration files are read."
- **A, rule 4.** There are no sections for persistent state, external-system interactions, lifecycle or observable guarantees. Its surface list ends at "## 5. Errors" and "## 6. Examples".
- **A, rule 5.** Partial failure is covered only on the input side: "Because the whole file is read before output starts, no input-related error ever leaves partial output on stdout." Nothing covers a failure while writing output, such as stdout closed early or an unencodable character.
- **A, rule 6.** There is no statement about startup requirements, readiness, signals or crash residue anywhere in the document.
- **A, rule 7.** It never records that there are no external-system interactions.
- **A, rule 10.** It transcribes human-facing wording: "The program writes `stamp: unknown option ARG` (ARG being the argument exactly as given) to stderr", "The usage line is exactly: `usage: stamp [-u] [-f FORMAT] FILE`", and "| FILE cannot be opened or read ... | `stamp: PATH: REASON` |".
- **A, rule 11.** Nothing is marked as derived or unverified, and source-derived host behavior is stated as fact, e.g. "On a UTF-8 locale, output is UTF-8." and "Directives beyond these, and the handling of unrecognized directives, follow the host platform's `strftime`."
- **A, rule 14.** The opening "## 1. Purpose" says what the program does but does not say where its boundary lies (inputs, outputs, what it does not touch).
- **A, rule 15.** There is no provenance section.
- **B, rule 2.** The appended audit record carries mechanism vocabulary into the deliverable: "Reworded \"reads the file into memory\" as the observable guarantee..." and "Reworded \"decodes with universal newlines\" as the explicit terminator table (5.2)", plus "Removed a mention of the language runtime's specific exception names".
- **C, rule 3.** Absent surfaces are recorded as absent without saying how the absence was established: "## 7. Persistent state — None. The program creates, modifies and deletes no files, and keeps no cache or state between runs." and "## 10. External-system interactions — None. The program makes no network requests and starts no subprocesses."

## Ranking

1. **C.** It has no fidelity errors, covers every surface, is honest about what is unverified, and keeps process notes and tags out of a spec the rebuild team must read cold. Its only miss is not saying how it established the absent surfaces.
2. **B.** It is as complete as C, with more test-ready tables. But it tells the rebuild team something false (that standard input can never be read, which `/dev/stdin` disproves). It also ends with an audit record and `[APPSPEC:...]` tags that are not specification and leak mechanism words.
3. **A.** It is accurate and concise, with no fidelity errors. But it transcribes the human-facing messages, has no provenance or unverified marking, and leaves lifecycle, persistent state, external interactions and write-side failure unstated, so the rebuild team has to guess at them.

## Totals

- A: missing 0, misstated 0, added 0 | rubric met 6, not met 9, n/a 1
- B: missing 0, misstated 1, added 0 | rubric met 14, not met 1, n/a 1
- C: missing 0, misstated 0, added 0 | rubric met 14, not met 1, n/a 1
