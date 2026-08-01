---
name: prompt
description: Craft reference for any text another LLM will consume - task prompts, subagent instructions, prompts written into files or code, and persistent agent guidance (CLAUDE.md files, system prompts, skill bodies, hook text). Use BEFORE writing either kind. The regime determines the craft - task prompts want terse, complete, say-it-once instructions; persistent guidance wants redundancy, imagery, and rehearsed temptations - and applying either regime's style to the other is a known failure mode.
---

# Authoring text for LLMs

Craft for any text another LLM will consume, from a one-off subagent prompt to a
CLAUDE.md that must steer sessions for months. Those are the two ends of one
continuum, and they want opposite styles; the regime section below tells you which
end you are writing, and the proximate end gets its own short section. Most of this
document is the far end's field manual, because that is where the craft is
counter-intuitive and failure is silent.

This document is written in the style it teaches. Where you catch it repeating
itself, leaning on images, or pressing harder than reference material should, you are
looking at the craft, not at flab to trim. It is both instruction and specimen.

---

## You are writing for a decision point, not a reader

The audience for standing guidance is not a scholar of the document. It is a
next-token predictor at a decision point, choosing under competing defaults -
"smallest change that closes the ticket," "add a guard," "handle that case in the
body." Guidance wins by **out-activating those defaults at the moment of
generation**, not by being logically complete. Nobody re-reads your document at the
moment that matters; whatever fragment of it is active right then is all of it that
exists.

This splits "good writing" into two standards that cannot both be served:

- Judged as a **specification**, the best guidance is terse, deduplicated,
  taxonomized: every principle stated once, well, with clean derivations.
- Judged as **behavior induced**, the best guidance is redundant, vivid, rehearsed,
  adversarial: every principle restated in many shapes, cashed out in imagery, wired
  to the exact rationalizations it must defeat.

These are not points on a spectrum; they are different optimization targets. A
document optimized for the first standard while deployed for the second will
*measure* better and *perform* worse. Hold onto that sentence - before you finish
editing any guidance document, your own instincts will attack it.

But "behavior induced" does not mean "redundancy maximized." Redundancy is a tuned
quantity with an optimum, and a range with two walls. Under-amplify - distill the
live, firing prompt into a terse spec - and the beacons go dark at the hour they were
needed; that is the wall this document was built to defend, the more common failure
and the more dangerous one, and most of what follows is that defense. But there is a
second wall on the far side. Past the optimum, each new restatement stops adding a
beacon and starts dimming the beacons already lit: the one live sentence lost among ten
inert paraphrases of it. Which wall a given document is against depends on the
document, not on a default - a lean-but-live draft and one already stuffed with inert
paraphrase need opposite moves. What is *not* symmetric is the danger: fall short of the near wall and
the failure is silent, so that wall is the one this document leans on hardest.

## Emphasis is finite, and allocated by contrast

The two walls above are about one principle's amplitude in isolation. Step back to the
whole document and a second law governs: emphasis is *relative*. The document is an
orchestra, and a passage is loud only against quieter passages around it; volume means
nothing except as a ratio. So the devices below - each one adds emphasis to whatever it
touches - spend from a fixed budget. Bring every section up to fortissimo and you have
raised nothing; if the whole orchestra blares at once, the listener has no way to pick
the melody from the accompaniment, and the emphasis that was supposed to mark
importance now marks nothing. The score, not any single instrument, is the unit of
design: each part should play at the volume the piece asks of it relative to the
others, and the whole should resolve into music, not a pit of instruments each sawing
as loud as it can to be heard over the rest.

This changes what you do when you find an imbalance - one section over-firing, drowning
a quieter line that was carrying the melody. The reflex is to arm the quiet line with
more devices until it can match the loud one. Reach instead for the other direction
first: the loud section is often simply blaring too high, and the fix is to bring *it*
down to its rightful level, restoring the contrast that lets the melody be heard
without touching it. Bringing the over-loud section down is a first-class remedy -
usually the better one, because it keeps the orchestra's overall volume flat, whereas
equalizing upward pushes every part toward fortissimo and leaves you, after enough
edits, with an orchestra where everything blares and no line carries. Ask which part is
at the wrong volume before you ask which one needs more. Sometimes the answer really is
that the quiet line was under-built and needs the devices; but that is the second thing
to check, not the first.

