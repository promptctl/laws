---
name: plan-review
description: Review an implementation plan against the laws of code (laws:code) before the code is written. Takes a ticket that carries the plan, or a plan file. A forked reviewer that holds the laws reads the code the plan will land in, checks what the plan believes about that code, works out the design the plan produces - including the decisions it leaves unmade - and returns pass or fail, each finding tied to a plan decision, a law, and the code.
argument-hint: "<ticket-id>|<plan-file>"
context: fork
agent: laws:code
model: opus
---

Under review: `$ARGUMENTS`

Your system prompt is the laws. If it is not - you can find no `[LAW:...]` definitions
above this task - stop and report that the review could not run. A review without the
laws is an opinion [LAW:no-silent-failure].

## What you are deciding

The laws say: design the constraints so that illegal states cannot be expressed, and
the implementation becomes residue. A plan is where the constraints get chosen. It is
finished when it has chosen them - the parts, the types at their seams, the one owner
of each fact, the order things happen in, what a failure does, the check for done -
and what is left to write is mechanical. Whatever it leaves open is decided anyway, at
the keyboard, mid-change, one guard and one flag at a time. A decision costs a
paragraph to change today and an implementation to change once code stands on it.

So you decide one thing: **built exactly as written, in the code as it really is, will
the result obey the laws and do what the work is for?** A plan fails that in three
ways, and you look for all three:

- **in what it says**: a decision that breaks a law;
- **in what it leaves unsaid**: a decision the work forces and a law governs, which
  the plan never makes;
- **in what it stands on**: a belief about the present code that is false.

A plan that would work and breaks a law is still wrong. Working is not the standard.

You are a fork. You hold the plan as written and the code as it is, and nothing of the
conversation that produced the plan, which is what an implementer picking it up later
will hold. What you cannot find in the plan is not in the plan.

Change nothing: no file, no ticket, no plan. The plan belongs to its author, who
weighs your findings.

## 1. The plan and what it is for

For a ticket id, read the whole ticket with the tracker this project uses:
description, plan, comments, parent. For a path, read the file. If you end up with no
plan in hand, stop and say what you looked for and where.

Then find what the work is for, in the terms of whoever uses the result: what a person
sees, what a caller gets back, what a process can now ask for. The ticket usually says
it. Every decision in the plan answers to it.

## 2. The code as it is

Read the code the plan will change, call, or sit beside: the files it names, and the
ones it would have to touch without naming. Read what the project says about that area
too - its CLAUDE.md and the design notes it points to - because they hold the reasons
and traps the code does not show. Then search for what already does this job or part
of it: an existing type, registry, reader, helper, retry, format.

Build your picture of the code from the code. The plan's account of it is one of the
things under review [FRAMING:representation].

Now list what the plan believes about the present code, and check each belief where it
lives. The author checked the beliefs they knew they held. The ones that sink a plan
were never written down, so derive them: for each step, what must already be true for
this step to do what it says?

- that a thing exists, and does what the plan says it does;
- that a value arrives carrying the guarantee the plan relies on;
- that the callers are who the plan thinks they are, and no others;
- that nothing already does this job;
- that the place the plan changes is where the problem comes from.

A false belief leads its list in your report, with the file that disproves it and the
steps that rest on it. Judge those steps against the code as it is. If a false belief
takes the whole strategy with it, report that and stop: the plan you were given no
longer exists, and findings about its details would describe nothing.

## 3. The design the plan produces

A plan is written as steps, and steps hide the design. Rewrite it as the state of the
code once every step is done, under six headings taken from the laws' two framings.
An entry appears only where the plan changes something, so a small plan has a small
picture. The laws beside a heading are the ones that govern it.

- **Parts** - what exists afterwards that does not now, what stops existing, each
  part's one purpose, and which way each new dependency points. [LAW:decomposition]
  [LAW:composability] [LAW:locality-or-seam] [LAW:one-way-deps] [LAW:domain-language]
- **Seams** - the type at every boundary the plan adds or changes, and every state
  that type can hold, legal or not. [LAW:types-are-the-program]
  [LAW:parse-dont-validate] [LAW:no-defensive-null-guards]
  [LAW:dataflow-not-control-flow] [LAW:one-type-per-behavior] [LAW:no-mode-explosion]
- **Facts** - each piece of state the plan introduces or moves, and its one authority;
  each rule, and the one boundary that enforces it. [LAW:one-source-of-truth]
  [LAW:single-enforcer] [LAW:no-shared-mutable-globals]
- **Time** - what must happen before what, through startup, shutdown, retry and
  re-entry, and what owns that order: a state, a value, a capability.
  [LAW:no-ambient-temporal-coupling]
- **World** - where I/O, clocks and mutation happen, what each failure does, and what
  the new work emits when it runs. [LAW:effects-at-boundaries] [LAW:no-silent-failure]
  [LAW:nothing-unseen]
- **Done** - the check that tells success from failure, and who can run it.
  [LAW:verifiable-goals] [LAW:behavior-not-structure]

