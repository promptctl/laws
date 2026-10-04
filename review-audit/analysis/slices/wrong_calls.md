# Wrong calls (472 rows, correct = "no")

Every row was read and given one label. Tallies are over the full slice, not a sample. 30 rows fit no pattern. "fc" = rows that are fix-caused second-round findings (101 in the slice).

## 1. Patterns

**no_response (242)**

| Pattern | n | fc | Examples | Mechanism |
|---|---|---|---|---|
| NR1 Review posted after merge (row states timing) | 54 | 5 | laws#29/F5, links-issue-tracker#443/F1, links-issue-tracker#375/F1, cc-candybar#229/F9 | Merged seconds to minutes after open or after the last push. cc-candybar#229: the reply named a held, never-pushed commit. |
| NR1b Same PR as an NR1 row (**inferred** timing) | 48 | 0 | cc-candybar#6/F2, laws#29/F1, links-issue-tracker#54/F2 | Row only says "no reply". |
| NR2 PR closed/recut; threads not carried over | 10 | 3 | cc-candybar#1/F2, links-issue-tracker#66/F1, links-issue-tracker#99/F1 | Code moved to a new PR, findings dropped. |
| NR3 Thread resolved silently, no change | 32 | 4 | memento#20/F2, links-issue-tracker#446/F3, links-issue-tracker#554/F2 | memento#20/F2 returned as F13. |
| NR4 Merged over an open unanswered thread | 14 | 1 | copirate-code-review-agent#46/F2, copirate-code-review-agent#112/F1, memento#10/F1 | CHANGES_REQUESTED still standing. |
| NR5 Repeat of an earlier unanswered finding | 25 | 7 | cc-candybar#10/F19, links-issue-tracker#55/F4, links-issue-tracker#554/F13 | One silence bought 2-4 more rounds or a re-shipped bug. |
| NR6 Same-round duplicate | 10 | 1 | copirate-code-review-agent#112/F3, links-issue-tracker#36/F5 | Reviewer restated itself. |
| NR7 Needed only a one-line rejection | 9 | 1 | copirate-code-review-agent#5/F14, links-issue-tracker#58/F2 | Premise wrong; silence left it open. |
| NR8 Outdated after a push, never answered | 7 | 0 | links-issue-tracker#37/F1, links-issue-tracker#38/F2 | Outdated read as answered; code unchanged. |
| NR9 Fixed in code, thread never answered | 4 | 2 | memento#26/F2, memento#26/F3 | No record. |

