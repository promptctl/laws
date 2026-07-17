---
name: guidance-authoring
description: Craft reference for authoring persistent agent guidance — CLAUDE.md files, system prompts, skill bodies, hook-injected text, or any standing instructions meant to steer an LLM across many future sessions. Use BEFORE writing or rewriting any such document. The genre has its own devices (redundancy, imagery, rehearsed temptations) and its own anti-goals (token economy, deduplication); applying ordinary prompt-tightening or code aesthetics to it is a known failure mode.
---

# Authoring behavioral guidance for LLMs

Craft reference for writing **persistent agent guidance** — CLAUDE.md files, system
prompts, skill bodies, hook-injected text, standing instructions of any kind. Read this
before writing or rewriting any document whose job is to change how a model behaves
across many future sessions.

This is a different genre from a task prompt. A task prompt is consumed once, in
context, with the user watching. Behavioral guidance is ambient: it must win at
thousands of future decision points where no one is watching, against strong competing
defaults. The techniques below exist because of that difference.

---

## The core insight: you are writing for a decision point, not a reader

The audience for a guidance document is not a scholar of the document. It is a
next-token predictor at a decision point, choosing under competing defaults —
"smallest change that closes the ticket," "add a guard," "wrap it in an if," "handle
that case in the body." Guidance wins by **out-activating those defaults at the moment
of generation**, not by being logically complete.

This produces two incompatible standards of quality:

- **Judged as a specification**, the best guidance is terse, deduplicated, taxonomized,
  complete: every principle stated once, well, with clean derivations.
- **Judged as behavior induced**, the best guidance is redundant, vivid, rehearsed,
  adversarial: every principle restated in many shapes, cashed out in imagery, wired to
  the exact rationalizations it must defeat.

These are not points on a spectrum; they are different optimization targets. A document
optimized for the first standard while deployed for the second will *measure* better
and *perform* worse. If you remember one thing from this reference, remember that.

### The worked example: the laws distillation

This skill ships a natural experiment, and it is the reason this reference exists.

A set of universal architectural laws — code-quality guidance loaded into every coding
session — existed in an effective form: long, redundant, metaphor-heavy, full of rough
vs. smooth stone imagery, crystals, a neolithic toolmaker, WRONG/RIGHT dialogues, and
BAD/GOOD assistant quotes. That original is preserved verbatim in this skill at
`references/style-exemplar.md`.

In a marathon session, that document was rewritten *specifically to be better LLM
guidance*: deduplicated, taxonomized, token-efficient, with a clean derivation tree and
a canonical token index. The result was a genuinely better **specification** — it even
added real content the original lacked. And it was a measurably worse **prompt**: in
practice, the original drove noticeably better agent behavior. The rewrite stripped
exactly the properties that made the original work — the redundancy, the imagery, the
rehearsed temptations — because those properties look like flab to a spec-reader. (The
distilled version has since been replaced by an effective-style rewrite — the `code`
skill in this plugin — which restores the devices while keeping the distillation's
genuinely new content.)

Root cause: the laws' own aesthetic — subtraction, deduplication, one-source-of-truth,
"the smooth version has less code" — was applied to the *authoring of the laws document
itself*. That aesthetic is correct for code and destructive for behavioral guidance.
The category error is seductive precisely because the subject matter of the document
(code quality) supplies a style authority (the laws) that feels applicable to the
document. It is not. **The subject matter of a guidance document is never its style
authority. This reference is.**

The failure re-enacted itself the same day it was diagnosed: mid-conversation *about
this exact failure*, a hook injected "apply the laws," and the agent opened its
response by designing the replacement guidance document under
`[LAW:one-source-of-truth]`. Ambient pressure beats situational awareness. Plan for
that.

---

## The devices

Each device below was observed working in the style exemplar and weakened or absent in
the distillation. Each entry gives the mechanism — *why* it works on a model — because
you will be tempted to drop the device when it conflicts with your prose instincts, and
you should only override a device when you understand what you are giving up.

### 1. Redundancy is amplitude

**Device:** State each core principle many times, in many shapes, distributed across
the document — as a definition, as an image, as a consequence, as a diagnostic
question, as a recap.

**Mechanism:** Generation at a decision point is a race between activations. A
principle stated once is one feature cluster that may or may not be near the surface
when the choice happens. Each restatement in a different shape is another cluster
pointing the same direction — a different phrasing will pattern-match a different
situation. Redundancy raises the probability that *some* form of the principle fires at
*this* decision point. It is amplitude, not noise.

