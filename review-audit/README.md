# review-audit

Tools for auditing how the coding agent responded to automated PR review across the
promptctl org: what the reviewers raised, what the agent did about it, whether that
was the right call, and how often a fix made in one review round caused a finding in
the next. The output feeds guidance changes to `laws:code` and `address-pr-reviews`.

## Pipeline

Each stage is a pure function of the previous stage's files; only `bank.py` talks
to GitHub.

```
bank.py    GitHub          ->  data/prs/<repo>/<number>.json      one PR, versioned on updatedAt
                               data/commits/<repo>/<oid>.json     one commit's diff, immutable
                               data/manifest.json                 the index: version + sha256 per object
shape.py   data/ (bank)    ->  derived/{prs,findings}.jsonl  one row per PR and per reviewer finding
bundle.py  derived/        ->  bundles/<repo>/<number>.md    one markdown packet per PR + batches.json
           (reviewing agents read a batch under prompts/classify.md and write verdicts/<batch>.jsonl)
report.py  derived/ + verdicts/  ->  aggregate tables + derived/joined.jsonl
render.py  derived/ + verdicts/  ->  rendered/index.md + rendered/<repo>/<number>.md   the verdicts as documents a person reads
```

```sh
review-audit/bank.py   sync --org promptctl --bank review-audit/data
review-audit/bank.py   verify --bank review-audit/data
review-audit/shape.py  --bank review-audit/data --out review-audit/derived
review-audit/bundle.py --derived review-audit/derived --out review-audit/bundles
review-audit/report.py --derived review-audit/derived --verdicts review-audit/verdicts
review-audit/render.py --derived review-audit/derived --verdicts review-audit/verdicts --out review-audit/rendered
```

`data/`, `derived/`, `bundles/` and `rendered/` are gitignored: large and reproducible from the stage before them; `verdicts/` is the hand-made input and is committed.

`bank.py sync` is idempotent, resumable and incremental. It lists what GitHub has, compares
it against `manifest.json`, and fetches only the difference: a PR whose `updatedAt` moved,
and any commit never seen before. A commit is immutable - its oid is its content - so once
banked it is never fetched again. Every object is written through a rename and indexed with
its sha256, so a killed run leaves no half-written file and re-running resumes where it
stopped. `bank.py verify` re-hashes the whole bank offline and reports anything that changed
since it was fetched, plus any commit a stored PR references but the bank lacks. `--refresh`
refetches every PR regardless of `updatedAt`, which is the escape hatch for the fact that
`updatedAt` is GitHub's freshness signal, not ours.

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
