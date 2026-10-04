# Slice: findings caused by an earlier fix (512 rows)

The slice has two kinds of row:
- `regression_from_fix` (R): 321 rows. The fix broke something that worked.
- `new_scope` (N): 191 rows. The fix added code that had its own defect.

By reviewer, 398 rows are copirate and 114 are copilot.

**Method.** All 512 rows read and hand-labelled, one label each; counts are whole-slice, not sampled.

## 1. Patterns

| # | Pattern / mechanism | Total | R | N | Examples |
|---|---|---|---|---|---|
| H | **The fix's new code shipped a failure mode of its own.** Examples: a catch-all catch, a throw after `mkdtemp` with no cleanup, a temp file with no cleanup arm, an untrusted field used as a path or markup. The new path lacked the hardening its neighbours have. | 80 | 48 | 32 | cc-candybar#146/F13, copirate-code-review-agent#131/F6, laws#35/F32, links-issue-tracker#144/F101 |
| I | **The reviewer found something low-value, or with a wrong premise, in the fix's lines.** 41 pushed back; 13 accepted a nit that should have been declined. | 70 | 4 | 66 | cc-candybar#197/F14, laws#25/F14, tmux-control-mode-js#148/F59, tinkerpadai-web#52/F7 |
| E | **The fix added a defective test.** Examples: env var or spy not restored, a leaked temp dir, a tautological assertion, a pass by coincidence, `chmod 000` under a CI runner that runs as root. | 54 | 23 | 31 | cc-candybar#15/F3, cc-miser#3/F17, elvenspeak#38/F5, crom#3/F99 |
| F | **The fix wrote false prose.** Examples: an error message naming the wrong mechanism, an absolute claim ("never", "the only"), an export notation in docs that doesn't exist. | 52 | 22 | 30 | cc-candybar#67/F3, links-issue-tracker#392/F20, tmux-control-mode-js#39/F6, laws#36/F27 |
| A | **The fix replaced, inlined or rewrote code and dropped a guarantee the old code gave.** Examples: switching from `Unmarshal` to `Decoder.Decode` lost the trailing-data rejection; inlining `RankAbove` lost the smoothing step; a delegate lost the timeout; a `settled` guard was removed. | 48 | 46 | 2 | links-issue-tracker#394/F11, links-issue-tracker#56/F2, cc-candybar#171/F12, cc-candybar#16/F5 |
| C | **The fix widened or narrowed what a matcher, predicate or parser accepts without listing the affected inputs.** Examples: a substring or suffix match, `[[:punct:]]`, an ancestor walk, a marker credited anywhere in the transcript. | 47 | 46 | 1 | cc-candybar#16/F6, copirate-code-review-agent#93/F14, laws#15/F24, memento#11/F24 |
| B | **The fix changed a shared function's contract and didn't re-check its other callers.** Examples: the function now rejects or throws, a None meaning changed, a constructor gained a side effect, a predicate became tri-state. | 42 | 42 | 0 | cc-candybar#218/F16, cc-candybar#221/F30, cc-candybar#24/F14, copirate-code-review-agent#147/F18 |
| G | **The fix restated a fact or helper that already has an owner.** Examples: a literal constant, a key format, a unit conversion, a second helper. | 30 | 13 | 17 | cc-candybar#197/F18, cc-candybar#187/F4, copirate-code-review-agent#124/F16, elvenspeak#20/F18 |
| D | **The fix moved or reordered code and broke an order, lock or lifecycle invariant.** Examples: work moved out of a lock, a `die` placed after a `mkdir`, a mutation hoisted ahead of a call that can throw. | 30 | 29 | 1 | links-issue-tracker#444/F14, laws#49/F36, cc-candybar#199/F10, laws#39/F45 |
| K | **The fix turned a narrow concern into a blanket rule.** Examples: every field marked optional, every option rejects an empty value, `ParseState` coerces all input, a hardened gate denies a routine command. | 21 | 21 | 0 | links-issue-tracker#100/F9, copirate-code-review-agent#131/F7, cc-candybar#3/F8, laws#34/F9 |
| T | **A new signature accepts more than the code honors.** Examples: an ignored option on a shared options type, `handlerFor(env)` that ignores `env`. | 14 | 3 | 11 | cc-candybar#221/F37, tinkerpadai-web#27/F27, tinkerpadai-web#36/F9 |
| Z | **An empty, zero or null case newly became reachable and is mishandled.** Examples: "0 of 0 exact", `[].some()`, `all()` over an empty input, an off-by-one at a cap. | 13 | 13 | 0 | cc-miser#3/F6, copirate-code-review-agent#112/F2, laws#34/F14, links-issue-tracker#150/F27 |
| J | **A revert or redo of an earlier fix brought back a defect** that an earlier round had already settled. | 8 | 8 | 0 | links-issue-tracker#61/F3, links-issue-tracker#498/F24, links-issue-tracker#552/F19 |
| X | **Commit hygiene.** `git add -A` swept in a stray edit, or a formatter rewrote unrelated code. | 3 | 3 | 0 | copirate-code-review-agent#142/F39, links-issue-tracker#150/F9 |

