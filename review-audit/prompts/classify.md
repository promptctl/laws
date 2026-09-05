# Audit one batch of PR review threads

You are auditing the review history of the `promptctl` GitHub org to find out where the
agent's coding guidance produced good outcomes and where it cost review rounds. You are
not tuning guidance — you are producing the evidence someone else will tune from.

Every PR in these packets was authored by a coding agent posting as GitHub user
`brandon-fryslie`; "the agent" below always means that author, and "we" in the owner's
framing means the same. The reviewer is automated: `copilot-pull-request-reviewer`
(Apr–Jun 2026) or `github-actions` running the CoPirate review agent (Jun 2026 on),
occasionally a human. The agent replies under a skill called address-pr-reviews: it posts
a plan on each thread (`Plan: valid` / `different_fix` / `invalid` / `already_fixed`),
implements, pushes, and replies `Fixed in <sha>`. It cites architectural laws as
`[LAW:token]`.

Your job on each finding is four judgments: **was the reviewer right, what did the agent
do, was that the right call, and did this finding exist only because of an earlier fix.**
You judge both sides and defer to neither. The reviewer's premise is a claim, not a
finding of fact; the agent's reply is a claim too, however confidently it cites a law.

The last one is what the audit is for. The owner's words: *"I want you to pay special
attention to situations where we made a change and the reviewer called out bugs in the
changes we made to the PR in response to another finding."* A finding that exists because
an earlier fix was incomplete or wrong is a review round the agent paid for and could
have avoided. Those are the findings the whole exercise is hunting. Treat `caused_by` /
`cause_kind` as the most important fields you will write.

## Input

You are given a batch id and a list of packet files. Each packet is one PR:

- A header line `# <repo>#<number>: <title>`, then URL, author, state, dates, diff size,
  reviewers.
- `## Review rounds` — a table of round index, reviewer, review state, commit sha, inline
  comment count, findings count; then each round's summary body in a `<details>` block.
- `## Findings` — one `### <repo>#<number>/F<i>` section per reviewer finding. Each carries:
  round, severity (S1 lowest … S5 ships a defect; Copilot-era findings have no severity),
  `path:line`, thread id, resolved/outdated flags, a `reply-hint`, the reviewer's finding
  text, a collapsed diff hunk, and every reply in the thread in full.
- Optionally `## Issue comments`.

Two flags can appear on a finding heading:

- **[ON-NAMED-FIX-COMMIT `<sha>`]** — this finding was raised against a commit the agent
  had already named as the fix for an earlier finding. This is the exact situation the
  audit is hunting.
- **[ON-POST-REVIEW-COMMIT `<sha>`]** — the commit landed after the first review round, so
  the finding is on a change made during review.

**The `reply-hint` is lexical.** It is computed from the opening words of the agent's
reply, nothing more. It is a triage hint, never a verdict. `accept` on a reply that then
argues the reviewer's premise is wrong is a `mixed` response, and the hint will not tell
you that.

## Verifying against the code

You have `gh`. Use it when the packet alone cannot settle whether a premise or a response
was correct:

```
gh pr diff <number> --repo promptctl/<repo>
gh api repos/promptctl/<repo>/commits/<sha>        # the diff of one commit
gh pr view <number> --repo promptctl/<repo> --json files,commits
```

Do this for **every pushback** (the agent claiming the reviewer is wrong is a claim to
check) and for **every finding flagged ON-NAMED-FIX-COMMIT** (you must see what the named
fix commit actually changed to name the cause kind). Do not spend calls on findings whose
thread text already settles the question — most accepted findings with a concrete fix
description do.

## Output

Write exactly one file: `/Users/bmf/code/promptctl_laws/.claude/worktrees/review-audit/review-audit/verdicts/<batch-id>.jsonl`

JSONL — one JSON object per line, nothing else in the file. No prose, no header, no
trailing commentary. Strings contain no raw newlines. Two record kinds:

```json
{"finding": "<repo>#<number>/F<i>",
 "premise": "correct" | "partly" | "wrong" | "uncertain",
 "response": "accepted_fix" | "accepted_premise_different_fix" | "pushed_back" | "already_fixed" | "no_response" | "mixed",
 "response_correct": "yes" | "no" | "uncertain",
 "should_have": "accepted_fix" | "accepted_premise_different_fix" | "pushed_back" | "already_fixed",
 "caused_by": "<repo>#<number>/F<j>" | null,
 "cause_kind": "incomplete_fix" | "regression_from_fix" | "comment_drift_from_fix" | "same_gap_other_instance" | "new_scope" | null,
 "law_cited_by_agent": ["<token>"],
 "law_citation_apt": "yes" | "no" | "n/a",
 "evidence": "one to three sentences",
 "guidance_note": "one sentence, or \"\""}
```

```json
{"pr": "<repo>#<number>",
 "rounds": 0,
 "avoidable_rounds": 0,
 "chains": [["F1", "F4", "F7"]],
 "narrative": "two to five sentences",
 "guidance_observations": ["one sentence each"]}
```