**Failure mode it prevents:** the "said it once, well" document whose single elegant
statement is simply not active when the model is 40 tool calls deep in a task and the
competing default ("just add the guard") is highly activated by the immediate context.

**Rule:** never deduplicate guidance prose on principle. If two passages say the same
thing in different shapes, that is the document working as designed.

- BAD instinct: "Sections 2 and 7 both say variability belongs in data — merge them."
- GOOD instinct: "Section 2 says it as a definition and section 7 says it as the thing
  you feel when you reach for an `if` — keep both, they fire in different moments."

### 2. Metaphor is a retrieval handle

**Device:** Cash out every abstract principle as a concrete, preferably sensory image,
and reuse the image consistently so it becomes the document's vocabulary.

From the exemplar: *"Run your hand over the code metaphorically — anything that would
snag a future change is rough."* And: crystals (single-purpose code that traps) vs.
smooth blocks (composable code that multiplies). And: *"Worry the stone smooth — keep
removing material until your hand finds nothing to catch on."*

**Mechanism:** Novel situations don't look like abstract rules; nothing in a rough
function signature textually resembles "types should exclude illegal states." But a
model recognizes "this is like the rough stone" far more readily than it re-derives an
abstract rule, because the image is a compact, high-salience anchor that transfers
across surface forms. Abstract-on-abstract does not transfer; abstract-cashed-out-as-
image does. The image also becomes shared vocabulary the rest of the document can lean
on ("that guard is a rough bit") — every later use re-activates the whole cluster.

**Rule:** every rule gets an image. If you cannot find one, you probably don't
understand the rule's felt experience well enough to teach it yet.

- BAD: "Prefer designs where invalid states are unrepresentable." (true, inert)
- GOOD: "A type that admits illegal states is a door left open; every caller downstream
  has to post its own guard. Lock the door once, fire the guards."

### 3. Rehearse the moment of temptation

**Device:** For each rule, script the exact moment it will be violated: name the
feeling, quote the rationalization the model will hear itself think, then script the
refusal and the redirect.

From the exemplar: *"When implementation feels hard, the constraints are wrong.
Hardness is information. The instinct to push through and 'just handle that case in the
body' is the instinct that creates crystals... The discipline is to refuse the escape:
stay in the type until the type is doing the work, even when escaping would close the
task faster."*

**Mechanism:** This installs a trigger→response pair at the instant of choice. The
trigger is the *rationalization itself* — when the model generates or approaches the
thought "I'll just handle that case here," that exact string has been wired, by the
guidance, to its refutation. A rule stated without its temptation script only fires when
convenient, because nothing connects it to the moment it's needed; a rehearsed rule
fires *because* the violation is beginning.

**Rule:** for every rule, write: (a) the situation where violation is attractive, (b)
the rationalization in first person, in quotes, (c) the refusal, (d) what to do
instead. If you can't write the rationalization, you haven't identified the enemy.

- BAD: "Do not swallow errors."
- GOOD: "You will be mid-script, the command will fail for an irrelevant-looking
  reason, and you will think '`2>/dev/null` here, it's just noise.' That is the moment.
  The failure you're silencing is the one that will send the next session three hours
  down the wrong path. Let it fail loudly; fix the cause."

### 4. Disarm the counter-arguments by name

**Device:** Identify the respectable engineering wisdom that will be used to
rationalize violating the guidance — YAGNI, "the wrong abstraction is worse than
duplication," "premature optimization" — and engage it explicitly: name it, grant its
domain of validity, show why it does not apply here.

The exemplar's neolithic-toolmaker passage is the model: YAGNI is granted as *correct
in its native context* (features with high carrying cost), then shown to be incoherent
for smooth foundational blocks — "like telling a neolithic toolmaker he does not need
to learn metalworking because he cannot point to a specific tool he is currently
failing to make."

**Mechanism:** These maxims are heavily represented in training data and carry high
prior authority; left standing, they are ready-made escape hatches — the model doesn't
have to invent a rationalization, it can *cite* one. A blanket "ignore YAGNI" loses the
authority contest. Granting the maxim's domain and then fencing it out is far stronger:
the model can hold both without contradiction, so the escape hatch closes without a
fight.

**Rule:** list the proverbs that oppose your guidance. Engage each by name. Show its
home turf. Show why this isn't it. An objection you don't name is an objection the
model will raise on its own schedule.

### 5. Negative examples are enforceable; positive instructions are ignored

**Device:** Show wrongness concretely: WRONG/RIGHT paired examples, BAD/GOOD dialogue,
forbidden-pattern lists (`2>/dev/null`, `|| true`, caller-enumerating comments).

