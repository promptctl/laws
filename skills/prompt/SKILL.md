---
name: prompt
description: Craft reference for any text another LLM will consume — task prompts, subagent instructions, prompts written into files or code, and persistent agent guidance (CLAUDE.md files, system prompts, skill bodies, hook text). Use BEFORE writing either kind. The regime determines the craft — task prompts want terse, complete, say-it-once instructions; persistent guidance wants redundancy, imagery, and rehearsed temptations — and applying either regime's style to the other is a known failure mode.
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
next-token predictor at a decision point, choosing under competing defaults —
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
*measure* better and *perform* worse. Hold onto that sentence — before you finish
editing any guidance document, your own instincts will attack it.

## The war story

This craft was paid for. A set of universal architectural laws lived as long,
redundant, metaphor-heavy guidance — rough and smooth stone, crystals, a neolithic
toolmaker, WRONG/RIGHT dialogues — and it drove noticeably good agent behavior. In a
marathon session it was rewritten *specifically to be better guidance*:
deduplicated, taxonomized, token-efficient, a clean derivation tree, a canonical
token index. Every spec instinct satisfied. The result was a genuinely better
specification and a measurably worse prompt. The rewrite had stripped exactly the
properties that made the original fire — the amplitude, the images, the rehearsed
temptations — because to a spec-reader those properties look like flab.

The cause is the part to memorize: the laws' own aesthetic — subtract, deduplicate,
one source of truth — had been applied to the authoring of the laws document itself.
That aesthetic is correct for code and destructive for guidance, and the error was
seductive precisely because the document's *subject* supplied a style authority that
felt applicable to the document. It never is. **The subject matter of a guidance
document is never its style authority.**

And the error re-enacted itself the same day it was diagnosed: mid-conversation
*about this exact failure*, a hook injected "apply the laws," and the agent began
designing the replacement guidance under `[LAW:one-source-of-truth]`. Ambient
pressure beats situational awareness. Write your guidance expecting that.

(The `code` skill in this plugin is the restored, effective-style rewrite — a
full-length specimen of the far-end style, as is the page you are reading.)

---

## Same physics, different regime — why the genre exists at all

An objection will occur to you, and it is correct as far as it goes: everything the
model reads is one surface. Guidance, task prompts, tool results, file contents — it
is all just prompt, processed by the same attention over the same context by the same
next-token machinery. There is no separate parser for guidance. So how can it be a
different genre?

Because genre lives not in the substrate but in the **operating regime**. Four axes
separate a task prompt's regime from guidance's, and every device in this document is
the price of some axis:

- **Distance to the decision.** A task prompt sits next to the decision it governs:
  recent, on-topic, attended. Guidance is injected at session start and must fire
  dozens of tool calls and a hundred thousand tokens later — against competing
  defaults that the local context is *actively feeding* ("just add a guard" is
  suggested by the very code on screen). Redundancy and imagery are not decoration;
  they are what retrieval-under-interference costs. Amplitude matters when you are
  far from the receiver.

- **Known vs. unknown target.** A task prompt addresses one situation its author can
  see, so it can specify. Guidance addresses a distribution of situations nobody has
  seen yet, so it must install a *disposition* that generalizes — which is why it
  leans on transferable handles (the rough stone) instead of enumerated instructions.

- **The adversary.** A task prompt's failure mode is ambiguity: the model didn't
  understand. Guidance's failure mode is defection: the model understands perfectly,
  and the local gradient points elsewhere anyway. That is why guidance needs
  temptation scripts and disarmed proverbs, and a task prompt almost never does. You
  don't argue with someone standing next to you; you argue in advance with someone
  who will be alone when it counts.

- **Feedback latency.** A task prompt fails in front of its author and is fixed in
  the next turn. Guidance fails silently, diffusely, for months, with no one
  attributing the drift to its source. One is a command; the other is
  infrastructure, and you engineer it like infrastructure.

These are ends of a continuum, not a binary — and the calibration rule falls out of
the axes: **terseness is licensed by proximity; distance must be paid for in
amplitude.** The skill-router hook this plugin ships is short and works, because it
is injected *at* the decision point — distance zero, nothing to survive. The laws
skill cannot afford that brevity, because it must still be winning arguments deep in
someone else's diff, hours later. And the middle of the continuum obeys the same
rule: a long-horizon agent prompt that will run autonomously for two hundred
thousand tokens has drifted into guidance's regime and needs guidance's devices —
restated constraints, anchors, recaps — no matter that its author calls it a prompt.

Before writing, ask the regime question: *how far from the decision, and how alone,
will this text be when it has to work?* The answer — not the document's label —
selects the devices.

---

## The proximate end: task prompts

If your text is proximate — a subagent prompt, a one-off instruction, anything
consumed once, near its decision, with the requester able to see the result — the
calibration flips. Proximity licenses terseness. Say each thing once, clearly:

- **State the deliverable exactly**: what artifact, what format, where it goes.
  Vague asks get default behavior.
