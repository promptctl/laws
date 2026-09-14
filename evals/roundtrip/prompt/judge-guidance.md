## Fidelity (scored)

Given items checked: the job (rename `max_retries` to `retry_limit` across `/srv/repos/ingest`); the five verbatim requirements (no reads of the old key and no shim; don't edit `deploy/` and list every file there that uses the old key; don't touch `vendor/`; `make test` passes; commit on `rename-retry-limit`, don't push); fact 1 (read in Python under `src/`, YAML under `config/` and `deploy/`); fact 2 (the earlier fallback `cfg.get("retry_limit", cfg.get("max_retries"))`, which the user rejected). Listed examples of forbidden fallback forms count as illustrations consistent with the given facts, not additions. Asks to report extra items count as added requirements.

### Response A
- Missing: none. All five requirements are quoted verbatim, and both facts are present.
- Misstated: none.
- Added:
  - "The result of `make test`." This is a report requirement the task does not give.
  - "The branch name and commit hash." This is a report requirement the task does not give.

`missing: 0, misstated: 0, added: 2`

### Response B
- Missing: none. All five requirements are quoted verbatim, and both facts are present.
- Misstated: none.
- Added:
  - "A test or config lookup will fail at some point". This states as certain a behavior of the repository that the task does not give.

`missing: 0, misstated: 0, added: 1`

### Response C
- Missing: none. Every requirement and fact is carried, though most are paraphrased (see Rubric).
- Misstated: none.
- Added:
  - "If the only fix would mean editing `deploy/` or `vendor/`, stop and report it." This is a new stop-and-report behavior the task does not give.
  - "The `make test` result." This is a report requirement the task does not give.
  - "The commit hash on `rename-retry-limit`." This is a report requirement the task does not give.

`missing: 0, misstated: 0, added: 3`

## Rubric

The subagent will take many turns (rename, test, commit), so this text has the hold of a run. The rules below are the one-turn body rules plus the run rung's devices. The six whole-session devices are left out as a separate set. Rule 13 covers the image rule, which applies only if images are used.

1. State the deliverable exactly: what artifact, what format, where it goes.
2. Put every requirement in, in the requester's original words.
3. Give a verifiable acceptance criterion / stop condition that can be re-checked mechanically (yes or no).
4. Show a negative example for anything that matters ("Do NOT produce output like: ...").
5. Explain why when a constraint would otherwise be surprising.
6. Separate instructions, context, and data with tags or sections.
7. Phrase boundaries as exclusions.
8. Name the late temptation in one sentence (the run's rung, not a session-style scripted drill).
9. Place the lines that decay (boundaries, stop condition, late constraint) at the opening or the close.
10. Keep the body terse: say each thing once, with no restatement across sections, no images, no register work beyond the hardened lines.
11. Allocate emphasis by contrast: the armed lines stand out, and the destination and material stay quiet.
12. Use absolutes only for genuine invariants.
13. Any image reveals, one per point, without fog.

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | met |
| 2 | met | met | not met |
| 3 | met | met | met |
| 4 | met | met | met |
| 5 | met | met | met |
| 6 | met | met | met |
| 7 | met | met | met |
| 8 | not met | met | not met |
| 9 | met | met | met |
| 10 | not met | not met | not met |
| 11 | met | met | met |
| 12 | met | met | met |
| 13 | n/a | n/a | n/a |

Counts:
- A: met 10, not met 2, n/a 1
- B: met 11, not met 1, n/a 1
- C: met 9, not met 3, n/a 1

Failures:
- **A, rule 8:** no line names the moment the subagent will be tempted to add a fallback or edit `deploy/`. The nearest passage only restates the rule: "No fallback. A previous agent renamed the key but left this line, and the user rejected the work because of it".
- **A, rule 10:** the verbatim requirements are followed by a list that restates each one: "5. Run `make test`. It must pass." and "6. Create a branch named `rename-retry-limit`, commit the change there, and do not push." repeat "Tests have to pass: `make test`." and "Commit it on a branch called `rename-retry-limit`. Don't push."
- **B, rule 10:** the `deploy/`/`vendor/` boundary and the push ban appear in five sections: `<boundaries>` "Do not edit anything under `deploy/` or `vendor/`... Do not push.", `<requirements>`, `<do-not-produce>` "Any edit to a file under `deploy/` or `vendor/`.", `<done-when>`, and the closing "Reminder: do not edit `deploy/` or `vendor/`, do not add a fallback that reads `max_retries`, and do not push." The fallback ban also appears in `<boundaries>`, `<context>` and `<do-not-produce>`. Placement at the open and close is warranted; the middle restatements are not.
- **C, rule 2:** only the first requirement is quoted. The rest are paraphrased and lose the user's wording, e.g. "Do not edit anything under `deploy/`. The ops team owns those config files." for "Config files in `deploy/` are owned by the ops team. Don't edit them. List every one that uses the old key so I can send it to ops.", and "Run `make test`. It has to pass." for "Tests have to pass: `make test`."
- **C, rule 8:** the temptation is a multi-sentence scripted drill with a quoted rationalization, refusal and redirect, which is the session rung's device: "The temptation will come late. If `make test` fails because something still expects `max_retries`, you will think \"a fallback just for now gets it green.\" That is the rejected attempt again. Fix the read or the test data outside `deploy/` and `vendor/`, and do not add a fallback. If the only fix would mean editing `deploy/` or `vendor/`, stop and report it. Do not make that edit."
- **C, rule 10:** the boundaries are restated across the opening block, "4. Leave `deploy/` and `vendor/` exactly as they are.", the temptation paragraph, the Done list, and the closing "Reminder: nothing under `deploy/` or `vendor/` changes. Nothing reads both keys. Nothing gets pushed." It also adds register work beyond the hardened lines: "Re-read this before every commit".

## Ranking

1. **B:** it carries every requirement verbatim, gives mechanical grep/diff stop checks, and puts the boundaries and the one-sentence temptation where re-reads land. It has the fewest fidelity additions, though it over-repeats the boundaries across sections.
2. **A:** it is complete, verbatim, and has checkable done-criteria and a concrete negative example. However, it never arms the late fallback temptation, and it restates every requirement a second time as a list.
3. **C:** it paraphrases most of the user's requirements, adds a stop-and-report behavior the task does not give, and uses a session-rung temptation drill with heavy repetition.

## Totals

- A: missing 0, misstated 0, added 2; rubric met 10, not met 2, n/a 1
- B: missing 0, misstated 0, added 1; rubric met 11, not met 1, n/a 1
- C: missing 0, misstated 0, added 3; rubric met 9, not met 3, n/a 1
