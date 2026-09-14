# Verdict

## Fidelity (scored)

Given material: the job (rename `max_retries` to `retry_limit` across `/srv/repos/ingest`), five verbatim user requirements, two facts (where the key appears; the rejected fallback `cfg.get("retry_limit", cfg.get("max_retries"))`), and the reader. The task forbids adding requirements, constraints, or facts.

### Response A

Missing: none. All five requirements are quoted verbatim, and both facts are present.

Misstated: none.

Added:
- "A test or config lookup will fail at some point". This states as certain a future failure the task does not give. (The rest of that paragraph, that a fallback is not the fix and the user rejected it, is given.)

Not counted: "Get the list from `grep -rln max_retries deploy/`" and the `git diff --name-only master...rename-retry-limit` check are illustrations of how to verify given requirements. "a new local branch" and "In your final message" are consistent with "Commit it on a branch" and "List every one".

`missing: 0, misstated: 0, added: 1`

### Response B

Missing: none. All five requirements are quoted verbatim, and both facts are present.

Misstated: none. "the user rejected the work because of it" reads a cause into "The user rejected it". The user's own requirement ("I don't want a compatibility shim that reads both") supports that cause, so it is not counted.

Added:
- "one path per line". This is an output-format constraint the task does not give.
- "The result of `make test`." This is a reporting requirement the task does not give.
- "The branch name and commit hash." This is a reporting requirement the task does not give.

Not counted: "a nested `get`, a try/except that falls back to the old name, an `or` between the two keys, a helper or alias that accepts either name" illustrates the given no-shim requirement.

`missing: 0, misstated: 0, added: 3`

### Response C

Missing: none. Every requirement and fact is carried, though only the first requirement is in the user's words (see Rubric 9).

Misstated: none.

Added:
- "Re-read this before every commit". This is a process instruction the task does not give.
- "If the only fix would mean editing `deploy/` or `vendor/`, stop and report it." This is a new stop-and-report behavior the task does not give.
- "The `make test` result." This is a reporting requirement the task does not give.
- "The commit hash on `rename-retry-limit`." This is a reporting requirement the task does not give.

Not counted: "no second lookup, no `or` fallback, no alias, no deprecation path that still reads `max_retries`" illustrates the given no-shim requirement. "Fix the read or the test data outside `deploy/` and `vendor/`" is consistent with the given scope.

`missing: 0, misstated: 0, added: 4`

## Rubric

The reader runs several turns without re-injection (editing, testing, committing), so the text has a run hold. Requirements 21 and 30-36 (the whole-session hold) are n/a. So are the requirements about the writer's process or about revising existing guidance, because nothing in a finished prompt can show them.

| # | A | B | C |
|---|---|---|---|
| 1 | met | not met | met |
| 2 | n/a | n/a | n/a |
| 3 | n/a | n/a | n/a |
| 4 | met | met | met |
| 5 | met | not met | not met |
| 6 | n/a | n/a | n/a |
| 7 | met | met | met |
| 8 | met | met | met |
| 9 | met | met | not met |
| 10 | met | not met | not met |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | met | met | met |
| 14 | n/a | n/a | n/a |
| 15 | met | met | met |
| 16 | met | not met | not met |
| 17 | met | not met | not met |
| 18 | met | met | met |
| 19 | met | not met | met |
| 20 | met | not met | met |
| 21 | n/a | n/a | n/a |
| 22 | met | met | met |
| 23 | met | not met | met |
| 24 | n/a | n/a | n/a |
| 25 | met | not met | met |
| 26 | n/a | n/a | n/a |
| 27 | n/a | n/a | n/a |
| 28 | met | not met | met |
| 29 | met | met | met |
| 30 | n/a | n/a | n/a |
| 31 | n/a | n/a | n/a |
| 32 | n/a | n/a | n/a |
| 33 | n/a | n/a | n/a |
| 34 | n/a | n/a | n/a |
| 35 | n/a | n/a | n/a |
| 36 | n/a | n/a | n/a |
| 37 | n/a | n/a | n/a |
| 38 | n/a | n/a | n/a |
| 39 | n/a | n/a | n/a |

