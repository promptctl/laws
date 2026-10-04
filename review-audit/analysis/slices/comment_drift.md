# Comment drift caused by fixes: 355 findings

355 rows (82 copilot, 273 copirate), all read and hand-tagged, one main pattern each; nothing sampled. 144 rows are on `.md` files: README 46, CHANGELOG 19, CLAUDE.md 18.

## 1. Patterns

| # | Pattern | Rows | Examples | Mechanism |
|---|---|---|---|---|
| A | The fix wrote new prose (comment, doc, test name, message) that was false when written | 111 | links-issue-tracker#406/F10, promptctl#13/F4, promptctl#7/F10, textual-js#16/F2 | Agent describes intent, not code. Breakdown: 29 universal claims ("every", "the ONE place", "always agreeing", "no unbounded waits"); 12 unchecked claims about outside systems (go-template-js#19/F13, laws#21/F9); 11 test names or comments that claim more than the assertions check (cc-candybar#31/F8); 9 wrong counts; 50 other wrong descriptions of its own code. |
| B | Code changed, and prose in a different file still describes the old behavior | 72 | cc-candybar#32/F13, promptctl#4/F13, links-issue-tracker#454/F7, elvenspeak#1/F54 | Fix commit touches code and test only; docs not searched. |
| C | A comment in the same file or function as the change is left stale | 37 | cc-candybar#205/F23, links-issue-tracker#171/F9, tmux-control-mode-js#59/F6 | Code under the comment edited, comment not reread. 10 rows: code inserted between a doc comment and its function (openconv#7/F9, go-template-js#12/F5). |
| D | Prose with a closed list or count ("the three ways", "both", "exactly four", "all three") stays unchanged when the fix adds a case | 33 | laws#36/F38, crom#24/F15, openconv#14/F6, laws#30/F3 | The number is a second copy of the code's list. laws#39 corrected its test totals three times (F97). |
| E | The fix rewrote one passage and left a contradicting passage in the same document | 18 | elvenspeak#13/F6, links-issue-tracker#416/F20, promptctl#7/F8, links-issue-tracker#504/F3 | Only the flagged paragraph was reread. |
| F | Line-number and position citations ("a few lines above", `file.go:809-857`) shifted by the fix's own inserted lines | 17 | links-issue-tracker#549/F18, links-issue-tracker#519/F9, crom#58/F13 | Insertions move later lines. 16 of 17 in links-issue-tracker, 15 in its `doc-v1-total` spec. |
| G | The same fact is written in two places, and the fix updated only one | 16 | copirate-code-review-agent#120/F15, links-issue-tracker#392/F31, textual-js#15/F10, cc-miser#3/F5 | README vs CLAUDE.md, comment vs spec. |
| H | The PR description is stale | 15 | cc-candybar#22/F10, links-issue-tracker#130/F3, tmux-control-mode-js#56/F4 | All 15 are from the copilot era. CoPirate does not read PR bodies. |
| I | A rename or move was not followed by a search for the old name | 12 | tmux-control-mode-js#53/F3, elvenspeak#10/F13, cc-candybar#4/F10 | tmux-control-mode-js#53: the agent's later `grep -rn createWebContentsSink` should have run with the rename; one rename, 4 findings (F3-F6). |
| J | The fix for a drift finding caused another drift | 10 | cc-candybar#222/F8, links-issue-tracker#387/F24, links-issue-tracker#175/F4, promptctl#9/F5 | Rewording kept the over-claim or added an error. |
| K | A user-facing message or usage text is stale | 6 | copirate-code-review-agent#124/F11, links-issue-tracker#163/F7 | Help, usage and error strings were not searched. |
| L | Prose from a first attempt survived the redo | 6 | links-issue-tracker#498/F18, links-issue-tracker#481/F15, laws#36/F42 | Redo kept the first attempt's doc text. |
| - | Fits no pattern | 2 | links-issue-tracker#413/F23, links-issue-tracker#490/F12 | |

Total: 355.

Patterns B, C, E, G, I, K and L are all "behavior changed and nobody searched for the old description". Together they cover **167 rows**. Pattern A, prose that was wrong when written, is the largest single pattern at **111**.

**Before vs after 2026-08-30.** Raised dates come from `derived/findings.jsonl`. As a share of all copirate findings, the slice was:
- before 08-23: 28/1,903 (1.5%)
- 08-23 to 08-29: 51/963 (5.3%)
- from 08-30: 194/3,283 (5.9%)

Pattern A in the same three windows was 11 (0.6%), 10 (1.0%) and 55 (1.7%).

