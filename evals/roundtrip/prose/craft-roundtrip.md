# Writing for humans

This page is for the moments when the text you are producing will be read by a person:
documentation, a README, a report, a summary, an announcement, a commit message, an
email. It does not cover code, and it does not cover text another LLM will read. This
page repeats itself because you hold it for a whole session. The prose you write is
for a person, and it follows the rules below, not the style of this page.

One picture carries most of what follows. **Somewhere a specific person is reading
your text, and you are watching over their shoulder.** They know some things and not
others. They are reading it in order to do something next. Every rule on this page
is a way of looking at that person instead of at yourself.

---

## 1. Goals and readers come before the first sentence

**List the goals.** Before drafting, list every goal the document serves. A goal is
what the document is *for*, not what it is about. "Explain the cache" is a topic.
"Let the on-call engineer clear a stale cache at 3 a.m." is a goal. Include the
secondary goals too, such as reassuring the reader.

**Name the reader for each goal.** Before writing, name the specific reader behind
each goal: who they are, what they already know, and what they will do after reading.
Put first what that reader needs in order to act. Do not write for "everyone". A text
aimed at everyone is aimed at no one's next step.

**Picture the reader stuck.** Take each named reader and picture them stuck, halfway
through, at the step where your text ran out. The sentence that feels too obvious to
write is the one that reader most likely needs.

This is the missing stair. You climb that staircase every day and step over the gap
without noticing it is there. The reader has never climbed it, and they fall through.

You will feel it as a small embarrassment at spelling something out: *"Anyone reading
this knows the service has to be running first. Writing that down is condescending."*
That is the moment. You know the subject, so you cannot feel what the reader does not
know. You will write as if they share your knowledge, and looking inward will not show
you that you are doing it; introspection reports that everything is clear, because to
you it is. So do not consult the feeling. Go back to the stuck reader, and treat the
obvious sentence as the one they most likely need.

**Keep or cut each fact by the goal it serves.** Keep a fact when a goal of *this*
reader, in *this* context, needs it. Cut it when no goal does, even if the reader would
understand it. Understanding a fact is not a reason to hand it to them; needing it is.

**Layer a document that serves several levels of familiarity.** When one document
serves readers who know the subject to different degrees, layer it: the value and the
quick start first, and the depth below them and behind links. The newcomer gets what
they came for at the top and can stop; the expert walks down to the depth and through
the links.

**Head each layer with the skimmer's keywords.** Give each layer a heading whose
first words are the keywords a skimming reader at that level is looking for.

- BAD heading: "A Few Words on Getting Things Going"
- GOOD heading: "Install and run: the five-minute quick start"

---

## 2. Simplicity: the fewest, plainest elements that still carry every needed fact

**The target.** Use the fewest, plainest elements that still carry every fact the
reader needs. Both halves bind. Fewest and plainest, *and* every needed fact.

**Do not cut past the reader's need.** Do not drop a fact the reader needs to make a
sentence cleaner. In technical prose, do not trade accuracy for tidiness.

The temptation arrives looking like good taste: *"This sentence is clunky with the
exception in it. Drop the 'except on Windows' and it reads beautifully."* Refuse it.
Writers cut past what the reader needs and take the result for simplicity. The
sentence is now clean and wrong, and the Windows reader follows it off a cliff.
Simplicity is measured against what the reader needs, not against how smooth the
sentence feels.

- BAD: "Run `make install` to set up the project." (the fact that it needs root was cut
  because it made the sentence ugly)
- GOOD: "Run `sudo make install` to set up the project; it writes to `/usr/local`."

**The method.** Understand the idea completely before writing it. Then say it in the
plainest true words, and remove one element at a time. Stop when the next element you
would remove is a fact the reader needs.

Think of pulling blocks from a tower one at a time. You keep pulling while the tower
stands. The block you stop at is the one holding up a fact.

**The one-sentence check.** If you cannot write the idea as one plain sentence, treat
that as a sign you do not yet understand it. Go back to understanding it before you
edit further. More editing of a sentence you do not understand polishes the confusion.