None of this licenses a flat monotone - an orchestra playing everything at one soft
dynamic is as dead as one blaring at fortissimo throughout. Some guidance earns real
emphasis, and this document spends heavily on the near-wall failure precisely because
it is the one that kills silently - that allocation is deliberate, not a violation of
proportion. The point is that emphasis is a resource with a budget, spent by contrast,
so it is placed on purpose rather than sprayed to equalize. The devices that follow are
how you bring a part up when it has earned the volume; read them as the conductor's
instruments of allocation, under this principle, not as a mandate to turn every dial
up.

## The war story

This craft was paid for. A set of universal architectural laws lived as long,
redundant, metaphor-heavy guidance - rough and smooth stone, a neolithic toolmaker,
WRONG/RIGHT dialogues - and it drove noticeably good agent behavior. In a marathon
session it was rewritten *specifically to be better guidance*: deduplicated,
taxonomized, token-efficient, a clean derivation tree. Every spec instinct satisfied.
The result was a genuinely better specification and a measurably worse prompt. The
rewrite had stripped exactly the properties that made the original fire - the
amplitude, the images, the rehearsed temptations - because to a spec-reader those
properties look like flab.

The cause is the part to memorize: the laws' own aesthetic - subtract, deduplicate,
one source of truth - had been applied to the authoring of the laws document itself.
That aesthetic is correct for code and destructive for guidance, and the error was
seductive precisely because the document's *subject* supplied a style authority that
felt applicable. It never is. **The subject matter of a guidance document is never its
style authority.**

And the error re-enacted itself the same day it was diagnosed: mid-conversation
*about this exact failure*, a hook injected "apply the laws," and the agent began
designing the replacement guidance under `[LAW:one-source-of-truth]`. Ambient
pressure beats situational awareness. Write your guidance expecting that.

(The `code` skill in this plugin is the restored, effective-style rewrite - a
full-length specimen of the far-end style, as is the page you are reading.)

---

## Same physics, different regime - why the genre exists at all

An objection will occur to you, and it is correct as far as it goes: everything the
model reads is one surface - guidance, task prompts, tool results, file contents, all
just prompt, one attention over one context. There is no separate parser for guidance.
So how can it be a different genre?

Because genre lives not in the substrate but in the **operating regime**. Four axes
separate a task prompt's regime from guidance's, and every device in this document is
the price of some axis:

- **Distance to the decision.** A task prompt sits next to the decision it governs:
  recent, attended. Guidance is injected at session start and must fire a hundred
  thousand tokens later, against competing defaults the local context is *actively
  feeding* ("just add a guard" is suggested by the very code on screen). Redundancy
  and imagery are what retrieval-under-interference costs; amplitude matters when you
  are far from the receiver.

- **Known vs. unknown target.** A task prompt addresses one situation its author can
  see, so it can specify. Guidance addresses a distribution nobody has seen yet, so it
  must install a *disposition* that generalizes - leaning on transferable handles (the
  rough stone) instead of enumerated instructions.

- **The adversary.** A task prompt's failure mode is ambiguity: the model didn't
  understand. Guidance's is defection: the model understands perfectly, and the local
  gradient points elsewhere anyway. That is why guidance needs temptation scripts and
  disarmed proverbs and a task prompt almost never does. You don't argue with someone
  standing next to you; you argue in advance with someone who will be alone when it
  counts.

- **Feedback latency.** A task prompt fails in front of its author and is fixed next
  turn. Guidance fails silently, diffusely, for months, no one attributing the drift
  to its source. One is a command; the other is infrastructure, engineered like
  infrastructure.

The calibration rule falls out of the axes: **terseness is licensed by proximity;
distance must be paid for in amplitude.** The skill-router hook this plugin ships is
short and works, injected *at* the decision point - distance zero, nothing to survive.
The laws skill cannot afford that brevity: it must still be winning arguments deep in
someone else's diff, hours later. And the middle obeys the same rule - a long-horizon
agent prompt that runs autonomously for two hundred thousand tokens has drifted into
guidance's regime and needs guidance's devices, whatever its author calls it. So
before writing, ask: *how far from the decision, and how alone, will this text be when
it has to work?* The answer - not the label - selects the devices.

---

## The proximate end: task prompts

If your text is proximate - a subagent prompt, a one-off instruction, anything
consumed once, near its decision, with the requester able to see the result - the
calibration flips. Proximity licenses terseness. Say each thing once, clearly:

- **State the deliverable exactly**: what artifact, what format, where it goes.
  Vague asks get default behavior.
