# PR review process, slice 2 (465 PRs, part01)

The slice holds 465 PRs, 1,676 review rounds and 267 rounds judged avoidable. 198 PRs took 1-2 rounds and 267 took 3 or more.

## 1. Patterns

Each PR is assigned by hand, after reading all 465 rows, to the one pattern that drove most of its rounds. Counts sum to 465. "Avoidable" sums the judged `avoidable_rounds`, a floor.

| # | Pattern | PRs | Rounds | Avoidable | Examples | Mechanism |
|---|---|---|---|---|---|---|
| A | **Code fix covered only the named instance** | 54 | 304 | 79 | links-issue-tracker#142, promptctl#25, tinkerpadai-web#27, tmux-control-mode-js#148 | The same gap in a sibling caller, arm or implementation was raised next round, one site per round. |
| B | **Fix updated one prose copy of a fact** | 29 | 131 | 31 | links-issue-tracker#406, links-issue-tracker#484, links-issue-tracker#520, links-issue-tracker#549 | The fix edited the quoted copy of a fact also stated in CHANGELOG, docs, comments or citations, or grepped the reviewer's exact phrase and missed rewordings. |
| C | **Fix added a new mechanism with no enumeration** | 36 | 194 | 59 | links-issue-tracker#392, links-issue-tracker#553, memento#11, tmux-control-mode-js#59 | A new predicate, regex gate, lock protocol or test helper was checked only against the reviewer's example; each round found the next input shape or interleaving. |
| D | **Fix wrote new prose that overclaimed** | 19 | 81 | 22 | promptctl#9, promptctl#13, tmux-control-mode-js#55, links-issue-tracker#516 | The comment, docstring or CHANGELOG line written in the fix asserted more than the code does ("byte-faithful", "the ONE place"). |
| E | **Reviewer's cure taken verbatim or in part** | 10 | 65 | 22 | links-issue-tracker#227, tinkerpadai-web#26, links-issue-tracker#418, tmux-control-mode-js#28 | The agent applied the suggested guard or lock as written. Or it applied one part of a multi-part suggestion, and the dropped part came back. |
| F | **Premise misjudged** | 6 | 25 | 5 | promptctl#6, textual-js#17, links-issue-tracker#163 | A wrong pushback was reversed later, or the agent accepted a premise its own test had refuted. |
| G | **Pushes while a round was open** | 17 | 110 | 18 | links-issue-tracker#144, links-issue-tracker#153, openconv#28, links-issue-tracker#481 | CI-iteration commits, rebases, partial fix sets or scope added mid-review each triggered a round that re-raised every open finding. links-issue-tracker#144 spent rounds 1-8 this way. |
| H | **Reviewer drip-fed original-diff defects** | 88 | 401 | 26 | promptctl#5, promptctl#24, links-issue-tracker#555, tmux-control-mode-js#174 | Few or no findings came from fixes. Each round surfaced 1-3 new issues in code unchanged since round 0. |
| I | **Reviewer re-raised declined points** | 2 | 17 | 4 | links-issue-tracker#317, tmux-control-mode-js#25 | Vendored or deferred items were raised again every round. |
| J | **Merged or closed with findings unanswered** | 36 | 54 | 1 | links-issue-tracker#375, links-issue-tracker#449, memento#20, tmux-control-mode-js#18 | Merged seconds after creation, threads resolved silently, or closed with real findings never ticketed. |
| — | Converged: all findings in one round, fixed in one push | 168 | 294 | 0 | — | — |

Patterns A+B+C+D (the fixes themselves) account for 138 PRs, 710 rounds and 191 avoidable. H, the reviewer's late recall, is the largest single group by rounds.

**Secondary behaviors.** These were counted by regex over all narratives and observations. They overlap the table and each other.

