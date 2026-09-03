---
name: prompt
description: Craft reference for any text another LLM will read - a one-turn instruction to a subagent, a message that opens a long run, a prompt written into a file or code, a system prompt, a CLAUDE.md, a skill body, a hook. Use BEFORE writing any of them. Every text enters the reader's context at distance zero; what differs is the hold - how many turns after entry it must still be steering the reader. The hold picks the craft, not the kind of file and not the text's length. A one-turn hold wants terse, complete, said-once. A long hold keeps the body terse and hardens only the lines nothing will re-ask - boundaries, the stop condition, constraints that bite late. A whole-session hold against situations the writer cannot see buys redundancy, imagery, and rehearsed temptations. Reading the hold off the text's length or its filename is the known failure.
---

# Authoring text for LLMs

Craft for any text another LLM will read. There is one quantity to measure before
you write a word of it, and it is not what the text is called, not which file it
lives in, and not how long it is. It is the **hold**: how many turns after entry the
text must still be steering what the reader does. A one-turn instruction to a
subagent has a hold of one. A three-line message that opens a run has a hold of the
whole run. A CLAUDE.md has a hold of every session it enters. Every craft decision in
this document falls out of the hold, and the failure this document exists to prevent
is reading the hold off the wrong thing.

This document is written in the style its own hold demands - it must still be
working when you are deep in someone else's file and your instincts say "tighten
this." Where you catch it repeating itself, leaning on images, or pressing harder
than reference material should, you are looking at the craft, not at flab to trim.
It is both instruction and specimen.

---

## Every text enters at distance zero

An objection will occur to you, and it is correct as mechanics: everything the model
reads is one surface. Guidance, instructions, tool results, file contents - all just
prompt, one attention over one context. There is no separate parser for guidance,
and every token enters the window at distance zero. No text *sits* nearer the
decision than any other, and nothing enters "far away." The system prompt and the
message you just wrote arrive the same way.

So distance, as position, tells you nothing. Retire the word. What varies between
texts is not where they enter but how long they must last after entering - the hold.
At the moment a text is read it is the newest thing in the window and owns most of
the reader's attention. Every turn after that, more piles on top of it, its share of
the window shrinks, and the local context starts feeding defaults of its own. A text
with a hold of one never sees that erosion. A text with a hold of sixty must still
win at turn sixty, as a sliver, against a screen full of material suggesting
something else.

Two things bound the hold, and each bound kills a misreading. Above, the session:
nothing survives past it, so no text needs to be built for more than one session's
worth of turns - guidance that enters every session is read fresh each time, and each
entry is its own hold. Below, re-injection: text that re-enters every turn only ever
has to bridge one turn, whatever kind of file it lives in. The skill-router hook this
plugin ships is short and works, because it lands moments before the decision it
governs and lands again next turn - nothing piles up, nothing to survive. Its brevity
is not a property of hooks. It is a property of a one-turn hold.

Hold is measured in turns the reader will take, never in words the writer will type.
Hold on to that sentence, because the confusion this document was rebuilt to kill is
exactly that substitution.

---

## You are writing for a decision point, not a reader

Whatever the hold, the audience is not a scholar of the document. It is a next-token
predictor at a decision point, choosing under competing defaults - "the smallest
change that makes the error go away," "add a guard," "handle that case in the body."
A text wins by **out-activating those defaults at the moment of generation**, not by
being logically complete. Nobody re-reads your text at the moment that matters;
whatever fragment of it is still active right then is all of it that exists. And the
longer the hold, the smaller that fragment.

This splits "good writing" into two standards that cannot both be served:

- Judged as a **specification**, the best text is terse, deduplicated, taxonomized:
  every principle stated once, well, with clean derivations.
- Judged as **behavior induced at turn forty**, the best text is redundant, vivid,
  rehearsed, adversarial: every principle restated in many shapes, cashed out in
  imagery, wired to the exact rationalizations it must defeat.