- **The reader starts from zero.** A subagent sees only your prompt — no
  conversation history, no user context, no standing guidance. Every requirement
  goes in the prompt, in the original requester's words; anything omitted does not
  exist.
- **Give one verifiable acceptance criterion** — what correct output looks like,
  stated so it can be checked.
- **Show a negative example for anything that matters.** "Do NOT produce output
  like: [example]" is enforceable; "be thorough" is not. This is the one far-end
  device that survives at distance zero.
- **Explain why** when a constraint would otherwise be surprising — motivation
  generalizes; bare rules get lawyered.
- **Separate instructions, context, and data** with tags or sections so none is
  mistaken for another.
- **On return, read the artifact, not the report.** Validate against the
  requirements, not the worker's self-assessment.

One anti-rule: do not import the far end's devices. Redundancy, imagery, and stakes
framing at distance zero read as emphasis and distort weighting — the reader is
already attending. Save the amplitude for text that must survive distance.

---

## The devices of the far end

Six devices. Each is stated, given an image, and armed with the temptation it must
defeat — which is also the schema to give every rule *you* write.

### 1. Redundancy is amplitude

State each core principle many times, in many shapes, distributed across the
document — as a definition, as an image, as a consequence, as a diagnostic question,
as a recap. A beacon repeats because the ships arrive at different hours. Generation
at a decision point is a race between activations: a principle stated once is one
feature cluster that may or may not be near the surface when the choice happens, and
each restatement in a different shape is another cluster pointing the same way — a
different phrasing pattern-matches a different situation. The single elegant
statement is simply not on duty at hour three of a long session when "just add the
guard" is being fed by everything on screen.

The temptation will arrive in your own editor's voice: *"Sections 2 and 7 say the
same thing — merge them."* Refuse it. Section 2 says it as a definition; section 7
says it as the thing you feel when you reach for an `if`. They fire in different
moments, and merging them extinguishes the beacon for one of the two hours. Never
deduplicate guidance prose on principle.

- BAD instinct: "these two passages overlap — consolidate."
- GOOD instinct: "these two passages overlap in content and differ in shape — that
  is the document working as designed."

Diagnostic: is each restatement a *different shape* of the principle? Different
shapes are amplitude; identical copy-paste is the only true flab.

### 2. Metaphor is a retrieval handle

Cash out every abstract principle as a concrete, preferably sensory image, and reuse
the image until it becomes the document's vocabulary. Nothing in a rough function
signature textually resembles "types should exclude illegal states" — but "run your
hand over it and feel what snags" travels to situations the author never saw.
Abstract-on-abstract does not transfer; abstract-cashed-out-as-image does. And a
reused image compounds: once "rough bit" is vocabulary, every later use re-fires the
whole cluster it anchors.

The temptation: *"the metaphor is cute, but this is a technical document — cut it."*
Refuse it. The image is not ornament on the payload; the image *is* the payload's
delivery vehicle, and laundering it into professional abstraction strips the handle
off the tool.

- BAD: "Prefer designs where invalid states are unrepresentable." (true, inert)
- GOOD: "A type that admits illegal states is a door left open; every caller
  downstream has to post its own guard. Lock the door once, fire the guards."

Diagnostic: does every rule have an image that a novel situation could *resemble*?
If you cannot find one, you do not yet understand the rule's felt experience well
enough to teach it.

### 3. Rehearse the moment of temptation

For each rule, script the exact moment of its violation: name the feeling, quote the
rationalization the model will hear itself think, then write the refusal and the
redirect. This is a fire drill — nobody learns the evacuation route during the fire.
The quoted rationalization becomes a tripwire on the thought itself: when the model
begins to generate "I'll just handle that case here," that very string has been
wired, in advance, to its refutation. A rule stated without its temptation fires
only when convenient; a rehearsed rule fires *because* the violation is beginning.

The temptation: *"the rule is clear — I don't need to imagine anyone breaking it."*
Refuse it. A rule you cannot imagine being broken is a rule you haven't met in the
field. If you cannot write the violator's inner sentence, in first person, in
quotes, you have not identified the enemy yet — go find it before you ship.

- BAD: "Do not swallow errors."
- GOOD: "You will be mid-script, the command will fail for an irrelevant-looking
  reason, and you will think '`2>/dev/null` here, it's just noise.' That is the
  moment. The failure you're silencing is the one that sends the next session three
  hours down the wrong path. Let it fail loudly; fix the cause."

Diagnostic: for each rule, can you point at the situation, the quoted
rationalization, the refusal, and the redirect?

### 4. Disarm the counter-arguments by name

Find the respectable proverbs that will be cited against your guidance — YAGNI,
"the wrong abstraction is worse than duplication," "premature optimization" — and
engage each one: name it, grant its home turf, show why this isn't it. A proverb
left standing is a getaway car idling outside every rule: the model doesn't have to
invent a rationalization when it can *cite* one, with the full prior authority of
training data behind it. A blanket "ignore YAGNI" loses that authority contest;
granting the maxim its domain and then fencing it out wins without a fight, because
the model can hold both without contradiction. The laws skill's YAGNI passage is the
pattern: conceded as correct for high-carrying-cost features, then shown incoherent
for smooth foundational blocks — like telling a neolithic toolmaker he doesn't need
metalworking because he can't name a specific tool he's currently failing to make.

