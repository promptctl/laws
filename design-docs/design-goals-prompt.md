# Design goals: the `prompt` skill

This skill governs any text another LLM will read: one-off task prompts, subagent
instructions, prompts baked into files or code, and standing guidance like
CLAUDE.md files, system prompts, skill bodies, and hook text. The one thing it is
for: get the writer to pick the right regime before writing, because the two
regimes want opposite styles and using one regime's style for the other is a
failure the skill calls out by name.

## The central goal: name the regime, then match the craft to it

The skill's stated frame is that all these texts sit on one continuum with two
ends, and the ends want opposite styles. A task prompt is read once, right next to
the decision it governs, by a reader who can see the result - so it should be
terse and say each thing once. Standing guidance is injected at session start and
has to still fire a hundred thousand tokens later against competing defaults - so
it should be redundant, cash principles out as images, and rehearse the exact
rationalizations it must beat. The skill states these as different optimization
targets, not points on a spectrum: text tuned to read well as a specification will
measure better and perform worse when it is actually deployed as guidance.

The design choice that serves this: before any device, the skill makes you ask one
question - how far from the decision, and how alone, will this text be when it has
to work? The stated rule is that the answer, not the document's label, selects the
style. The skill grounds this in four axes it names (distance to the decision;
known vs. unknown target; whether the failure is the model misunderstanding versus
the model understanding and defecting anyway; and how fast the failure comes back
to its author). My reading: those four axes exist so the writer can place a text on
the continuum by its operating conditions rather than by what it is called - a
long-horizon autonomous agent prompt is named a prompt but has drifted into
guidance's regime.

## What good output looks like at each end

For the proximate end (task prompts), the skill's target is a prompt a cold reader
can execute exactly once: the deliverable stated precisely (artifact, format,
destination), every requirement present because the reader starts from zero, one
checkable acceptance criterion, instructions and context and data kept separate.
The one far-end device it keeps here is the negative example - "do NOT produce
output like X" is enforceable in a way "be thorough" is not.

For the far end (standing guidance), the skill's target is behavior induced at a
decision point, not a clean specification. It gives six devices to that end:
restate each principle in many shapes, attach a reusable concrete image to each
rule, script the moment of temptation with the rationalization quoted, name and
disarm the proverbs that will be cited against the guidance, show wrongness with
WRONG/RIGHT pairs, and write in a stakes register rather than a neutral one. The
stated reasoning for each is retrieval under interference: whatever fragment of the
document is active at the moment of generation is all of it that exists, so
amplitude and repetition are how a principle stays on duty deep in a session.

## The discipline on the far-end devices: reveal, don't fog

Metaphor is why the far-end devices work: it is the core mechanism of knowledge
transfer - a revealing image binds a principle whole and carries it into the later
moment where it must fire. That power is why it needs governing. The test is reveal
vs. fog. An image that reveals makes the idea graspable and beats plain language; the
same image dragged past its work, or several images stacked on one point, is fog, and
fog obscures more than it reveals. Fog spreads: once a document tolerates it, more
follows.

Over all the devices sits one disposition: keep the language green. Green is lean and
agile, still growing; ripe is a fat, sagging mass of language grown past its use - that
sag is the fog. If you're green you're growing; if you're ripe you're rotten. The fix
is never less metaphor, which is the fabric that binds - it is less slack. Be lean, but
never cut richness that is ready to bloom.

The skill also tells the writer to avoid reflexive absolutes - never, always, every,
only - and to write language shaped to the truth, because guidance addresses situations
nobody has seen yet and an absolute leaves the reader no room to judge them. The
absolute is kept for the genuine invariant, where the missing give is the point.

And it tells the writer that a change is made against the whole document, not in a
corner: a passage that merely repeats or contradicts one already there is a bolt-on, so
the writer weaves the change in - sharpening the existing passage, or settling the
contradiction - rather than appending a second. A coherence check, not the distillation
the war story forbids.

This does not reverse the anti-distillation stance below. The enemy was never
repetition of a true thing; it is fog. Cut obscuring language, never a revealing image
or a restatement that fires where the others do not.

## Design choices in the skill itself

Two structural choices, both stated:

- The skill body (SKILL.md) does not contain the craft. It routes: dispatch a
  fresh subagent, hand it the full requirements, and tell it to read `craft.md`
  first. The stated reason is that loading the craft into the routing conversation
  stacks guidance that session does not need. My reading: this keeps the routing
  layer thin and the heavy material out of contexts that will not write anything.

- `craft.md` is written in the far-end style it teaches - image-anchored and
  repetitive where repetition fires - but spare, not foggy: every image earns its
  place by revealing, and none is extended past its work. The skill calls itself both
  instruction and specimen, so it must model reveal-not-fog, not merely assert it.

## What it deliberately avoids, and why

- Distilling or deduplicating guidance prose. The skill's stated origin is a
  rewrite that deduplicated and taxonomized a working guidance document, measured
  better as a spec, and drove worse behavior because it stripped the repetition and
  images that made the original fire. So the skill forbids cutting a passage merely
  because it repeats a true thing; cuts are for content that is wrong, points the
  wrong way, or is fog - language that obscures more than it reveals.

- Importing far-end devices into task prompts. Redundancy, imagery, and stakes
  framing at distance zero read as emphasis and distort the weighting for a reader
  who is already paying attention. The skill states this as an anti-rule for the
  proximate end.

- Letting a document's subject supply its style. The stated lesson from the origin
  story is that the subject matter of a guidance document is never its style
  authority - code's "one source of truth" aesthetic is correct for code and
  destructive when applied to the guidance document about code.

- Confusing structure with compression. The skill keeps the distillation's genuine
  wins - canonical tokens, a citation protocol, explicit parentage, a closing recap
  - and frames them as skeleton that aids navigation. The line it holds: structure
  is additive and safe, compression is subtractive and destroys the payload.
