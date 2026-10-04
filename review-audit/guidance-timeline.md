# Guidance timeline

Dates on which the guidance under audit changed, so review outcomes can be read
against the guidance that was live when the PR was reviewed. Sources: git history of
`brandon-fryslie/dotfiles`, `promptctl/laws`, `promptctl/memento`.

## Reviewer eras

| period | reviewer login | engine |
|---|---|---|
| 2026-04 .. 2026-06-09 | `copilot-pull-request-reviewer` | GitHub Copilot review; no severity tags |
| 2026-06-09 .. 2026-06-20 | (z.ai / local providers) | short-lived; address-pr-reviews retargeted to z.ai then a provider contract |
| 2026-06 .. present | `github-actions` | CoPirate (`copirate-code-review-agent`), `**[S1..S5]**` severities, `[LAW:*]` tags, convergence sweeps |

## The laws (`laws:code`)

| date | change |
|---|---|
| 2026-01-14 | architectural laws first added to CLAUDE.md |
| 2026-02-09 | dataflow-not-control-flow added |
| 2026-04-18 | no-defensive-null-guards added; scripting and subagent discipline |
| 2026-05-01 | python-deps and commit-requirement laws; ticket-lifecycle tightened |
| 2026-06-08 | "Rework the laws" |
| 2026-06-10 | CLAUDE.md second half deduped and rewritten against the laws |
| 2026-07-12 | laws moved out of CLAUDE.md into a `/code` skill |
| 2026-07-16 | laws plugin released (`laws@promptctl`); effective-style rewrite |
| 2026-07-17 | comments-carry-meaning keyed on altitude (0.15.0) |
| 2026-08-01 | parse-dont-validate restored as a first-class law; boundary exception made structural |
| 2026-08-30 | polishing-by-subtraction made citable; comment-bloat in review responses addressed (#29) |

## address-pr-reviews

| date | change |
|---|---|
| 2026-04-18 | skill created (with 12 others) |
| 2026-05-01 | 'valid' classification expanded with judgment questions |
| 2026-05-13 | step-loop machinery, Copilot completion signals |
| 2026-05-15 | 3-pass iteration cap removed |
| 2026-05-17 | human review threads aggregated alongside Copilot findings |
| 2026-05-24 | skill owns close-out: merge, close ticket, recap; message-in-a-bottle at end |
| 2026-05-29 | three-arm classified handoff (fire/define/halt) |
| 2026-06-09 | retargeted from Copilot to z.ai; thread resolution made a verified step |
| 2026-06-10 | provider contract introduced |
| 2026-06-11 | adversarial review provider |
| 2026-06-14 | plan-first rounds, change-request dismissal, finalize-session |
| 2026-06-20 | preflight uptakes reviewer updates |
| 2026-06-23 | wording update |
| 2026-08-22 | moved to the memento plugin |
| 2026-08-30 | "the reviewer's divergence check was paying agents to write comments": comments-stay-minimal, a wrong comment is fixed by shrinking it |
| 2026-09-01 | memento extracted into its own repo |