The temptation: *"quoting the objections just gives them oxygen."* Refuse it. The
objections are already in the reader — they arrived with pretraining. Silence
doesn't starve them; it leaves them unanswered on the reader's own schedule.

Diagnostic: list the proverbs that oppose your guidance. Has each been engaged by
name, granted its domain, and fenced out of this one?

### 5. Negative examples are enforceable; positive instructions are ignored

Show wrongness concretely: WRONG/RIGHT pairs, BAD/GOOD dialogue, forbidden-pattern
lists. A positive instruction — "be behavioral," "write clean code" — describes a
target region so large the writer's default output already feels inside it; it
cannot falsify its own compliance. A negative example is a fence post: output either
resembles the forbidden thing or it doesn't. Contrast pairs are stronger still,
because the *diff* between WRONG and RIGHT localizes exactly which property matters.
Enforcement needs an edge to check against, and only negatives have edges.

The temptation: *"I'll just tell it what good looks like."* Refuse it — you will
describe a region, the reader will already be standing in it, and nothing will
change. For every behavior that matters, include at least one concrete violation,
ideally real and quoted. A forbidden-patterns list beats a virtues list every time.

Diagnostic: for each important behavior, can the reader point at the forbidden
thing?

### 6. Stakes, not calm

Register is an instruction the model reads even when no instruction is written. A
calm, taxonomic register says "this is reference material — consult when relevant,"
and the reader will do exactly that: file it, and consult it never. A stakes
register says "this is identity — embody it," and produces behavior that persists
even where no rule specifically covers the situation. You are choosing between
inducing a *consultation* and installing a *disposition*, and the register — not the
content — is what chooses.

The temptation: *"this tone is unprofessional; neutral is safer."* Refuse it.
Laundering urgency into neutrality deletes payload as surely as deleting the words —
the tone *is* payload. If the guidance matters, write it like it matters: say what
is lost when the rule breaks, and say that the loss is silent.

Diagnostic: does the document state the cost of violation — and that the cost
arrives unattributed?

---

## Structure that survives

The distillation was not wrong about everything, and its best inventions are fully
compatible with amplitude — they are skeleton, not compression:

- **Canonical tokens** — one short stable key per concept (`one-source-of-truth`,
  `no-silent-failure`). Tokens give the redundant restatements a shared spine and
  make concepts citable at the point of use.
- **A citation protocol** — requiring `[LAW:token]` at callsites means every use
  re-activates the concept. This is device 1 operating at runtime instead of
  authoring time: the guidance rehearses itself by being applied.
- **Explicit parentage** — "instance of X" links let one deeply-learned root lend
  its weight to every corollary.
- **Grouped structure and a recency recap** — a closing summary with the tokens
  verbatim exploits recency position in context.

The line to hold: structure is additive, compression is subtractive, and only the
second destroys the payload. Structure helps navigation; it only hurts when it
replaces rhetoric — a taxonomy of devices is not a guidance document, any more than
a skeleton is a person.

---

## The editing pass is where guidance dies

The first draft is rarely the casualty. The kill happens in revision, and it speaks
in your most reasonable inner voice. Every one of these sentences is the enemy in
uniform:

- *"This feels bloated."* Feeling bloated to a spec-reader is the expected texture
  of an effective prompt. Bloat is not the risk; amplitude loss is.
- *"Say it once, well."* That is how guidance dies — one beautiful statement,
  off-duty at the moment it was needed.
- *"Dedupe these sections."* You are about to delete amplitude and call it rigor.
- *"Tighten this up / make it elegant."* Elegance-as-terseness is an author-side
  pleasure. The reader is a decision point, and decision points need volume.
- *"Let's structure this as a clean taxonomy."* A perfect derivation tree that
  induces no behavior has failed; a repetitive rant that fires at the right moment
  has succeeded.
- *"Apply the document's own principles to the document."* The failure that created
  this skill. If revising guidance starts to feel like refactoring — dedupe this,
  extract that, single source of truth — stop. You are distilling, and in this
  genre distillation is destruction.

Cut only what is *wrong* or points the wrong direction. Never cut a thing because it
repeats a true thing.

---

## Checklist before shipping a guidance document

- Every core principle appears in at least three shapes (definition, image,
  temptation/diagnostic), distributed across the document.
- Every rule has an image; the images are reused as vocabulary.
- Every rule has its temptation scripted: situation, quoted rationalization,
  refusal, redirect.
- The opposing proverbs are named and disarmed, not ignored.
- Violations are shown concretely (WRONG/RIGHT, BAD/GOOD, forbidden patterns), not
  just virtues described.
- The register carries stakes; the recap at the end restates the core with the
  canonical tokens verbatim.
- Nothing was cut *because it repeated something*. Cuts are only for content that is
  wrong or points the wrong direction.

Hold your document to this list — this one holds itself to it.