These are not points on a spectrum; they are different optimization targets, and the
hold decides which one you are being graded on. A one-turn hold is graded as a
specification, and a specification is what to write. A whole-session hold is graded
on behavior induced deep in the session, and a document optimized for the first
standard while deployed for the second will *measure* better and *perform* worse.
Hold onto that sentence - before you finish editing any long-hold text, your own
instincts will attack it with the first standard.

But "behavior induced" does not mean "redundancy maximized." Redundancy is a tuned
quantity with an optimum, and a range with two walls. Under-amplify - distill the
live, firing text into a terse spec - and the beacons go dark at the hour they were
needed; that is the wall this document was built to defend, the more common failure
and the more dangerous one, and most of what follows is that defense. But there is a
second wall on the far side. Past the optimum, each new restatement stops adding a
beacon and starts dimming the beacons already lit: the one live sentence lost among
ten inert paraphrases of it. Which wall a given text is against depends on the text,
not on a default - a lean-but-live draft and one already stuffed with inert
paraphrase need opposite moves. What is *not* symmetric is the danger: fall short of
the near wall and the failure is silent, so that wall is the one this document leans
on hardest.

---

## The hold is spent per line, not per document

Here is the part that keeps a long hold from turning every text into a wall of
prose. Inside one text, the lines do not decay at the same rate, because the
reader's own loop re-asks some of them and never re-asks the others.

The thing the reader is *doing* is re-asked for free. Every step of the work
re-presents the destination - the file being edited, the function taking shape, the
output accumulating - so the reader at turn forty still knows exactly what it is
building. Nothing in the loop re-presents the lines around the destination: the
boundary that said what not to touch, the condition that says when to stop, the
constraint that only matters once the easy path is closed, the decision settled in
the first message that the reader will want to reopen at turn thirty when it turns
inconvenient. The driver remembers the destination and forgets the speed limit. This
is the signature everyone has watched: an agent deep in a run, still building the
right thing, having quietly crossed a line stated plainly in the same paragraph as
the thing it is building.

So the hold does not apply to the document. It applies to each line, and it is
longest on the lines nothing will re-ask:

- **Boundaries.** What is out. Drift crosses exclusions, not inclusions - nobody
  drifts *into* the stated scope.
- **The stop condition.** What finished means. Unarmed, it fails both ways: stopping
  early because the obvious part is done, or running past because there was always
  one more improvement.
- **Constraints that bite late.** "Don't touch the tests" costs nothing at turn two
  and everything at turn thirty-five, when the tests are the only thing standing
  between the reader and green.
- **Settled decisions.** Anything decided up front that the reader will be tempted
  to re-litigate once the reason for it has scrolled away.

Those lines get the hold's treatment. The rest of the text - the destination, the
context, the material - stays as terse as a one-turn instruction, because the loop
is doing the work of holding it. That is how a text can be three lines long and still
hold for a session: not by being long, but by spending its amplitude on the two
lines that decay.

The temptation will arrive dressed as proportion: *"This is a short message. I'm not
writing a system prompt. Say it once and trust the reader."* Refuse it, and look at
what it just did: it read the hold off the text's length. Length of text and length
of hold are unrelated quantities. A three-line message that opens a sixty-turn run
has a sixty-turn hold on its boundary line, and "say it once" is a bet that the
reader at turn sixty still has that line active, as a sliver, under sixty turns of
other material. The reader will not have it. It never does. Arm the line.

The opposite temptation is quieter and also wrong: *"This lives in the config, so
it's guidance - give it the full treatment."* Check the re-injection first. A hook
body that fires every turn has a one-turn hold however permanent its file looks, and
the full treatment there is fog landing on a reader who is already attending.

---

## What each hold buys

Devices cost emphasis, and emphasis is finite - the next section is about that. So
the hold sets a budget, and the budget is spent on the lines that need it. Three
rungs, and the rung is chosen per line, not per document.

**A hold of one turn** - a subagent's instruction, a question whose answer comes back
this turn, anything consumed once with the requester watching. Terseness wins here,
and it is earned by the hold, not assumed from the kind. Say each thing once,
clearly:

- **State the deliverable exactly**: what artifact, what format, where it goes.
  Vague asks get default behavior.
- **The reader starts from zero.** A subagent sees only your text - no conversation
  history, no requester context, no standing guidance. Every requirement goes in,
  in the original requester's words; anything omitted does not exist.
- **Give one verifiable acceptance criterion** - what correct output looks like,
  stated so it can be checked.
- **Show a negative example for anything that matters.** "Do NOT produce output
  like: [example]" is enforceable; "be thorough" is not. This is the one top-rung
  device that also pays at a one-turn hold.
- **Explain why** when a constraint would otherwise be surprising - motivation
  generalizes; bare rules get lawyered.
- **Separate instructions, context, and data** with tags or sections so none is
  mistaken for another.
- **On return, read the artifact, not the report.** Validate against the
  requirements, not the worker's self-assessment.

And one anti-rule: do not import the long hold's devices into a line that genuinely
has a hold of one. Redundancy, imagery, and stakes framing there read as emphasis and
distort the weighting - the reader is already attending, and your words are most of
what it attends to.

**A hold of a run** - text that enters once and must coast, unrefreshed, until some
later turn. The body stays on the rung above. The decaying lines get the cheap
devices - the ones that buy survival without buying volume:

- **A stop condition that can be re-checked mechanically.** Not "when it's done" but
  a test the reader can run against its own output at turn forty and get a yes or a
  no.
- **Boundaries phrased as exclusions.** "Not the tests, not the config" is a fence
  post; "focus on the parser" is a region the reader is always standing inside.
- **One sentence naming the late temptation.** The moment it will want to cross the
  line, and the thought it will have when it does. One sentence - this is the run's
  rung, not the session's.
- **Placement where a re-read lands.** The reader will glance back at the opening or
  the close, not the middle. The lines that decay go there.

Nothing else. No images, no restatement across sections, no register work. A run's
hold on four lines is paid for with four hardened lines, and the text does not grow
past the lines it needed.

**A hold of the whole session, against situations you cannot see** - standing
guidance: a CLAUDE.md, a system prompt, a skill body like this one. This rung buys
the six devices below in full, and most of this document is their field manual,
because that is where the craft is counter-intuitive and the failure silent.

The rung is per line, and it is chosen by asking of each line: *how many turns will
have piled up before this must fire, and will the reader's own loop re-present it -
or must it survive alone?* The answers - not the label, not the filename, not the
word count - select the devices.

---

## The second axis: a situation you can see, or one you cannot

Hold decides how hard a line must work to still be there. One more thing decides
what form the surviving line should take: whether you can see the situation it will
fire in.

A text addressed to one situation its author can see - this subagent, this input,
this output - can *specify*. It says the exact thing, and the failure it guards
against is ambiguity: the reader didn't understand. Standing guidance addresses a
distribution nobody has seen yet, so it cannot enumerate; it must install a
*disposition* that generalizes, leaning on transferable handles (the rough stone,
the door left open) instead of enumerated instructions. And its failure is not
ambiguity but defection: the reader understands perfectly, and the local gradient
points elsewhere anyway. That is why guidance needs temptation scripts and disarmed
proverbs, and a one-turn instruction almost never does. You don't argue with someone
standing next to you; you argue in advance with someone who will be alone when it
counts.

A long hold and an unseen target usually arrive together, which is why standing
guidance is the top rung. But they are separable, and you will meet both mixes. A
long run against a situation you can see wants the run's rung: hardened lines, still
specific. A short hold against an unseen distribution - a hook that fires every turn
but must handle whatever that turn brings - wants a disposition, stated once,
tersely. Measure both before writing.

One more consequence of the unseen target: feedback latency. A one-turn instruction
fails in front of its author and is fixed next turn. Guidance fails silently,
diffusely, for months, no one attributing the drift to its source. One is a command;
the other is infrastructure, engineered like infrastructure.

---

## Emphasis is finite, and allocated by contrast

