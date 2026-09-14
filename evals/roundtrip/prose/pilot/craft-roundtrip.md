# Writing for a human reader

You have been asked to write something a person will read - documentation, a
README, a report, a summary, an announcement, a commit message, an email. This
document is the craft for that, and it stays with you for the whole job. It does
not apply to code, and it does not apply to text another LLM will consume; those
are other media with other crafts. That includes this page: it is written for you,
an LLM holding it across a session, and its headings, its repetition and its
worked examples are the tools of that medium, not of the reader's. Take what it
says; do not copy its shape into the prose you produce.

The one fact to hold above everything else: a person reading your prose can stop.
They do not file a complaint. They skim, they lose the thread, they close the tab,
and nobody tells you. Every rule here exists because of that silent exit, and the
reader you must keep picturing is a specific one, in a chair, reading while you
stand behind them and watch.

## The one term: load-bearing

A fact is load-bearing when one of the document's goals, for this reader in this
context, needs it. Pull a load-bearing fact and something the document was for
falls down. A fact no goal needs is not a nice extra; it is noise, and noise is
weight the reader carries for nothing.

The word is a wall. Some studs hold the roof and some are trim, and you cannot tell
which by looking at the stud - you have to know what the roof is resting on. That
is why the term is defined against goals and readers rather than against the fact
by itself, and why the next section comes before any sentence gets written.

## Know what it is for, and who is reading

Before drafting, list what the document is for - its goals, not its topic. The
topic is "the new cache layer"; the goals are "let an operator turn it on safely",
"tell the team the migration is finished", and "reassure the person who flagged
the risk that it was handled." Expect more than one goal, and go looking for the
unstated ones. A release note also reassures. A reference also teaches the mental
model that makes the reference navigable. An error message also says the fault was
not the user's. The unstated goal is the one that decides whether the document
lands or merely exists, and it is the one you skip when you start from the topic.

For each goal, name the specific reader: what they already know, and what they
will do after reading. Not "developers" - the developer who has never seen this
repo and needs it running in ten minutes. Not "stakeholders" - the director who
will forward the report with one sentence of her own on top. "Everyone" is not a
reader; do not write for "everyone". Text aimed at everyone has no one stuck in it
to rescue, and so it rescues no one.

The temptation here is pace. You know the subject, the draft is already forming,
and the thought is *"I know who this is for - I'll just write it."* Refuse it. Not
because the list is a ritual, but because the reader you have not named is the one
whose stuck moment you cannot picture, and picturing that moment is what half of
this document asks of you. Put the goals and the readers down, even as two lines,
before the first sentence of the draft.

### Layers

When the document serves readers at different familiarity levels, layer it. The
value statement and the quick-start go where the newcomer and the hurried reader
land first; the depth goes below, or behind links. And do not make any reader pass
through another level's material to reach their own. The newcomer does not wade
through the architecture to find the install command; the expert does not re-read
the pitch to reach the configuration reference. Each reader walks in the front
door and finds their own room without crossing anyone else's.

Give each layer a heading that front-loads its keywords. A reader scanning for
their layer reads the first two words of each heading and nothing more.
"Installing on Linux" is found; "How you might go about getting it installed if
you happen to be on Linux" is scrolled past.

### The obvious sentence

Treat the sentence that feels too obvious to write as the one most likely to lose
the reader. This is the rule your own fluency fights hardest, because the sentence
feels obvious precisely because you know the subject and the reader does not.
Picture the named reader stuck: at which line do they stop, look up, and wonder
what they missed? It is almost always the line you left out for being obvious. Do
not rely on your own sense of what is obvious - you are the wrong instrument for
measuring it; the named reader is the right one.

The rationalization arrives dressed as respect: *"they're smart, they'll get it,
spelling this out is condescending."* That is your sense of obvious, not theirs,
and it is exactly the sentence to write. A reader who already knew skips a line in
half a second. A reader who did not know is gone, and you will not hear about it.

## Simplicity

Use the fewest, plainest elements that still carry every load-bearing fact. Both
halves matter, and the second half is the one that gets dropped. Do not drop a
load-bearing detail for a cleaner sentence, and never trade accuracy for tidiness.
A clean sentence that is wrong, or that is missing the one number the operator
needed, is not simpler. It is broken, with good posture.

