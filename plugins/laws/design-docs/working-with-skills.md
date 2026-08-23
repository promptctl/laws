# Working with the skills without stacking their crafts

The skill bodies under `skills/*/SKILL.md` and `skills/*/references/craft.md` are
persuasive guidance, each written to the standard of one medium and built to keep
firing deep in a session against competing defaults. An agent that reads one and then
does other work carries that standard into the other work: reading one skill puts its
whole standard on duty and biases what you do next. Most standards sit together fine -
code, its ticket, and its docs are complementary work. But one standard actively damages
another: read laws:code and the prompts you write afterwards come out corrupted by it.
That is the failure that has already ruined a session here, and it runs one way - the
damage is code's effect on prompts, not a quarrel between equals.

So there is one rule, and a way to work under it.

## The rule

Crafts coexist; one *ordering* does not. Most media are complementary, so a session that
produces code and its ticket and its docs may hold those crafts together - their
standards do not fight, and the guard lets them share a session.

The rule is directed, and the direction is the whole of it: **once laws:code is engaged,
laws:prompt may not be loaded.** Code's standard degrades prompts written under it, and
that is the failure that has ruined a session here. The reverse is not a failure at all -
write a prompt first, turn to code afterwards, and both come out fine, so the guard
allows it. It is not a mutually incompatible pair; it is a one-way edge.

That asymmetry has a practical consequence worth planning around. If a task needs both
media, **do the prompt first.** Ordering the work that way costs nothing and leaves the
session free to pick up code afterwards; ordering it the other way puts the session in a
state where the prompt work can only be reached by retiring the code craft.

When you do need a craft the session's current state refuses, you don't load it here:
consult it through a disposable subagent, or - if the session's whole job has become
that craft - /clear and load it clean.

## What to read instead

The design-goals docs, `design-docs/design-goals-<skill>.md`. They describe a skill's
intent in plain register; they are prose *about* the skill, not guidance written in
its medium. Reading `design-goals-code.md` tells you what the code skill is for
without putting you into code-mode. Most meta-work - indexing the skills, checking
them for consistency, planning a change - runs off these and never touches a body.

## When the goals doc doesn't have the answer

Dispatch a disposable subagent seeded with exactly one skill. Ask it your specific
question. Keep only the answer; discard the subagent. Reading the body puts the whole
standard on duty; receiving a distilled answer back is just data. The subagent can
take follow-up questions, so it works as a single-skill oracle you consult instead of
ever inlining the text.

Two things make this safe: the subagent reads only one skill, so nothing stacks, and
it does no other work, so its contamination dies with its context.

## Writing or changing a skill

This is the exception where you may hold the craft yourself. If editing this one skill
is the session's whole job, load its craft and edit directly - holding the whole is how
a change integrates instead of bolting on. If you're mid other work and don't want that
standard on you, dispatch a subagent whose only job is this skill. Either way, edit the
goals doc first, and when the change is done read the produced file - not a summary -
against the goals doc. Never load a craft that conflicts with this one in the same
session; that one you dispatch.

## The direction the intent flows

The design-goals doc is the source of intent; the skill is written and audited
against it. Change a skill by editing its goals doc first, then bringing the skill into line -
directly if it's your one craft, or through a subagent otherwise. Don't mine a skill body to recover what it was
trying to do - that is what the goals doc is for. (The current goals docs were
reverse-engineered from the skills as a one-time bootstrap; from here they lead.)
