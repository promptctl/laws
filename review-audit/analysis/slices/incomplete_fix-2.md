# incomplete_fix, slice 2 (464 rows): what the first fix missed

Slice: `caused-incomplete_fix.part01.jsonl`. All 464 rows read; one hand-assigned pattern per row; full tallies, not a sample. Eras: copirate 367, copilot 97. Round-2 response right 449 times, wrong 11, uncertain 4.

## 1. Patterns

| # | Pattern (what the first fix did) | Rows | Examples | Mechanism |
|---|---|---|---|---|
| C | **Predicate written from one shape.** A validator, classifier or guard covered the reported shape; the next round found another it should have rejected (blank/padded, leading `+`, substring match, denylist, per-entry-only cap, absent key). | 92 | laws#48/F18, links-issue-tracker#128/F4, links-issue-tracker#150/F14, links-issue-tracker#390/F30, memento#11/F13 | No accept/reject table was written. Each round added one row. |
| A | **Stale claim fixed only at the anchored line.** The same false phrase survived in another comment, CHANGELOG, doc, error string or fixture. | 64 | laws#47/F7, links-issue-tracker#143/F16, links-issue-tracker#519/F13, links-issue-tracker#520/F19 | No grep for the phrase; or a grep for one wording that missed a paraphrase (#520/F19). |
| D | **New branch shipped untested, or the test could not fail.** (presence instead of position, unwired spy, fixtures too different to catch the bug). | 59 | laws#69/F20, links-issue-tracker#134/F13, textual-js#14/F16, tmux-control-mode-js#154/F26 | Review fix treated as an edit; test never seen failing on revert. |
| B | **Sibling code site not updated.** Another caller, consumer, twin command or counter of what the fix changed kept the old behavior. | 51 | laws#69/F36, links-issue-tracker#142/F16, links-issue-tracker#390/F8, textual-js#1/F15 | Fix stopped at the flagged call site. |
| Q | **A design-doc rewrite contradicted another section, or left a parameter unstated.** | 36 | links-issue-tracker#413/F24, links-issue-tracker#413/F66, links-issue-tracker#413/F102 | New sentence not checked against the doc's own sections; 35 rows from #413/#416. |
| F | **Race narrowed, not closed.** Check-then-act left, value instead of identity guard (ABA), one ordering walked. | 30 | links-issue-tracker#121/F6, links-issue-tracker#304/F3, links-issue-tracker#513/F23, tmux-control-mode-js#154/F18 | Remaining interleaving never named. |
| E | **Part of the finding dropped.** The reviewer named two locations/concerns/guards; the fix did one. | 26 | links-issue-tracker#119/F55, links-issue-tracker#143/F19, links-issue-tracker#396/F11, tmux-control-mode-js#38/F16 | Concerns not mapped to fix lines. |
| G | **Error or cleanup handled on one exit only.** (join only when primary err nil, `.catch` misses sync throw, trap armed after an early exit). | 25 | laws#49/F44, links-issue-tracker#119/F11, memento#17/F14, tinkerpadai-web#27/F54 | Failure exits never listed. |
| K | **Parallel implementation kept or created.** Twin path synced instead of collapsed, or a dedup fix added a new copy. | 18 | links-issue-tracker#95/F7, links-issue-tracker#447/F8, openconv#12/F11, tmux-control-mode-js#148/F46 | "Match the other site" instead of one owner. |
| L | **The fix rested on an unchecked assumption about a dependency.** (diff-gated broadcaster, `os.File` finalizer, `ExitCode()` after a signal). | 17 | promptctl#4/F12, links-issue-tracker#392/F32, links-issue-tracker#313/F10 | The producer's source would have refuted it. |
| S | **Wrong pushback or dismissal cost a round.** | 11 | links-issue-tracker#549/F11, links-issue-tracker#144/F70, textual-js#17/F9, openconv#28/F55 | Reply rebutted a different site, or never re-ran the finding's case. |
| H | **Residue left behind.** Dead param, old API left public, mode bit moved up a level. | 6 | links-issue-tracker#134/F9, links-issue-tracker#227/F9 | Old path not deleted. |
| I | **"Resolved in sha" was not in that sha.** | 5 | links-issue-tracker#119/F31, links-issue-tracker#144/F89, links-issue-tracker#552/F12 | Reply not checked against the diff. |
| R | **A partial push triggered review before planned fixes landed**. | 5 | links-issue-tracker#481/F12 | Mid-round partial push. |
| P | **Guard placed at a caller, not at the owning boundary.** | 4 | tmux-control-mode-js#38/F6, promptctl#25/F29 | — |
| M | **Answered with a comment instead of code.** | 3 | tmux-control-mode-js#174/F37 | — |
| — | No pattern | 12 | | |

The counts sum to 464.

## 2. What guidance already gets right

- **Different_fix lands the structural cure.** address-pr-reviews: "different_fix — reviewer identified a real issue but proposed the wrong fix; a better fix is coming". laws:code [LAW:one-source-of-truth]: "find the canonical representation; read from it, derive from it". 60 of 66 different_fix responses were correct; round 2 often fixed at the owner instead of taking the narrow cure:
  - links-issue-tracker#157/F11 moved requiredness onto the target registry.
  - links-issue-tracker#553/F11 replaced the reviewer's paren-matcher with go/parser.
  - links-issue-tracker#387/F15 used an allowlist instead of a prefix heuristic.
  - links-issue-tracker#394/F15 rejected padded input instead of normalizing a second form.
  - links-issue-tracker#304/F4 corrected the reviewer's mechanism and still fixed the real race.
