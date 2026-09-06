# Orchestrator notes

Observations that the verdict schema has no field for, reported by classifying agents
in their chat replies or found while verifying their files. Raw input for the written
analysis; not a deliverable itself.

Each entry names the batch it came from so it can be traced back.

## Schema gaps

**Cross-PR reversal has no representation.** `caused_by` reaches only inside a packet:
one finding caused by the fix for another finding in the same PR. It cannot say "a
later PR undid the decision this pushback defended", which is a *more* expensive
outcome than a second review round — the agent won the argument with the reviewer and
lost to reality weeks later.

- `batch-077-laws` — laws#38/F5: the agent declined to change a pointer stub's manifest
  keywords, arguing the stub must stay maximally discoverable and keep the real skill's
  trigger phrases. laws#45 then deleted the whole stub plugin, because those retained
  names won the `memento:*` skill namespace over the actually-installed plugin: a live
  session got a "go install this" pointer while the real 298-line procedure was already
  loaded. The pushback read as correct inside the packet and was wrong outside it.
  Same packet, F1/F4: a deferral the agent argued for was honoured later by laws#44 —
  visible only from outside the packet.

Do not change the schema while a wave is in flight; agents mid-run are writing against
the current one and a mid-wave edit makes batches disagree. Decide after the wave.

## Candidate guidance findings

**Evidence the reviewer cannot reach.** The reviewer sees one repo. When a claim rests
on a fact in another repo, the agent tends to have verified it already and to leave the
evidence out of the PR body, so the reviewer raises it and the agent spends a round
posting proof it held before it opened the PR.

