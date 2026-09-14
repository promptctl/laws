# Writing for a Human Reader

Scope: prose a person will read - documentation, READMEs, reports, summaries, announcements, commit messages, emails - and not code or text another LLM will consume.

## Terms

- Needed fact: a fact that at least one of the document's goals, for its named reader in its context, requires.

## Requirements

### General

1. Do not copy the shape of this guidance - its headings, repetition, and examples - into the prose you produce.

### Goals and readers

2. Before writing the first sentence of the draft, write down the document's goals (what it is for, not its topic) and a reader for each goal, even if only as two lines. Do not skip this on the ground that you already know who the document is for.
3. Expect more than one goal, and look for goals nobody stated.
4. For each goal, name a specific reader: what they already know and what they will do after reading. Do not name "everyone" or a broad category such as "developers" as the reader.
5. When the document serves readers at different familiarity levels, place the value statement and the quick-start where newcomers and hurried readers land first, and the depth below or behind links. Do not make any reader pass through another level's material to reach their own.
6. Give each layer a heading that puts its keywords first.
7. Write the sentences that feel too obvious to write, including when leaving them out feels like respecting the reader's intelligence. Find them by picturing the named reader stuck and asking at which line they would stop; do not rely on your own sense of what is obvious.

### Simplicity

8. Use the fewest, plainest elements that still carry every needed fact. Do not remove a needed fact or trade accuracy to make a sentence cleaner, including on the ground that the reader can find the fact elsewhere; you may reshape the sentence or leave it as it is.
9. Judge whether a detail is a needed fact against this reader in this context, not against the fact alone. Keep it when a goal needs it; cut it when no goal needs it, even if the reader would understand it.
10. Understand the subject completely before writing. When you cannot write the plain version of a sentence, close the gap in your understanding (read the code, run the thing, or ask) before editing its wording; do not rephrase around the gap.
11. Write the plainest true words, then remove elements one at a time, and stop before the first removal that would take out a needed fact, not when the text feels short enough.

### Revising a draft

12. Apply requirements 13-21 where a passage of the draft reads wrong, not as a checklist run over every sentence. How the prose reads overrides whether any of requirements 13-21 was followed: a sentence that reads badly is bad even if it follows all of them, and a sentence that reads right is right even if it breaks one.
13. Open the document, and each section, with its conclusion.
14. In a README, lead with what the project is and reach the install command fast. In a report, lead with the recommendation and put the reasoning after it.
15. Prefer plain words over formal substitutes, and prefer active sentences that name the actor over passive ones. You may use the passive when the actor is unknown or beside the point, or when the sentence reads better with the object first.
16. When a sentence reads flat, end it on the new or important thing rather than on a trailing qualifier. Do not apply this where it makes the prose monotonous or flatter.
17. Put one idea in each paragraph. When a paragraph reads wrong and you cannot say why, count its ideas.
18. Write in sentences and paragraphs. Use a list only when the items are parallel and discrete (options, steps, requirements), keep list items grammatically parallel, and do not break connected reasoning into a list.
19. State concrete behavior, not abstract qualities, and give the number where an adjective stands in for evidence. Cut or replace any claim that could be moved unchanged into another project's documentation without anyone noticing.
20. When a phrase impresses more than it informs, replace it with the observable thing it stands for, or cut it if nothing would be observable were it true. Check a phrase most closely when you want to sound smart.
21. After drafting, delete warm-up and throat-clearing openers, restatements of what the reader just read, hedges that carry no information, and intensifiers that do no work. Undo any cut that makes the reader stumble or reread; clarity outranks brevity.

### Signs to revise

22. Treat each condition in requirements 23-26 as a sign to revise, not a ban. When one appears, find and fix what produced it; do not only remove the sign itself.
23. Treat headers and sections in a document that should be a few paragraphs as a sign to revise, and check whether a few plain paragraphs would serve the document's goals.
24. Treat bold placed mid-sentence for emphasis as a sign to revise, and rebuild the sentence so its structure carries the emphasis.
25. Treat symmetrical filler ("not only X but also Y") as a sign to revise.
26. Vary paragraph length and sentence shape; treat uniform length and shape as a sign to revise.

### Final test

27. Read the draft aloud, or imagine the named reader reading it while you watch, and fix every place you would be uncomfortable having them read, lose attention, or hurry past.
28. Write a sentence two or three ways and keep the version that sounds right, not the one that follows the most of requirements 13-21.
29. Ship only when you would be comfortable watching the named reader read every line, regardless of whether the document is complete, long enough, or satisfies every requirement above. Rework any line you would rather they skimmed before shipping.