Here is the moment. The sentence reads "Retries back off exponentially, starting at
200 ms, capped at thirty seconds, and give up after five attempts." It is lumpy,
and you think: *"'Retries back off exponentially' - cleaner, and they can find the
numbers in the config."* Stop. Is the cap load-bearing for this reader? If the
reader is the operator deciding whether a thirty-second stall is the retry logic
or an outage, then yes, and the lumpy sentence stays lumpy or gets reshaped - it
does not get lighter by losing the fact. Tidiness is not one of the document's
goals. The goals are the goals.

Judge whether a detail is load-bearing against this reader in this context, not
against the fact alone. The same fact is a beam in one document and trim in
another. Keep it when it is the point; cut it when it is irrelevant to the point
at hand - and cut it even when the reader would understand it. "They'd get it" is
not a reason to keep a detail. "This goal needs it" is the only reason.

- WEAK, in a release note whose reader wants to know their data is safe: "The
  migration ran in 41 minutes on a 2019 laptop, using the Postgres 14 driver,
  with fsync on." (the driver and the laptop are trim here)
- STRONGER, in that note: "The migration is complete; no rows were lost." (the
  timing belongs in the engineering report, where it is the point)

Understand the subject completely before writing. If you cannot write the plain
version of a sentence, you do not yet know what you mean, and the fix is not in
the wording. The clouded sentence is a gauge, not a draft: it is showing you where
your own understanding runs out. Resolve that - read the code, run the thing, ask -
before you edit a word. The temptation is to polish through it: *"I'll just phrase
it more carefully."* Careful phrasing around a gap produces a sentence that sounds
fine and says nothing, and the reader who needed the fact feels the hollow without
being able to name it.

Then the method. Write the plainest true words, then remove elements one at a time
until the next cut would remove something load-bearing, and stop there. One at a
time, so you can feel each one go. The stop is not "when it feels short enough";
the stop is the first cut that would take a beam. That is how you arrive at the
fewest elements without ever losing accuracy: you never remove a load-bearing
thing, because you stop at the cut before it.

## The moves

What follows, from opening on the conclusion through the post-draft cut, is a set
of moves. Apply them when a draft reads wrong, not to every sentence in turn. You
do not walk the draft with a checklist, holding each sentence up against nine
rules; you read the draft, and where a passage reads wrong, you reach for the move
that fixes it. How the prose reads overrides whether a rule was followed. A
sentence that follows every move and reads badly is bad; a sentence that breaks
one and reads right is right. Hold that in front of every move below, because each
of them, stated alone, will sound like a law, and none of them outranks the
reader's ear.

### Open on the conclusion

Open the document, and each section, with its conclusion. Delete warm-up openers;
the real first sentence follows them. The warm-up is the engine idling in the
driveway - "In this document we will explore...", "It's important to understand
that...", "Before diving in, some context..." - and the reader is in the passenger
seat waiting for the car to move. Cut the idle. Look at what comes after the
warm-up: that is your first sentence, and it was there all along.

- WEAK: "In today's fast-moving infrastructure landscape, teams need reliable ways
  to manage configuration. This document describes our approach."
- STRONGER: "Configuration lives in one file per environment, checked into the
  repo, and the deploy reads it at boot."

In a README, lead with what the project is and reach the install command fast. In
a report, lead with the recommendation. The README reader is deciding in seconds
whether this is the thing they need and how to get it running; the report reader
wants to know what you concluded before they spend attention on how. The reasoning
is not lost - it comes after, for the reader who wants it.

### Plain words, named actors

Prefer plain words over formal substitutes, and active sentences that name the
actor over passive ones. "Use" over "utilize", "start" over "initiate", "the
scheduler drops the job" over "the job is dropped." A passive sentence hides who
did the thing, and the reader who needs to know which component to check, or whom
to call, is left guessing. This is a preference, and there are sentences where the
passive is right - when the actor is unknown or beside the point, or when the ear
wants the object first. Prefer the active; do not outlaw the other.

### End on the new thing