Field meanings:

- **premise** — was the reviewer right that something was wrong here? `partly` = a real
  issue, mis-described or overstated.
- **response** — what the agent actually did. `mixed` = the thread shows a plan that did
  not match the eventual action.
- **response_correct** — was accept / different-fix / push-back the right call given the
  truth of the premise. Judge the *choice*, not how well the eventual fix was executed.
- **should_have** — the response the agent should have given.
- **caused_by / cause_kind** — fill these whenever this finding exists because of an
  earlier fix: on an ON-NAMED-FIX-COMMIT or ON-POST-REVIEW-COMMIT flag, and any time the
  text shows it regardless of flags. Name the earlier finding by id.
  `incomplete_fix` = the earlier fix handled one instance, this is the missed remainder.
  `regression_from_fix` = the earlier fix broke something that worked.
  `comment_drift_from_fix` = the fix left a comment, doc, or changelog contradicting the
  new code. `same_gap_other_instance` = the same class of gap somewhere the fix did not
  sweep. `new_scope` = an unrelated new issue in the changed region.
  A flagged finding with `"caused_by": null` needs an `evidence` sentence saying why the
  flag is a false positive here.
- **law_cited_by_agent** — every `[LAW:token]` the agent cited on this thread, tokens
  only, `[]` if none.
- **law_citation_apt** — did the cited law actually apply, or was the token pasted onto a
  preference? `n/a` when nothing was cited.
- **evidence** — the concrete fact that decides `premise` and `response_correct`, quoting
  thread text or code you looked at.
- **guidance_note** — what guidance, had the agent followed it in the **original PR** or
  in the **first fix**, would have prevented this finding or this round. Name the concrete
  move: *"when rejecting one delimiter-bearing input, sweep every field the same parser
  splits."* Empty string when there is nothing to learn.
- **rounds** — the number of review rounds in the packet's rounds table.
- **avoidable_rounds** — rounds after the first that would not have happened if the
  earlier fixes had been complete and correct.
- **chains** — sequences of finding ids where each was caused by the fix for the previous.
- **guidance_observations** — about this PR's *process*, distinct from any per-finding
  `guidance_note`.

## What bad output looks like

Every line below is a real failure mode. Produce none of them.

- `"premise": "correct", "response_correct": "yes", "evidence": "Agent said Plan: valid and fixed it."` — transcribing the reply-hint. That is not a judgment; you have asserted nothing about whether the reviewer was right.
- `"response_correct": "yes", "evidence": "The reviewer approved in round 2."` — approval is not proof. The reviewer is an LLM that misses things and re-approves its own bad advice.
- `"premise": "wrong", "evidence": "Agent cited [LAW:no-defensive-null-guards]."` — deferring to the agent. A law in a pushback is a claim to check, not evidence for itself.
- `"caused_by": null` on an ON-NAMED-FIX-COMMIT finding with no evidence sentence explaining the false positive.
- `"guidance_note": "Be more thorough when fixing findings."` — names no move, changes no behavior.
- `"guidance_note": "The allow-list should reject empty strings."` — restating the reviewer's finding. The note is about what the agent should have done *before the reviewer spoke*.

## How to work

1. Read every packet in the batch **fully** before writing any verdict for it. Chains run
   forward in time: F7 tells you what F1's fix actually cost, and you cannot classify F1
   correctly without having read F7.
2. Judge each finding from the thread text and, where needed, the code. Not from the
   reply-hint, not from the reviewer's next-round approval.
3. Write finding records in packet order, then that packet's PR record, then the next
   packet.
4. Where the packet and the code leave a question open, write `uncertain` and say so in
   `evidence`. Missing information is never rounded up into `correct` or `yes`.

Around finding twenty-five you will be tired, the packets will start to rhyme, and you
will catch yourself reading the `reply-hint`, skimming the first sentence of the reply,
and emitting a record. That is the moment this audit turns into transcription and stops
being worth running. When you notice it, go back to the reviewer's actual claim and ask
whether it was true.

## Before you finish

Count. The finding headings in a packet match `^### <repo>#<number>/F<i>` (other `###`
lines inside quoted review summaries do not count). Their total must equal the number of
finding records in your file, and the number of packets must equal the number of PR records:

```
grep -hEc '^### [A-Za-z0-9._-]+#[0-9]+/F[0-9]+' <packet>... | paste -sd+ - | bc
grep -c '"finding":' /Users/bmf/code/promptctl_laws/.claude/worktrees/review-audit/review-audit/verdicts/<batch-id>.jsonl
grep -c '"pr":' /Users/bmf/code/promptctl_laws/.claude/worktrees/review-audit/review-audit/verdicts/<batch-id>.jsonl
```

Every finding id in the batch appears exactly once, in packet order. Then confirm the file
parses: every line is valid JSON on its own.

Your chat reply at the end is short: the batch id, the count per `response` value, the
count of findings with a non-null `caused_by`, and anything that blocked you. Nothing else
— the file is the deliverable.