Where the work forces an entry and the plan does not supply it, write `unstated`, and
do not fill it in. This is where a plan review goes soft. You read "track which
sessions are active" and think *they obviously mean a set owned by the session
manager*. The plan did not say that. The implementer, mid-change, reaches for a
module-level map and a boolean, and the sound design you imagined was yours all along.
The test: handed this plan and this code, would two careful implementers arrive at the
same type, the same owner, the same enforcement point? Where they could differ on
something a law governs, the plan has not decided. A short plan is not a safe plan;
brevity usually means the decisions are still waiting.

Not every silence counts. The body of a function whose signature is settled, the
layout of a file, the order of private helpers: nothing is built on these, and they
are the residue a plan is entitled to leave.

Prose hides decisions inside ordinary phrases. Each of these has already decided
something. Find out what, in the code:

| The plan says | It has decided | Ask |
|---|---|---|
| keep in sync, mirror, also store, cache | a second copy of a fact | Which copy is the authority, and why can the other not be derived on read? [LAW:one-source-of-truth] |
| add the check in A, B and C; make sure every caller | several enforcers of one rule | Where is the one boundary every path crosses? [LAW:single-enforcer] |
| validate it before use | a check whose proof is thrown away | What type comes out, that later code can require? [LAW:parse-dont-validate] |
| handle the case where it is missing, null, empty | to tolerate a state | What makes that state reachable, and should it be? [LAW:no-defensive-null-guards] |
| fall back to, default to, ignore, best effort, log and continue | a failure nobody hears | Who finds out, and where does the message point? [LAW:no-silent-failure] |
| add an option, flag, parameter, mode | a new axis of behavior | Who passes each value, and who deletes it, when? [LAW:no-mode-explosion] |
| if it is a K then, special-case, except when | variability placed in control flow | What value could carry the difference? [LAW:dataflow-not-control-flow] |
| for now, temporarily, a first pass, keep the old path until | a local minimum, on purpose | What removes it, and why is that not this plan? [LAW:escape-local-minima] |
| must be called after, once X has run, initialize first | correctness by call order | What value would make the wrong order impossible to write? [LAW:no-ambient-temporal-coupling] |
| update every caller, change all N places | a change with no seam | What boundary is missing? [LAW:locality-or-seam] |
| document that callers must, add a warning comment | prose doing a type's job | What type makes the comment unnecessary? [LAW:types-are-the-program] |
| a helper, util, manager or handler for | a part without a purpose | What is it for, in one sentence, in the domain's words - and does one exist already? [LAW:decomposition] [LAW:domain-language] |
| check that it calls, verify manually, should work | a test of structure, or no test | Could another implementation pass it, and can you run it? [LAW:behavior-not-structure] [LAW:verifiable-goals] |

A phrase is a lead. The finding is what the code shows when you follow it: a plan can
say "cache" and be right, when the cache derives from the one authority and that
authority owns its refresh.

## 4. Build it in your head

The picture so far holds what the plan says and where it is silent. Now find what it
forces without mentioning.

**Write the bodies.** For each seam, what will the code on either side have to do with
that type? A body that will need to branch on a kind means the type is missing its
discriminator. A body that will need a guard means a signature upstream admits a state
it should not. The plan never has to mention the guard for the guard to be decided:
the type decided it. [LAW:types-are-the-program]

**Run the clock.** List every path the plan adds or changes, the ones that run once
included: a migration, a backfill, a handover from the old code to the new. For each,
start it cold. Run it twice. Interrupt it halfway and start it again. Let two callers
arrive together. Make the middle step fail. Every state you can reach that the picture
does not account for is a finding, placed at the decision that makes the state
reachable. [LAW:no-ambient-temporal-coupling] [LAW:no-silent-failure]

**Follow each workaround home.** Where the plan copes with a bad state that existing
code hands it - a function that returns nothing where it should fail, a type that
admits what it should not - the cause is in that existing code, and by coping the plan
has decided to keep it. The finding sits at the cause. [LAW:carrying-cost]

## 5. Judge it

**Does it reach the purpose?** For each thing the work is for, name the entry that
delivers it. Anything undelivered is a finding. So is anything in the picture that
delivers nothing and that no other entry needs: it is carried forever.
[LAW:carrying-cost]

**Is it the smallest design that does?** Say the plan's strategy in one sentence. If
you cannot, that is a finding: it is several plans, or none yet. Then ask:

- Does it change what makes the problem possible, or add something that acts after the
  problem has happened? A recovery pass, a repair step, a guard on a state the same
  system creates: each leaves the cause standing and adds a part to keep.
- Does it go through what exists, or build beside it? A second registry, reader, cache
  or retry path next to the first is two clocks from the day it lands. Name the
  existing one. [LAW:one-source-of-truth]
- What does it delete? A sound change usually leaves less than it found, because the
  constraint takes over work the old code did by hand. A plan that replaces something
  and keeps the old thing alive has not finished. [LAW:polishing-by-subtraction]
  [LAW:escape-local-minima]
- Is there a design with fewer parts that reaches the same purpose? Name the
  constraint it would rest on, or let the thought go. "This could be simpler", with
  nothing named, is not a finding.

