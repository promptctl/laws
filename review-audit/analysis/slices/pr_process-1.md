# PR review process: slice part00 (465 PRs, alphabetical first half)

Slice totals: 1,571 review rounds, 200 judged-avoidable rounds (a floor), 201 PRs with at least one fix-caused chain. 206 PRs closed in ≤2 rounds and 127 took ≥5. Only 12 of the ≤2-round PRs have a chain, against 110 of the ≥5-round PRs. Chains are what separate long PRs from short ones.

Method: every row got one primary pattern (sums to 465). I read every narrative, split chain rows into A/B/F by hand, and assigned the rest by keyword match with hand correction. "Incidence" counts are overlapping keyword matches over the whole slice.

## 1. Patterns (primary assignment)

| # | Pattern | PRs | Rounds | Avoidable | Example ids |
|---|---|---|---|---|---|
| A | Fix covered the cited instance; a sibling instance or mirrored prose came back next round | 120 | 637 (mean 5.3; 75 PRs ≥5) | 120 | cc-candybar#4, copirate-code-review-agent#103, laws#39, elvenspeak#33 |
| B | Fix's own new code carried a new defect (regression, overclaiming comment, vacuous or missing test, unverified reviewer cure) | 73 | 306 (mean 4.2) | 60 | cc-candybar#202, laws#34, elvenspeak#36, links-issue-tracker#29 |
| BYP | Review loop skipped: merged before the review posted, merged over open threads, or threads resolved with no reply | 49 | 65 | 2 | links-issue-tracker#54, cc-candybar#9, copirate-code-review-agent#109, laws#29 |
| D | Reviewer drip: later rounds raised findings on original, unchanged PR code (token-capped or partial scopes, approve-then-flag) | 44 | 180 (mean 4.1) | 1 | copirate-code-review-agent#89, cc-candybar#215, copirate-code-review-agent#76, cc-candybar#162 |
| F | Agent's own push process bought rounds: partial push, unrelated or unprompted commits mid-review, redesign after approval, ignored out-of-diff item | 16 | 94 (mean 5.9) | 16 | laws#27, crom#45, copirate-code-review-agent#116, cc-candybar#240 |
| X | Cross-PR hygiene: wrong base or contaminated branch, or a superseding PR that did not carry over open findings | 15 | 18 | 1 | links-issue-tracker#84, go-template-js#5, links-issue-tracker#66, links-issue-tracker#26 |
| E | Reviewer re-raised a settled decline as the main cost | 3 | 12 | 0 | cc-candybar#131, cc-candybar#141 |
| none | Converged, or no process failure | 145 | 259 (mean 1.8) | 0 | — |

