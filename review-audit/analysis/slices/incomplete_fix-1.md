# incomplete_fix, part 1 (464 rows)

Every row was read and given one pattern. Counts cover the whole slice; none are sampled. The slice has 405 copirate and 59 copilot rows, and 430 rows were judged correct=yes. 55 rows were caused by another row in this slice, so one root took three or more rounds. Examples: laws#15 F4→F13→F19, copirate-code-review-agent#107 F10→F21→F26, cc-candybar#14 F8→F21→F25.

## 1. Patterns

| # | Pattern | Rows | Examples | Mechanism |
|---|---|---|---|---|
| 1 | Sibling code site not swept: twin call site, branch, return path or helper copy left | 61 | copirate-code-review-agent#108/F12, crom#58/F7, cc-candybar#146/F8, elvenspeak#1/F85 | Fix scoped to the anchored line; no grep for the same expression |
| 2 | Value domain partly covered: C1 after C0, `,`/`:` after `.`, the sum after the product, `''` after the wrong type, ties | 60 | cc-candybar#14/F25, laws#15/F19, copirate-code-review-agent#107/F26, copirate-code-review-agent#90/F4 | Patched the reviewer's example input; no accept/reject table |
| 3 | Fix shipped without a test: new branch, boundary or wiring untested; manual smoke instead | 78 | go-template-js#19/F8, elvenspeak#1/F58, copirate-code-review-agent#148/F4, crom#32/F20 | Reviewer item 9 ("Missing tests") raises it next round |
| 4 | Stale copy of a claim, figure or phrase left in another comment, README, CLAUDE.md or help text | 42 | cc-miser#3/F8, crom#30/F3, elvenspeak#1/F56, copirate-code-review-agent#104/F10 | Only the anchored line was edited; sweeps filtered by file or line (cc-candybar#218/F19) |
| 5 | Failure modes partly enumerated: open-but-silent socket, ETIMEDOUT, OverflowError, resumed process, shallow clone | 41 | laws#28/F7, crom#18/F8, elvenspeak#20/F29, copirate-code-review-agent#155/F8 | No failure-shape table for each call in the guarded span |
| 6 | Fix wrote a new false claim: "never throws", "covered by construction", "single source", "same table" | 31 | crom#3/F44, cc-candybar#150/F35, copirate-code-review-agent#108/F11, crom#4/F2 | A comment written to prove completeness became the next divergence finding |
| 7 | Claimed fix not on reviewed head: wrong branch, held or partial push, plan item never landed | 29 | cc-candybar#10/F3, cc-candybar#229/F8, crom#60/F4, crom#32/F30 | "Fixed in <sha>" not checked against the head; cc-candybar#10 alone is 15 rows |
| 8 | Finding's own list partly done: it named several sites or parts and the fix did a subset | 21 | cc-candybar#205/F26, copirate-code-review-agent#104/F11, copirate-code-review-agent#130/F36, elvenspeak#33/F12 | Listed items not checked off against the diff |
| 9 | Vacuous test: it passed with the fix reverted | 19 | copirate-code-review-agent#122/F17, crom#3/F78, elvenspeak#32/F29, laws#46/F37 | No mutation check before pushing |
| 10 | Changed contract, consumers not updated: exit code, laziness, required field, throw became return | 18 | laws#4/F7, laws#4/F10, elvenspeak#20/F26, cc-candybar#205/F15 | Grepped the definition, not the readers |
| 11 | Weaker remedy than the one named: reword, deny-list, check inside the loop, path made rarer | 17 | cc-candybar#133/F9, laws#15/F35, cc-candybar#199/F7, copirate-code-review-agent#130/F14 | Addressed the sentence, not the defect |
| 12 | Re-implemented instead of reusing: retyped constant or regex, parallel predicate | 14 | cc-candybar#152/F13, copirate-code-review-agent#162/F7, laws#39/F113, cc-candybar#190/F13 | The fix created a second source of truth |
| 13 | Enumeration written from memory, not derived from code | 11 | cc-candybar#228/F12, copirate-code-review-agent#120/F21, laws#36/F26, crom#12/F7 | List not derived from its source |
| 14 | Residue of a removal: dead import or export, unread attribute | 10 | crom#10/F8, copirate-code-review-agent#130/F24, laws#39/F105 | Filtered linter run; abandoned attempt not diffed |
| 15 | Earlier pushback or deferral was wrong | 9 | cc-candybar#177/F9, copirate-code-review-agent#108/F10, crom#3/F47 | Declined on a false premise |
| — | No pattern fits | 3 | cc-candybar#12/F2, cc-candybar#31/F6 | |