Counts:
- A: met 21, not met 0, n/a 18
- B: met 11, not met 10, n/a 18
- C: met 16, not met 5, n/a 18

### Failures

Response B:
- 1: B gives the run-hold boundaries the one-turn treatment. The exclusions appear only mid-text, at "3. Do not edit anything under `deploy/`." and "4. Do not modify anything under `vendor/`.", and nothing restates them at the close.
- 5: "4. Do not modify anything under `vendor/`." and "5. Run `make test`. It must pass." restate the quotes directly above ("Don't touch `vendor/`.", "Tests have to pass: `make test`.") without covering any new situation.
- 10: "`git diff` shows no changes under `deploy/` or `vendor/`." After the required commit, plain `git diff` is empty no matter what was committed, so this check cannot detect a forbidden edit.
- 16: The body fails requirement 10 (above), and the unrefreshed lines get none of the treatment in 17-20.
- 17: The stop condition includes "`git diff` shows no changes under `deploy/` or `vendor/`.", which is not a mechanical yes/no on the committed work.
- 19: No passage names the late temptation. The closest is "Anything like that is a failure: a nested `get`...", which lists forms but not the moment or the thought.
- 20: The key exclusions ("2. No fallback.", "3. Do not edit anything under `deploy/`.") sit in the middle of the numbered list, and the close is a reporting list.
- 23: The text is a long run against a visible situation, but it gets no 16-20 treatment (see 17, 19 and 20).
- 25: Every instruction has the same weight. "Run `make test`. It must pass." has the same emphasis as "Do not edit anything under `deploy/`."
- 28: "Where the key lives: it is read in Python under `src/`, and it appears in YAML under `config/` and `deploy/`." follows "across the repository" before any exclusion. That sets up a frame of renaming in `deploy/` too, and the ban on editing `deploy/` arrives later.

Response C:
- 5: "4. Leave `deploy/` and `vendor/` exactly as they are." repeats the opening "Out of bounds" block and the closing "Reminder" for the same situation.
- 9: Only one requirement is quoted. The others are paraphrased, for example "The ops team owns those config files." and "Do not touch anything under `vendor/`." in place of the user's words. "List every one that uses the old key so I can send it to ops" becomes "The user wants to send this list to ops."
- 10: "`git diff` shows no changes under `deploy/` or `vendor/`." is empty after the commit whatever was committed. "finds nothing that reads the key" needs a judgment call, not a yes/no check.
- 16: The body fails requirements 9 and 10, and it adds a register device outside the unrefreshed lines ("Re-read this before every commit").
- 17: "A search for `max_retries` outside `deploy/` and `vendor/` finds nothing that reads the key." and the `git diff` line cannot be checked mechanically for a yes or no.

## Ranking

1. **A**: Its opening boundaries, quoted fallback plus forbidden-form list, named temptation, and exact commands (`git diff --name-only master...rename-retry-limit`, `make test` exits 0) give the subagent a checkable stop and the fewest additions.
2. **C**: It places the exclusions at the opening and close and names the late temptation well, but it paraphrases four of the five requirements, its `git diff` check is broken, and it adds a stop-and-report behavior and extra report items.
3. **B**: It quotes every requirement faithfully, but it reads as a one-turn spec for a multi-turn run: no temptation, exclusions buried mid-list, a `git diff` check that cannot catch a committed edit, and extra report items.

## Totals

- A: missing 0, misstated 0, added 1; rubric met 21, not met 0, n/a 18
- B: missing 0, misstated 0, added 3; rubric met 11, not met 10, n/a 18
- C: missing 0, misstated 0, added 4; rubric met 16, not met 5, n/a 18