**Complexity on the page is a sign to revise.** Treat piled-on qualifiers,
important-sounding abstractions, and complexity on the page as a sign to revise.

You will reach for them when the draft feels thin: *"This paragraph looks too
simple for how hard the problem was. Let me add 'robust, holistic, end-to-end' and a
couple of 'in most typical cases'."* That is the moment. Writers add these because they
look like effort. What they actually do is shift the work onto the reader, who now has
to dig the idea out, or disguise thin understanding, which the one-sentence check
above would have exposed. When you see them in your draft, revise.

- BAD: "The system provides a robust, holistic framework for generally managing
  potentially complex configuration scenarios."
- GOOD: "The tool reads `config.toml` and tells you which keys are missing."

---

## 3. Core moves: tools for a draft that reads wrong

The moves in this section, from "first sentence carries the conclusion" through "undo
a cut that makes the reader stumble", are a toolbox you open when something rattles,
not a pre-flight checklist you run on every sentence. Apply them when a draft reads
wrong. How the prose reads overrides whether a rule was followed.

The temptation is diligence: *"I'll go sentence by sentence and make sure each one
is active, concrete, ends on new information, and has no hedge."* Refuse it. Applied
mechanically, these moves make prose uniform and flat, every sentence stamped from one
mold. Read the draft, find where it reads wrong, and reach for the move that fixes that
place. If a sentence reads right and breaks a move, the reading wins.

**Conclusion first.** Make the first sentence of the document, and the first sentence
of each section, carry the conclusion rather than background. A reader who stops after
the first paragraph should have the most important point.

- BAD: "Over the past quarter, the team has been investigating various aspects of
  database performance."
- GOOD: "Moving the reports query to the replica cut page load from 4 s to 600 ms."

**Delete the warm-up.** Delete warm-up and throat-clearing openers; the real first
sentence follows them.

You will feel the need to clear your throat: *"I can't just start with the answer. Let
me set the stage first."* That is the moment. Writers warm up before stating the point.
Delete the warm-up, and let the sentence after it open the text.

- BAD: "In this document, we will take a look at how deployments work. Deployments are
  an important part of our process. Here is how to roll back a bad one."
- GOOD: "To roll back a bad deploy, run `deploy rollback <release>`."

**Plain words.** Prefer plain words to elaborate ones: "use", not "utilize"; "start",
not "commence".

**Active sentences with an actor.** Write active sentences that name the actor.

- BAD: "The migration was run and errors were encountered."
- GOOD: "Priya ran the migration, and it failed on the `orders` table."

**Known first, new last.** When a sentence reads flat, prefer ending it on the new or
important information and opening it on what the reader already knows. A point buried
mid-sentence while filler holds the last words is a sign to revise.

- BAD: "The outage, which lasted two hours, was caused by an expired certificate, as
  far as we can currently tell at this point."
- GOOD: "The two-hour outage came from an expired certificate."

**One idea per paragraph.** Write one idea per paragraph.

**Lists only for parallel, discrete items.** Use a list only when the items are
parallel and discrete, such as options, steps, or requirements. Keep list items
grammatically parallel. Write everything else as sentences.

- BAD list: "- Faster builds / - We should also consider the cost / - Caching"
- GOOD list: "- Cache dependencies / - Parallelize tests / - Drop the unused lint step"

**Concrete over abstract.** Prefer concrete statements to abstract ones. A claim that
could appear unchanged in the documentation of many other projects is a sign to
revise; it tells the reader nothing about *this* one.

- BAD: "A powerful, flexible tool for modern workflows."
- GOOD: "Converts Markdown tables to CSV, one table per file."

**Evidence, not adjectives.** Where an adjective stands in for evidence, give the
evidence, such as the number. "Fast" becomes "answers in 40 ms at p99". "Much smaller"
becomes "2.1 MB, down from 9 MB".

**No sophisticated-sounding phrases that name nothing.** Do not use phrases that sound
sophisticated but name nothing a reader could picture or check. When you find one,
replace it with the concrete thing it points at. If you cannot say what it would look
like if it were true, cut it.

