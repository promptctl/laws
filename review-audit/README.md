# review-audit

Tools for auditing how the coding agent responded to automated PR review across the
promptctl org: what the reviewers raised, what the agent did about it, whether that
was the right call, and how often a fix made in one review round caused a finding in
the next. The output feeds guidance changes to `laws:code` and `address-pr-reviews`.

## Pipeline

Each stage is a pure function of the previous stage's files; only `fetch.py` talks
to GitHub.

```
fetch.py   GitHub GraphQL  ->  data/<repo>/<number>.json     one file per PR, cached on updatedAt
shape.py   data/           ->  derived/{prs,findings}.jsonl  one row per PR and per reviewer finding
bundle.py  derived/        ->  bundles/<repo>/<number>.md    one markdown packet per PR + batches.json
           (reviewing agents read a batch under prompts/classify.md and write verdicts/<batch>.jsonl)
report.py  derived/ + verdicts/  ->  aggregate tables + derived/joined.jsonl
```

```sh
review-audit/fetch.py  --org promptctl --out review-audit/data
review-audit/shape.py  --data review-audit/data --out review-audit/derived
review-audit/bundle.py --derived review-audit/derived --out review-audit/bundles
review-audit/report.py --derived review-audit/derived --verdicts review-audit/verdicts
```

`data/` is gitignored: it is large and reproducible. Re-running `fetch.py` refetches
only PRs whose `updatedAt` changed; `--refresh` refetches everything.

## What a finding row carries

A finding is a review thread whose first comment is by someone other than the PR
author. Besides the text, the row records the review round that raised it, the
commit it was raised against, and two flags that locate the pattern this audit is
most interested in:

- `on_post_review_commit`: the commit was pushed after the first review round, so
  the finding is on a change made during review.
- `on_named_fix_commit`: that commit is one the agent had already named in a
  "Fixed in <sha>" reply to an earlier finding. The finding is on a fix.

`response_hint` is a lexical read of the agent's first reply (accept, pushback,
different_fix, already_fixed). It exists to triage; the verdicts come from agents
reading the whole thread.

## Finding ids

`<repo>#<number>/F<i>`, with `i` counting a PR's findings in the order they were
raised. `bundle.py` prints them and `report.py` joins on them; both derive the
ordering from the same sort of `derived/findings.jsonl`.
