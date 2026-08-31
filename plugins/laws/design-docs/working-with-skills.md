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

Crafts coexist; certain *orderings* do not. Most media are complementary, so a session that
produces code and its ticket and its docs may hold those crafts together - their
standards do not fight, and the guard lets them share a session.

The rule is directed, and the direction is the whole of it: **an ordering listed in
`hooks/scripts/incompatible-crafts.txt` is refused; every ordering absent from it may
coexist.** That file is the authority - both enforcers read it, neither hard-codes a craft
name, and adding an edge there changes the rule everywhere at once. Do not restate its
contents as a fixed pair anywhere else. A second copy is a second thing to go stale, and
the copy is what a reader will believe.

Today it holds one edge, and it is the one that paid for this document: **once laws:code is
engaged, laws:prompt may not be loaded.** Code's standard degrades prompts written under it,
and that is the failure that has ruined a session here. The reverse is not a failure at all -
write a prompt first, turn to code afterwards, and both come out fine, so that ordering is
deliberately absent from the file. It is not a mutually incompatible pair; it is a one-way
edge.

## Don't stack crafts even where the guard allows it

The guard enforces correctness, and correctness is not the only cost. A craft body is
large, and two of them in one context window is a real price paid out of the budget the
actual work needs. So the ordering rule is the floor, not the goal: **prefer doing the
second craft's work in a subagent, whatever the order.** The legal ordering is a
fallback for when that is impractical, not the thing to aim for.

That means the answer to "this task needs a prompt and some code" is not "sequence them
carefully in one session." It is: do one of them here, and dispatch the other.

### The subagent must be a fresh one

This is the part that is easy to get wrong, because the obvious convenience is exactly
the thing that breaks it.

A **fresh** subagent starts with an empty context, loads only the craft it needs, and
returns its answer. That is sound. A **fork** - any subagent that inherits the parent's
conversation - is not: it carries the parent's already-loaded craft body along with it,
so it does the work under precisely the standard we were trying to keep away from it.

The guard cannot save you here. The craft lock is keyed by session *and agent*, so a
forked agent gets a fresh, empty lock slot and the guard will happily allow the load -
the lock records what was *loaded*, not what was *inherited*, and a fork is the case
where those two diverge. Nothing will refuse it and nothing will warn you.

The cost of a fresh agent is that you must write the task context into its prompt
instead of getting it for free. That is the correct price.

If the session's whole job has become that craft, the other option is /clear and load it
clean.

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

## Violations are recorded

The routing this document describes now leaves a record. A hook watches every Write and Edit, infers the written file's medium from the pattern table in `hooks/scripts/medium-map.txt` (first matching pattern wins; unclassifiable files are ignored), and when that medium's craft is not among the session's engaged crafts, appends one JSON line to `${XDG_STATE_HOME:-~/.local/state}/claude-laws/violations.jsonl`. The guard's refusals land in the same file. So there are two kinds of record: `unrouted-medium-write` - a file was written without its craft engaged - and `incompatible-load` - the guard refused a craft ordering. The session also gets a single nudge per medium, pointing at the right craft or a fresh subagent.

**The observer never blocks.** Nothing is refused or reverted on its account; the record exists so a violation can be counted after the fact without anyone having watched it happen. The map file is the policy - edit it to change how files classify.

## The direction the intent flows

The design-goals doc is the source of intent; the skill is written and audited
against it. Change a skill by editing its goals doc first, then bringing the skill into line -
directly if it's your one craft, or through a subagent otherwise. Don't mine a skill body to recover what it was
trying to do - that is what the goals doc is for. (The current goals docs were
reverse-engineered from the skills as a one-time bootstrap; from here they lead.)