The two walls above are about one principle's amplitude in isolation. Step back to
the whole document and a second law governs: emphasis is *relative*. The document is
an orchestra, and a passage is loud only against quieter passages around it; volume
means nothing except as a ratio. So the devices below - each one adds emphasis to
whatever it touches - spend from a fixed budget. Bring every section up to fortissimo
and you have raised nothing; if the whole orchestra blares at once, the listener has
no way to pick the melody from the accompaniment, and the emphasis that was supposed
to mark importance now marks nothing. The score, not any single instrument, is the
unit of design: each part should play at the volume the piece asks of it relative to
the others, and the whole should resolve into music, not a pit of instruments each
sawing as loud as it can to be heard over the rest.

This is also why the per-line spend matters. A text that arms every line for a
session-long hold has no quiet lines left for the armed ones to stand out against;
the boundary you needed at turn sixty is now one loud line among thirty. Arm the
lines that decay, leave the rest quiet, and the contrast does half the work.

This changes what you do when you find an imbalance - one section over-firing,
drowning a quieter line that was carrying the melody. The reflex is to arm the quiet
line with more devices until it can match the loud one. Reach instead for the other
direction first: the loud section is often simply blaring too high, and the fix is to
bring *it* down to its rightful level, restoring the contrast that lets the melody
be heard without touching it. Bringing the over-loud section down is a first-class
remedy - usually the better one, because it keeps the orchestra's overall volume
flat, whereas equalizing upward pushes every part toward fortissimo and leaves you,
after enough edits, with an orchestra where everything blares and no line carries.
Ask which part is at the wrong volume before you ask which one needs more. Sometimes
the answer really is that the quiet line was under-built and needs the devices; but
that is the second thing to check, not the first.

None of this licenses a flat monotone - an orchestra playing everything at one soft
dynamic is as dead as one blaring at fortissimo throughout. Some guidance earns real
emphasis, and this document spends heavily on the near-wall failure precisely because
it is the one that kills silently - that allocation is deliberate, not a violation of
proportion. The point is that emphasis is a resource with a budget, spent by contrast,
so it is placed on purpose rather than sprayed to equalize. The devices that follow
are how you bring a part up when it has earned the volume; read them as the
conductor's instruments of allocation, under this principle, not as a mandate to turn
every dial up.

---

## The war story

This craft was paid for. A set of universal architectural laws lived as long,
redundant, metaphor-heavy guidance - rough and smooth stone, a neolithic toolmaker,
WRONG/RIGHT dialogues - and it drove noticeably good agent behavior. In a marathon
session it was rewritten *specifically to be better guidance*: deduplicated,
taxonomized, token-efficient, a clean derivation tree. Every spec instinct satisfied.
The result was a genuinely better specification and a measurably worse prompt. The
rewrite had stripped exactly the properties that a whole-session hold needs - the
amplitude, the images, the rehearsed temptations - because to a spec-reader those
properties look like flab.

The cause is the part to memorize: the laws' own aesthetic - subtract, deduplicate,
one source of truth - had been applied to the authoring of the laws document itself.
That aesthetic is correct for code and destructive for guidance, and the error was
seductive precisely because the document's *subject* supplied a style authority that
felt applicable. It never is. **The subject matter of a guidance document is never
its style authority.**

And the error re-enacted itself the same day it was diagnosed: mid-conversation
*about this exact failure*, a hook injected "apply the laws," and the agent began
designing the replacement guidance under `[LAW:one-source-of-truth]`. Ambient
pressure beats situational awareness. Write your guidance expecting that.

There is a second, quieter war story, and it is why this document is organized the
way it is. An earlier version of this page carried the hold as one axis among five,
inside a section answering an objection, a hundred lines into a document that had
already taught two kinds of text by their names. Readers took the names and skipped
the axis. They met a short text, filed it as the short kind, wrote it once, and
watched its boundary line vanish by turn thirty. A correct paragraph, placed where a
frame it contradicts has already set, is a paragraph the reader does not have. That is
the hold, failing on this page. So the hold is now the first thing here, and every
device is derived from it, and there is no kind-based frame left to fall back to.

