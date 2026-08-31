---
name: address-pr-reviews
description: Address open PR review findings with judgment — read every finding, decide whether the feedback is right, fix or push back, resolve, and re-review by pushing. Repeat until clean. Use when the user says "address the PR review", "handle the review threads", "go through the review comments", or asks to respond to PR feedback on a specific PR or the current branch's PR.
---

# Address PR Review Findings

Read every pending review finding on the PR, **post your plan on each thread first**, then implement, push (which re-runs the reviewer), confirm-and-resolve the threads you fixed, and dismiss the reviewer's now-stale change request. Repeat until clean. Same model people use at a real company: handle reviewer findings AND human-reviewer threads in one pass, push back with reasoning when you disagree, resolve, dismiss, re-review.

[LAW:one-source-of-truth] `provider.fetch` is the single source of pending findings for this loop — every open finding on the PR, keyed by `thread_id` (when available). There is no second stream.

**Provider** — the active review backend is loaded from `provider.json` in the skill directory (or `PR_REVIEW_PROVIDER` env var). The provider contract is in `PROVIDER_CONTRACT.md`. To switch providers, change `provider.json`; the loop below does not change.

```python
# Load the provider once at the start of the loop
import provider_loader
provider = provider_loader.get()  # reads provider.json, validates CAPABILITIES
# or pin one explicitly for this session: provider_loader.get("adversarial")
```

## Setup — derive PR_URL, OWNER, REPO, PR_NUM once

If the user didn't give you a PR number, infer it:

```bash
PR_URL=$(gh pr view --json url --jq .url)
read -r OWNER REPO PR_NUM < <(echo "$PR_URL" | sed -E 's#.*github\.com/([^/]+)/([^/]+)/pull/([0-9]+).*#\1 \2 \3#')
```

All subsequent commands use `$OWNER`, `$REPO`, `$PR_NUM`, and `$PR_URL`.

## Preflight — confirm the reviewer is installed

**This is the first thing the skill does** (after deriving the repo vars above), before the loop. When `provider.CAPABILITIES["setup_check"]` is `True`, run **one** `setup_check`; the `installed` boolean it returns says whether there is a reviewer to run at all.

```python
check = provider.setup_check(OWNER, REPO)
if not check["installed"]:
    raise SystemExit(f"Reviewer not installed: {check['message']}")
```

[LAW:no-silent-failure] a missing reviewer is the one failure that would otherwise look like "clean review, zero findings." Surface it as a hard stop, never an empty pass. Installed → proceed to the loop.

When a provider declares `setup_check: False`, the whole section is skipped: there is no installed workflow to check. (Every current provider — `action`, `local`, `adversarial` — declares it `True`, so read `CAPABILITIES` rather than assuming from the provider name.)

## The loop

Each round runs in phases: **plan every finding, then implement, then confirm-and-resolve, then dismiss the stale change request.** Repeat the round until **step 2 returns zero unresolved findings**.

[LAW:no-ambient-temporal-coupling] the round has one owner of *when* resolution happens, split by a single fact per finding — does addressing it require a code change? A no-change finding (invalid, already-fixed) resolves the moment you decide it, because its resolution depends on nothing future. A change-needed finding resolves only **after the push that makes the fix real** — resolving it earlier would mark an unfixed thread "done," a lie about the code (`[FRAMING:representation]`). So the plan phase captures the change-needed set and the confirm phase drains it; the loop's empty `fetch` (step 2) is the net that re-surfaces anything dropped.

### 1. Trigger (if required) and wait for the review to finish

If `provider.CAPABILITIES["trigger"]` is `True`, request a review explicitly:

```python
provider.trigger(PR_URL)
```

Then wait for the review to complete (all providers, always):

```python
result = provider.wait(PR_URL)
```

Blocks until the review for the PR's **current head SHA** reaches `completed`, then returns `{status, conclusion, sha, url}`. If the head SHA's review is already complete (nothing new pushed), it returns at once.

[LAW:no-silent-failure] if `conclusion` is anything other than `success`, the reviewer itself errored — its findings are absent, not empty. Stop and surface the run `url`; do not treat a failed run as a clean review.

### 2. Fetch findings, and capture the change requests to dismiss

```python
data = provider.fetch(PR_URL)

# Capture the blocking reviews to dismiss at round end (step 8).
pending_reviews = []
if provider.CAPABILITIES["dismiss_review"]:
    pending_reviews = provider.change_requests(PR_URL)["reviews"]
```

