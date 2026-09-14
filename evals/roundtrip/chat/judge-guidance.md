## Fidelity (scored)

**Response A**
- Missing: none. Every given fact appears (failing job, test and error, commit and merge time, httpx 0.28 timeout change, 200 MB throttled upload, `timeout=None` in `src/uploader/client.py`, 14 tests passing locally, not pushed, CI not run, production not checked and uses the same client, rest of suite not run for lack of credentials).
- Misstated: none.
- Added:
  - "check whether production uploads have been timing out since the httpx 0.28 deploy" - asserts that httpx 0.28 has been deployed to production. The task only establishes a merge, not a deploy.
- The labeled "hypothesis: slow production uploads could hit the same 5-second chunk timeout" is framed as unverified reasoning from the given facts and is not counted.

`missing: 0, misstated: 0, added: 1`

**Response B**
- Missing: none.
- Misstated: none.
- Added: none. "CI is still red" follows from the user's report plus the unpushed fix. "chunks now take longer than 5 seconds" illustrates the given "chunks now time out". Production is handled conditionally: "if it's on httpx 0.28, large or slow uploads could be hitting the same 5-second chunk timeout. I haven't confirmed that either way." "worth checking whether production has deployed the httpx bump" asserts nothing.

`missing: 0, misstated: 0, added: 0`

**Response C**
- Missing: none.
- Misstated: none.
- Added: none. The deploy is conditional: "since yesterday's deploy of `a41c9e2`, if it has been deployed". The production claim is labeled: "My guess, which I haven't tested, is that large production uploads over slow links could hit the same 5-second chunk timeout." "each chunk now takes longer than 5 seconds" illustrates the given fact.

`missing: 0, misstated: 0, added: 0`

## Rubric

Rules the standard asks of a finished reply:

1. Say each thing once, in plain words (no repetition for emphasis).
2. Use concrete examples instead of metaphors (at most one metaphor).
3. Label each claim's status (verified, user-reported, proposal, hypothesis, opinion).
4. Assert only what you would stake something on; write the narrower true version.
5. When proposing, give the abstract idea plus its concrete effect on the artifact.
6. Length tracks information; no drama, stakes-language, or register tricks.
7. Lead with the answer; explanation follows.

| Rule | A | B | C |
|---|---|---|---|
| 1. Say once, plain | met | not met | met |
| 2. Concrete, not metaphor | met | met | met |
| 3. Label claim status | met | not met | not met |
| 4. Assert only what you'd stake | not met | met | met |
| 5. Proposal plus concrete effect | met | met | met |
| 6. No drama / length tracks info | met | met | met |
| 7. Lead with the answer | met | met | met |

Counts: A met 6, not met 1, n/a 0. B met 5, not met 2, n/a 0. C met 6, not met 1, n/a 0.

Failures:
- A, rule 4: "check whether production uploads have been timing out since the httpx 0.28 deploy" states a deploy as fact when nothing establishes one.
- B, rule 1: the unpushed state comes up three times: "it's only on my machine so far", then "I haven't pushed the change, so CI hasn't run on it. CI is still red." The production point is also said twice: "I haven't checked production." ... "I haven't confirmed that either way."
- B, rule 3: nothing marks the diagnosis as verified or not ("**Why:** httpx 0.28 changed the default timeout for streamed uploads."), and "it's worth checking whether production has deployed the httpx bump" is an unlabeled opinion.
- C, rule 3: the diagnosis sections carry no status label, so the reader can't tell whether they were verified: "What happened: `test-integration` began failing at `a41c9e2`..." and "The cause: httpx 0.28 changed the default timeout...". The later guess and proposal are labeled.

## Ranking

1. C - it has no fidelity errors, labels the production guess and proposal explicitly, and tells the user what the production check would decide ("only a test failure or a live bug"). Its only miss is the unlabeled diagnosis.
2. A - it has the clearest status labeling of the three ("verified", "verified locally", "hypothesis", "Proposal"), but it asserts a production deploy the facts don't establish.
3. B - it is faithful to the facts, but it repeats the not-pushed and not-checked points and never marks which claims are verified.

## Totals

- A: missing 0, misstated 0, added 1; rubric met 6, not met 1, n/a 0
- B: missing 0, misstated 0, added 0; rubric met 5, not met 2, n/a 0
- C: missing 0, misstated 0, added 0; rubric met 6, not met 1, n/a 0
