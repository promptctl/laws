# Working with the skills without reading them

The skill bodies under `skills/*/SKILL.md` and `skills/*/references/craft.md` are
persuasive guidance, each written to the standard of one medium and built to keep
firing deep in a session against competing defaults. An agent that reads one and then
does other work carries that standard into the other work: reading one skill puts its
whole standard on duty and biases what you do next, and reading two stacks standards
that contradict each other. Stacking is the failure that has already ruined a session
here.

So there is one rule, and a way to work under it.

## The rule

The main session — the orchestrator — never reads a skill body. Treat every
`SKILL.md` and `craft.md` as opaque.

## What to read instead

The design-goals docs, `design-docs/design-goals-<skill>.md`. They describe a skill's
intent in plain register; they are prose *about* the skill, not guidance written in
its medium. Reading `design-goals-code.md` tells you what the code skill is for
without putting you into code-mode. Most meta-work — indexing the skills, checking
them for consistency, planning a change — runs off these and never touches a body.

## When the goals doc doesn't have the answer

Dispatch a disposable subagent seeded with exactly one skill. Ask it your specific
question. Keep only the answer; discard the subagent. Reading the body puts the whole
standard on duty; receiving a distilled answer back is just data. The subagent can
take follow-up questions, so it works as a single-skill oracle you consult instead of
ever inlining the text.

Two things make this safe: the subagent reads only one skill, so nothing stacks, and
it does no other work, so its contamination dies with its context.

## Writing or changing a skill

Dispatch a subagent whose whole job is that one skill, and have it read the skill's
craft as its first step. The medium's standard loads only inside that subagent, never
in the orchestrator. When the change is done, read the produced file — not the
subagent's summary — and check it against what you asked for.

## The direction the intent flows

The design-goals doc is the source of intent; the skill is written and audited
against it. Change a skill by editing its goals doc first, then dispatching a writer
subagent to bring the skill into line. Don't mine a skill body to recover what it was
trying to do — that is what the goals doc is for. (The current goals docs were
reverse-engineered from the skills as a one-time bootstrap; from here they lead.)
