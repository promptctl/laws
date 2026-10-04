# PR review audit: analysis and proposals

Every reviewer finding on every PR in the promptctl org, through 2026-10-03: 8,060 findings on 930 PRs, each judged by a classifier agent under `prompts/classify.md`. The tables come from `report.py`. The patterns come from nine slice reports in `analysis/slices/`, each written by an agent that read every row of its slice (`analysis/slices/BRIEF.md` is the brief they worked from). Counts in this document trace to those reports; example ids are `repo#PR/F<n>` and can be opened with `render.py`.

This ticket proposes guidance changes. It makes none.

## The numbers that matter

| | |
|---|---|
| Agent accepted the fix | 5,795 (72%); right in hindsight 5,722 times (99%) |
| Agent pushed back | 715 (9%); right 562 times (79%), wrong 95 |
| Agent never answered | 424 (5%); wrong to leave it 242 times |
| Reviewer premise correct or partly correct | 7,598 (94%) |
| **Findings caused by the agent's own earlier fix** | **2,217 (28%)** |
| **Review rounds containing such a finding** (derived, `report.py`) | **967 of 3,247 (30%)** |

The agent judges findings well. The rounds come from its fixes. More than a quarter of everything the reviewer raised is about code the agent wrote in response to an earlier finding on the same PR.

That share has not fallen as the guidance evolved. By month raised: May 25%, July 21%, August 32%, September 31%. (Two confounders: the copirate reviewer raised more findings per round from 2026-08 on, and the mix of repos changes over time.)

What the fix-caused findings are (`cause_kind`): incomplete fix 928, same gap at another instance 422, comment drift from the fix 355, regression from the fix 321, new scope the fix added 191.

## What the guidance gets right