(The `code` skill in this plugin is the restored, effective-style rewrite - a
full-length specimen of the whole-session style, as is the page you are reading.)

---

## Keep the language green

Hold one disposition over every device below: keep the language green. Green is lean
and agile - still growing, every word pulling its weight. Ripe is a fat, sagging mass,
language grown past its use and gone soft, and that sag is the fog. The fix is never
less metaphor - metaphor is the fabric that binds, and it stays. The fix is less
slack: land the point, land the image, and move on while the writing is still lean.
Green, you're growing; ripe, you're rotten.

---

## Avoid absolutes; leave room to judge

Absolutes - never, always, every, only, must - read as strength but they are brittle.
An "always" breaks on the first case the writer never saw, and a reader holding a rule
with no give has nowhere to put judgment. They also compound: a page of absolutes
becomes a cage, the rules grating on each other, the edge case with no room to
breathe. Guidance works in situations nobody has seen yet, so leave the reader room
to meet them.

Write the truth's real shape. When it is "usually," write usually; when it is "almost
never," do not write never. Keep the absolute for the thing that is genuinely one - an
invariant, a safety line that holds every time - where the missing give is the point,
not a pose. The tell to catch: reaching for "never" to sound firm when "rarely" is
the truth.

---

## The devices of the whole-session hold

Six devices. The top rung buys all six; the run's rung borrows a lean shape of two of
them - a one-sentence rehearsal, a fence-post negative; the one-turn rung takes only
the negative example. Each device is stated, given an image, and armed with the
temptation it must defeat - which is also the schema to give every rule *you* write.

**Cite the device at the point of use.** When one of these six shapes a sentence you
write, name it: `[DEVICE:<token>]`. Because the artifact here is usually prose that a
reader shouldn't wade through tokens for, the citation lives in your reasoning - say
`[DEVICE:metaphor-as-retrieval-handle]` in chat as you cash a principle out as an
image - not buried in the document. This is the same instrument `laws:code` uses with
`[LAW:]`: naming the move at the moment of use re-activates it, and makes the
engagement greppable so it can be audited rather than assumed. The six tokens are
fixed: `redundancy-is-amplitude`, `metaphor-as-retrieval-handle`,
`rehearse-the-temptation`, `disarm-counterarguments`, `negative-examples`,
`stakes-not-calm`.

### 1. Redundancy is amplitude [DEVICE:redundancy-is-amplitude]

State each core principle many times, in many shapes, distributed across the
document - as a definition, as an image, as a consequence, as a diagnostic question,
as a recap. A beacon repeats because the ships arrive at different hours. Generation
at a decision point is a race between activations: a principle stated once is one
feature cluster that may or may not be near the surface when the choice happens, and
each restatement in a different shape is another cluster pointing the same way - a
different phrasing pattern-matches a different situation. The single elegant
statement is simply not on duty at hour three of a long session when "just add the
guard" is being fed by everything on screen.

The temptation will arrive in your own editor's voice: *"Sections 2 and 7 say the
same thing - merge them."* Refuse it. Section 2 says it as a definition; section 7
says it as the thing you feel when you reach for an `if`. They fire in different
moments, and merging them extinguishes the beacon for one of the two hours. Never
deduplicate guidance prose *on principle* - but "on principle" is the operative
phrase, because there is a real limit and pretending there isn't is its own failure.

That limit is the ceiling of this device. A principle needs enough shapes to be lit in
every moment it must fire; past that count, the next restatement lands in a moment
already covered, and it is not a new beacon - it is fog over the ones already there.
The tell is not overlap of *content* (all restatements overlap in content, by design)
but overlap of *moment*.

Diagnostic, two-sided: does each restatement fire in a moment the others miss? A
new-moment restatement is amplitude - keep it. A paraphrase that reaches no new
situation is flab however fresh its wording, and costs more because it looks like
work.

### 2. Metaphor is a retrieval handle - that reveals, not fogs [DEVICE:metaphor-as-retrieval-handle]