Total: 464. Of these, 68 rows are duplicate threads on a root and are counted under that root's pattern. Examples: 12 threads at copirate-code-review-agent#108 F12–F31, 4 at crom#10/F8–F12, 4 at elvenspeak#10/F14–F19.

## 2. What the guidance already gets right

- **address-pr-reviews, the `different_fix` class.** The text is "reviewer identified a real issue but proposed the wrong fix; a better fix is coming". 54 of the 57 different_fix responses here were judged correct, and many were structural:
  - an allow-list `Pick` (cc-candybar#199/F9)
  - reusing `install()` (elvenspeak#1/F92)
  - canonicalizing paths at creation (laws#35/F27)
  - one gh boundary (laws#35/F41)
  - an AST-derived registry test (elvenspeak#20/F28)
- **address-pr-reviews step 4.** The text is "A wrong comment is fixed by shrinking it". Where the agent followed it, the thread stayed closed: 5 roots, 11 rows (elvenspeak#1/F56, elvenspeak#10/F14, elvenspeak#2/F2, crom#4/F4, laws#47/F6). The same step already warns "the comment you write to prove alignment is the next round's divergence finding". Pattern 6 (31 rows) shows the rule is correct but did not hold when the agent wrote the fix.
- **Reviewer prompt, the grep instruction.** The text is "Grep the repository for that symbol's other uses". Together with item 8 (comment/code mismatch), this surfaced patterns 1, 4 and 10 (121 rows). The judges agreed with the reviewer's premise in 437 rows.
- **Reviewer prompt, the PRIOR-ROUND PUSHBACKS block.** Wrong pushbacks were refuted with specifics (cc-candybar#177/F9, crom#3/F47). Sound pushbacks held (copirate-code-review-agent#74/F11, laws#34/F12, cc-candybar#146/F12).
- **laws:code `[LAW:one-source-of-truth]`.** The text is "read from it, derive from it". Round-2 fixes for pattern 12 converged on exactly that (cc-candybar#152/F13, cc-miser#5/F13).

## 3. Proposals (ranked by rounds saved)

1. **Sweep the class.** Patterns 1, 4 and 10: 121 rows. Goes in address-pr-reviews, step 4 "Implement the planned changes": "Before pushing, grep the whole repo for the flagged expression, literal, phrase and helper. Search multi-line with no file filter, covering code, tests, README, CLAUDE.md and help text. Also grep for every reader of any value whose meaning the fix changes. Fix every hit in one commit, and put the grep and its hit count in the 'Fixed in' reply."
2. **Write the case table first.** Patterns 2 and 5: 101 rows. Goes in laws:code, `[LAW:parse-dont-validate]`, next to its Diagnostic: "Before writing a guard, predicate, escape, bound or catch, write its table. List every member of the input's class: empty, whitespace, null, boundary ±1, ties, and the whole control-character or exception family. List every way each call can fail or hang. The reviewer's example is one row of that table."
3. **Each fix commit carries a test that fails without the fix.** Patterns 3 and 9: 97 rows. laws:code `[LAW:verifiable-goals]` already says "build the check while you build the feature". That rule did not carry over to review fixes. Goes in address-pr-reviews, step 6: "A behavior-changing fix commit includes its test. Revert the fix locally, watch the test go red, then restore the fix. A manual smoke run or a promised test does not count as the fix."
4. **Check off before writing "Fixed in".** Patterns 7 and 8: 50 rows. Goes in address-pr-reviews, step 7: "First confirm the sha is an ancestor of `gh pr view --json headRefOid`. Then check every location, part and plan item that the finding and your plan named against the pushed diff. Name in the reply any item you are declining."
5. **The reviewer reports the whole remainder at once.** Targets the 55 chained rows. Goes in the reviewer prompt (`reviewCharter`, src/prompt.js), replacing "flag the clearest instance and note the pattern once" with: "When a finding is the remainder of an earlier round's fix, list every site and every unhandled input class in that one finding." Today's wording lets each round surface one more instance.

## 4. Caveats

- One pattern per row, and the boundaries between patterns 1, 4 and 8 are soft. When a finding already named the stale copy, I counted the row under pattern 8.
- Counts are rows, not roots. Duplicate threads inflate pattern 1 (copirate-code-review-agent#108) and pattern 7 (cc-candybar#10).
- cc-candybar#10's 15 rows are labeled incomplete_fix, but the cause there is a stuck branch.
- The judges noted mislabeled reply hints (cc-candybar#25/F5, crom#1/F5, crom#58/F7, go-template-js#19/F10).
- 6 rows are correct=uncertain because the packet lacked the code.
- install.sh no longer embeds the reviewer prompt. It references `promptctl/copirate-code-review-agent@v1`, so I read that repo's origin/main `src/prompt.js` instead. I did not check whether the address-pr-reviews text I quote predates the copilot-era rows.
