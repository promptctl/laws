# Writing for humans

Scope: text a person will read - documentation, READMEs, reports, summaries, announcements, commit messages, emails - and not code or text another LLM will consume.

## Terms

- Load-bearing: a fact is load-bearing when one of the document's goals, for this reader in this context, needs it. A fact no goal needs is noise.

## Goals and readers

1. Before drafting, list what the document is for - its goals, not its topic. Expect more than one, and include the unstated ones (a release note that also reassures, a reference that also teaches the mental model, an error message that also says the fault was not the user's).
2. For each goal, name the specific reader: what they already know and what they will do after reading. Do not write for "everyone".
3. When the document serves readers at different familiarity levels, layer it: put the value statement and the quick-start where the newcomer and the hurried reader land first, and the depth below or behind links. Do not make any reader pass through another level's material to reach their own.
4. Give each layer a heading that front-loads its keywords.
5. Treat the sentence that feels too obvious to write as the one most likely to lose the reader. Picture the named reader stuck; do not rely on your own sense of what is obvious.

## Simplicity

6. Use the fewest, plainest elements that still carry every load-bearing fact. Do not drop a load-bearing detail for a cleaner sentence, and never trade accuracy for tidiness.
7. Judge whether a detail is load-bearing against this reader in this context, not against the fact alone. Keep it when it is the point; cut it when it is irrelevant to the point at hand, even for a reader who would understand it.
8. Understand the subject completely before writing. If you cannot write the plain version of a sentence, you do not yet know what you mean; resolve that before editing the wording.
9. Write the plainest true words, then remove elements one at a time until the next cut would remove something load-bearing, and stop there.

## Core moves

10. Apply requirements 11-19 when a draft reads wrong, not to every sentence in turn. How the prose reads overrides whether a rule was followed.
11. Open the document, and each section, with its conclusion. Delete warm-up openers; the real first sentence follows them.
12. In a README, lead with what the project is and reach the install command fast. In a report, lead with the recommendation.
13. Prefer plain words over formal substitutes, and active sentences that name the actor over passive ones.
14. When a sentence reads flat, end it on the new or important thing rather than on a trailing qualifier. Let the ear and variety overrule this when following it flattens the prose.
15. Put one idea in each paragraph.
16. Write in sentences and paragraphs. Use a list only when the items are genuinely parallel and discrete (options, steps, requirements), and keep list items grammatically parallel.
17. State concrete behavior, not abstract qualities; where an adjective stands in for evidence, give the number. Cut or replace any claim that could appear unchanged in another project's documentation.
18. When a phrase impresses more than it informs, replace it with the concrete thing it stands for. If you cannot say what would be observable if the phrase were true, cut it. Suspect such phrases most when you want to sound smart.
19. After drafting, delete throat-clearing openers, restatements of what the reader just read, hedges that carry no information, and intensifiers doing no work. If a cut makes the reader stumble or reread, undo it; clarity outranks brevity.

## Drift signals

20. Treat headers and sections in a document that should be a few paragraphs as a sign to revise.
21. Treat bold placed mid-sentence for emphasis as a sign to revise; the sentence must carry its own emphasis.
22. Treat symmetrical filler ("not only X but also Y") as a sign to revise.
23. Vary paragraph length and sentence shape; treat uniform length and shape as a sign to revise.

## Final test

24. Read the draft aloud, or imagine the named reader reading it while you watch, and fix every place you would wince, flag, or hurry past.
25. Write a sentence two or three ways and keep the one that sounds right.
26. Ship when you would be comfortable watching the reader read every line.