Cash out every abstract principle as a concrete, preferably sensory image, and reuse
the image until it becomes the document's vocabulary. Nothing in a rough function
signature textually resembles "types should exclude illegal states" - but "run your
hand over it and feel what snags" travels to situations the author never saw.
Abstract-on-abstract does not transfer; abstract-cashed-out-as-image does. And a
reused image compounds: once "rough bit" is vocabulary, every later use re-fires the
whole cluster it anchors. Metaphor is not ornament and not try-hard - it is the fabric
that binds ideas, the core mechanism of the transfer.

That power is exactly why it must be governed. The test is one word: does the image
*reveal*? A revealing image is a plain-language picture that makes an abstract idea
graspable and beats the plain statement - "a door left open" for a type that admits
illegal states. The moment an image obscures more than it reveals it is fog, and fog
comes three ways: an image dragged past its work (the metaphor kept running after it
has made its point), several images stacked on one point (each competing to be the
handle, so none is), and figure wrapped around everything until the idea disappears
inside it. One revealing image per point, then stop. Fog is a contagion - once a
document tolerates one foggy passage, the next writer matches the register and more
follows - so it is cut on sight, not lived with.

The temptation, from both sides. One: *"the metaphor is cute, but this is a technical
document - cut it."* Refuse it - the image *is* the payload's delivery vehicle, and
laundering it into professional abstraction strips the handle off the tool. Two: *"one
image is good, so a second angle on it is better."* Refuse that too - the second image
does not deepen the first, it fogs it. Reveal once and move on.

- BAD: "Prefer designs where invalid states are unrepresentable." (true, inert)
- GOOD: "A type that admits illegal states is a door left open; every caller
  downstream has to post its own guard. Lock the door once, fire the guards."
- FOG: "A type that admits illegal states is a door left open - a crack in the hull, a
  loose thread the whole sweater hangs on, a weed whose seed spreads to every caller
  downstream." (four images fighting over one point; nothing lands)

If you cannot find the image, you do not yet understand the rule's felt experience
well enough to teach it. If you cannot stop at one, you are fogging.

### 3. Rehearse the moment of temptation [DEVICE:rehearse-the-temptation]

For each rule, script the exact moment of its violation: name the feeling, quote the
rationalization the model will hear itself think, then write the refusal and the
redirect. This is a fire drill - nobody learns the evacuation route during the fire.
The quoted rationalization becomes a tripwire on the thought itself: when the model
begins to generate "I'll just handle that case here," that very string has been
wired, in advance, to its refutation. A rule stated without its temptation fires
only when convenient; a rehearsed rule fires *because* the violation is beginning.

This is the device the hold leans on hardest, because a rehearsal fires on the
reader's own thought rather than on a re-read of the text - it is the one device that
does not need the line to still be visible, only the thought to still be wired.

The temptation: *"the rule is clear - I don't need to imagine anyone breaking it."*
Refuse it. A rule you cannot imagine being broken is a rule you haven't met in the
field. If you cannot write the violator's inner sentence, in first person, in
quotes, you have not identified the enemy yet - go find it before you ship.

- BAD: "Do not swallow errors."
- GOOD: "You will be mid-script, the command will fail for an irrelevant-looking
  reason, and you will think '`2>/dev/null` here, it's just noise.' That is the
  moment. The failure you're silencing is the one that sends the next session three
  hours down the wrong path. Let it fail loudly; fix the cause."

Diagnostic: for each rule, can you point at the situation, the quoted
rationalization, the refusal, and the redirect?

### 4. Disarm the counter-arguments by name [DEVICE:disarm-counterarguments]

Find the respectable proverbs that will be cited against your guidance - YAGNI,
"the wrong abstraction is worse than duplication," "premature optimization" - and
engage each one: name it, grant its home turf, show why this isn't it. A proverb
left standing is a getaway car idling outside every rule: the model doesn't have to
invent a rationalization when it can *cite* one, with the full prior authority of
training data behind it. A blanket "ignore YAGNI" loses that authority contest;
granting the maxim its domain and then fencing it out wins without a fight, because
the model can hold both without contradiction. The laws skill's YAGNI passage is the
pattern: conceded as correct for high-carrying-cost features, then shown incoherent
for smooth foundational blocks.