`fetch` returns canonical JSON: every open finding on the PR keyed by `thread_id` (nullable for providers without GitHub threads). One shape per finding.

`change_requests` returns the automated reviewer's `CHANGES_REQUESTED` reviews — `[{"review_id", "author", "commit_id"}]` — captured **now, before any push**, so step 8 dismisses exactly the reviews this round addressed and never the fresh re-review your push triggers. [LAW:one-source-of-truth] the dismiss set is what you read here, not what is blocking after you mutate the PR. It is scoped to Bot authors: a human's `CHANGES_REQUESTED` is theirs to clear, never auto-dismissed. [LAW:no-silent-failure]

Schema:

```json
{
  "findings": [
    {
      "file": "path/to/file.py",
      "line_start": 42,
      "line_end": 42,
      "body": "This silently swallows the error — surface it instead.",
      "author": "github-actions",
      "thread_id": "PRRT_xyz...",
      "is_resolved": false,
      "thread_comments": [
        {"author": "github-actions", "body": "This silently swallows the error — surface it instead."},
        {"author": "alice", "body": "agreed, fix incoming"}
      ]
    }
  ]
}
```

**Unresolved findings** = every entry where `is_resolved` is false. `thread_id` is non-null when the provider declares `resolve: True`. If the unresolved list is empty, **the loop is done** — step 1 already guaranteed the run completed, so empty is unambiguous. Proceed to **Finalize** below.

[LAW:verifiable-goals] this empty `fetch` is the **only** thing that establishes done. Never infer doneness from "I pushed my fixes" or "I addressed everything" — re-run `fetch` and read zero unresolved. A fixed-but-unresolved finding still counts as unresolved here, which is the safety net: it re-surfaces as `already_fixed`, and you resolve it now rather than leaving it open forever.