Mechanisms:
- **A:** The agent fixes the cited line, and the reviewer returns next round with the next instance: one OS call or axis per round (crom#17, elvenspeak#59), one copy of a fact restated across README/CLAUDE.md/USAGE (laws#44, elvenspeak#33), or one side of a TS/Rust mirror (cc-candybar#148). In 9 PRs the agent named the class in its own reply and still fixed one instance (cc-candybar#133, crom#63).
- **B:** The fix diff never got the scrutiny the original diff got. Shapes:
  - A comment claiming "provable", "every X" or "total" that the code did not hold (copirate-code-review-agent#91, cc-candybar#222, crom#44).
  - A test that passes with the fix removed (elvenspeak#38, crom#13).
  - The reviewer's literal cure taken unverified (cc-candybar#202 follow-symlinks, links-issue-tracker#8 TryLockContext).
  - A rewrite under review pressure (crom#18, laws#21).
- **BYP:** Merged seconds after opening, or with zero replies; mostly Copilot-era links-issue-tracker, plus copirate-code-review-agent#109 and laws#18. Findings resurfaced in follow-ups (links-issue-tracker#55).
- **D:** The reviewer re-reads the whole PR each round and surfaces about one original-code finding per round; all 9 post-round-0 findings in copirate-code-review-agent#89 were on original code.
- **F:** Each push re-triggers a full review. A push carrying 1 of 13 fixes (laws#27) or 2 of 3 fixes (crom#45) spends a whole round re-reporting work that is still in flight.

Secondary incidence (overlapping):

| Behavior | PRs |
|---|---|
| Duplicate threads for one defect | 105 |
| Evidence-backed pushbacks (measured, reproduced, probed) | 82 |
| Round cap reached, head merged unreviewed | 40 |
| Mutation-checked tests | 39 |
| Mid-review or unprompted scope additions | 31 |
| Out-of-diff summary item ignored, then returned inline | 18 |
| Declined point re-raised | 14 |
| Plan reply promised more than the commit delivered | 7 |

## 2. What the guidance already gets right

- **Pushback with evidence holds.** address-pr-reviews: "invalid — ... Push back and **cite the law**". In practice the agent cited checkable facts instead (82 PRs), and those declines almost never recurred. Examples: copirate-code-review-agent#82, laws#28, copirate-code-review-agent#93 (live API disproved the reviewer and prevented a shipped bug), cc-candybar#159.
- **different_fix earns its keep.** The "different_fix — reviewer identified a real issue but proposed the wrong fix" arm produced better-than-proposed fixes in, for example, copirate-code-review-agent#90, copirate-code-review-agent#158, crom#37 and elvenspeak#48. The judges explicitly credit this arm in copirate-code-review-agent#90 and laws#15.
- **Plan on every thread.** "Post a comment on the thread stating your plan" made threads auditable (copirate-code-review-agent#27). In the BYP PRs with no replies, judges could not tell fixes from dismissals (links-issue-tracker#20).
- **Shrink, don't grow, comments.** "A wrong comment is fixed by shrinking it". Deleting a restatement stopped recurrence in elvenspeak#1, laws#30 and crom#33.
- **Single-commit rounds converge.** ≤2-round PRs typically fixed every round-0 finding in one commit (crom#55, elvenspeak#55, go-template-js#31).
- **Already covered in current text, so these are not gaps:**
  - Body findings: address-pr-reviews now routes "a finding the reviewer could not anchor to a diff line (a body finding ...) rides the same `fetch`", which addresses the 18 out-of-diff misses.
  - Merge-before-review: Finalize runs only after "this empty `fetch` is the **only** thing that establishes done".
  - Re-raises: the reviewer prompt (src/prompt.js) has a PRIOR-ROUND PUSHBACKS block ("do NOT record that same point again this round"). The BYP and E rows look like the skill not being invoked, or predating these texts. I could not date-check them from this slice.

## 3. Proposals (ranked by rounds they would save)

**P1 (pattern A, 120 PRs, 120 judged-avoidable rounds plus most of 688 chain links).** Document: address-pr-reviews, step 3 "Plan phase", directly after the four classifications. Proposed wording:

> For a valid or different_fix finding, name the class it is an instance of. Grep the PR's diff and the repo for every other instance: other call sites, the mirrored implementation, and each README, CLAUDE.md, USAGE or comment sentence stating the changed fact. List those locations in the plan comment, and fix all of them in this round's commit.

Current text has no sweep step. Step 4 says only "Make the code changes for every finding in the change-needed set".

**P2 (pattern B, 73 PRs, 60 avoidable).** Document: address-pr-reviews, step 7 "Confirm phase", before the "Fixed in <sha>" reply. Proposed wording:

> Before replying Fixed, review the fix commit as new code. Each new or changed test must fail with the fix reverted. Each comment or doc claim the commit adds must hold for every input the code accepts. The commit must contain everything the plan comment promised.

Existing laws:code [LAW:verifiable-goals] ("what deterministic check separates success from failure here - and have you run it?") did not hold at fix time. The revert-and-see-red habit appears in 39 PRs and was credited with zero follow-on findings (laws#28, laws#25), but it is not written anywhere.

**P3 (pattern A, reviewer side).** Document: review action prompt, src/prompt.js `reviewCharter`, the line "flag the clearest instance and note the pattern once". Proposed wording:

> One comment per distinct issue: flag the clearest instance, and list every other location of the same pattern you saw (path:line) in that comment, so one fix round can close the class.

Today "note the pattern once" pairs with instance-only fixes, and remainders return as new findings (elvenspeak#10, copirate-code-review-agent#108).

**P4 (pattern F, 16 PRs primary, 31 incidence, 16 avoidable).** Document: address-pr-reviews, step 6 "Commit and push". Proposed wording:

> Push once per round, after every change-needed finding's fix is committed. While the PR is under review, push nothing else: an unrelated fix, an unrequested redesign, or new hardening goes in a ticket or a separate PR.

The current "Batch related concerns; separate unrelated" governs commits, not pushes, and did not stop laws#27 (13 of 16 findings stale) or copirate-code-review-agent#116 (redesign after approval).

**P5 (pattern D, 44 PRs; also inflates the 40 cap-hit PRs).** Document: review action prompt, `renderPriorFindingsBlock`/convergence framing, which applies to rounds after the first. Proposed wording:

> On a review after the first, read the commits since the last reviewed head first, and check each fix and its siblings. Report an issue on code unchanged since a head you already reviewed only at severity 3 or above. Collect lower-severity items on unchanged code in one summary list.

Judges attribute D rounds to reviewer recall, not agent fixes (copirate-code-review-agent#89, laws#11, cc-candybar#71). This trades some S1/S2 recall for fewer rounds, so it is an owner tradeoff.

## 4. Caveats

- `avoidable_rounds` counts a round only if all its findings were fix-caused; judges call it a floor (cc-candybar#177), so A and B cost more than 120 and 60.
- The A/B split is a judgment call; many PRs show both shapes, and I assigned the dominant one.
- Keyword incidence is approximate ("duplicate" also matches duplicated code).
- Judges flag ON-NAMED-FIX-COMMIT as unreliable and corrected for it unevenly, so some chains may hold pre-existing findings.
- Local /code-review fixes have no finding ids, so chains undercount fix-caused cost (laws#69, cc-candybar#243).
- Rows carry no era field. I could not check whether BYP and E predate the current texts.
- Round counts include cancelled and rate-limited runs, which inflate cc-candybar#10 (34) and laws#67 (15).
