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
design doc could not cite a single law token. An inventory of the code craft would
have answered both questions in one read, without engaging anything.

## The claim the design rests on

A craft's hold on the reader comes from its devices, not its propositions. The
whole-session form buys redundancy, imagery, second-person address, rehearsed
temptations, and paired examples of good and bad output. Those are what keep the
standard active turns later. A flat, third-person, said-once statement of the same
law carries the fact and almost none of the pull.

This is a hypothesis, not an established result. The design includes a way to test
it, below. If it is false, the fallback is a thinner file (section map and tokens
only) that carries even less.

## What a dehydrated file contains

One file per craft, called its inventory below, sitting next to the craft it
describes. It holds:

- A status line saying what the file is and is not: it lists the craft's contents so a
  reader can reason about them, and it does not engage the craft. Doing the medium's
  work requires loading the craft through the Skill tool as today.
- The medium's purpose in one flat paragraph.
- A map of the craft's sections, in order, so a writer can see where a new section
  slots.
- One entry per law: the token, the property in one indicative sentence, what it rules
  out, and which bindings specialize it. No examples.
- One line per domain binding and one line per device.
- The refused orderings involving this craft, stated as facts with the reason.
- The size of the live craft in tokens, so a writer preparing a section knows the
  budget they are adding to.

Today the code craft carries 22 law tokens across about 9,800 words. The prompt craft
carries 2 tokens; prose, ticket, and application-spec carry none and are organized by
section instead. An inventory is one line per law or section, so it should be a small
fraction of the craft it describes. Size is not a target; one line per item is the
rule, and the size follows.

## The register that makes it inactive

The file is written in the opposite register from the craft, on purpose:

- Third person, indicative. "The law states that effects live at boundaries." Never
  "you must" or "when you feel the pull to."
- Each point once. No restatement in other words.
- No metaphor, imagery, or rehearsed temptation.
- No good-versus-bad example pairs. Examples are the device that trains the standard.
- Paraphrase only. The craft's memorable phrasings are its hold; quoting them imports
  it.

In the prompt craft's terms, this is a text written for a zero-turn hold. It is read,
consulted, and left behind.

## Who writes it

Writing the inventory requires reading the craft, so the writer is engaged by it. That
is fine as long as the writer is disposable: a fresh subagent seeded with only that
craft produces the file, and the orchestrating session reads the result, not the
craft. This is the same subagent pattern the guard already prescribes for
cross-craft work, applied to producing the inventory instead of using it.

## Keeping it true

The file is a second description of the craft's content, and a second description
drifts. This is the design's main risk and the reason it needs a mechanical check.

Recommended: the inventory is authored, not generated, and a test enforces parity.
For token-bearing crafts, every `[LAW:...]` token in the craft appears in the
inventory and every token in the inventory appears in the craft. For every craft, the
section headings match in order. A new law or section added to a craft without an
inventory entry fails the check. The test lives beside the existing hook tests so it
runs where they run.

Rejected: generating the inventory from the craft. The crafts are prose and carry no
structure a generator could read beyond tokens and headings. Making them carry
one-line summaries for the generator's sake would change the craft to serve tooling.
If drift shows up despite the parity check, revisit.

The laws editing skill in `.claude/skills/laws/SKILL.md` describes each medium as
three files. Building this adds a fourth, and the skill's rules need one more entry:
a change to a craft ships with its inventory update in the same commit, and the
inventory follows the register above.

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
- Design docs and tickets that cite laws by token, such as the observability doc,
  which could not.
- Tools that cite tokens, such as the sheriff audit and the posse remediation skill.
  Whether they should read the inventory instead of whatever they read today is
  untested.
- A human reading the inventory to learn what the laws are without reading a
  whole-session prompt.

## Testing the central claim

The parity check tests accuracy. It does not test the claim that the file is inactive.
That claim is tested the way this repo tests guidance: an agent reads only the code
inventory, then does prompt-craft work, and the owner reads the raw output against
the known corruption pattern the guard exists for. No scored layer. If the output
shows the code standard bleeding through, the register rules were not enough and the
thinner fallback applies.

## Recommended shape

- Path: `skills/<medium>/references/dehydrated.md`, for every medium including code,
  which gets a `references/` directory for it.
- Name: "dehydrated," the owner's word, because it tells the reader on sight that
  the file is not the active form.
- One parity test, one rule added to the editing skill, one subagent run per craft to
  produce the first versions.

## Open before building

- Whether the code inventory lists every domain binding or only the universal laws.
  This doc did not measure how much of the code craft the bindings account for.
- Whether heading parity is too loose for the crafts without tokens, and what a
  tighter check would key on.
- Whether the inventory should record the refused orderings at all, or leave that to
  `incompatible-crafts.txt` as the single home.