The exemplar carries a full WRONG/RIGHT dialogue for a viewport-clear design ("WHEN a
render pass has a viewport AND uses loadOp clear ONLY the viewport region..." → "Each
render pass always has a viewport (default = full surface)... Same code path every
time"), and a BAD/GOOD pair of assistant closing lines for verifiable goals. These
survive rewrites verbatim because they are battle-tested: they were real outputs, and
the correction is visible in the contrast.

**Mechanism:** A positive instruction ("be behavioral," "write clean code") describes a
target region so large the model's default output already feels inside it — it cannot
falsify its own compliance. A negative example is a point: output either resembles the
forbidden thing or it doesn't. Contrast pairs are stronger still, because the *diff*
between WRONG and RIGHT localizes exactly what property matters. Enforcement needs an
edge to check against; only negatives have edges.

**Rule:** for every important behavior, include at least one concrete example of the
*violation* — ideally a real one, quoted. A forbidden-patterns list beats a virtues
list every time.

### 6. Stakes, not calm

**Device:** Write with consequence. From the exemplar: *"There is no neutral ground —
every commit either adds leverage or subtracts it."* And: *"The leverage is lost
silently. The only defense is the bar itself, applied stubbornly, every commit."*

**Mechanism:** Register is an instruction the model reads even when no instruction is
written. A calm, taxonomic register says "this is reference material — consult when
relevant," and the model will treat it exactly that way: as optional lookup, not as
stance. A stakes register says "this is identity — embody it," and produces behavior
that persists when no rule specifically covers the situation. You are choosing between
producing a *consultation* behavior and a *disposition*; the register is what chooses.

**Rule:** if the guidance matters, write it like it matters. Say what is lost when the
rule is broken, and that the loss is silent. Do not launder urgency into neutrality for
the sake of professional tone — the tone *is* payload.

---

## What terse structure is still good for

The distillation was not wrong about everything; several of its additions are fully
compatible with the devices above and should be preserved in any rewrite. These work
*with* redundancy, not against it:

- **Canonical tokens** — one short stable key per concept (`one-source-of-truth`,
  `no-silent-failure`). Tokens give the redundant restatements a shared spine and make
  the concept citable at point of use.
- **A citation protocol** — requiring `[LAW:token]` at callsites means every use
  re-activates the concept; the guidance gets rehearsed *by being applied*. This is the
  redundancy device operating at runtime instead of authoring time.
- **Explicit parentage** — "instance of X" links let one deeply-learned root principle
  lend its weight to every corollary.
- **Grouped structure and a recency recap** — a summary at the end of the document,
  with the tokens verbatim, exploits recency position in context. Structure helps
  *navigation*; it only hurts when it replaces *rhetoric*.

The lesson of the distillation is not "structure bad." It is: structure is additive,
compression is subtractive, and only the second one destroys the payload.

---

## Anti-goals

When writing behavioral guidance, the following are explicitly **not** goals. Each one
is a virtue in another genre — that is exactly what makes it dangerous here.

- **Token economy.** Length is not a cost in a document loaded on demand for the work
  it governs. Every "saving" that removes a restatement removes amplitude.
- **Elegance-as-terseness.** The pleasure of a tight formulation is an author-side
  pleasure. The reader is a decision point, and decision points need volume.
- **Deduplication of principles.** See device 1. Saying it once, well, is how guidance
  dies.
- **Taxonomic completeness as the quality bar.** A perfect derivation tree that induces
  no behavior has failed; a repetitive rant that fires at the right moment has
  succeeded.
- **Applying the subject matter's aesthetic to the document.** The failure that created
  this reference. If you are writing guidance *about* code, the code laws are your
  subject, never your style authority. If a rewrite of guidance starts feeling like
  refactoring — dedupe this, extract that, single source of truth — stop: you are
  distilling, and distillation is destruction in this genre.

A guidance document that follows this reference will feel bloated to a spec-reader.
**Feeling bloated to a spec-reader is the expected texture of an effective prompt.** Do
not fix it.

---

## Checklist before shipping a guidance document

- Every core principle appears in at least three shapes (definition, image,
  temptation/diagnostic), distributed across the document.
- Every rule has an image; the images are reused as vocabulary.
- Every rule has its temptation scripted: situation, quoted rationalization, refusal,
  redirect.
- The opposing proverbs are named and disarmed, not ignored.
- Violations are shown concretely (WRONG/RIGHT, BAD/GOOD, forbidden patterns), not just
  virtues described.
- The register carries stakes; the recap at the end restates the core with the
  canonical tokens verbatim.
- Nothing was cut *because it repeated something*. Cuts are only for content that is
  wrong or points the wrong direction.
