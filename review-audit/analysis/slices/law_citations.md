# Inapt law citations (280 rows): how laws get misapplied

Slice: 280 findings where the agent's response cited a `[LAW:*]` and the judge ruled the citation inapt. 175 are copirate-era and 105 copilot-era. I read every row and assigned each one to exactly one pattern. Every row fits a pattern; none are left over.

The headline: 231 of 280 responses were still correct (`correct=yes`). In 161 rows (E1-E4) the token is noise on a decision that was right. The citation costs review rounds in two patterns. In A (26) the law was the argument for a call that was later reversed. In C (25) the citation claimed a property the code did not have, which hid the defect until the reviewer found it.

## 1. Patterns

| # | Pattern | Count | Examples | Mechanism |
|---|---|---|---|---|
| D | The pushback was right (47) or can't be verified (8), but it rests on a fact, the ticket, or scope, with a law token attached | 55 | cc-candybar#141/F2, tinkerpadai-web#57/F20, copirate-code-review-agent#89/F2, tmux-control-mode-js#148/F28 | address-pr-reviews says "Push back and **cite the law**", so the agent attaches one even when the argument is `gh api` output or reachability. single-enforcer (12) and no-mode-explosion (6) stand in for "out of scope". |
| A | The law is the argument for a wrong pushback, deferral or alternative fix, and it is reversed one or more rounds later | 26 (25 `correct=no`) | links-issue-tracker#481/F5, copirate-code-review-agent#144/F3, tmux-control-mode-js#175/F4, promptctl#6/F2, links-issue-tracker#227/F3 | A law's absolute phrasing gets applied outside its scope: "unconditional" refuses a perf conditional, "single source" picks a proxy field, "verifiable" claims a Windows probe can't be written. Each was conceded a round later. |
| C | The citation claims compliance that the code it labels doesn't have | 25 | promptctl#7/F6, copirate-code-review-agent#162/F4, links-issue-tracker#147/F4, promptctl#25/F13, copirate-code-review-agent#142/F25 | `single-enforcer` over a copied rule, `one-source-of-truth` over a hand-copied normalizer, `dataflow` over a new `if`-skip, `no-shared-mutable-globals` over a new module-level `let`. The next round catches it. |
| E1 | A comment, doc or message-wording fix labeled with a structural law | 44 | tmux-control-mode-js#53/F3, openconv#8/F21, elvenspeak#20/F12, links-issue-tracker#499/F5 | Stale names and false claims in prose get labeled one-source-of-truth (17), comments-explain-why-only (9), or polishing-by-subtraction (5, cited "to keep the text short"). |
| E2 | A test fix (missing case, wrong fixture, selector) labeled behavior-not-structure or something else | 23 | openconv#28/F19, tmux-control-mode-js#175/F5, copirate-code-review-agent#157/F4, links-issue-tracker#119/F5 | 14 of the 23 cite behavior-not-structure, which the reviewer prompt attaches to every missing-test finding (see proposal 4). |
| E3 | An error, resource or lifecycle bug labeled with a neighbouring law | 25 | cc-candybar#4/F1, links-issue-tracker#119/F7, copirate-code-review-agent#77/F2, crowdshipai-web#10/F4 | An empty `catch {}` gets labeled no-defensive-null-guards or single-enforcer. A temp-dir leak, a thrown TypeError, or a stale value gets labeled no-silent-failure (7). |
| E4 | Any other correct code fix (ordering, perf, string matching, value ranges, cross-runtime parity) with a decorative token | 69 | links-issue-tracker#147/F1, links-issue-tracker#150/F19, cc-candybar#159/F6, tinkerpadai-web#26/F18 | Mostly the two broadest laws: dataflow-not-control-flow (17, mostly step reorderings) and types-are-the-program (13, value-level bugs with no type change). |
| B | Accepted a wrong-premise finding or applied an incomplete fix; the label played no part | 13 (all `correct=no`) | tinkerpadai-web#45/F12, cc-candybar#202/F7, links-issue-tracker#163/F3, tinkerpadai-web#27/F62 | Wrong accepts that happen to carry a token. |

Total: 55+26+25+44+23+25+69+13 = 280.

**Echo.** In at least 44 rows (43 of them copirate-era) the agent cited the same token the reviewer had tagged on the finding. That is a floor, because the finding text is truncated. Many E-pattern inapt tokens start with the reviewer.