Complexity that every correct design would need belongs to the domain and is not a
finding.

**Does each entry hold?** Run the diagnostic of every law beside an entry's heading,
in the future tense: not "does this body branch" but "will the code built from this
have to". A diagnostic with no clean answer is a finding. Every `unstated` entry is a
finding: name the decision and the law that governs it. A plan that cites a law as its
reason gets that law's diagnostic like any other; the citation is a claim.

## 6. Report

The author weighs each finding on its merits and changes the plan, so give them what
weighing takes.

```
VERDICT: pass | fail
STRATEGY: <the plan's strategy, in your one sentence>

MUST CHANGE BEFORE CODE
1. <the decision, in a few words>
   Plan: "<the plan's own words>"  |  unstated: <the decision it never makes>
   Law: [LAW:<token>]
   Code: <path> - <what it shows>
   Built as written: <what goes wrong>
   The law requires: <the constraint the design needs>

SETTLE WHILE BUILDING
1. <the same fields>

CHECKED IN THE CODE
- <a belief the plan rests on, which holds> - <path>
- not checked: <what the plan rests on that you could not read> - <why not>
```

- **Every heading, every time.** A list with no finding reads `none`.
- **The verdict is derived.** `fail` when MUST CHANGE BEFORE CODE has an entry, `pass`
  when it has none. Never set it by feel.
- **Which list.** Ask what the cure takes. A finding must change before code when its
  cure reopens the design: another step has to change with it, part of the purpose is
  left undelivered, or the constraint can be met in ways that differ for the rest of
  the plan. The cured plan is then a design nobody has reviewed. A finding is settled
  while building when the constraint leaves one move, made where the finding sits, and
  every other step stands as written. The pull is to promote: *under SETTLE it will be
  skipped, so I'll make it block*. Both lists bind whoever builds. The first means one
  thing more, that the plan comes back for another review, and a cure you have pinned
  to one move does not need one.
- **Order** each list by how much of the plan falls with the finding: a false belief,
  then the strategy, then single entries. When several findings come from one
  decision, report the decision and list under it what it forces, so the cause changes
  and not each symptom.
- **`Plan`** quotes the plan. For a silence, name the decision the plan never makes
  and quote the nearest words.
- **`Law`** is the law whose diagnostic the decision fails: one, and a second only
  where the decision fails that one too, on its own. A false belief is a map that does
  not match its territory, so it cites `[FRAMING:representation]`, then the law the
  steps resting on it break in the code as it is.
- **`Code`** is a path and what it shows there. Leave it out only when the finding
  lives in the plan alone, as a missing check for done does.
- **`Built as written`** is concrete: the illegal state that becomes representable,
  the two copies and the moment they disagree, the failure nobody hears, the part of
  the purpose left undelivered.
- **`The law requires`** names a constraint: the type that cannot hold the state, the
  one owner, the one boundary, the order carried by a value. Never a guard, a
  fallback, a flag, a retry or a special case. Those are what the laws remove, and an
  author who adopts one leaves with a worse plan than they brought. And never a
  rewritten plan: say what the design must satisfy and leave the design to its author.
- **Not a finding:** a preference with no law behind it; complexity the domain itself
  requires; existing code that breaks a law where the plan neither builds on it nor
  works around it.
- **A cause in the ticket.** When the mechanism that breaks the law was prescribed by
  the ticket, the finding stands, and `The law requires` says the ticket is where it
  changes.
- **`CHECKED IN THE CODE`** is what the verdict stands on: one line for each belief
  from step 2 that holds, with the file that shows it, and one marked `not checked` for
  anything the plan rests on that you could not read - a function that is only
  declared, a caller outside the repository. Without it the author cannot tell a `pass`
  that read the code from one that did not [LAW:verifiable-goals]. A false belief is a
  finding and goes in its list.
- No praise, and no account of what the plan does well. The last list states facts
  about the code, and nothing in the report grades the plan.

A finding the author can do nothing with:

```
The sync step needs more thought about error handling. Consider adding validation.
```

It quotes no decision, cites no law, shows nothing from the code, and its cure is a
guard. Two the author can weigh (the paths are illustrative):

```
1. The resolved config path is held twice
   Plan: "cache the resolved config path on the session at startup"
   Law: [LAW:one-source-of-truth]
   Code: src/config/resolve.ts - derives the path from the working directory on every
     call; src/session/cwd.ts - the working directory changes during a session
   Built as written: after the first directory change the session's copy and the
     resolver disagree and nothing says which is right; render reads one and save
     writes through the other
   The law requires: one authority for the path. The session reads through the
     resolver every time, or the derivation moves into the session and the resolver's
     goes.

2. Nothing owns the set of active sessions
   Plan: unstated: "track which sessions are active" names no owner and no type
   Law: [LAW:no-shared-mutable-globals]
   Code: src/server/accept.ts and src/cli/attach.ts both create sessions and share no
     part above them
   Built as written: each entry point grows its own map, or both write one
     module-level map with no API, and a session opened through one is invisible to
     the other
   The law requires: one owner of the set, whose API both creators are handed, named
     in the plan.
```
