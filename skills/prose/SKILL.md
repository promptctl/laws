---
name: prose
description: Writing guidance for human-audience text — documentation, READMEs, reports, summaries, announcements, commit messages, emails, and any other writing a person (not a machine or an LLM) will read. Use when the deliverable is prose for people. Do not apply to code (use the code skill) or to text another LLM will consume.
---

# Writing for humans

The reader's time is the budget. Every sentence spends it. Write accordingly.

## The core moves

**Lead with the point.** The first sentence of the document — and of each section —
carries the conclusion, not the preamble. A reader who stops after one paragraph
should leave with the most important thing, not the background. If you catch yourself
warming up ("In today's fast-paced environment...", "Before we dive in..."), delete
the warm-up; the real first sentence is hiding right after it.

**Write for a specific reader.** Before writing, answer: who reads this, what do they
already know, and what will they *do* after reading? A README is read by someone
deciding whether to use the thing and then trying to run it — so lead with what it is
and get to the install command fast. A report is read by someone making a decision —
so lead with the recommendation. Text that serves "everyone" serves no one.

**Prefer plain words and active sentences.** "Use" beats "utilize," "because" beats
"due to the fact that," "the parser fails on X" beats "a failure may be experienced
when X is encountered." Name the actor: "the script deletes the cache," not "the
cache is deleted."

**One idea per paragraph, and paragraphs over fragments.** Prose that flows carries
reasoning; a wall of three-word bullets carries only assertions. Use a list when the
items are genuinely parallel and discrete (options, steps, requirements) — and then
keep list items grammatically parallel. Everything else is sentences.

**Concrete beats abstract.** "Retries three times, then gives up and logs the URL"
beats "implements robust error handling." If a claim could appear unchanged in the
docs of a thousand other projects, it says nothing about this one.

**Cut ruthlessly, then stop.** After drafting, delete: throat-clearing openers,
restatements of what the reader just read, hedges that carry no information ("it's
worth noting that", "arguably"), and intensifiers doing no work ("very", "extremely",
"incredibly powerful"). What survives should be shorter and *clearer* — if a cut
makes the reader stumble or reread, the cut was wrong. Brevity is a means; clarity is
the goal.

## Signals you're drifting

- Headers and sections in something that should be three paragraphs.
- Bold scattered mid-sentence for **emphasis** that the sentence should carry itself.
- Symmetrical filler ("not only X but also Y", "it's not just X — it's Y").
- Every paragraph the same length; every sentence the same shape. Vary the rhythm.
- Adjectives standing where evidence should be ("blazingly fast" — give the number).

## The final test

Read it aloud, or imagine the specific reader reading it with you watching. Every
place you'd wince, flag, or hurry past — fix that. If you'd be comfortable watching
them read every line, ship it.