> **Read `thread_comments` before deciding.** A finding may already contain replies (yours from a prior iteration, a human's pushback on the reviewer, or a back-and-forth). The full chain is in `thread_comments`; `body` is just the first comment for quick scanning.

> **`line_start` may be `null`** for a file-level (non-line-anchored) comment. Open the file and read the `body`/`thread_comments` for context; the finding still resolves by `thread_id` like any other.

### 3. Plan phase — triage every finding, resolve the no-change ones

For **each** unresolved finding, before writing any code: open the file at `file:line_start`, read `body` and the full `thread_comments` chain, and classify. Classification is the same regardless of `author`:

- **valid** — reviewer is right; a fix is coming
- **different_fix** — reviewer identified a real issue but proposed the wrong fix; a better fix is coming
- **invalid** — reviewer is wrong, or the suggestion violates an architectural law (defensive null guards, silent fallbacks, mode explosion, duplicate enforcement, control-flow in place of data-flow variance, etc.). Push back and **cite the law** (`[LAW:no-defensive-null-guards]`)
- **already_fixed** — resolved by a later commit; nothing to change

**Post a comment on the thread stating your plan for this finding** — what you'll do and why. This comment goes on every finding, valid or not; it is the durable record of the decision.

```bash
gh api graphql -f query='
mutation($id:ID!,$body:String!){
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){ comment{id} } }
' -F id="$THREAD_ID" -F body="Plan: ..."
```

The classification carries **one discriminator: does addressing this finding require a code change this round?**

- **No change (invalid, already_fixed)** — the plan comment *is* the resolution. State why (cite the law for `invalid`), then **resolve the thread now**:

  ```python
  provider.resolve(THREAD_ID)
  ```

- **Change needed (valid, different_fix)** — post the plan comment and **leave the thread unresolved**. It resolves in step 7, after the fix is real. Add its `thread_id` to your change-needed set.

[LAW:dataflow-not-control-flow] resolve-now vs. resolve-later is a value the classification carries, not a side branch — the same plan step runs for every finding; the discriminator picks when resolution happens. [LAW:single-enforcer] resolve only ever goes through `provider.resolve`, never a raw mutation — it's the one path that confirms GitHub accepted the resolution, so a resolve that didn't take can't pass as done.

When `provider.CAPABILITIES["resolve"]` is `False`, findings have no resolvable thread — note each finding's disposition in a reply if the provider supports it. The loop still converges when `fetch` returns zero open findings.

### 4. Implement the planned changes

Make the code changes for every finding in the change-needed set. Nothing here for a round whose findings were all no-change — the set is empty and this step does nothing.

**Comments stay minimal.** [LAW:comments-carry-meaning] a comment earns its place only by standing where the code cannot — a non-obvious *why*, a constraint from outside the file. Otherwise write none. Not a narration of the fix, not the finding restated, not the reasoning you already posted on the thread; that record lives on the thread, which is why you posted it there.

This loop has its own temptation: the reviewer flags comments that diverge from their code, and you will think *"I'll spell the invariant out here so nothing misreads it again."* That is how the bloat gets in — the comment you write to prove alignment is the next round's divergence finding.

**A wrong comment is fixed by shrinking it.** [LAW:polishing-by-subtraction] a pass that grows the comment is patching, not fixing. The rule has an edge you can check: **the replacement is shorter than what it replaced**, often nothing at all, because the code beneath it already says the true thing. If your corrected comment is longer than the wrong one, you didn't fix it, you fed it.

- BAD: `# The reviewer noted this could swallow the error. We now re-raise instead of returning None, so callers see the failure — previously the caller's "if result:" check treated failure as empty.`
- GOOD: no comment; the `raise` says it.
- WRONG comment: `# retries 3 times with backoff` over a loop that now retries 5 times with none.
- BAD fix: `# Retries up to 5 times. Backoff was removed because upstream rate-limits by token bucket, so exponential backoff made the burst worse — see the thread on PR #41.` (longer than the lie it replaced)
- GOOD fix: delete it — the loop reads. Or, if the token-bucket reason is genuinely not in the code: `# no backoff: upstream is token-bucket limited`

### 5. Address failing checks

Check the PR for any failing checks. Address them before continuing.

### 6. Commit and push your fixes

Commit messages describe the **why** (architectural concern), not "address review comment" — each commit must stand alone in `git log`. Batch related concerns; separate unrelated.

Pushing triggers re-review for providers that auto-fire on push (`trigger: False`). If a round made no code change — only no-change resolutions — the head SHA is unchanged, its run is already complete, and step 1 returns immediately next round; the loop converges via step 2's empty list. For providers that require explicit triggering (`trigger: True`), the `trigger` call in step 1 handles re-running the reviewer. The rare case of forcing a re-run without a new commit for workflow-based providers is `gh run rerun <run-id>`.

### 7. Confirm phase — resolve every change-needed finding

The fix now exists in a pushed commit. For **each** finding in the change-needed set: post a comment on its thread describing the fix (reference the commit), then resolve it.

```bash
gh api graphql -f query='
mutation($id:ID!,$body:String!){
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){ comment{id} } }
' -F id="$THREAD_ID" -F body="Fixed in <sha>: ..."
```

```python
provider.resolve(THREAD_ID)
```

[LAW:no-ambient-temporal-coupling] this phase is gated on the push, not deferred past it: you confirm-and-resolve the captured set here, in this round, before step 8. The empty `fetch` in the next round's step 2 is the safety net — a change-needed thread left unresolved re-surfaces and is handled again, never silently dropped.

### 8. Dismiss the stale change request

When `provider.CAPABILITIES["dismiss_review"]` is `True`, dismiss each review captured in step 2 — the now-addressed `CHANGES_REQUESTED` reviews — with a message explaining the resolution:

```python
msg = (f"All findings from this review are addressed (fixes pushed and threads "
       f"resolved) or responded to on their threads. Dismissing the stale "
       f"change request; re-review runs on the new commit.")
for r in pending_reviews:
    provider.dismiss_review(PR_URL, r["review_id"], msg)
```

[LAW:dataflow-not-control-flow] the dismiss runs unconditionally when the capability is present; an empty `pending_reviews` dismisses nothing — there is no "if a review exists" branch. [LAW:single-enforcer] dismissal goes through `provider.dismiss_review`, which verifies GitHub recorded the `DISMISSED` state — an unconfirmed dismissal raises rather than passing as done. [LAW:no-silent-failure]

When `dismiss_review` is `False`, the provider posts no blocking review (it comments rather than requesting changes) — this step is a no-op the capability flag carries, exactly as `resolve` is.

**Round postcondition:** every thread from this round is resolved, and the change request the reviewer raised is dismissed. That is the end state for a single review round.

### 9. Go to step 1.

## Finalize — when the loop exits clean

The loop exits with zero unresolved findings after a clean re-review. The PR is reviewed; the work is done. [LAW:single-enforcer] this skill is the single place that closes a PR loop — merge, ticket-close, and recap live here, not scattered across callers or punted to the user. [LAW:dataflow-not-control-flow] finalize runs unconditionally on every clean exit; the data (the PR, the in-progress ticket, the merged commits) is what each step operates on. Per `<ticket-lifecycle>`, the agent owns ticket close-out — Finalize is where that happens. The recap step is the durable record for the next agent (its own justification, not something `<ticket-lifecycle>` requires).

[LAW:one-source-of-truth] **follow the tooling's runtime guidance.** Each step's tool (`gh pr merge`, `lit done`, `/recap`) emits its own instructions at runtime — preview tokens, next-step hints, branch-protection messages, admin-bypass prompts, apply-token strings, output paths. The skill describes the *shape* of each step; the tool itself is the authoritative source for *how* to follow through. Read what the tool prints and do what it says — don't paper over a warning, don't guess past a prompt, don't substitute the skill's wording when the tool gave you a literal token or path to use.

### A. Merge the PR

```bash
gh pr merge "$PR_URL" --squash --delete-branch
```

Squash is the repo's configured merge strategy. `--delete-branch` cleans up the remote branch (and the local one if checked out). [LAW:one-source-of-truth] `gh pr merge`'s exit code is the canonical signal of merge success — failure (required checks not satisfied, merge conflict, branch protection) halts Finalize. Don't add a `gh pr view --json merged` check as a second source; the exit code is the truth. At that point the agent's job changes from "close out" to "fix the merge blocker."

### B. Close the lit ticket

```bash
lit done "$TICKET_ID"
```

The ticket is the one this PR closed — pull it from the PR body, branch name, or the ticket you were working on in this session, and assign it to `$TICKET_ID`. The code block above is the canonical case: a confidently identified `$TICKET_ID`. Don't run `lit done` with an empty, guessed, or unverified value. `lit done` is a two-phase transition: the first call prints a preview with an apply token; capture it as `$TOKEN` and rerun with `--apply="$TOKEN"` to commit. For an out-of-band PR with no associated lit ticket, Step B is a no-op — skip the command entirely and note the missing-ticket case in the recap so the next agent sees it.

### C. Recap the merged work

Invoke `/recap` with a short note describing what was merged. The recap is the durable historical record — what shipped, what's left, what to watch out for. It lives in the project's recap log; future sessions browsing history read it there.

### D. Record the next instruction and run the close-out

The close-out runs `finalize-session` — the mandatory final step that records what shipped and the next instruction to pick up. It has two outcomes: run finalize-session (with content shaped by the candidate's classified state) or halt and surface a per-candidate failure table to the user. [LAW:types-are-the-program] the section's output is `NextInstruction = Finalize(direct_work) | Finalize(define_task) | HaltAndExplain(failure_table)` — variants of one typed value, dispatched mechanically from the classification step. Well-definedness is *not* a run/skip gate; it shapes what the instruction says. The only halt case is project-level misalignment across every examined candidate.

**These three arms are exhaustive — no "skip," "hold," or "ask instead" arm exists.** The user being present or the step feeling minor are NOT inputs to this decision. Deviating requires citing a clause *in this skill*; a tool's tone or purpose is never authorization (`finalize-session` "requires no user action" means exactly that — run it without asking, not "only run it when the user is absent"). Absent such a clause the prescribed arm **executes as written** — never a silent skip, never a fallback to asking.

**Step 1 — Enumerate candidates.** Read multiple candidates in priority order:

1. An explicit instruction the user gave during this session for what comes next.
2. A concrete follow-up this PR surfaced and you queued as a ticket.
3. The top entries of `lit ready` — pull at least the top three with `lit show <id>` (or all of them if fewer exist).

A pool is needed because the highest-priority slot may hold work that no longer fits where the project actually is after this PR's epic shipped. The next-best aligned candidate is what to actually pick up next.

**Step 2 — Classify each candidate.** Each candidate sits in exactly one state:

- **AlignedAndDefined** — aligned with the project's current trajectory AND the work could be started without asking the user clarifying questions (acceptance criteria explicit, scope bounded, dependencies met).
- **AlignedButFuzzy** — aligned with the project's current trajectory BUT exploratory or probe-shaped ("explore X", "consider Y", "investigate Z"); the body of work is to *define* the actual work, not to start it.
- **Misaligned** — the candidate's premise no longer matches the project's actual requirements. Common after an epic ships: the queued item assumed an older architecture, depends on a hypothesis the recent work invalidated, expands surface area the user has decided to contract, or opens a strategic thread the user has not validated at the project level.

**What "aligned" means here — project-level, not session-level.** It asks: does this candidate continue the trajectory the project is actually on right now? After an epic ships, work queued before it may need rescoping, re-prioritization, or outright deletion to fit the project's new shape. That's a strategy call the agent cannot make for the user — when no candidate is aligned, the user must intervene before any next instruction is meaningful.

**Step 3 — Dispatch.** Take the highest-priority candidate classified as Aligned (Defined or Fuzzy). Its state shapes what the instruction says:

- **AlignedAndDefined** → record the direct work. The next instruction is a precise pointer (ticket ID, acceptance criteria, or `/next` when the candidate is the top of `lit ready`).
- **AlignedButFuzzy** → record a define-task: (1) understand the problem the candidate raises, (2) investigate possible solutions, and (3) prepare a proposal for the user that surfaces the important information quickly without burying them in irrelevant detail. Implementation waits on user approval of direction.

Empty aligned-pool (every examined candidate classified Misaligned, or no candidates exist at all) → **HaltAndExplain**. Do not run finalize-session. Surface to the user, in this turn, a per-candidate failure table — the candidate's title/ID and the precise reason it failed (what shipped, what direction the project moved, what the candidate assumed that no longer holds). Vague summaries are unacceptable; the user needs the specifics to rescope, reorder, or close the tickets.

**Step 4 — Run finalize-session** (AlignedAndDefined and AlignedButFuzzy arms):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/message-in-a-bottle/bin/finalize-session "$(cat <<'EOF'
Last session shipped PR #<num> — <one-line description of what merged>.
<forward-looking notes the next agent should know: in-flight context,
follow-ups this PR surfaced, things to watch out for>

<next instruction — for AlignedAndDefined: a precise pointer (ticket ID,
acceptance criteria) or /next. For AlignedButFuzzy: "Understand the
problem in <ticket>, investigate possible solutions, and prepare a
proposal for the user that surfaces the important information quickly
without burying them in irrelevant detail. Return with the proposal —
do not implement until the user approves direction.">
EOF
)"
```

[LAW:single-enforcer] if a `/goal` is active in this session, carry it: pass `--goal '<the exact condition>'` as the leading argument, exactly as message-in-a-bottle's contract requires. An un-carried goal silently dies at the close-out — a multi-PR goal (e.g. "every open PR on this branch is merged") would stop at this first PR. Omit `--goal` entirely when no goal is set.

[LAW:dataflow-not-control-flow] the variability lives in the candidates' classified state, not in whether the agent decided to look or run. The instruction's content (direct vs define-task) and the halt-vs-run decision are both mechanical consequences of classification — the data picks the variant. Well-definedness in particular is a content discriminator, not a run/skip gate.

[LAW:one-source-of-truth] when finalize-session runs, its content derives from the same authored recap as step C — past-tense canonical form vs forward-looking action, one substrate consumed for two purposes.

Then stop. The loop is finished, the work is shipped, the recap is filed.

## Rules

- **You own the close-out.** When the loop exits clean, run Finalize (merge, close lit ticket, recap). Don't punt these to the user — `<ticket-lifecycle>` is explicit that the agent closes its own tickets, and a PR that sits open waiting for a human to push the merge button is the same anti-pattern. Step D runs whenever an aligned candidate exists in the pool; the instruction it records (direct work vs define-task) is shaped by whether the candidate is well-defined. The only halt case is project-level misalignment across every examined candidate — alignment is a strategy question the agent cannot answer on the user's behalf, and that case is surfaced as a per-candidate failure table for the user to act on.
- **Architectural laws override reviewer authority.** Refuse suggestions that violate `[LAW:...]`. Cite the law in the pushback reply on the thread — that text is the durable record of why the code is the way it is.
- **Plan on every thread before you touch code.** Each finding gets a plan comment in the plan phase — pushback-with-law for the ones you reject, the intended fix for the ones you accept. The comment is the durable record of the decision; the reviewer doesn't reply, so your comment is the only one.
- **Resolve every finding you addressed, including pushbacks — through `provider.resolve(thread_id)`, and only on confirmation.** No-change findings resolve in the plan phase; change-needed findings resolve in the confirm phase, after the fix is pushed — never before, because resolving an unfixed thread lies about the code. Open findings accumulate forever; resolution is the step that gets silently dropped, which is why it runs through the provider's verified path, not a raw mutation.
- **Dismiss the reviewer's stale change request once its findings are handled.** Through `provider.dismiss_review`, scoped to the captured Bot change-requests, with a message explaining the resolution. A human's `CHANGES_REQUESTED` is never auto-dismissed — that one is theirs to clear. The round's end state is zero unresolved threads and no stale change request blocking the PR.
- **Conflicts between findings** — surface to the user before acting. Don't pick a side silently.
