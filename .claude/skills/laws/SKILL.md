---
name: laws
description: Rules for editing the laws skills in THIS repo. Use when creating, editing, or reviewing any `skills/*/SKILL.md`, any `skills/*/references/craft.md`, or any `design-docs/design-goals-*.md`. Says which content belongs in which file. How to write the prose well is laws:prompt's job, not this skill's.
---

# Editing the laws skills

Each medium - code, prose, ticket, chat, prompt, application-spec - is made of three
files. These rules keep each file's content in the right place. That's all this skill
does. It does not teach you how to write well in any medium; that's laws:prompt.

## Say it plainly

The problems here are simple: content is in the wrong file, or a rule from one medium
got copied into another. Say that, in plain words. When content is wrong, delete it -
don't coin a term, build a taxonomy, or reach for a metaphor to make a simple call
sound rigorous. Jargon that hides the simple reality is the failure, not a sign of
care. Simple is the goal, not a step toward something more impressive.

## The three files

- **`design-docs/design-goals-<medium>.md`** - what the skill is for, in plain prose.
  This is the source of intent; the skill is written to match it. Change this first
  when you change a skill.
- **`SKILL.md`** - how the main session dispatches a writer subagent and checks the
  result. Nearly the same for every medium. It says nothing about how to write well.
- **`references/craft.md`** - how to write well in this one medium. Read by whoever
  writes the change: a dispatched subagent, or the main session itself when editing this
  one skill is the whole job. Never loaded next to a conflicting craft.

## The rules

1. Compatible crafts coexist; incompatible ones do not. Each `craft.md` loads a whole
   medium's standard; most standards are complementary (code, its ticket, its docs), but
   an *incompatible* pair stacks and corrupts each other - laws:code with laws:prompt is
   the known one, and the guard refuses the second of that pair. A session may hold
   several compatible crafts, and a session whose whole job is one skill may load that
   skill's craft and edit it directly - holding the whole craft is how a change integrates
   instead of bolting on. When you need a craft that conflicts with one already engaged,
   you don't load it here; that one you dispatch to a disposable subagent.
   (`design-docs/working-with-skills.md` has the details.)
2. `craft.md` has no dispatch or verify steps. Those are the main session's job, and
   the writer subagent has no one to dispatch.
3. `SKILL.md` has no writing advice - not how to write, and not the reasons behind how
   to write. Those go in `craft.md`.
4. The `SKILL.md` files are the same across media except the medium name and path. If a
   change to one is more than that, either it's wrong or it's a shared improvement that
   belongs in all of them. (One real exception today: application-spec's dispatch needs
   extra content - where to find the app, and what a finished spec must be. That's fine.
   A medium can add what its dispatch actually needs; it just can't differ for no
   reason.)
5. A rule from one medium stays in that medium's files. Don't copy it into another - a
   ticket rule can be false for a report. Check by grepping a rule's distinctive phrase;
   it should appear under one medium only.

## Workflow

The full order is in `design-docs/working-with-skills.md`. In short:

1. Edit the goals doc first.
2. Bring the craft into line. If editing this skill is the session's whole job, load its
   craft and edit directly, holding the whole so the change integrates. Otherwise
   dispatch a subagent that loads only that craft. Never load a second craft in the same
   session.
3. Read the file it produced - not its summary - and check it against the goals doc.

## The failure this prevents

Someone added a "keep the dispatch prompt clean of your own solutioning" paragraph to
three `SKILL.md` files (prompt, prose, ticket). In the ticket one they wrote it using a
ticket-specific rule - leave the "how" to the implementer. Then they copied that
ticket-worded paragraph into prose and prompt, where the rule is false: a report is
supposed to carry the answer, not leave it open.

Two mistakes: writing advice ended up in `SKILL.md` (rule 3), and a ticket rule got
copied into other media (rule 5). The fix: the plain point - "don't dump your session's
guesses into the dispatch prompt" - is true for every medium, so it goes in all the
`SKILL.md` files, worded the same. The ticket-specific reasoning stays in
`ticket/craft.md`.

Watch the reflex that let it ship: reviewing the copies, the reviewer called it "the
right kind of duplication." Repeating a point in different words inside one `craft.md`
is fine. Copying one medium's rule into another medium's files is not.
