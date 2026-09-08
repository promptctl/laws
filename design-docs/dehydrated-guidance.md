# Dehydrated guidance: the concepts of a craft without its effects

**2026-09-08, owner direction; design record, not yet built.** Each craft gets a
second, inactive form that lists what the craft contains without engaging the
reader in its standard. A session uses it to reason about a craft (what is already
there, where a new section fits, what a law says) when reading the craft itself
would corrupt the work at hand.

## What the owner asked for

A "dehydrated" or inactive version of the guidance, for the code craft and the prose
craft and by extension every craft, usable when a session wants the concepts but not
the effects. The motivating case: writing a new section for the code guidance. The
material has to be prepared conceptually against what the code craft already says,
but reading the code craft engages it, and an engaged code craft degrades prompt
writing, which is what authoring a craft section is.

## The problem it solves

A craft is written to change how the reader works for a whole session. That is its
purpose and the source of its cost. The guard in `hooks/scripts/skill-router.sh`
refuses loading laws:prompt after laws:code because the engaged code standard was
shown to corrupt prompt text written afterwards. The prescribed escape is a fresh
subagent seeded with only the other craft.

That escape covers doing the other craft's work. It does not cover a third case:
reasoning about a craft's content without adopting its standard. Today a session in
that position has two options, and both are bad. Read the craft and take the
engagement, or work blind.

The observability brainstorm on 2026-09-07 is the live example. Asked how a new law
would fit beside the existing ones, the session wrote "as I remember them" about which
laws exist and guessed at whether fail-loud already covered the case. The resulting
design doc could not name which laws the new one sits beside. An inventory of the
code craft would have answered both questions in one read, without engaging anything.

## The claim the design rests on

A craft's hold on the reader comes from its devices, not its propositions. The
whole-session form buys redundancy, imagery, second-person address, rehearsed
temptations, and paired examples of good and bad output. Those are what keep the
standard active turns later. An abstract, emotionally uninvolving statement of the
same law carries the concept and none of the pull.

This is the hypothesis the design commits to. There is no fallback design if it
fails; the test below says whether it holds.

## No binding devices outside the guidance

A binding device is a device used to bind context to the agent's attention. Law
tokens, the `[LAW:...]` markers the code craft uses, are one. They exist to make the
agent hold a law in attention while it works, and that is exactly the effect the
inventory must not have.

So the inventory may discuss law tokens as a concept, and it names each law in plain
words, but the tokens themselves never appear in it. The rule is general: no binding
device may appear outside the guidance. Anything whose job is to bind attention
belongs in the craft and nowhere else.

## What a dehydrated file contains

One file per craft, called its inventory below, sitting next to the craft it
describes. It holds:

- A status line saying what the file is and is not: it lists the craft's contents so a
  reader can reason about them, and it does not engage the craft. Doing the medium's
  work requires loading the craft through the Skill tool as today.
- The medium's purpose in one flat paragraph.
- A map of the craft's sections, in order, so a writer can see where a new section
  slots.
- One entry per law: its plain-words name, the property in one indicative sentence,
  what it rules out, and which bindings specialize it. No token, no examples.
- One line per domain binding and one line per device.
- The refused orderings involving this craft, stated as facts with the reason.
- The size of the live craft in tokens, so a writer preparing a section knows the
  budget they are adding to.

Today the code craft carries 22 laws across about 9,800 words. The prompt craft
carries 2; prose, ticket, and application-spec carry none and are organized by
section instead. An inventory is one line per law or section, so it should be a small
fraction of the craft it describes. Size is not a target; one line per item is the
rule, and the size follows.

## The register that makes it inactive

The inventory is emotionally uninvolving and abstract. That is the whole of the
register rule; everything else follows from it. The craft grips by being concrete,
vivid, and addressed to the reader. The inventory releases by being none of those.

In practice that means third person and indicative mood, each point stated once, no
metaphor or imagery, no rehearsed temptation, no good-versus-bad example pairs, and
paraphrase in place of the craft's own memorable phrasing, since that phrasing is
part of its hold. This is the opposite of the prose craft's "concrete beats
abstract," on purpose: concreteness is what makes text stick, and the inventory is
not supposed to stick.