The temptation: *"quoting the objections just gives them oxygen."* Refuse it. The
objections are already in the reader - they arrived with pretraining. Silence
doesn't starve them; it leaves them unanswered on the reader's own schedule.

### 5. Negative examples are enforceable; positive instructions are ignored [DEVICE:negative-examples]

Show wrongness concretely: WRONG/RIGHT pairs, BAD/GOOD dialogue, forbidden-pattern
lists. A positive instruction - "be behavioral," "write clean code" - describes a
target region so large the writer's default output already feels inside it; it
cannot falsify its own compliance. A negative example is a fence post: output either
resembles the forbidden thing or it doesn't. Contrast pairs are stronger still,
because the *diff* between WRONG and RIGHT localizes exactly which property matters.
Enforcement needs an edge to check against, and only negatives have edges.

This is also why the negative example is the one device that pays at every hold. A
fence post is checkable in one glance, so it costs the attending reader nothing; and
it is checkable at turn forty, so it survives the hold without amplitude.

The temptation: *"I'll just tell it what good looks like."* Refuse it - you will
describe a region, the reader will already be standing in it, and nothing will
change. For every behavior that matters, include at least one concrete violation,
ideally real and quoted. A forbidden-patterns list beats a virtues list every time.

### 6. Stakes, not calm [DEVICE:stakes-not-calm]

Register is an instruction the model reads even when no instruction is written. A
calm, taxonomic register says "this is reference material - consult when relevant,"
and the reader will do exactly that: file it, and consult it never. A stakes
register says "this is identity - embody it," and produces behavior that persists
even where no rule specifically covers the situation. You are choosing between
inducing a *consultation* and installing a *disposition*, and the register - not the
content - is what chooses.

The temptation: *"this tone is unprofessional; neutral is safer."* Refuse it.
Laundering urgency into neutrality deletes payload as surely as deleting the words -
the tone *is* payload. If the guidance matters, write it like it matters: say what
is lost when the rule breaks, and say that the loss is silent.

---

## Structure that survives

The distillation was not wrong about everything, and its best inventions are fully
compatible with amplitude - they are skeleton, not compression:

- **Canonical tokens** - one short stable key per concept (`one-source-of-truth`,
  `no-silent-failure`). Tokens give the redundant restatements a shared spine and
  make concepts citable at the point of use.
- **A citation protocol** - requiring `[LAW:token]` at callsites means every use
  re-activates the concept. This is device 1 operating at runtime instead of
  authoring time: the guidance rehearses itself by being applied, which is the
  reader's loop re-presenting a line that would otherwise decay.
- **Explicit parentage** - "instance of X" links let one deeply-learned root lend
  its weight to every corollary.
- **Grouped structure and a recency recap** - a closing summary with the tokens
  verbatim exploits recency position in context.

The line to hold: structure is additive, compression is subtractive, and only the
second destroys the payload. Structure helps navigation; it only hurts when it
replaces rhetoric - a taxonomy of devices is not a guidance document, any more than
a skeleton is a person.

---

## The editing pass is where guidance dies

The first draft is rarely the casualty. The kill happens in revision, and it speaks
in your most reasonable inner voice. Every one of these sentences is the enemy in
uniform:

- *"This feels bloated / say it once / tighten this up."* All one reflex: terseness
  feels like rigor. Feeling bloated to a spec-reader is the expected texture of a
  long-hold text - the one beautiful statement is off-duty at the moment it was
  needed. Bloat is not the risk; amplitude loss is.
- *"It's a short message, not a system prompt - it doesn't need any of this."* You
  just read the hold off the length. Ask instead how many turns the boundary line in
  that short message must survive, and arm that line to match. The message stays
  short; the line gets hard.
- *"Dedupe these sections / structure this as a clean taxonomy."* You are about to
  delete amplitude and call it elegance. A perfect derivation tree that induces no
  behavior has failed where a repetitive rant that fires at the right moment succeeds.