- **"A wrong comment is fixed by shrinking it"** (address-pr-reviews step 4). links-issue-tracker#484/F3 deleted the miscount rather than correcting it, so it cannot drift again. links-issue-tracker#550/F17 removed the whole measured clause from the copies that did not own it.
- **Law citations are mostly apt:** 119 apt vs 11 not (one-source-of-truth 43, single-enforcer 26).
- **The review prompt's pushback block works.** The text: "If a reply is itself mistaken ... state a direct, specific counter to the author's reasoning". 3 of 4 wrong pushbacks were re-raised with a counter and reversed before merge (links-issue-tracker#549/F14, links-issue-tracker#390/F22, links-issue-tracker#144/F79), at a round each.

## 3. Proposals (ranked by rows addressed)

**P1. address-pr-reviews, step 4 "Implement the planned changes", new paragraph after the first sentence. Addresses A + B = 115 rows.**
> A finding is one instance of a class. Before committing, name the class and sweep for it: grep the phrase, literal or claim you corrected across code, comments, docs, CHANGELOG, user-facing strings and fixtures, and grep every caller, consumer and sibling of the function, field, flag or error you changed. Fix every hit in the same commit, or name the ones you leave in the plan comment.

Why this is a gap: the review prompt says "flag the clearest instance and note the pattern once". So the reviewer reports one site by design, and nothing on the author side expands it back to all the sites.

**P2. laws:code [LAW:parse-dont-validate], after the "Missing a leg?" paragraph. Addresses C = 92 rows.**
> Before writing a predicate, parser, classifier or guard, write its accept/reject table: each shape the producer emits, and each it must refuse — empty, blank, padded, signed, leading-zero, prefixed, substring-embedded, the key-absent default, and for an error classifier every exit code. A reviewer who finds one missing row has found a table that was never written; write it then, not one more row.

Why this is a gap: the law's three legs (dedicated unit, proving type, loud failure arm) say nothing about which inputs the unit refuses. Every row in C has all three legs and still accepts a shape the producer never emits.

**P3. address-pr-reviews, step 4, after P1. Addresses D = 59 rows.**
> Every branch, guard, error arm or contract method a fix adds ships in the same commit with a test that reaches it, and you have watched that test fail with the fix reverted.

Why this is a gap: laws:code [LAW:verifiable-goals] already says "build the check while you build the feature; run it". That did not hold here because address-pr-reviews says nothing about tests, so a review fix reads as an edit rather than a feature. The "fail on revert" clause targets the vacuous tests in D: textual-js#14/F16, tmux-control-mode-js#154/F26, links-issue-tracker#444/F15.

**P4. address-pr-reviews, step 7 "Confirm phase", before the "Fixed in <sha>" comment. Addresses E + I + R = 36 rows.**
> Before posting "Fixed in <sha>", read that sha's diff against the finding: every location it names changed, every concern and alternative guard it raised is implemented or declined on the thread, and every test your plan promised is present. Push a round's fixes together; a push with planned fixes still missing reviews the partial state.

**P5. laws:code [LAW:no-ambient-temporal-coupling], appended to the Diagnostic line. Addresses F = 30 rows.**
> And for a fix that claims to close a race: name the interleaving left between the check and the act it guards. If one remains, the race is narrowed, not closed — make check and act one atomic step (exclusive create, held lock, a token compared by identity, not by value).

Why this is a gap: the law's sleep/flake framing covers timing bets. It does not cover check-then-act, or value-equality ownership guards (ABA). Examples: links-issue-tracker#121/F6 and tmux-control-mode-js#166/F11.

Q (36 rows) gets no proposal: 35 of its rows come from two design-doc PRs, so a guidance change built on it would rest on two data points.

## 4. Caveats

- One reader, one label per row; A/B/C/E blur. A row whose earlier finding named the missed site counts as E.
- About 58 rows are same-round duplicates, where the multi-scope reviewer posted one defect from several scopes. Examples: tmux-control-mode-js#154 F18–F25 (6 copies), links-issue-tracker#394 F10–F19 (5), links-issue-tracker#390 F8–F18. Counts are findings, not distinct defects; C and F are inflated most.
- links-issue-tracker supplies 276 of the 464 rows (59%), and #413/#416 alone supply 43.
- Several evidence fields say the commit in caused_by is incidental and name a different real cause (links-issue-tracker#121/F8, promptctl#1/F10, links-issue-tracker#160/F10).
- correct=yes (449) grades the round-2 response only. Every first fix in this slice was incomplete by construction.
- The brief places the review prompt in install.sh. The current install.sh only references `promptctl/copirate-code-review-agent@v1`. I read the prompt from `/Users/bmf/code/copirate-code-review-agent/src/prompt.js` (HEAD 80d9ab0, 2026-09-21), which postdates most copilot-era rows.