In the prompt craft's terms, this is a text written for a zero-turn hold. It is read,
consulted, and left behind.

## Who does not write it

Who writes the inventory is not worth documenting. Who does not write it is.

The session that will consume the inventory does not write it. Writing requires
reading the craft, and a session that has read the craft has taken the engagement
the inventory exists to avoid.

A session engaged in some other craft does not write it as a side task. The
inventory has its own register and its own rule about binding devices, and a session
holding a different standard writes in that standard.

## A craft of its own

The owner's direction is that dehydrating guidance may want a separate craft: a
medium whose deliverable is the inactive description of another craft, with the
register above as its standard and the binding-device rule as its constraint. Under
the laws editing skill in `.claude/skills/laws/SKILL.md` that makes it a medium like
the others, with a goals doc, a `SKILL.md`, and a `references/craft.md`, rather than
a fourth file bolted onto each existing medium.

What is not settled is how that craft relates to the guard. Its writer has to read
the target craft to describe it, so either the dehydrating craft's standard is strong
enough to describe an engaged craft without leaking it, or the writing happens in a
disposable session whose only output is the inventory. Which of those holds is a
question for the craft's design, not this doc.

## Keeping it true

The inventory is a second description of the craft's content, and a second
description drifts. This is the design's main risk and the reason it needs a
mechanical check.

Recommended: the inventory is authored, not generated, and a test enforces parity.
For the code craft, every law in the craft has an entry in the inventory and every
entry names a law in the craft, matched on the law's plain-words name rather than its
token, since the token is not allowed in the inventory. For every craft, the section
headings match in order. A new law or section added to a craft without an inventory
entry fails the check. The test lives beside the existing hook tests so it runs where
they run.

Rejected: generating the inventory from the craft. The crafts are prose and carry no
structure a generator could read beyond tokens and headings. Making them carry
one-line summaries for the generator's sake would change the craft to serve tooling.

The laws editing skill needs one more rule: a change to a craft ships with its
inventory update in the same commit, produced under the dehydrating craft.

## Where it fits in the existing workflow

The editing skill says a session whose whole job is one craft loads that craft and
edits it directly, holding the whole so the change integrates. The inventory does not
replace that. It serves the step before it: deciding what to write, where it goes,
and what it overlaps. Prepare dehydrated, write hydrated.

The guard needs no change. It records engagement only when a craft loads through the
Skill tool, so reading an inventory file leaves no marker and refuses nothing. That is
the behavior the design wants. It also means the guard cannot tell an inventory read
from a raw craft read; the protection against the latter is convention, as it already
is today.

## Other uses

Once it exists, the inventory serves cases beyond the motivating one:

- A prompt-craft session that needs to know what the code craft covers, which is the
  one refused ordering.
- Design docs and tickets that need to name which laws a change touches, such as the
  observability doc, which could not.
- A human reading the inventory to learn what the laws are without reading a
  whole-session prompt.

Tools that cite tokens, such as the sheriff audit and the posse remediation skill, are
not a use. The inventory carries no tokens, so it cannot feed a citation.

## Testing the central claim

The parity check tests accuracy. It does not test the claim that the file is inactive.
That claim is tested the way this repo tests guidance: an agent reads only the code
inventory, then does prompt-craft work, and the owner reads the raw output against
the known corruption pattern the guard exists for. No scored layer.

## Recommended shape

- Path: `skills/<medium>/references/dehydrated.md`, for every medium including code,
  which gets a `references/` directory for it.
- Name: "dehydrated," the owner's word, because it tells the reader on sight that
  the file is not the active form.
- One parity test, one rule added to the editing skill, one dehydrating craft, one
  run of that craft per existing medium to produce the first versions.

## Open before building

- Whether the code inventory lists every domain binding or only the universal laws.
  This doc did not measure how much of the code craft the bindings account for.
- Whether heading parity is too loose for the crafts without laws, and what a tighter
  check would key on.
- Whether the inventory should record the refused orderings at all, or leave that to
  `incompatible-crafts.txt` as the single home.
- How far the binding-device rule reaches. The hook sources under `hooks/` cite law
  tokens in code comments today. Whether "outside the guidance" includes code is not
  decided here.
- How the dehydrating craft coexists with the guard, per the section above.