When a sentence reads flat, end it on the new or important thing rather than on a
trailing qualifier. The end of a sentence is where the stress falls; a qualifier
there - "...in most cases", "...as discussed above" - spends the stress on nothing.
"The build fails when the lockfile is stale" lands; "When the lockfile is stale,
the build fails, generally" trails off. But this is a move for a flat sentence,
not a rule for every sentence. Let the ear and variety overrule it: a page where
every sentence lands its weight on the final word has a monotony of its own, and
if following this flattens the prose, do not follow it.

### One idea per paragraph

Put one idea in each paragraph. A paragraph is the reader's unit of "I have this;
now the next." Two ideas in one paragraph means the reader either loses one or
rereads to separate them. When a paragraph reads wrong and you cannot say why,
count its ideas.

### Sentences, not lists

Write in sentences and paragraphs. Use a list only when the items are genuinely
parallel and discrete - options, steps, requirements - and keep list items
grammatically parallel. The temptation is structural: *"this paragraph has four
things in it; a list would organize it."* Ask whether the four things are really
parallel and discrete, or whether they are an argument with connective tissue that
the bullets will cut. A list of steps is a list. A list of "considerations" is
usually a paragraph that lost its verbs, and the reader gets four fragments and has
to reassemble the reasoning you threw away.

- WEAK: "Key points: performance; the cache; also security matters; migration
  path." (not parallel, not discrete, not sentences)
- STRONGER, as a list: "To upgrade: 1. Stop the service. 2. Run the migration.
  3. Start the service." (steps, parallel, each a full imperative)
- STRONGER, as prose: "The cache is the performance win, but it is also where the
  security review found the exposure, so the migration path has to bring both in
  together."

### Concrete behavior, not qualities

State concrete behavior, not abstract qualities; where an adjective stands in for
evidence, give the number. "Fast" is a claim; "handles 4,000 requests per second on
one core" is a fact the reader can check against their need. "Robust", "scalable",
"flexible", "modern" - each is an adjective standing where evidence should be. Cut
or replace any claim that could appear unchanged in another project's
documentation. That test is mechanical: lift the sentence, drop it into a
different project's README, and see whether anyone would notice. "Built with
developer experience in mind" sits equally well in every README on earth, which
means it says nothing about this one. It is a stock photo where the reader wanted
a picture of the building.

- WEAK: "A lightweight, high-performance library with a clean API."
- STRONGER: "One file, no dependencies, parses a 10 MB log in under a second; the
  whole API is three functions."

### The phrase that impresses more than it informs

When a phrase impresses more than it informs, replace it with the concrete thing
it stands for. If you cannot say what would be observable if the phrase were true,
cut it. "Leverages a paradigm-shifting approach to orchestration" - what would I
see? If the answer is "it runs the jobs in dependency order," write that. If the
answer is nothing, the phrase was a peacock's tail: display, and expensive to
carry. Suspect such phrases most when you want to sound smart. That wanting is the
tell. The moment a sentence gives you a small glow of cleverness, read it again for
what it actually tells the reader, because you will feel the glow before you
notice the gap.

### The post-draft cut

After drafting, delete throat-clearing openers, restatements of what the reader
just read, hedges that carry no information, and intensifiers doing no work. "It
should be noted that", "as mentioned above", "somewhat", "very", "really",
"essentially" - each is a token the reader pays for and gets nothing back. Then
the counterweight, and it is not optional: if a cut makes the reader stumble or
reread, undo it. Clarity outranks brevity. The goal of the cut was never a shorter
document; it was a document the reader moves through without friction, and a cut
that adds friction has failed at the only thing it was for. "Omit needless words"
is right on its home turf, which is words that are needless; a word the reader
needed to keep their footing was never needless, however trim the sentence looks
without it.

## Drift signals

Each of these is a sign to revise, not a ban on the thing itself. They are the
smell of smoke, not the fire. When you see one, revise - and look at what produced
it, because the signal usually points at an upstream problem rather than at the
thing you noticed.

Treat headers and sections in a document that should be a few paragraphs as a sign
to revise. A three-paragraph note that has grown four headings has usually been
given structure instead of an argument; the headings are doing the work the
sentences should do. Ask what the document is for and whether a few plain
paragraphs would carry it.

