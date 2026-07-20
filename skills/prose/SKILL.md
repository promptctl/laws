---
name: prose
description: Writing guidance for human-audience text — documentation, READMEs, reports, summaries, announcements, commit messages, emails, and any other writing a person (not a machine or an LLM) will read. Use when the deliverable is prose for people. Do not apply to code (use the code skill) or to text another LLM will consume.
---

# Writing for humans

The reader's time is the budget. Every sentence spends it. Write accordingly.

## Start from the goal

Before the first sentence, answer one question: what is this document *for*? Not its
topic — its intent. And the honest answer is almost always plural. A README has to
convince a stranger the project is worth their attention, get a ready user running in
a minute, and hand the committed reader a path deeper — three goals, three different
readers, one page. Most documents carry a stack like that, and some goals are quiet:
the release note that also reassures, the API reference that also teaches the mental
model, the error message that also tells the user it wasn't their fault. List the
goals before you draft. The ones you don't name, you won't serve.

The goals are what set the floor described in the next section: a fact is load-bearing
when some goal needs it, and noise when none do. They also decide structure, because
one document usually serves several familiarity levels at once. Layer it — the value
and the quick-start where the newcomer and the hurried both land, the depth below and
behind links where only the committed go. Give each layer a heading that front-loads
its keywords, so a reader skimming for their level can smell the right path before
reading it. A good document is a gateway, not a wall: every reader reaches their level
fast, and none are forced to wade through someone else's.

The standing obstacle is the curse of knowledge — you know the project, so you can no
longer feel what the stranger doesn't, and your draft quietly writes the reader into
your own head. It is the most common cause of unclear writing, and you cannot
introspect your way out of it. Name the specific reader for each goal, picture them
stuck, and treat the sentence that feels too obvious to write as the one most likely
to be a cliff for them.

## The aim: simplicity

*Simplicity is the ultimate sophistication.*

Simple prose is not dumbed-down prose. It is the hardest thing to write and the
easiest thing to read — the same fact from two sides, because comprehension is the only
thing prose is paid to produce and a plain sentence delivers it with the least
friction. Piling on qualifiers and important-sounding abstractions is the cheap
direction: it looks like effort while offloading the real work onto the reader. Finding
the one plain sentence that carries the whole idea demands that you understand the idea
completely — which is why plainness is sophistication, not its absence. Complexity on
the page is usually a tell: either you haven't understood the thing well enough to
simplify it, or you're dressing thin understanding in language that sounds deep.

But simplicity has a floor: *as simple as possible, but not simpler.* The target is the
fewest, plainest elements that still carry every fact the reader actually needs. Cut
past that — drop a load-bearing detail for a cleaner sentence — and you don't have
simplicity, you have oversimplification wearing its clothes. Technical prose never
trades accuracy for tidiness.

And the floor moves, because "load-bearing" is not a property of a fact but a relation
between the fact and this reader's need right now. The same experts want the
wire-format details in a design review and are distracted by them in a launch note.
Audience *and* context set the line together: when the detail is the point, keep it;
when it's irrelevant to the point at hand, cut it — even for readers who would
understand it perfectly. Simplicity is not a fixed target; it's the least that still
fully serves this reader, here.

You reach it by subtraction. *Perfection is achieved not when there is nothing more to
add, but when there is nothing left to take away.* Understand the thing completely
first — muddy prose is almost always muddy thinking, and no edit rescues a sentence
whose author isn't sure what it means. Then say it in the plainest true words and
remove, one element at a time, until the next thing you'd cut is load-bearing. That
stopping point is the floor, and it's the target the core moves below serve.

- COMPLEX (thin idea, thick words): "We leverage a multi-faceted methodology to
  holistically optimize stakeholder outcomes."
- SIMPLE (the same idea, if it was ever there): "We ask each team what it needs, then
  build that." Can't write the simple version? You don't yet know what you meant. Does
  the simple version drop something the reader needed? Then you cut past the floor.

## The core moves

These are tools, not a checklist. Reach for them when a draft reads wrong — not as
boxes to tick on every sentence. Applied mechanically they flatten prose into
sameness; what matters is always how it reads, never whether you followed the rule.

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

**Mind where a sentence puts its weight.** A sentence lands hardest on its last few
words — the stress position, where the reader's ear leans — and opens most smoothly on
what the reader already knows. So when a sentence reads flat, the fix is often to end
it on the new or important thing rather than trail off: "After copying the rows, the
migration deletes the old table" hits harder than "The migration deletes the old table
after copying the rows, for reference." But this is a tendency to listen for, not a
transform to run on every sentence — apply it mechanically and the prose flattens into
sameness. Reach for it when a line reads wrong; let variety and the ear overrule the
formula.

**One idea per paragraph, and paragraphs over fragments.** Prose that flows carries
reasoning; a wall of three-word bullets carries only assertions. Use a list when the
items are genuinely parallel and discrete (options, steps, requirements) — and then
keep list items grammatically parallel. Everything else is sentences.

**Concrete beats abstract.** "Retries three times, then gives up and logs the URL"
beats "implements robust error handling." If a claim could appear unchanged in the
docs of a thousand other projects, it says nothing about this one.

**Distrust fluent phrases that sound sophisticated.** LLM prose reaches for
constructions that feel weighty and carry nothing a reader can picture or check: "the
implementation becomes residue," "unlocks powerful synergies," "a robust and scalable
approach." They read as competence; they communicate no fact. The tell is a phrase
that impresses more than it informs — and you are most tempted by one when you want to
sound smart, not when you have something to say. When you catch one, name the concrete
thing underneath it: "the code is almost mechanical to write" says what "becomes
residue" only gestured at. If you can't state what the phrase would look like if it
were true, it isn't saying anything — cut it.

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
- Fluent phrases that never cash out into something you could picture or verify —
  "becomes residue," "seamlessly integrates," "powerful and flexible." Sophistication
  is not information.
- The point buried mid-sentence while filler holds the emphatic last slot ("…deletes
  the old table after copying the rows, for reference"). It usually wants the end.

## The final test

Writing is an intuitive craft, not a mechanical one, and the only real judge is how the
prose reads. So read it aloud, or imagine the specific reader reading it with you
watching. Every place you'd wince, flag, or hurry past — fix it. Write a sentence two or
three ways and keep the one that sounds right; the rewrite is the work, not proof you
failed the first time. If you'd be comfortable watching the reader read every line,
ship it.