The jump lines up with copirate #108 on **08-23**, which added the "Comment/code mismatch" check to the review prompt. Reviewer findings labeled "Comment mismatch" went from 10 to 213 to 910 across the three windows. The address-pr-reviews change on 08-30 shows **no drop** in drift caused by fixes. That includes Pattern A, the comments the agent writes, which is what that change was aimed at. What it did change is how the agent fixes a drift finding (next section).

## 2. What current guidance gets right

- **Review prompt, check 8** (`src/prompt.js`: "review every comment against the code it describes"). Premise correct in 338/355 rows; agent's response correct in 344.
- **address-pr-reviews, "A wrong comment is fixed by shrinking it … the replacement is shorter than what it replaced."** The agent deleted or narrowed the stale prose instead of restating it in 25 of the 194 rows from 08-30 on, against 7 of 161 before. This comes from a keyword match on the evidence field. Examples:
  - cc-candybar#195/F16: removed the number instead of correcting it
  - crom#24/F15: dropped the count and added the fourth case
  - textual-js#16/F6: "deleted the count from both files … so it cannot drift again"
- **address-pr-reviews, "Post a comment on the thread stating your plan … on every finding."** Where the agent followed it, the result was correct. 3 of the 4 incorrect rows are `no_response` threads that were closed with no reply (cc-candybar#7/F2, memento#26/F6, openconv#18/F7). That is the rule not being followed, not a gap in it.

## 3. Proposals (ranked by the review rounds they would save)

**P1. address-pr-reviews, step 4, a new paragraph after "Comments stay minimal".** Targets the "nobody searched" group (167 rows: B, C, E, G, I, K, L). Neither address-pr-reviews nor laws:code tells the agent to search for old descriptions. `[LAW:one-source-of-truth]` says "find and use the canonical one", which is about code sources.
> "A fix that changes behavior leaves its old description somewhere. Before committing, search the repo for the old name, value, and mechanism words: comments, README, CLAUDE.md, CHANGELOG, docs, usage and error strings. Rewrite or delete every hit in the same commit."

**P2. address-pr-reviews, step 4, a new paragraph after "A wrong comment is fixed by shrinking it".** Targets Pattern A (111) and Pattern J (10). "Comments stay minimal" tells the agent *whether* to write a comment. Nothing tells it to check what it wrote, and the 08-30 data shows minimal comments still come out false.
> "Every sentence the fix adds is a claim the next round will check against the code. This covers comments, docs, changelog lines, test names and messages. Check each one against the new head before pushing. If you did not check a claim (an 'every', 'only' or 'always', a count, how an outside tool behaves), cut it rather than hedge it."

**P3. laws:code, `[LAW:comments-carry-meaning]`, after the "So a comment dies two deaths" paragraph.** Targets Pattern D (33). laws:code already lists "a count stored next to the list it counts" as WRONG under `[LAW:one-source-of-truth]`. It did not hold because it reads as a rule about data, and agents don't apply it to prose.
> "Prose that counts or lists what the code holds ('the three ways it fails', 'both refs', 'exactly four') is a same-altitude copy and goes stale with the next case. Name the kind of thing, not the number."

**P4. Review action prompt, `src/prompt.js` check 8, after "five comments repeating one stale claim are one finding naming the pattern".** Targets Pattern G (16) and the follow-up rounds where a second review found another copy of the same stale claim:
- cc-candybar#203/F6: the agent fixed 4 more places and still missed the docs table that F10 found
- copirate-code-review-agent#147/F33: the next copy was raised as F38
- copirate-code-review-agent#167/F12: the agent did not act on an earlier outside-diff mention

The current rule tells the reviewer to name the pattern, not where it occurs. Even with the rule in place, 20 of the 25 same-round duplicate findings came after it landed (laws#44/F10, links-issue-tracker#418/F12, openconv#7/F11).
> "For a stale claim, search the repository for every other place that states it, inside or outside the diff, and list each file:line in that one finding."

## 4. Caveats

- Each row has one main pattern, chosen by me. A/J and B/C/E have fuzzy edges, so the subtotals are judgment calls. The combined 167 is more reliable than its parts.
- About 25 rows are the reviewer reporting the same drift twice or three times in one round. They inflate the counts, but they do not add rounds.
- Before/after is confounded by the 08-23 reviewer change and by repo mix (elvenspeak, memento, textual-js, openconv appear only after 08-30).
- Pattern H drops to zero because the reviewer changed, not because the agent improved.
- Pattern F is almost all in one project spec that uses line citations on purpose, with its own citation-check gate (links-issue-tracker#557/F3). So it is not proposed as a laws change.
- The shrink counts (25 vs 7) come from a keyword match on the judges' evidence text, not from reading each diff.
- `install.sh`'s heredoc is workflow YAML with no prompt; the reviewer prompt was read from `copirate-code-review-agent/src/prompt.js` at 80d9ab0.