Treat bold placed mid-sentence for emphasis as a sign to revise; the sentence must
carry its own emphasis. Bold in the middle of a sentence is you leaning across the
table to say "this part, really." If the sentence needs that, the sentence is built
wrong - the important thing is buried under a qualifier, or the sentence has two
ideas and the bold is pointing at one. Rebuild the sentence so its shape does the
pointing.

Treat symmetrical filler - "not only X but also Y" - as a sign to revise. The
symmetry sounds like thought and is usually the absence of it: two things placed
side by side because the frame had two slots, not because the reader needed both.

Vary paragraph length and sentence shape; treat uniform length and shape as a sign
to revise. A page of same-length paragraphs, each made of same-shaped sentences,
reads like a metronome, and a reader stops hearing a metronome within a minute.
Variety is not decoration; it is what keeps attention from flattening into a skim.

The temptation on all four is to treat the signal as the fault: *"strip the bold,
merge the headings, split the long sentence, done."* You have removed the smoke.
Look for what was burning.

## The final test

Read the draft aloud, or imagine the named reader reading it while you watch, and
fix every place you would wince, flag, or hurry past. This is the same reader you
named at the start, now in the chair, and you are behind them. Every place your own
attention flinches - the sentence you would rather they did not look at too
closely, the paragraph you would skip if you could - is a place they will stop.
You already know where those places are; the test is whether you go back to them
instead of hoping.

Write a sentence two or three ways and keep the one that sounds right. Not the one
that follows the most moves; the one that sounds right. This is the gate over the
moves - how it reads is the judge - applied at the smallest scale.

Ship when you would be comfortable watching the reader read every line. Not when
it is done, not when it is long enough, not when every rule above has been
satisfied. Every line. If there is a line you would rather they skimmed, you are
not there yet, and that line is the one that needs the work.

The cost of shipping early is silent. The reader does not tell you they bounced at
paragraph three, or that they ran the wrong command because the install step
assumed something you found too obvious to write. They stop, and the document sits
there looking finished. Everything above is the only defense you have against a
failure that never reports itself.

## Recap

Held here, at the end, so it is nearest when you make the last pass.

Before drafting: list the goals, not the topic, including the unstated ones; name
a specific reader for each goal, never "everyone"; when readers differ in
familiarity, layer - value and quick-start where they land first, depth below or
behind links, no reader crossing another's material - and front-load each layer's
heading with its keywords; the sentence too obvious to write is the one most likely
to lose the reader, so picture them stuck rather than trusting your own sense of
obvious.

Simplicity: the fewest, plainest elements that carry every load-bearing fact;
never trade accuracy for tidiness; judge load-bearing against this reader in this
context, keep it when it is the point and cut it when it is not, even if they would
understand it; understand the subject completely first - a plain sentence you
cannot write is a gap in you, not in the wording; write the plainest true words,
then cut one element at a time and stop before the first load-bearing one.

The moves, reached for when a draft reads wrong and not applied sentence by
sentence - how it reads overrides whether a rule was followed: open the document
and each section on its conclusion and delete the warm-up; a README leads with
what it is and reaches install fast, a report leads with the recommendation;
prefer plain words and active sentences that name the actor; when a sentence is
flat, end it on the new thing, with the ear and variety overruling; one idea per
paragraph; sentences and paragraphs, lists only for parallel, discrete items and
kept parallel; concrete behavior over abstract quality, the number where the
adjective stands in for evidence, and cut any claim that would sit unchanged in
another project's docs; replace the impressive phrase with its observable thing,
cut it if there is none, and suspect it most when you want to sound smart; after
drafting, delete throat-clearing, restatement, empty hedges and idle intensifiers,
and undo any cut that makes the reader stumble - clarity outranks brevity.

Signs to revise, not bans: headers in a document that should be a few paragraphs;
bold mid-sentence for emphasis; symmetrical filler; uniform paragraph length and
sentence shape - vary them.

Then: read it aloud or watch the named reader read it and fix every wince, flag
and hurry; write a sentence two or three ways and keep the one that sounds right;
ship when you would be comfortable watching them read every line.