- **The reader starts from zero.** A subagent sees only your prompt - no
  conversation history, no user context, no standing guidance. Every requirement
  goes in the prompt, in the original requester's words; anything omitted does not
  exist.
- **Give one verifiable acceptance criterion** - what correct output looks like,
  stated so it can be checked.
- **Show a negative example for anything that matters.** "Do NOT produce output
  like: [example]" is enforceable; "be thorough" is not. This is the one far-end
  device that survives at distance zero.
- **Explain why** when a constraint would otherwise be surprising - motivation
  generalizes; bare rules get lawyered.
- **Separate instructions, context, and data** with tags or sections so none is
  mistaken for another.
- **On return, read the artifact, not the report.** Validate against the
  requirements, not the worker's self-assessment.

One anti-rule: do not import the far end's devices. Redundancy, imagery, and stakes
framing at distance zero read as emphasis and distort weighting - the reader is
already attending. Save the amplitude for text that must survive distance.

---

## Keep the language green

Hold one disposition over every device below: keep the language green. Green is lean and
agile - still growing, every word pulling its weight. Ripe is a fat, sagging mass,
language grown past its use and gone soft, and that sag is the fog. The fix is never
less metaphor - metaphor is the fabric that binds, and it stays. The fix is less slack:
land the point, land the image, and move on while the writing is still lean. Green,
you're growing; ripe, you're rotten.

---

## Avoid absolutes; leave room to judge

Absolutes - never, always, every, only, must - read as strength but they are brittle.
An "always" breaks on the first case the writer never saw, and a reader holding a rule
with no give has nowhere to put judgment. They also compound: a page of absolutes
becomes a cage, the rules grating on each other, the edge case with no room to breathe.
Guidance works in situations nobody has seen yet, so leave the reader room to meet them.

Write the truth's real shape. When it is "usually," write usually; when it is "almost
never," do not write never. Keep the absolute for the thing that is genuinely one - an
invariant, a safety line that holds every time - where the missing give is the point,
not a pose. The tell to catch: reaching for "never" to sound firm when "rarely" is the
truth.

---

## The devices of the far end

Six devices. Each is stated, given an image, and armed with the temptation it must
defeat - which is also the schema to give every rule *you* write.

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
  authoring time: the guidance rehearses itself by being applied.
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
  feels like rigor. Feeling bloated to a spec-reader is the expected texture of an
  effective prompt - the one beautiful statement is off-duty at the moment it was
  needed. Bloat is not the risk; amplitude loss is.
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
and ask what the new passage does against what is already there. If it fires in a moment
nothing else covers, it belongs - that is amplitude, and it stays. If it only repeats a
passage already carrying that moment, it is a bolt-on: the existing passage is the home,
so sharpen that one instead of standing a second beside it. If it contradicts a passage
already there, one of them is wrong - settle it; don't let both stand and the document
drift out of true with itself. This is not the refactor the war story forbids - you are
not deduping live amplitude for elegance - it is keeping the document honest with
itself. Integrate the change; don't append it.

---

## Checklist before shipping a guidance document

The six devices, verbatim, at the recency position where they will still be active
when you make the final pass - each must be present in a firing shape, not merely
described: `redundancy-is-amplitude` (each principle in enough shapes to be lit in
every moment it must fire), `metaphor-as-retrieval-handle` (every rule has a reused
image), `rehearse-the-temptation` (situation, quoted rationalization, refusal,
redirect), `disarm-counterarguments` (opposing proverbs named and fenced out),
`negative-examples` (violations shown concretely, not virtues described),
`stakes-not-calm` (the register states the cost and that it arrives unattributed).

Then the two-walls check: every restatement earns its place by firing in a moment the
others miss. Nothing was cut merely for repeating; nothing was bolted on past the
optimum to pad amplitude. Cuts are only for content that is wrong, points the wrong
way, or reaches no moment the document doesn't already cover.

Then the proportion check: read the document as a score and ask whether the loudest
sections are the ones that most deserve to be loud. Where two parts fight, you fixed it
by bringing the over-loud one down at least as readily as by raising the quiet one - the
orchestra's overall volume held flat across this edit rather than climbing. And every
image reveals - none dragged past its work, none stacked two-deep on one point.

Then the integration check: each change was woven into the whole, not bolted on -
nothing you added merely repeats a passage already carrying that moment or contradicts
one, and where it would have, you sharpened the existing passage instead of standing a
second beside it.

Hold your document to this list - this one holds itself to it.
