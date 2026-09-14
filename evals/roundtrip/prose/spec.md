# Writing for humans: specification

Scope: text a person will read, such as documentation, READMEs, reports, summaries, announcements, commit messages, and emails; not code, and not text another LLM will read.

## Requirements

### Goals and readers

1. Before drafting, list every goal the document serves (what it is for, not its topic), including secondary goals such as reassuring the reader.
2. Before writing, name the specific reader for each goal: who they are, what they already know, and what they will do after reading. Put first what that reader needs in order to act, and do not write for "everyone".
3. Picture each named reader stuck, and treat the sentence that feels too obvious to write as the one that reader most likely needs. Failure: writers who know the subject cannot feel what the reader does not know, write as if the reader shares their knowledge, and cannot detect this by introspection.
4. Keep a fact when a goal of this reader, in this context, needs it; cut it when no goal does, even for readers who would understand it.
5. When a document serves readers at several levels of familiarity, layer it: put the value and the quick start first, and put depth below them and behind links.
6. Give each layer a heading whose first words are the keywords a skimming reader at that level is looking for.

### Simplicity

7. Use the fewest, plainest elements that still carry every fact the reader needs.
8. Do not drop a fact the reader needs to make a sentence cleaner, and in technical prose do not trade accuracy for tidiness. Failure: writers cut past what the reader needs and take the result for simplicity.
9. Understand the idea completely before writing it; then say it in the plainest true words and remove one element at a time, stopping when the next element you would remove is a fact the reader needs.
10. If you cannot write the idea as one plain sentence, treat that as a sign you do not yet understand it, and go back to understanding it before editing further.
11. Treat piled-on qualifiers, important-sounding abstractions, and complexity on the page as a sign to revise. Failure: writers add them because they look like effort, which shifts the work onto the reader or disguises thin understanding.

### Core moves

12. Apply requirements 13-24 when a draft reads wrong, not as a checklist on every sentence; how the prose reads overrides whether a rule was followed. Failure: applied mechanically, they make prose uniform and flat.
13. Make the first sentence of the document, and of each section, carry the conclusion rather than background, so that a reader who stops after the first paragraph has the most important point.
14. Delete warm-up and throat-clearing openers; the real first sentence follows them. Failure: writers warm up before stating the point.
15. Prefer plain words to elaborate ones.
16. Write active sentences that name the actor.
17. When a sentence reads flat, prefer ending it on the new or important information and opening it on what the reader already knows. Treat a point buried mid-sentence while filler holds the last words as a sign to revise.
18. Write one idea per paragraph.
19. Use a list only when the items are parallel and discrete, such as options, steps, or requirements, and keep list items grammatically parallel; write everything else as sentences.
20. Prefer concrete statements to abstract ones. Treat a claim that could appear unchanged in the documentation of many other projects as a sign to revise.
21. Where an adjective stands in for evidence, give the evidence, such as the number.
22. Do not use phrases that sound sophisticated but name nothing a reader could picture or check. When you find one, replace it with the concrete thing it points at; if you cannot say what it would look like if it were true, cut it. Failure: writers, and LLM writers especially, reach for these phrases when they want to sound smart rather than when they have something to say.
23. After drafting, delete restatements of what the reader just read, hedges that carry no information, and intensifiers that do no work.
24. If a cut makes the reader stumble or reread, undo it; clarity outranks brevity.

### Signs to revise

25. Treat headers and sections in a text that should be about three paragraphs as a sign to revise.
26. Treat bold scattered mid-sentence for emphasis as a sign to revise; the sentence should carry the emphasis itself.
27. Treat symmetrical filler, such as "not only X but also Y" or "it's not just X - it's Y", as a sign to revise.
28. Vary paragraph length and sentence shape; treat every paragraph the same length or every sentence the same shape as a sign to revise.

### Final test

29. Read the draft aloud, or imagine the specific reader reading it while you watch, and fix every place where you would wince, flag, or hurry past.
30. Write a sentence two or three ways and keep the one that sounds right.
31. Ship the text when you would be comfortable watching the reader read every line.
