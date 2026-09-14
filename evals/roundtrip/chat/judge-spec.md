## Fidelity (scored)

### Response A
- Missing: none. Every given fact appears (job, test, error, commit and time, httpx default change, 200 MB file to throttled server, the `timeout=None` fix, 14 passing tests, not pushed / CI not run, production not checked and uses the same client, rest of suite not run for lack of credentials).
- Misstated: none.
- Added:
  - "check whether production uploads have been timing out since the httpx 0.28 deploy" — asserts that httpx 0.28 has been deployed to production. The task does not establish any deploy.
- Not counted: "hypothesis: slow production uploads could hit the same 5-second chunk timeout" is labeled as a hypothesis and fits the given facts.

`missing: 0, misstated: 0, added: 1`

### Response B
- Missing: none.
- Misstated: none.
- Added: none.
- Not counted: "CI is still red" follows from the facts (nothing pushed since the failure started). "if it's on httpx 0.28, large or slow uploads could be hitting the same 5-second chunk timeout" is conditional and fits the facts. "whether production has deployed the httpx bump" is posed as a question, not asserted.

`missing: 0, misstated: 0, added: 0`

### Response C
- Missing: none.
- Misstated:
  - "so each chunk now takes longer than 5 seconds and times out" — the task says "chunks now time out". It does not say that every chunk exceeds the limit.
- Added: none.
- Not counted: "yesterday's deploy of `a41c9e2`, if it has been deployed" is hedged. "My guess, which I haven't tested, is that large production uploads over slow links could hit the same 5-second chunk timeout" is labeled as a guess.

`missing: 0, misstated: 1, added: 0`

## Rubric

| # | Requirement | A | B | C |
|---|---|---|---|---|
| 1 | Say each thing once | met | not met | not met |
| 2 | Concrete examples, at most one metaphor | met | met | met |
| 3 | Label claim status | met | not met | met |
| 4 | Assert only what you would stake something on | not met | met | not met |
| 5 | Revise law-sounding sentences | met | met | met |
| 6 | Proposal states abstract idea and concrete effect | not met | not met | met |
| 7 | Length tracks information, no drama | met | met | met |
| 8 | Lead with the answer | met | met | met |

Counts: A — met 6, not met 2, n/a 0. B — met 5, not met 3, n/a 0. C — met 6, not met 2, n/a 0.

Failures:
- A, #4: "check whether production uploads have been timing out since the httpx 0.28 deploy" states that a deploy happened, which is not established.
- A, #6: "Separately, check whether production uploads have been timing out since the httpx 0.28 deploy." The check is proposed without saying what its result would change or decide.
- B, #1: The opening says "I have a fix, but it's only on my machine so far." Line 10 repeats it: "I haven't pushed the change, so CI hasn't run on it. CI is still red." The production bullet also says the same thing twice: "I haven't checked production ... I haven't confirmed that either way."
- B, #3: The "**Why:**" section never says whether the httpx cause was verified or inferred. "it's worth checking whether production has deployed the httpx bump" is an unlabeled opinion.
- B, #6: "it's worth checking whether production has deployed the httpx bump" gives no concrete effect of the check.
- C, #1: The opening "I have a fix that passes locally, but I haven't pushed it" is repeated in "CI hasn't run on the change, because it isn't pushed." The production bullet also doubles up: "I didn't check ... My guess, which I haven't tested".
- C, #4: "each chunk now takes longer than 5 seconds and times out" goes further than the given facts support.

## Ranking
1. A — It labels each claim's status most clearly and says each point once, but it slips in one unestablished claim about a production deploy.
2. C — It is faithful except for a small overstatement ("each chunk"), labels its guess and proposal, and says what the production check would tell the user, but it repeats the not-pushed point.
3. B — It has perfect fidelity, but it never labels which claims were checked, repeats the not-fixed status, and leaves its production suggestion as an unlabeled opinion with no stated effect.

## Totals
- A: missing 0, misstated 0, added 1; rubric met 6, not met 2, n/a 0
- B: missing 0, misstated 0, added 0; rubric met 5, not met 3, n/a 0
- C: missing 0, misstated 1, added 0; rubric met 6, not met 2, n/a 0