- **`different_fix` (address-pr-reviews step 3).** "reviewer identified a real issue but proposed the wrong fix; a better fix is coming". 840 of 884 such responses were right. The best results in the corpus come from this arm: fixing at the owner instead of the flagged line. For example elvenspeak#32/F14 normalized once in `Voice.__post_init__` and closed six threads; links-issue-tracker#553/F11 replaced the reviewer's paren matcher with `go/parser`.
- **Fixing at the single owner converges.** PRs that finished in one or two rounds fixed every finding in one commit, at the shared owner (`pr_process-2.md`: promptctl#23 generalized to all five mutators and took 2 rounds; promptctl#21, the same week, went site by site and took 6). `[LAW:single-enforcer]` and `[LAW:locality-or-seam]` are the texts that produced this.
- **Pushback backed by evidence holds.** Pushbacks carrying a command output, a measurement or a source quote closed in one exchange, and the reviewer's PRIOR-ROUND PUSHBACKS block (`src/prompt.js`) kept them closed. Wrong pushbacks were refuted with specifics and reversed before merge, at the cost of one round.
- **"A wrong comment is fixed by shrinking it" (2026-08-30).** After it landed, the agent deleted or narrowed stale prose instead of rewording it in 25 of 194 drift fixes, against 7 of 161 before (keyword count, `comment_drift.md`). Deleted restatements did not drift again.
- **The reviewer is right.** 94% correct or partly correct premises; the "grep the repository for that symbol's other uses" instruction is what surfaces most of the sibling defects below.

## Where the rounds go

The six finding-level slices are disjoint, so these sum. 1,753 of the 2,217 fix-caused findings fall in six families.

| Family | Findings | Mechanism | Source |
|---|---|---|---|
| **1. The fix covered the flagged instance only** | 825 | Sibling call site, other arm, mirrored implementation, or another prose copy of the fact left unchanged. The next round finds it, often one instance per round. | all 422 `same_gap`; `incomplete_fix-1` patterns 1, 4, 10; `incomplete_fix-2` A, B; `comment_drift` B, C, E, G, I, K, L |
| **2. A new check was written from one example** | 308 | A predicate, parser, guard, catch or race fix covered the reviewer's input shape. The next round finds the next shape, failure mode or interleaving. | `incomplete_fix-1` 2, 5; `incomplete_fix-2` C, F, G; `regression_new_scope` C, Z |
| **3. The fix shipped without a test that can fail** | 210 | No test, or a test that passes with the fix reverted, or a test that leaks env or temp state. | `incomplete_fix-1` 3, 9; `incomplete_fix-2` D; `regression_new_scope` E |
| **4. Prose the fix wrote was false when written** | 204 | Comments, docs, error messages and test names that claimed "every", "the only", "never", a count, or a mechanism the code doesn't have. | `comment_drift` A, J; `regression_new_scope` F; `incomplete_fix-1` 6 |
| **5. Existing code changed without checking what depended on it** | 120 | A rewrite dropped a guarantee the old code gave; a shared function's contract changed and its other callers weren't checked; moved code broke a lock or ordering rule. | `regression_new_scope` A, B, D |
| **6. "Fixed in <sha>" that the sha doesn't support** | 86 | The commit did part of what the finding or the plan listed, or wasn't on the reviewed head. | `incomplete_fix-1` 7, 8; `incomplete_fix-2` E, I, R |

At PR level (`pr_process-1.md`, `pr_process-2.md`), families 1 and 2 dominate: across the two halves, 203 PRs and 1,072 rounds were driven mainly by instance-only fixes, and 36 PRs and 194 rounds by unenumerated new checks. Across all 930 PRs, 240 of the 269 that took 5 or more rounds had a fix-caused chain, against 21 of the 404 that took 2 or fewer.

**Why family 1 is so large: the two documents hand off a gap.** The reviewer prompt says "One comment per distinct issue — flag the clearest instance and note the pattern once" (`src/prompt.js:89`). So the reviewer reports one site by design. address-pr-reviews contains no instruction to search past the flagged line: no "sweep", "sibling" or "every instance" anywhere in it. The pattern note is prose; the agent fixes the anchored line; the reviewer finds the next site next round.

**Why the existing comment rule didn't stop family 4.** "A wrong comment is fixed by shrinking it" governs how the agent *repairs* a drift finding, and it covers code comments. Family 4 is prose the agent *writes* during a fix, and most of the regression-side cases are error messages and docs. The fix-caused drift share did not drop after 2026-08-30. The jump in drift findings came on 2026-08-23, when copirate #108 added the comment/code mismatch check to the reviewer.

### Smaller sources

- **Reviewer drip-feed.** 132 PRs (44 + 88 across the halves) were driven by the reviewer finding new issues in code unchanged since round 0, one to three per round. The 2026-08-10 convergence sweep did not end it (links-issue-tracker#491, #504, #555 in September).
- **Pushes while a round is open.** 33 PRs (16 + 17), averaging about 6 rounds. Each push starts a full review that re-raises every open finding (links-issue-tracker#144 spent rounds 1-8 this way; laws#27 pushed 1 of 13 fixes).
- **Merged without the review loop.** 85 PRs (49 + 36) merged before the review posted, merged over open threads, or resolved threads with no reply. links-issue-tracker#400 merged 2 seconds after it was opened. 54 no-response findings state the post-merge timing outright (`wrong_calls.md`). These PRs never ran address-pr-reviews, so no wording change reaches them.
- **Wrong pushbacks.** 95. The commonest cause (36) is a claim the diff, the code or installed docs contradict; 26 more were reversed by the agent a round later on the same facts (`wrong_calls.md` PB1, PB2).
- **Law citations used as decoration.** 280 of 2,509 citations were judged inapt. 161 of those sat on a correct decision and cost nothing. 51 cost rounds: in 26 the law was the argument for a call later reversed, and in 25 the citation claimed a property the code didn't have, which hid the defect (`law_citations.md` A, C). address-pr-reviews says "Push back and **cite the law**", so the agent attaches a token even when the argument is a fact or the ticket's scope (55 rows).

## Proposals

Ranked by the rounds they would save. Each names the document, the place, and the wording. The laws:code items are proposals for the owner to approve word for word.

### P1. Sweep the class before fixing. Family 1, 825 findings.

**address-pr-reviews, step 3 "Plan phase", after the classification list:**

> For a valid or different_fix finding, the plan names the defect class, not the line. Before implementing, search for every other instance: the same expression or callee at other call sites, the other arms of the switch or union, the other implementations, the other end of a pair, and every prose copy of the fact (comments, README, CLAUDE.md, CHANGELOG, docs, usage and error strings). Search for the claim's key term, not the reviewer's phrase. The plan comment lists what the search found, and the fix covers all of it or says why not.

**Reviewer prompt, `src/prompt.js`, replacing "flag the clearest instance and note the pattern once":**

> One comment per distinct issue, anchored at the clearest instance. In its body, list the file:line of every other instance you saw, inside or outside the diff.

The two halves work together: the reviewer's list makes the author's sweep checkable.

### P2. Write the case table before the check. Family 2, 308 findings.

**laws:code, `[LAW:parse-dont-validate]`, after its Diagnostic:**

> Before writing a predicate, parser, classifier, guard or catch, write its accept/reject table: each shape the producer emits and each it must refuse (empty, blank, padded, signed, prefixed, substring-embedded, the absent key, every exit code, every way each call in the span can fail). A reviewer who finds one missing row has found a table that was never written. Write the table then, not one more row.

The law's three legs (dedicated unit, proving type, loud failure arm) say nothing about which inputs the unit refuses. Every row in `incomplete_fix-2` pattern C has all three legs and still accepts a shape the producer never emits.

### P3. A fix ships with a test that fails without it. Family 3, 210 findings.

**address-pr-reviews, step 4 "Implement the planned changes":**

> A behavior-changing fix commit includes the test that reaches the new branch, guard or error arm. Revert the fix, watch the test fail, restore it. A test written for a fix follows its file's existing setup and teardown idiom (env, spies, temp dirs, timeouts). A manual smoke run or a promised test is not the fix.

laws:code `[LAW:verifiable-goals]` already says "build the check while you build the feature". It did not carry over to review fixes because address-pr-reviews says nothing about tests, so a fix reads as an edit. Revert-and-see-red appeared in 39 PRs (first half) and those PRs show no follow-on test findings; it is written nowhere.

### P4. Check every sentence the fix writes. Family 4, 204 findings.

**address-pr-reviews, step 4, after "A wrong comment is fixed by shrinking it":**

> Every sentence a fix adds is a claim the next round checks against the code. That covers comments, docs, CHANGELOG lines, error messages and test names. Check each against the new head before pushing. A claim you didn't check (an "every", "only" or "never", a count, how an outside tool behaves) is cut, not hedged.

**laws:code, `[LAW:comments-carry-meaning]`:**

> Prose that counts or lists what the code holds ("the three ways it fails", "both refs") is a copy of the code and goes stale with the next case. Name the kind of thing, not the number.

laws:code already lists "a count stored next to the list it counts" as wrong under `[LAW:one-source-of-truth]`. The 33 rows in `comment_drift.md` pattern D show agents don't apply that to prose.

### P5. Before changing existing code, list what depends on it. Family 5, 120 findings.

**address-pr-reviews, step 4:**

> When a fix replaces, inlines, moves or changes the contract of existing code (what it returns, throws, accepts, or when it runs), the plan first lists what the old code guaranteed (errors it classified, guards, side effects, its empty-input result, the lock or order it ran under) and every caller of what changed. The fix keeps each, or says which it drops and why.

### P6. Verify "Fixed in" against the pushed diff. Family 6, 86 findings, plus 18 unsupported "Fixed"/"already fixed" replies among the wrong calls.

**address-pr-reviews, step 7 "Confirm phase", before the `Fixed in <sha>` reply:**

> Before replying "Fixed in <sha>", confirm the sha is on the PR head (`git merge-base --is-ancestor <sha> <headRefOid>`) and check off, against that sha's diff, every location, part and test the finding and your plan named. Name in the reply any item you are declining. Never reuse one thread's reply on another.

### P7. Push once per round. 33 PRs, about 200 rounds.

**address-pr-reviews, step 6 "Commit and push":**

> Push once per round, after every change-needed fix is committed. While a round's findings are open, push nothing else: no CI experiments, rebases, base merges or new scope. Each push starts a review that re-raises every open finding.

### P8. Pushback carries evidence; a law token is not evidence. 79 wrong-pushback and false-accept rows, 51 round-costing citations.

**address-pr-reviews, step 3, the `invalid` bullet ("Push back and cite the law") and the two matching phrases ("cite the law for `invalid`", "Cite the law in the pushback reply"):**

> Push back with the evidence that settles it: the `+` line, a test, command output, the spec. Cite a law only when the suggestion itself violates that law. A reviewer who is wrong about a fact gets the fact.

**laws:code, "How to cite the laws", after "Never invent a new token":**

> A citation is a checkable claim about the line it sits on: that law's Diagnostic, asked of this code, comes back clean. If the decision rests on a fact, a spec, the ticket or an ordering bug, no law decided it. State the fact and write no token.

### P9. The owner's call: a severity floor on re-reviews of unchanged code. 132 PRs, about 580 rounds.

**Reviewer prompt, `src/prompt.js`, the re-review framing (`renderPriorFindingsBlock`):**

> On a review after the first, read the commits since the last reviewed head first, and check each fix and its siblings. Report an issue in code unchanged since a head you already reviewed only at severity 3 or above. Put anything lower in one summary list.

This trades late S1/S2 recall for fewer rounds. Many late drip findings are S1 comment nits (promptctl#16, tmux-control-mode-js#44), but some are not. That's an owner decision, not something the data settles.

### Not a wording change: the merge-without-review gap

85 PRs merged before the review or over open threads. address-pr-reviews already says an empty `fetch` is "the only thing that establishes done"; these PRs never ran it. Text can't fix that. It needs a merge gate (a required status check on the reviewer's completion for the head SHA).

## Caveats

- Patterns are one agent's hand labels per slice, one label per row. Boundaries between neighboring patterns are soft (sibling site vs. missing set member vs. partial fix), so the family totals are more reliable than any single pattern's count.
- About 58 `incomplete_fix` rows and 31 `same_gap` rows are one defect posted several times in the same round by different reviewer scopes. They inflate finding counts but not rounds.
- links-issue-tracker supplies 59% of one `incomplete_fix` half; two of its design-doc PRs (#413, #416) supply 35 rows of one pattern, which got no proposal.
- Judged `avoidable_rounds` is a floor. Classifier agents read its definition differently (`notes/wave-notes.md`). The derived 30% above doesn't depend on it.
- `caused_by` is a judgment. Judges sometimes moved the cause away from the commit the reviewer flagged.
- Some secondary counts in the slice reports are keyword matches over judge prose. Each report labels which.
- Six repos have successful review runs but never archived a transcript (`bank.py verify`): cc-miser, crom, crowdshipai-web, tinkerpadai-web, tmux-control-mode-js, and one horizon run repo. Their code-review workflow lacks the archive step. Transcripts expire 90 days after the run.