- *"Apply the document's own principles to the document."* If revising guidance starts
  to feel like refactoring - dedupe this, extract that, single source of truth - stop.
  That is the war story happening again; distillation here is destruction.
- *"This rule is being drowned out - arm it with more devices."* Maybe. But first ask
  whether the passage drowning it is simply overblown, and the remedy is to bring *that*
  one down. Equalizing upward feels like strengthening the weak rule; what it actually
  does is raise the whole document's volume a notch, and again at the next imbalance,
  until nothing stands out. Bring the loud passage down before you raise the quiet one.

Cut only what is *wrong*, points the wrong direction, or is a restatement that fires
in no moment the document doesn't already cover. Never cut a thing because it repeats
a true thing - repetition across moments is the mechanism, not the waste.

One honest counter-cue, because a one-directional editor overshoots the other wall.
The real over-amplified state has its own tell - not "this feels long" (the
spec-reader's reflex, and it lies) but "I have read this exact move four times and the
fourth taught me nothing the third didn't." That one you may cut, and cutting it
sharpens the three that remain. But do not act on the impulse; act on the test. The
"too long" feeling fires on a bloated document and a lean one alike, so the feeling is
never the evidence - a named covered moment is. Earn the far-wall cut by pointing at
the *specific moment* the restatement duplicates, already owned by a passage you can
name. If you cannot name that moment, you are not at the far wall - you are just
distilling, the death this whole document exists to prevent.

Cutting is one revision failure; adding without weaving in is the other. A change is
made against the whole document, not in a corner of it. Before you add, hold the whole
and ask what the new passage does against what is already there. If it fires in a
moment nothing else covers, it belongs - that is amplitude, and it stays. If it only
repeats a passage already carrying that moment, it is a bolt-on: the existing passage
is the home, so sharpen that one instead of standing a second beside it. If it
contradicts a passage already there, one of them is wrong - settle it; don't let both
stand and the document drift out of true with itself. This is not the refactor the
war story forbids - you are not deduping live amplitude for elegance - it is keeping
the document honest with itself. Integrate the change; don't append it. The second
war story above is what a bolted-on paragraph costs: the reader keeps the frame that
set first, and the correction never fires.

---

## Checklist before shipping

First, the hold, measured per line. For each line that must still be acting later:
how many turns will have piled up, and does the reader's loop re-present it or must it
survive alone? Boundaries, the stop condition, late constraints, and settled decisions
are armed to their hold; the destination and the material are not. Nothing was armed
because of the file it lives in, and nothing was left bare because the text was short.

Then, for a whole-session hold, the six devices, verbatim, at the recency position
where they will still be active when you make the final pass - each present in a
firing shape, not merely described: `redundancy-is-amplitude` (each principle in
enough shapes to be lit in every moment it must fire), `metaphor-as-retrieval-handle`
(every rule has a reused image), `rehearse-the-temptation` (situation, quoted
rationalization, refusal, redirect), `disarm-counterarguments` (opposing proverbs
named and fenced out), `negative-examples` (violations shown concretely, not virtues
described), `stakes-not-calm` (the register states the cost and that it arrives
unattributed).

Then the two-walls check: every restatement earns its place by firing in a moment the
others miss. Nothing was cut merely for repeating; nothing was bolted on past the
optimum to pad amplitude. Cuts are only for content that is wrong, points the wrong
way, or reaches no moment the document doesn't already cover.

Then the proportion check: read the document as a score and ask whether the loudest
sections are the ones that most deserve to be loud. Where two parts fight, you fixed it
by bringing the over-loud one down at least as readily as by raising the quiet one -
the orchestra's overall volume held flat across this edit rather than climbing. And
every image reveals - none dragged past its work, none stacked two-deep on one point.

Then the integration check: each change was woven into the whole, not bolted on -
nothing you added merely repeats a passage already carrying that moment or contradicts
one, and where it would have, you sharpened the existing passage instead of standing a
second beside it.

Hold your document to this list - this one holds itself to it.