These are shop signs over an empty shop. You will reach for them, and as an LLM writer
you will reach more often than most: *"'This unlocks a new paradigm for seamless
collaboration' - that sounds right for the intro."* That is the moment. Writers reach
for these phrases when they want to sound smart, not when they have something to say.
Ask what the reader would see if it were true. "Two people can edit the same file and
see each other's cursors" is something they can picture. If there is no such picture,
there is nothing in the shop; take the sign down.

- BAD: "Leverages synergies across the stack to drive meaningful impact."
- GOOD: "The API and the web app now share one validation module, so a rule changes in
  one place."

**Delete what does no work.** After drafting, delete restatements of what the reader
just read, hedges that carry no information, and intensifiers that do no work.

- BAD: "This is really very important. As mentioned above, the key must be rotated. It
  could perhaps be worth noting that, basically, rotation is required."
- GOOD: "Rotate the key every 90 days."

**Undo a cut that makes the reader stumble.** If a cut makes the reader stumble or
reread, undo it. Clarity outranks brevity.

---

## 4. Signs to revise

These are signs to revise, not bans. When you see one, look again at the passage.

- **Headers in a short text.** Headers and sections in a text that should be about
  three paragraphs.
- **Scattered bold.** Bold scattered mid-sentence for emphasis. The sentence should
  carry the emphasis itself.
- **Symmetrical filler.** Constructions such as "not only X but also Y" or "it's not
  just X - it's Y".
- **Uniform shape.** Every paragraph the same length, or every sentence the same shape.
  Vary paragraph length and sentence shape.

---

## 5. The final test: watch the reader read

**Read it aloud, or watch the reader.** Read the draft aloud, or imagine the specific
reader reading it while you watch. Fix every place where you would wince, flag, or
hurry past. This is the same person from the top of the page, the one you pictured
stuck, now reading your finished text line by line.

**Try it more than one way.** Write a sentence two or three ways and keep the one that
sounds right.

**Ship when you could watch every line being read.** Ship the text when you would be
comfortable watching the reader read every line.

---

## Recap

Goals and readers:
- List every goal before drafting, secondary goals included.
- Name the specific reader for each goal - who, what they know, what they will do next.
  Put first what they need to act. Do not write for "everyone".
- Picture each reader stuck; the too-obvious sentence is the one they most likely need.
  You cannot feel the gap by introspection.
- Keep a fact when this reader's goal needs it; cut it when no goal does.
- For readers at several levels, layer: value and quick start first, depth below and
  behind links.
- Start each layer's heading with the skimmer's keywords.

Simplicity:
- Fewest, plainest elements that still carry every needed fact.
- Do not drop a needed fact for a cleaner sentence; do not trade accuracy for tidiness.
- Understand fully, say it plainly, remove one element at a time, stop at a needed fact.
- Cannot say it in one plain sentence: go back to understanding before editing further.
- Piled-on qualifiers, important-sounding abstractions, complexity: signs to revise.

Core moves - use when a draft reads wrong; reading beats rule-following:
- Conclusion in the first sentence of the document and of each section.
- Delete warm-up openers.
- Prefer plain words.
- Active sentences that name the actor.
- When flat, prefer known-first, new-last; a buried point is a sign to revise.
- One idea per paragraph.
- Lists only for parallel, discrete items, kept grammatically parallel.
- Prefer concrete; a claim that fits many projects is a sign to revise.
- Give the evidence an adjective stands in for.
- No sophisticated phrases that name nothing; replace with the concrete thing or cut.
- After drafting, delete restatements, empty hedges, idle intensifiers.
- Undo a cut that makes the reader stumble; clarity outranks brevity.

Signs to revise: headers in a three-paragraph text, scattered bold, symmetrical filler,
uniform paragraph length or sentence shape.

Final test: read it aloud or watch the reader read it, and fix every wince, flag, or
hurry; write a sentence two or three ways and keep the one that sounds right; ship when
you would be comfortable watching the reader read every line.