- Round cap hit, head merged unreviewed: 35 (links-issue-tracker#504, openconv#24).
- A declined or deferred point was re-raised: 23 (tmux-control-mode-js#154, links-issue-tracker#532).
- Out-of-diff summary findings were ignored until they came back inline: 20 (links-issue-tracker#520, memento#15).
- A "Fixed in"/plan reply didn't match the commit: 17 (links-issue-tracker#413, links-issue-tracker#394).
- Merged before the reviewer posted: 13 (links-issue-tracker#400, tmux-control-mode-js#18).

**What the 1-2-round PRs did differently.**

- **One commit for all findings.** 35 narratives say every finding was fixed in one commit (links-issue-tracker#480, tmux-control-mode-js#13).
- **Fixed at the shared owner, not the flagged site.** links-issue-tracker#517 put the cap in the shared renderer. promptctl#23 generalized to all five mutators and converged in 2 fix commits; the same-week promptctl#21 fixed site by site and took 6 rounds. tmux-phoenix#6 made the delimiters unrepresentable in the types.
- **Checked before deciding.** The agent reproduced or measured before accepting or rejecting (links-issue-tracker#228, links-issue-tracker#307, links-issue-tracker#422).

## 2. What current guidance already gets right

- **address-pr-reviews, step 3 classification:** "**different_fix** — reviewer identified a real issue but proposed the wrong fix." In 28 PRs the agent kept the diagnosis and shipped a better cure than the one proposed (links-issue-tracker#161, links-issue-tracker#291, links-issue-tracker#308, openconv#3). Pattern E is where that classification was skipped.
- **address-pr-reviews:** "Post a comment on the thread stating your plan … on every finding." Where agents did this, duplicate findings were cheap: one fix, one reply per copy (links-issue-tracker#284, links-issue-tracker#502, openconv#27). The 36 PRs in J never ran the skill at all; links-issue-tracker#400 merged 2 seconds after creation. Changing the text won't fix that. The fix is a merge gate.
- **address-pr-reviews, body findings:** "rides the same `fetch`." This landed 2026-09-26 (memento 83ed2b3). The latest slice PRs I dated are from 2026-09-21 or earlier, so the 20 ignored-summary cases come before it. It is covered now, so I make no proposal.
- **Reviewer prompt, `src/prompt.js` pushback block:** "If a reply soundly shows the finding was wrong … do NOT record that same point again." Pushbacks backed by a run, hex dump or source quote usually closed in one exchange (links-issue-tracker#228, links-issue-tracker#318, links-issue-tracker#423). Re-raises persisted where the decline cited only a law or deferred without a ticket (tmux-control-mode-js#154, tmux-control-mode-js#174).

## 3. Proposals

Ranked by the rounds they would save.

**1. address-pr-reviews, step 3 (plan comment) and step 4 (implement). Addresses A + B: 83 PRs, 435 rounds, at least 110 avoidable.**

Neither document says to sweep: address-pr-reviews has no "sibling", "sweep" or "every instance" text. Proposed wording:

> "For a valid or different_fix finding, the plan names the defect class, not the line. Before implementing, search the diff and every file it touches for other instances — sibling call sites, the other arms or implementations, and every prose copy of the fact (CHANGELOG, docs, comments, line citations), searching the claim's key term rather than the reviewer's phrase. The plan lists what the search found; the fix covers all of it."

This also covers D's prose: "A wrong comment is fixed by shrinking it" (step 4, added 2026-08-30) reaches code comments only, and links-issue-tracker#516 and links-issue-tracker#550 (September) still drifted in CHANGELOG and spec prose.

**2. address-pr-reviews, step 4. Addresses C: 36 PRs, 194 rounds, at least 59 avoidable.**

> "When a fix adds a predicate, parser, lock or ordering, or a new state, write its accept/reject table (or interleaving table) before the code and commit one test per row, run once against the pre-fix code to show it fails. A fix checked only on the reviewer's example is not done."

There is evidence for the test step: in 31 PRs, mutation-checking new tests caught vacuous ones (links-issue-tracker#518, textual-js#1). No document asks for it.

**3. Review action prompt, `src/prompt.js` `buildReviewInput`, beside "Flag any problem this change introduces". Addresses H: 88 PRs, 401 rounds.**

The convergence sweep (2026-08-10) did not end drip-feed: links-issue-tracker#491, links-issue-tracker#504 and links-issue-tracker#555 (September) still surfaced unchanged-code issues one per round. Proposed wording:

> "On a re-review (prior findings exist), code unchanged since the last reviewed head has already been reviewed: record a finding there only at severity 3 or above, and mention anything lower in one summary sentence. Commits since the last reviewed head get the full charter."

Trade-off: this gives up late S1/S2 recall on unchanged code. Many late findings were S1 comment nits (promptctl#16, tmux-control-mode-js#44).

**4. address-pr-reviews, step 6. Addresses G: 17 PRs, 110 rounds, mean 6.5 per PR.**

> "Push once per round, after every change-needed fix is committed. While a round's findings are open, push nothing else to the branch — CI experiments, rebases, base merges, new scope — because each push starts a review that re-raises every open finding."

**5. Review action prompt, `src/prompt.js` `reviewCharter`.** The current line is: "One comment per distinct issue — flag the clearest instance and note the pattern once." Replace it with:

> "One comment per distinct issue, anchored at the clearest instance; in its body list the file:line of every other instance you saw."

This makes proposal 1's sweep checkable; in tmux-control-mode-js#46 "and similarly" was ignored. Its savings overlap proposal 1's.

## 4. Caveats

- Primary assignment is my judgment; many PRs mix patterns (links-issue-tracker#143 is A and E), and borderline PRs could move between A, B and H.
- Secondary counts are regex matches over judge prose, spot-checked only.
- `avoidable_rounds` is applied inconsistently: judges counted a round avoidable only if every finding in it was fix-caused. H's floor of 26 understates its cost.
- Rows have no date or era. I dated 14 PRs with `gh pr view` and know nothing about when the others ran relative to guidance changes.
- `rounds` includes cancelled runs and cap non-reviews (memento#19, tmux-phoenix#2).
- The reviewer prompt is not in install.sh, which only pins `promptctl/copirate-code-review-agent@v1`. I read it at `/Users/bmf/code/copirate-code-review-agent` HEAD 80d9ab0.
- Whether a convergence sweep keeps going is intra-round behavior, not visible in PR-level rows.
