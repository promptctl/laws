---
name: laws
description: Rules for editing the laws skills in THIS repo - which content belongs in which file, and which rules stay inside one medium. Use when creating, editing, or reviewing any `skills/*/SKILL.md`, any file under a skill's `references/`, or any `design-docs/design-goals-*.md`. How to write the prose well is laws:prompt's job, not this skill's.
---

# Editing the laws skills

Each medium is one skill. A skill takes whatever shape makes it most effective for
its own medium: one file or twenty, decided by what that skill needs, never copied
from another skill.
These rules keep content in the right skill. That's all this skill does. It does not
teach you how to write well in any medium; that's laws:prompt.

## Say it plainly

The problems here are simple: content is in the wrong place, or a rule from one medium
got copied into another. Say that, in plain words. When content is wrong, delete it -
don't coin a term, build a taxonomy, or reach for a metaphor to make a simple call
sound rigorous. Jargon that hides the simple reality is the failure, not a sign of
care. Simple is the goal, not a step toward something more impressive.

## The rules

1. Compatible crafts coexist; incompatible ones do not. A craft loads a whole medium's
   standard, and reading it changes what you do next, by design. Most standards are
   complementary (code, its ticket, its docs), but some *orderings* are refused: with one
   craft engaged, what you write next under another comes out wrong.
   `hooks/scripts/incompatible-crafts.txt` lists those orderings as directed edges - an
   edge refuses one direction and says nothing about loading the same two the other way
   round - and the guard refuses the second load of one. Read them as edges, not as pairs:
   the file used to hold symmetric pairs, and the reverse direction it refused along the
   way was a false refusal that cost real conversation to escape.
   A session may hold several compatible crafts, and a
   session whose whole job is one skill may load that skill's craft and edit it
   directly - holding the whole craft is how a change integrates instead of bolting on.
   When you need a craft that conflicts with one already engaged, you don't load it
   here; that one you dispatch to a disposable subagent.
   (`design-docs/working-with-skills.md` has the details.)
2. A rule from one medium stays in that medium's files. Don't copy it into another - a
   ticket rule can be false for a report. Check by grepping a rule's distinctive phrase;
   it should appear under one medium only.

## Workflow

The full order is in `design-docs/working-with-skills.md`. In short:

1. Say what the skill is for before changing it. That statement lives in
   `design-docs/design-goals-<medium>.md`: edit the goals doc first, then change the
   skill to match it. A new skill gets one before it ships - dropping the fixed
   three-file shape did not drop this. The spec skill shipped without a goals doc and
   nothing caught it until a review went looking, which is the whole cost of leaving
   the rule unwritten.
2. If editing this skill is the session's whole job, load its craft and edit directly,
   holding the whole so the change integrates. If the craft is incompatible with one
   already engaged here, dispatch a subagent that loads only that craft; never stack a
   refused ordering in one session.
3. Read the file it produced - not its summary - and check it against the goals doc.

## The failure this prevents

Someone added a "keep your own solutioning out of it" paragraph to three skills
(prompt, prose, ticket). In the ticket one they wrote it using a ticket-specific rule -
leave the "how" to the implementer. Then they copied that ticket-worded paragraph into
prose and prompt, where the rule is false: a report is supposed to carry the answer,
not leave it open.

The fix: the ticket-specific reasoning lives in the ticket skill; a medium that needs
its own version writes it in its own words.

Watch the reflex that let it ship: reviewing the copies, the reviewer called it "the
right kind of duplication." Repeating a point in different words inside one skill is
fine. Copying one medium's rule into another medium's files is not.
