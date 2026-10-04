# same_gap_other_instance: which siblings get missed

Slice: 422 rows (66 copilot, 356 copirate). I read every row and gave each one exactly one primary pattern. The tallies cover the whole slice, not a sample. Every row fits a pattern, so 0 rows are left unassigned. Responses: 343 accepted_fix, 47 accepted_premise_different_fix, 12 pushed_back, 11 mixed, 7 no_response, 1 already_fixed. 400 of 422 were judged correct.

## 1. Patterns (counts sum to 422)

| # | Sibling that was missed | Rows | Examples | Mechanism / the search that would have found it |
|---|---|---|---|---|
| B | **The same code shape at another call site, consumer, command, file or implementation** (another `execSync`, another `_ = release()`, another lock user, another `.json()`, another forwarder) | 124 | cc-candybar#4/F14, crom#3/F102, tmux-control-mode-js#9/F1, promptctl#21/F10 | The fix edited only the line the reviewer named. A grep for the expression being fixed, or for the callee or primitive, would have listed every site. |
| A | **The same prose claim in another doc or comment** (CLAUDE.md vs docs/, README vs USAGE or action.yml, CHANGELOG vs code comment, neighbouring docstrings, citations, enum group headers) | 119 | cc-candybar#224/F3, copirate-code-review-agent#107/F32, links-issue-tracker#392/F13, laws#27/F43 | The agent rewrote the quoted sentence. It did not grep the claim's distinctive phrase, so the README, CHANGELOG or test-header copy stayed wrong. |
| F | **A missing member of a hand-maintained set**, found one per round (preflight tools, verb lists, a widget's config dependencies, flag/key/field validation, barrel exports, lenient-decoder defaults) | 46 | laws#35/F37, laws#69/F28, links-issue-tracker#413/F79, cc-candybar#51/F10 | The agent added the member the reviewer named instead of rebuilding the set from its source: the commands the code runs, the table rows, the fields in the struct. |
| H | **The same test gap in another branch, outcome, engine or file** | 28 | crom#32/F18, elvenspeak#59/F9, tinkerpadai-web#44/F9 | The agent pinned the branch the reviewer named. The sibling Broken/catch/reason branches stayed untested. |
| J | **Another fallible step or exit path in the same function** (throw sites, finally/teardown, failure exits, steps after a durable write) | 19 | laws#15/F32, cc-candybar#150/F42, crom#17/F8 | The agent wrapped one call in place. Listing every call between acquire and return would have caught the rest. |
| D | **Another arm of the same switch, union, outcome set or table** | 18 | cc-candybar#22/F7, links-issue-tracker#294/F10, links-issue-tracker#143/F7 | The agent fixed one case and did not walk the others. |
| G | **A helper the fix introduced, applied to only some of its call sites** (old global accessor, old barrel import, unhardened wait loop) | 15 | cc-candybar#146/F3, copirate-code-review-agent#142/F32, tmux-control-mode-js#148/F22 | The fix created the canonical helper but did not grep for the expression the helper replaces. |
| R | **The fix commit's own new code repeats the defect it fixes** | 11 | laws#39/F36, links-issue-tracker#142/F12, laws#36/F37, tinkerpadai-web#56/F14 | The fix commit was not re-read against the rule it had just accepted. |
| S | **Another sink of the same untrusted value** (Markdown, message, URL interpolation) | 10 | copirate-code-review-agent#108/F38, copirate-code-review-agent#108/F48, crom#22/F17 | Sanitizing happened per value. Doing it at the point where the message is assembled closes every sink at once. |
| K | **The same stale number or count in other docs** | 8 | cc-miser#3/F20, links-issue-tracker#387/F22, links-issue-tracker#550/F16 | Nobody grepped for the old number. |
| E | **The other half of a symmetric pair** (encode/decode, client/server, success/error trace, read/write side of a race) | 7 | copirate-code-review-agent#75/F7, laws#46/F15, links-issue-tracker#447/F15 | Only one end of the pair was fixed. |
| C | **The mirror implementation in another runtime, language or parser** | 7 | cc-candybar#4/F24, cc-candybar#148/F10, textual-js#12/F8, laws#27/F51 | The TS fix was not ported to Rust, or the Python fix was not ported to bash. |
| L | **Leftover references to a deleted or renamed name** | 6 | cc-candybar#211/F6, textual-js#12/F12, copirate-code-review-agent#166/F2 | The grep used the literal phrase from the finding, not every name and form of the concept. For example, `.json` vs `input_*.json`. |
| X | **A deferral recorded only on the thread, then re-raised** | 4 | tmux-control-mode-js#154/F11, tmux-control-mode-js#154/F12, tmux-control-mode-js#154/F16 | Nothing in the code marked the ticket, so the next round flagged the same site again. |

These cut across the table (not added to the 422):
- **31 rows are duplicates** of another row in this slice: one gap raised in several threads in the same round. Examples: elvenspeak#32/F15–F20 and cc-candybar#177/F16.
- **35 rows include the agent admitting the miss** in its reply, e.g. "I closed the drift for action.yml and left it open one file over" (copirate-code-review-agent#113/F14).
- **6 rows involve a reviewer who had already named the second location, which the agent dropped**: copirate-code-review-agent#104/F7, copirate-code-review-agent#108/F33, copirate-code-review-agent#130/F27, laws#39/F99, links-issue-tracker#392/F15, links-issue-tracker#119/F51.

## 2. What guidance already gets right

- **laws:code `[LAW:single-enforcer]`**: *"find where the invariant canonically lives; if this isn't it, delete the local check and route through the boundary that is"*. Also **`[LAW:locality-or-seam]`**: *"I'll just update the five call sites … Refuse it … route the five sites through it"*. These produced the best different_fix answers. About 28 of the 47 different_fix rows (counted by keyword match) closed the whole class at one point instead of patching the next instance. Examples:
  - elvenspeak#32/F14: normalised in `Voice.__post_init__`, which closed six threads.
  - copirate-code-review-agent#103/F3: one `parseJsonObject`.
  - laws#36/F10: `HORIZON_BASE_TOOLS`.
  - promptctl#21/F11: a `fireAndReset` helper.
  - crom#33/F7: deleted the enumeration rather than extending it.
- **Reviewer prompt** (copirate-code-review-agent `src/prompt.js`): *"Grep the repository for that symbol's other uses and read those sites before you judge the change safe."* 400/422 premises held up, and only 7 rows were judged `no`.
- **address-pr-reviews step 3**: the `different_fix` class plus "Architectural laws override reviewer authority". This let the agent turn down the reviewer's local patch in favour of the single-point fix in the rows above.

## 3. Proposals (ranked by rounds saved)

**P1. address-pr-reviews, step 3 "Plan phase", after the four-class list.** Addresses B+D+J+E+C+G+S (200 rows).
> Before planning a valid or different_fix finding, name the defect as a searchable shape: the expression or callee you are changing, the other arms of the switch or union, the other implementations of the interface, and the other end of the pair. Grep the repo for that shape. The plan comment lists every hit and says, for each one, fix or why not. A plan that names only the reviewer's line is incomplete.

Why: nothing in the skill tells the agent to look past the flagged line. `[LAW:one-source-of-truth]` ("When you inherit two … demote one") only applies once a second copy is noticed.

**P2. address-pr-reviews, step 4, in the "A wrong comment is fixed by shrinking it" paragraph.** Addresses A+K+L (133 rows).
> A wrong claim rarely lives in one place. Grep the claim's distinctive phrase, the old name, and the old number across code, README, CHANGELOG, docs/ and test headers, and fix every hit in the same commit.

Why: the shrinking rule is about how long the fix is. Nothing in it is about where else the claim lives, and A is the second-largest pattern.

**P3. address-pr-reviews, step 3, inside the `different_fix` bullet.** Addresses F (46 rows), the multi-round chains.
> When a finding says an enumerated set is missing a member (tools, verbs, fields, exports, dependencies), the fix rebuilds the set from what it describes: the commands the code invokes, the table's rows, the struct's fields. Adding only the named member is the next round's finding.

**P4. Reviewer prompt, `src/prompt.js` charter, replacing "flag the clearest instance and note the pattern once".** Addresses the 31 duplicate rows and the serial discovery behind B/A/F.
> Flag the clearest instance and, in that same comment, list every other site with the same defect as `path:line`, so the author can fix them all in one round.

Why: "note the pattern once" gives the agent a description of the pattern but no list of sites. The agent fixes the one anchored line, and later rounds or sweeps re-flag the other sites one at a time.

**P5. address-pr-reviews, step 7 "Confirm phase", before the `Fixed in <sha>` reply.** Addresses R (11) and H (28), plus the 6 rows where the agent dropped a location the reviewer had named.
> Before replying `Fixed`, check off each location the finding named, and re-read this round's own new code and tests against every rule the round accepted. Code written for a fix is where the class most often comes back.

## 4. Caveats

- The brief puts the review prompt in `install.sh`, but `install.sh` only renders the workflow YAML. I took the prompt text from `/Users/bmf/code/copirate-code-review-agent/src/prompt.js`, using the branch checked out at the time, not master.
- The pattern tags are my own single-pass judgments. The B/F/G boundaries are fuzzy (an "other site of a primitive" vs an "unadopted helper"), so read B, F and G as one ~185-row family with soft internal splits.
- The 31 duplicates inflate per-gap counts.
- The 28 single-point different_fix rows, the 35 self-admissions and the 6 reviewer-named rows come from keyword matches over the `evidence` text, checked by eye. They are approximate.
- Several judges noted that the commit the reviewer flagged was not the real cause; the cause was an earlier fix that didn't sweep (e.g. cc-candybar#218/F7, elvenspeak#21/F15). `caused_by` attribution can therefore be off by one fix.
- S, H, K, L and X appear only in the copirate era (356 of 422 rows), so era comparisons are thin.