Unpatterned: 29 (e.g. cc-candybar#7/F1). 38 of the 242 needed a pushback, not a fix.

**pushed_back (95)**

| Pattern | n | Examples | Mechanism |
|---|---|---|---|
| PB1 Pushback rests on a claim the diff, the code, or installed docs contradict | 36 | links-issue-tracker#100/F2, links-issue-tracker#119/F47, cc-candybar#22/F18, laws#39/F61 | Read `-` lines instead of `+`. Grepped the wrong symbol. Said `!` throws at runtime. Called a Bun default unverifiable with bun-types installed. links-issue-tracker#119 pasted one wrong reply 8 times. |
| PB2 Agent reversed its own pushback or deferral a round later, same facts | 26 | tmux-control-mode-js#148/F34, links-issue-tracker#549/F2, tmux-control-mode-js#175/F4, copirate-code-review-agent#117/F1 | "Not re-litigating", then conceding. |
| PB3 Right call, but the reason lived only in the thread | 12 | cc-candybar#146/F11, tmux-control-mode-js#148/F45, tmux-control-mode-js#25/F9 | Accepted races and deliberate breaks re-raised up to 5 times. |
| PB4 Cheap in-PR fix or test deferred (no ticket, or the ticket was too narrow) | 10 | elvenspeak#61/F3, laws#69/F31, cc-candybar#22/F11 | Scope used as the reason. |
| PB5 One-word rejection | 6 | go-template-js#2/F4, links-issue-tracker#102/F9 | Copilot era. |
| PB6 Answered one half of a two-part finding | 4 | links-issue-tracker#33/F7, cc-candybar#22/F9 | The other half returned (links-issue-tracker#34/F1). |

Unpatterned: 1 (links-issue-tracker#98/F2).

**accepted_fix (52)**

| Pattern | n | Examples | Mechanism |
|---|---|---|---|
| AF1 Accepted a false premise without the refuting check | 17 | tmux-control-mode-js#73/F1, laws#1/F1, links-issue-tracker#134/F5, links-issue-tracker#8/F4 | Includes `checkout@v6` "does not exist". In links-issue-tracker#134/F5 the agent's own reply refuted the premise. |
| AF2 Applied a change the finding itself called harmless | 8 | tmux-control-mode-js#148/F24, tinkerpadai-web#27/F60, memento#16/F14 | Ties accepted. |
| AF3 Applied the reviewer's cure verbatim; the cure drew the next finding | 24 | tmux-control-mode-js#154/F13, links-issue-tracker#418/F1, cc-candybar#202/F7, links-issue-tracker#227/F7 | Diagnosis right, cure not traced. tmux-control-mode-js#154/F13's value guard led to 7 more findings. |
| AF4 Accepted a guard on a boundary it refused elsewhere | 2 | tmux-control-mode-js#174/F48 | Inconsistent position. |

**accepted_premise_different_fix / mixed / already_fixed (37 / 33 / 13)**

| Pattern | n | fc | Examples | Mechanism |
|---|---|---|---|---|
| X1 Fix covered some of the named instances or conjuncts | 28 | 15 | memento#11/F27, links-issue-tracker#513/F5, links-issue-tracker#144/F66, laws#39/F99 | The finding listed N sites, or A and B; the commit did one. |
| X2 Named structural cure swapped for a comment, wording, or narrower edit | 20 | 1 | cc-candybar#133/F3, laws#15/F17, links-issue-tracker#227/F3, promptctl#25/F14 | Later replaced by the reviewer's cure. |
| X3 "Fixed in <sha>" / "Verified" / "already fixed" that the cited commit or PR head does not support | 18 | 10 | cc-candybar#10/F10, links-issue-tracker#144/F4, copirate-code-review-agent#75/F13, links-issue-tracker#100/F4 | Templates pasted across threads. cc-candybar#10 was verified against another branch. |
| X4 Over-built fix, later deleted | 7 | 1 | laws#34/F4, tmux-control-mode-js#28/F1 | Threat model unchecked. |
| X5 Thread argued both sides | 11 | 2 | openconv#9/F2, laws#36/F18, memento#15/F2 | A plan was posted before the premise was settled, then retracted. |

Cross-cut: in 39 rows the judge called the cited law inapt (e.g. links-issue-tracker#134/F8).

## 2. What guidance already gets right

- **The review prompt dedupes within a round.** `src/prompt.js`: "One comment per distinct issue — flag the clearest instance and note the pattern once". That would remove about 23 same-round duplicates (NR6; cc-candybar#22/F19-F23; links-issue-tracker#375/F6-F11; laws#29/F8-F10).
- **The installer excludes build output.** `install.sh` `BASELINE_EXCLUDES` includes `dist/**`. That removes the 5 dist copies in copirate-code-review-agent#5 (F6, F8, F10, F13, F15).
- **The review prompt has no advisory tier.** "There is no advisory tier". 85 rows were tagged Advisory; 27 of them got no response.
- **The review prompt forwards prior pushbacks.** "If a reply soundly shows the finding was wrong … do NOT record that same point again". This targets PB3 re-raises (tmux-control-mode-js#148/F17).
- **The review prompt bans naming findings.** "do not request changes for style, naming preference". That kills copirate-code-review-agent#5/F9 and F10.
- **address-pr-reviews treats only an empty fetch as done.** "this empty `fetch` is the **only** thing that establishes done". PB2 (26) and X1 (28) were caught by the next round before merge, at the cost of one round each.

## 3. Proposals (all address-pr-reviews, ranked by rounds saved)

1. **§3 Plan phase, after the classification list.** Covers PB1 + PB2 + AF1 = 79 rows. The current text, "Push back and **cite the law**", asks for a law but not for evidence. Proposed wording:
   > "Every plan comment states its evidence. For valid or different_fix: the `+` line, or the command output, that produces the named failure. For invalid: the `+` line, test, or output showing it cannot occur. A law citation is not evidence; run the check before classifying."

2. **§3 plan comment and §7 reply.** Covers X1 + X2 + PB6 = 52 rows (15 fix-caused). Proposed wording:
   > "When a finding names several sites, instances, or a conjunction of checks, the plan lists each one with its disposition, and the 'Fixed in' reply maps each to the diff. Replacing a named structural cure with a comment edit is a decline and states its reason."

3. **§7, before the `Fixed in <sha>` example.** Covers X3 = 18 rows. Proposed wording:
   > "Before 'Fixed in <sha>' or already_fixed, confirm `git merge-base --is-ancestor <sha> $(gh pr view --json headRefOid -q .headRefOid)` and that the sha's diff touches the finding's lines. Never reuse one thread's reply on another."

4. **§4 "Comments stay minimal".** Covers PB3 = 12 rows. Two current lines keep the decision in the thread only: "Not … the reasoning you already posted on the thread" and "that text is the durable record". Proposed wording:
   > "Exception: when you decline a finding and the code will look wrong to the next reader (an accepted race window, a deliberately narrow type, an intended public break), put the one-line reason at the site, or a CHANGELOG entry for a break. The thread is gone after merge."

5. **Rules, and Finalize step A.** Covers NR1 + NR4 = 68 stated rows, plus 48 inferred. It saves few rounds but stops unread findings shipping; links-issue-tracker PRs 54, 55 and 56 re-shipped 3 bugs. Proposed wording:
   > "No route merges a PR with an installed reviewer until `provider.wait` has returned for the head SHA and `fetch` is empty, including merges issued outside this skill."

## 4. Caveats

- NR1 timing comes from judge prose. NR1b is a PR-level inference.
- Copilot-era rows (230) cannot be dated against the skill text in force at the time. NR3 already breaks the existing rule "Plan on every thread before you touch code".
- 63 rows' evidence overrides an automated caused-by flag. The judges re-derived `cause_kind` with varying strictness.
- PB1 and PB2 overlap. A row went to PB1 when its evidence names the contradicting line.
- The review prompt is not in `install.sh`, which renders only the workflow. It is in `copirate-code-review-agent/src/prompt.js`, read at 80d9ab0.