**Where the law text invites the misreading** (counts are that law's rows across all patterns):
- **one-source-of-truth (56):** cited for stale comments (E1 17) and for "consistent with sibling code" (D 13). comments-carry-meaning calls a same-altitude echo "a divergent second copy" and labels itself an "Instance of `[LAW:one-source-of-truth]`", which invites the stale-comment reading.
- **single-enforcer (40):** "Any cross-cutting invariant" gets read as "anything one place should own": a template owning a file, one `close()` site, call ordering. 5 C rows cite it over a duplicated check.
- **dataflow-not-control-flow (38):** "the same operations execute in the same order" pulls in ordering fixes (E4 17). "Side effects are unconditional" backs refusals that were later reversed (A 6).
- **types-are-the-program (27):** "Every law below is an instance of this one" makes it the catch-all for value-level bugs (E4 13).
- **behavior-not-structure (20):** there is no token for missing coverage, and the reviewer prompt uses this one for it.
- **no-silent-failure (19):** cited for errors that were already loud and for leaks (E3 7).

**Tokens not in the current SKILL.md:** `comments-explain-why-only` appears in 10 rows (7 copilot, 3 copirate). It was the real token until commit 48b8f67 (2026-07-17), so these are stale, not invented. `no-silent-fallbacks` (3, copilot) was never a token. It matches address-pr-reviews' prose list "silent fallbacks". `enumeration-gap` (2) is a skill name, not a law. The reviewer itself minted `[LAW:correctness]` (tmux-control-mode-js#83/F1). The brief's `no-error-swallowing` and `representation` do not occur in this slice.

## 2. What guidance already gets right

- **Verifying the reviewer before obeying.** address-pr-reviews, step 3: "**invalid** — reviewer is wrong". 47 of the 55 D pushbacks were right, decided by a check the agent ran, e.g. `gh api .../releases` refuting "checkout@v6 doesn't exist" (cc-candybar#141/F2, tmux-control-mode-js#75/F2).
- **no-silent-failure in substance.** laws:code: "Errors surface loudly." The agent refused silent catches even under the wrong token: tmux-control-mode-js#59/F16, cc-candybar#4/F1, links-issue-tracker#106/F2. E3 is 25/25 correct.
- **The decision rarely depends on the token.** E1-E4 are 161/161 correct.

## 3. Proposals (ranked by rounds saved)

1. **laws:code, "How to cite the laws", after "Never invent a new token; ... an instance of an existing law that you haven't recognized yet."** Addresses A (26) and C (25). That sentence, together with "When a law influences any decision, you MUST cite it", pushes the agent to force-fit a token. Proposed wording: *"A citation is a checkable claim about the line it sits on: ask that law's Diagnostic of this code, and it must come back clean. If the decision rests on a fact, a spec, a ticket or an ordering bug, no law decided it — state the fact and write no token."*

2. **address-pr-reviews, step 3 `invalid` bullet ("Push back and **cite the law**"), and the matching phrases at "State why (cite the law for `invalid`)" and in Principles ("Cite the law in the pushback reply").** Addresses D (55) and the 11 A rows that were wrong pushbacks (e.g. links-issue-tracker#390/F14, copirate-code-review-agent#147/F19). Proposed wording: *"Push back with the evidence that settles it — command output, file:line, the spec. Cite a law only when the suggestion itself violates that law; a reviewer who is simply wrong about a fact gets the fact, not a token."*

3. **laws:code, `[LAW:dataflow-not-control-flow]`, after its Diagnostic.** Addresses dataflow rows in A (6) and C (8), and the ordering mislabels in E4. Proposed wording: *"This law asks whether the set of operations depends on the input. It does not say which order a fixed sequence should run in, and it never obliges you to keep an operation no input needs — deleting work is not a branch, and gating an expensive read behind a variant the type already carries is that variant's own arm."*

4. **address-pr-reviews, "A wrong comment is fixed by shrinking it. [LAW:polishing-by-subtraction]".** Addresses cc-candybar#227/F3, where the agent deleted an overclaiming comment instead of fixing the behaviour and the gap survived, and laws#15/F17, where it changed "a couple of scenarios" to "one scenario" and the finding came back as F22. Also covers 5 E1 rows that cite polishing just for brevity. Proposed wording: *"First decide which side is wrong. If the comment states what the code should do, fix the code; shrink only a comment whose code is already right."*

5. **Reviewer prompt (`promptctl/copirate-code-review-agent` `src/prompt.js`), item 9 and the body-tag rule.** Addresses E2 (14 behavior-not-structure rows) and the 44+ echo rows. Item 9 tags every missing-test finding `[LAW:behavior-not-structure]`. Proposed wording: *"9. Missing tests for risky logic — new non-trivial behavior with no test over its failure modes (no law token). A test that asserts implementation instead of behavior is [LAW:behavior-not-structure]."* Add to the tag rule: *"Use a [LAW:token] only when the finding is that law's violation; a bug takes a kind tag."*

## 4. Caveats

- The judges and the law text disagree about stale comments. The judges ruled one-source-of-truth inapt for them (17 E1 rows), but laws:code's comments-carry-meaning calls a same-altitude echo "a divergent second copy" of the code. Some of those rows are arguably apt.
- The echo count (44) is a floor, because `finding` is truncated.
- The line between C and E (a false claim vs. decoration) is my judgment from each row's `evidence`. A few evidence strings are truncated (e.g. promptctl#6/F3, cc-candybar#33/F1).
- Every row in the slice was selected for `cite_apt=no`. The ~2,229 apt citations weren't visible, so section 2 can't credit citations that worked.
- The reviewer prompt is no longer in install.sh, which only references `promptctl/copirate-code-review-agent@v1`. The prompt is in that repo's `src/prompt.js` (origin/main).
