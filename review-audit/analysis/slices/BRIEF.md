# Brief: cluster one slice of a PR-review audit

## The ticket you are serving (the owner's words, verbatim)

"Fetch all review content and review threads from every historical PR in the promptctl org with a deterministic, re-runnable script. Classify each reviewer finding by how the agent responded (accepted fix, accepted premise but different fix, pushed back) and whether that response was correct in hindsight, with special attention to second-round findings that were bugs in first-round fixes. Deliver a written analysis of where current guidance (laws:code, address-pr-reviews, the review action prompt) produced good outcomes and proposals for changing it to need fewer review rounds. No guidance edits in this ticket - analysis and proposals only."

The fetching and classifying are done. 8,060 reviewer findings across 930 PRs have verdicts. You are one of nine agents, each reading one slice of those verdicts. Your output feeds the written analysis.

## The guidance under audit (read the parts relevant to your slice)

- laws:code: /Users/bmf/code/promptctl_laws/.claude/worktrees/layers-4c0.1/plugins/laws/skills/code/SKILL.md (the coding agent's architectural laws, cited as [LAW:token])
- address-pr-reviews: /Users/bmf/code/promptctl_memento/memento/skills/address-pr-reviews/SKILL.md (how the coding agent answers review findings)
- the review action prompt: the reviewer's prompt is embedded in /Users/bmf/code/dotfiles/config/claude/skills/agent-code-review-setup/install.sh (grep for the heredoc that becomes the workflow's prompt)

Guidance changed over time. Two reviewer eras exist in the data: `copilot` (GitHub Copilot, roughly 2026-04 to 2026-06-09) and `copirate` (the repo's own Claude-based review action, 2026-06 onward, with [S1..S5] severities). Don't propose fixing something the current guidance already says. Check the current text before you claim a gap.

## Your slice

File: {SLICE}
What it holds: {WHAT}

One JSON object per line. Fields: id (`repo#PR/F<n>`), era, sev, path, finding (the reviewer's text, truncated), response (what the coding agent did), correct (was that right in hindsight), should_have, premise (was the reviewer right), caused_by (the earlier finding whose fix caused this one), cause_kind, laws_cited, cite_apt, evidence (the judging agent's reasoning), guidance_note (the judging agent's suggestion for what guidance would have prevented it).

The file is too big to read in one go. Read it in chunks with the Read tool (offset/limit), cover every line, and tally as you go.

## What to produce

Write a markdown report to exactly this path: {OUT}

1. **Patterns.** Group the rows into recurring, *actionable* patterns: concrete agent or reviewer behaviors, e.g. "fix narrowed a check at the flagged call site but left the sibling call site in the same file". Give each pattern a count (rows you assigned to it, so your counts must sum to at most the slice size; say how many rows fit no pattern), 2-4 example ids, and one line on the mechanism.
2. **What guidance already gets right.** Where the rows show the current guidance producing good outcomes, name the guidance text (file + a short quote) and the evidence (count + example ids).
3. **Proposals.** For the top patterns, propose a specific change to ONE of the three documents: which document, where in it, and the proposed wording (1-3 sentences). Tie each proposal to the pattern it addresses and its count. At most 5 proposals, ranked by the rounds they would save.
4. **Caveats.** Anything in the slice that makes a count unreliable (e.g. the judging agents disagreeing on a definition). One line each.

Keep it under 1,500 words.

## Bad output (do not produce any of these)

- "Agents should be more careful about completeness." A platitude with no mechanism, no count, no document. It can't be acted on.
- "Pattern: incomplete fixes (464 rows)." That's the slice's label restated, not a pattern inside it.
- A proposal that adds a rule the document already states. Quote the existing line instead and ask why it didn't hold.
- Counts estimated from a sample and presented as totals. If you sampled, say so and give the sample size.
- Example ids that aren't in your slice file.
- Editing any guidance file. This ticket is analysis and proposals only. Write only your report file.

## Acceptance

- The report exists at {OUT}.
- Every example id appears in your slice file (grep can check this).
- Pattern counts are tallied over the whole slice, or explicitly labeled as sampled.
- Each proposal names a document, a location, and wording, and traces to a counted pattern.

Reply with one line: the report path and the top pattern's count.