- `batch-077-laws` — 2 of 5 findings (laws#38 F2, F3) were exactly this. The agent had
  run the verifying install against an isolated `CLAUDE_CONFIG_DIR` *before* opening the
  PR. Cheap and generalizable: state the verified cross-repo fact beside the command or
  in the PR body.

## Flag precision

`on_named_fix_commit` over-fires badly, and the pipeline is already built to survive
that: `report.py` derives the headline "caused by an earlier fix" number from the
judged `caused_by` field, and cross-tabulates the flag against it separately, so the
flag's false-positive rate becomes a measured output rather than a hidden error.
Say this explicitly in the analysis — a reader will otherwise assume the flag is the
metric.

- `batch-070-laws` — 8 of 10 ON-NAMED-FIX-COMMIT flags are causal false positives,
  each checked against the commits API: laws#11's c27b5cb is test-file-only (+8-5) and
  b4b0233 is +10-2 in the router, while F2-F7 sit in untouched code from the original
  b50c47e; laws#13's run-suite.sh was added in cdbc132 and untouched by c3b026a;
  laws#9's `JUDGE_HERE` is in lib.sh at 166c81f; laws#14's `|| true` is visible in F1's
  own round-0 hunk. Here the flag tracks "the reviewer re-sampled this file", not
  "the fix broke something".

## Avoidable rounds without a chain

A round can be avoidable with no fix-causation at all, so `avoidable_rounds` and
`chains` move independently. `check.py` does not couple them and should not start.

- `batch-070-laws` — laws#14: F1's fix rewrote the exact grep expression F2 then
  flagged for `|| true`. Re-reading the line being edited would have saved rounds 1
  and 2. Recorded as `avoidable_rounds: 1` with `chains: []`.

### Why the flag over-fires — mechanism, and the fix

`shape.py:121` sets `on_named_fix_commit` on a purely temporal test: the finding's
`original_commit` is a sha the agent named as a fix, and it was raised after the naming.
Nothing positional. So when a reviewer re-reviews the whole PR at the fix commit, every
finding in that round inherits the flag, including findings about original code the fix
never touched.

- `batch-079-laws` — laws#44: 4 flags are positional false positives (F5, F6, F9, F12).
  The goal_ref race, the stale "two acceptance criteria" count, the hardcoded `master`
  default ref and the script-scope `mktemp` all landed in the PR's *first* commit
  `a9647c1`; the named fix commits `c9636cd` and `9775d5e` never touched those lines.
  Rounds 2 and 3 were reviewed wholesale against a named fix commit, so the whole round
  inherited the flag mechanically.

Proposal for the pipeline (not for this wave — regenerating `derived/` and `bundles/`
mid-wave shifts finding ids under running agents): intersect the flag with the fix
commit's changed paths, and ideally its changed line ranges. Keep the temporal flag as
a separate, weaker signal rather than replacing it.

## `avoidable_rounds` under-reports, by design

classify.md defines an avoidable round strictly: a round that would not have happened
had the earlier fixes been complete. A round that also carried an original-commit defect
does not disappear, so it does not count — even when fix-caused findings dominate it.
The aggregate sum is therefore a floor, not an estimate. The analysis must say so, and
should lean on `caused_by` for the real cost.

- `batch-079-laws` — laws#44 runs 5 rounds and scores `avoidable_rounds: 0`, because
  rounds 1, 2 and 3 each also carried an original-commit defect. Yet 6 of its 13
  findings are doc/comment drift from the agent's own code-only fix commits.

## Incidental findings worth surfacing to the owner

- `batch-079-laws` — laws#43/F1: branch protection on `promptctl/.github` master is real
  (`enforce_admins: true`) but `required_approving_review_count` is **0**. The agent's
  pushback was right that protection exists and did not mention this gap.

## Corpus boundary: unanchored findings are invisible

`shape.py` builds findings from review-thread roots. An issue the reviewer raises only
in a round's summary body, never anchored to a line, never becomes a row. The summary
bodies are in the bundles, so classifying agents see them, but nothing counts them.
Every rate this audit reports is over *threads raised*, not *issues raised*. Say so, or
the numbers read as more complete than they are.

- `batch-071-laws` — laws#17's round-0 summary flagged a stale "Never load a second
  craft in the same session" line contradicting that PR's own new rule 1, and called it
  a fix-before-merge item. It is in no packet as a finding, and nothing in the corpus
  says whether it was fixed.

## Verification is `gh api` only, never local git

This worktree cannot resolve PR commit shas — history was rewritten/squashed, so
`77710fc`, `f54d9b8`, `ece684a` are all "not a valid object name" against 235 local
commits. Agents that reach for `git show` waste calls before falling back. Put this in
classify.md before the next wave.

## Deferred remediation that never landed — confirmed live

- `batch-076-laws` — laws#36/F15: the agent declined to edit vendored macklebox content
  and filed `promptctl-horizon-cc4` to add `horizon/seeds/**` to `EXCLUDE_PATTERNS_EXTRA`.
  Verified now: the ticket is still `open`, and `.github/code-review.conf` on origin/master
  still reads `plugins/laws/skills/**,plugins/laws/design-docs/**,design-docs/**` with no
  horizon entry. The reviewer pays to review vendored seeds on every PR that touches one.
  This is the shape to watch for: a pushback whose correctness depends on a follow-up
  that never happened.

## Round counts include non-review rounds

- `batch-076-laws` — laws#36 scores `rounds: 6` per classify.md's literal rule (six rows
  in the rounds table), but round 5 is a `NOT REVIEWED` round-cap notice carrying zero
  findings. Any mean-rounds figure needs to exclude zero-finding notice rounds or it
  inflates.

## Highest fix-causation seen so far

- `batch-076-laws` — laws#36: 28 of 44 findings have a non-null `caused_by`.

## HEADLINE: the agent accepts false platform claims without testing them

Three independent agents found the same failure in three different PRs: the reviewer
asserts a confident, checkable fact about a shell or a platform binary, the fact is
false, and the agent accepts it and ships a fix for a bug that does not exist. Every one
of these was falsifiable by a single command. This is the mirror image of the failure
everyone expects (the agent pushing back wrongly) and it is more expensive, because an
accepted false premise leaves a permanent change in the code and no argument in the
thread to re-read later.

Verified independently by the orchestrator, not taken on the agents' report:

- **`set -e` and command substitution** (`batch-069-laws`, laws#1/F1 and laws#4/F1).
  Reviewer: "bash's `set -e` has a known, version-dependent gap" for
  `reply="$(drive_turn ...)"`. Tested on bash 3.2.57 and 5.3.9: a bare `x=$(false)`
  under `set -e` DOES abort. Only the `local`/`declare`/`export` form swallows the
  status, because the builtin's own success masks the substitution's failure. Both
  call sites in question were bare top-level assignments. The claimed failure could not
  occur.
  Worse than a single miss: on the second PR the agent called it "same class as the
  drive.sh finding" and wrote it into commit message 39b5109 — an unchecked claim
  promoted to precedent across PRs.

- **macOS `base64 -d`** (`batch-075-laws`, laws#35/F5). Reviewer: stock macOS `base64`
  rejects `-d`. Tested `/usr/bin/base64` on Darwin 25.3: both `-d` and `-D` round-trip
  at exit 0.

Guidance proposal, in the agents' own words: *"Run a version-dependent shell claim in
the target shell before adopting it"* and *"before reusing a previous round's reasoning
as precedent, re-run the one command that would falsify it; a wrong shell fact repeated
across PRs is cheaper to kill on first sight."*

## Unrequested mid-review hardening buys its own findings

A distinct source of avoidable rounds with no representation in the schema at all: the
agent pushes a commit during review that no finding asked for, and the reviewer finds
new problems in it. `cause_kind` cannot express this — every cause kind requires a
`caused_by` naming an earlier finding, and here there is none.

- `batch-080-laws` — laws#46: `b02acff` was an unrequested mid-review hardening commit
  (byte cap, idle timeout, reject branch). It bought three fresh findings (F32, F35,
  F38) that no earlier finding caused. Recorded in the PR record's
  `guidance_observations`, invisible to the `cause_kind` histogram.

The report must read `guidance_observations` for this class, or add a cause kind that
does not require a causing finding.

## Corpus quality

- **Duplicate threads inflate finding counts.** `batch-075-laws` — the same reviewer
  comment posted twice on one line under two thread ids: F4/F12 at
  `verify-instrument.sh:51`, F37/F42 at `pin-instrument.sh:55`.
- **`reply_hint` is unreliable in both directions.** `batch-080-laws` — all three
  `pushback` hints (F11, F19, F24) sit on replies that open with "Valid." classify.md
  already warns the hint is lexical and agents handled it correctly; do not let any
  aggregate lean on it.
- **A PR can merge with its head commit never reviewed.** `batch-075-laws` — laws#35
  hit the round cap; head commit `08c0ff8` rewrote `horizon_reviewer_sha` into a new
  shared boundary and was never reviewed. "Rounds to clean" is undefined for this PR;
  it did not reach clean, it ran out.

## Flag over-fire, further confirmations

- `batch-069-laws` — 12 of 14 flags are causal false positives.
- `batch-075-laws` — 11 flagged findings are line-level false positives.
- `batch-080-laws` — over-reports by roughly 2:1; 7 of 16 round-1 flagged findings sit
  on files `13de7cd` never touched.

## HEADLINE: pushing a partial fix batch re-triggers review and buys stale rounds

Two batches found the same process cost independently. The agent fixes some of a round's
findings, pushes, and the reviewer re-reviews at that head — where the remaining fixes do
not exist yet. Every not-yet-fixed finding is re-reported. The agent then spends a round
replying "already fixed" to real defects that were real at the commit read and gone at
head. Nothing was wrong with any fix; the cost is entirely in when the push happened.

- `batch-073-laws` — laws#27 round 2 is exactly this and it is the largest single
  effect in the packet: the agent pushed one round-1 fix (`7d98fbf`) while the other
  twelve were still being implemented. Thirteen findings came back, all `already_fixed`,
  all genuine at the commit read. Verified: `7d98fbf` is an ancestor of every round-1
  fix commit.
- `batch-072-laws` — laws#25 round 1: F5-F8 were raised on `0210886` (01:47), which
  predates the fix `36da072` (02:05). Duplicates raised on a pre-fix head, not
  consequences of a fix.

This deserves its own cause kind — the agent's suggestion is `raised_on_unfixed_head` —
because `ON-POST-REVIEW-COMMIT` currently conflates it with "a finding on a change made
during review", which is a different and much more interesting story.

Guidance proposal: push one commit per review round carrying all of that round's fixes,
or hold the push until the round's fixes are complete. Do not push a partial batch.

## Cross-PR causation, second sighting

`batch-072-laws` — laws#25/F3 exists because laws#21/F7's declined streaming fix was
measured for a once-per-turn hook that laws#25 then wired to PreToolUse. Recorded in
`evidence`, `caused_by` left null. Same shape as `batch-077-laws`'s laws#38/F5. Two
independent sightings now; a cross-PR link is worth adding.

## Commit resolvability is per-PR, not a property of the worktree

Two agents made opposite absolute claims and both were reporting a true sample.
Resolved by direct test: `7d98fbf`, `0c06531`, `2c5c1d9` (laws#27) resolve with
`git cat-file -t`; `77710fc`, `f54d9b8`, `ece684a` (laws#15/#17/#20) do not. A
squash-merge replaces a PR's commits with one new commit, and the originals become
unreachable once the branch is deleted; other merge strategies keep them reachable.
Note for classify.md: try local git first, fall back to `gh api` — do not assume either.

## Within-round duplicate findings, second sighting

`batch-073-laws` — the reviewer duplicated findings inside round 2: F31 = F39,
F38 = F41. With `batch-075-laws`'s two duplicate pairs, raw per-round finding counts
overstate distinct issues in any aggregate.

## Recurring defect shapes (from laws#27, 18 of 56 caused_by)

- One fix closes one instance of a class and leaves its siblings: F1 spawned three
  separate guard-vs-gate divergences; F5 spawned four copies of one stale Path-A claim.
- A doc sentence goes stale because a sibling code fix in the same commit set added an
  arm the sentence does not mention.

## HEADLINE, second face: "I cannot verify this" is itself a checkable claim

The false-premise pattern has a mirror. Sometimes the agent declines on the grounds that
the fact is unreachable — and the fact is installed on the machine it is running on.

- `batch-078-laws` — laws#39/F61/F81. The agent pushed back with "Bun's per-slot
  defaults are not something I can verify from anything on this machine." Verified by the
  orchestrator: `bun 1.2.23` is on this machine and
  `~/.bun/install/cache/bun-types@1.2.23@@@1/bun.d.ts` carries the answer in `@default`
  tags — stdin `"ignore"` (line 6827), stdout `"pipe"` (6839), stderr `"inherit" for
  spawn` (6851). The reviewer was wrong too: its proposed fix used the wrong stdin
  default and would have shipped a bug. Both sides guessed at something `grep` answers.
  Same class on F82 (`Bun.write`'s Blob/Response overloads) and F73/F74/F90
  (CryptoHasher's `digest(): Buffer`, `update(input, encoding?)`,
  `constructor(algorithm, hmacKey?)`) — all documented in the installed types.

- Fourth false reviewer premise, verified: `batch-074-laws` laws#28/F4, bash fork vs
  exec. Measured by PID identity: `bash -c` with a single simple command execs (shell pid
  == command pid); a script file whose last line is that command forks. The reviewer's
  premise was false and the agent's measurement was right.

Guidance proposal: before writing "I cannot verify X", run the one command that would.
Installed types, `--version`, and the binary itself are evidence, and they outrank both
sides' recollection.

## A refactor that only MOVES code poisons the flag wholesale

- `batch-078-laws` — laws#39: the F22 fix extracted `bun-host.mjs` into `bun-surface.js`
  and `embedded-fs.js`. Rounds 1-2 then flagged roughly twenty findings against code that
  was byte-for-byte pre-review logic which had merely relocated. The agent's rule —
  same logic as before the review means `caused_by: null` plus a stated relocation note —
  is the right one and should be written into classify.md for later waves.

## Merged without answering the reviewer

- `batch-074-laws` — laws#29: no reply on 9 of 10 threads, and the PR was merged 41
  seconds after pushing a commit the reviewer had never seen. Those findings were then
  actioned in laws#30. This is the `no_response` cluster showing up as a process fact.

## Best judgment call seen in the wave

- `batch-074-laws` — laws#34 round 2: the agent publicly retracted three plans it had
  just posted and deleted the whole git argument grammar rather than patching it. The
  agent classifying it calls this the batch's clearest evidence that "accept the finding
  and patch" is the wrong default when the finding is a false denial in your own guard.
  Worth quoting in the analysis as the positive case.