The rows sum to 512.

**Was the fix larger than the finding asked?** Usually not.
- Only K (21) and part of J show a fix that went beyond the finding.
- The large R groups (A, B, C, D, Z: 180 rows, 176 of them R) are fixes of the right size. They broke things because nobody checked what depended on the changed code: what the deleted code guaranteed, the other callers, and the inputs newly admitted.
- In N, the defects sit in what the fix added around itself: tests (E), prose (F) and error paths (H).

**Fixes cluster.** 30 earlier findings account for 117 rows. For example, links-issue-tracker#100/F7-F13 all trace to one fix. 67 rows restate a defect already reported in the same slice; 34 of those are in the current `[S1-5]` format.

## 2. What guidance already gets right

- **address-pr-reviews §3 `different_fix`.** The text reads: "reviewer identified a real issue but proposed the wrong fix; a better fix is coming". 76 rows took this path and 71 were judged correct. Examples: cc-candybar#202/F11 (switched to lstat instead of adding depth caps), cc-candybar#221/F20 (the registry owns an AbortController instead of a shorter sleep), links-issue-tracker#521/F14, crom#22/F8.
- **address-pr-reviews: "invalid — … Push back" and "Architectural laws override reviewer authority."** 45 of 65 pushbacks were correct: 42 of 53 under copirate, against 3 of 12 under copilot. Winners carried a measurement or repro: cc-candybar#197/F14, crowdshipai-web#10/F16, textual-js#17/F17.
- **Review prompt, hunt item 3: "Breakage & regressions — a broken caller, … a default that shifts under existing callers".** The A, B and D rows show the reviewer catching these regressions with concrete repros. 132 of 154 law citations in the slice were judged apt.

## 3. Proposals, ranked by rounds saved

1. **Patterns A + B + D (120 rows, 117 of them R).** Add to address-pr-reviews §4 "Implement the planned changes", after its first sentence:
   > "When a fix replaces, inlines, moves, or changes the contract of existing code (what it returns, throws, accepts, or when it runs), the plan comment first lists what the old code guaranteed (errors it classified, guards, side effects, its empty-input result, the lock or order it ran under) and every caller of the changed function; the fix keeps each, or says which it drops and why."

2. **Patterns C + Z (60 rows).** Add to address-pr-reviews §4:
   > "When a fix widens or narrows what a predicate, matcher, parser, or gate accepts, the same commit adds a test for one input it newly admits that must still be refused, one legitimate input it must still accept, and the empty input."
3. **Pattern E (54 rows).** Add to address-pr-reviews §4:
   > "A test written for a fix is new code under review: copy its file's existing setup/teardown idiom (env, spies, temp dirs, subprocess timeouts) and confirm it fails with the fix reverted."

   laws:code `[LAW:behavior-not-structure]` covers tests coupled to structure. It does not cover tests that pass vacuously or leak state.
4. **Pattern F (52 rows).** address-pr-reviews §4 already says "the comment you write to prove alignment is the next round's divergence finding" and "A wrong comment is fixed by shrinking it". It didn't hold here because it scopes to code comments, and most F rows are error messages and docs (cc-candybar#67/F3, tmux-control-mode-js#39/F6). Extend that paragraph:
   > "The same holds for error messages and docs a fix writes: each mechanism or absolute ('only', 'never', 'exactly') they state is checked against the code before the push, or cut."
5. **Pattern K (21 rows, 7 of them from one fix, e.g. links-issue-tracker#100/F9).** Add to address-pr-reviews §3, under `different_fix`:
   > "If the fix generalizes the finding (every field, every option, every mode, repo-wide), the plan comment names one legitimate input the general rule now refuses or silences — or narrows the fix to the finding's case."

The review prompt gets no proposal. It already says "There is no advisory tier", rules out "speculative 'might one day'" findings, and asks for "One comment per distinct issue". 42 of the 70 I rows use the older `Advisory (non-blocking)` format, which predates that text. The 34 restated findings in the current format fit the multi-scope instruction "Overlapping findings are de-duplicated downstream". That points at the dedupe code, not the prompt.

## 4. Caveats

- One annotator labelled every row in a single pass from truncated text. The boundaries between A, B and D are soft, and H is the broadest bucket.
- The 67-row restatement count comes from a regex over the evidence field. I saw at least 2 false positives.
- Judges sometimes re-attributed `caused_by` away from the commit the reviewer flagged (cc-candybar#8/F12, promptctl#1/F9), so the cause links are judgment calls.
- Bursts weight the counts. A single fix (links-issue-tracker#394/F11 and its five repeats) puts 6 rows in A.
- In 25 of the 70 I rows the premise was judged wrong, so "correct" there depends on the judge re-checking the reviewer's claim.
