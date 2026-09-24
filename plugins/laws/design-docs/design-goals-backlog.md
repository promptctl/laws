# Design goals: the backlog skill

The backlog skill is for deciding what work goes into a project's backlog, and what
stays out. It governs the set of tickets as a whole: which work is planned now, what
shape that work takes, and how each piece proves itself. It does not govern how a
single ticket is written; that is the ticket skill's job.

## What it is for

A backlog is the project's agenda. It is written in one session and pulled from by
many later sessions that were not in the room when it was planned. The skill exists so
that those later sessions find work they can build, in a shape that serves the
project's whole scope, stated no more confidently than anyone knew at the time.

The skill serves seeding an empty backlog and extending one after a layer of work has
landed. Both are the same act: from where the project stands now, plan forward from
what is known, at the detail it supports. Seeding is the first turn of that cycle, not
a one-time plan for the whole project.

It is distinct from inventing work by reading a codebase for unfinished migrations or
missing features. That is what the fill-backlog skill does. This skill starts from what
the project intends, usually a founding document, and plans forward from what is known.

## The ideas it carries

**Plan the whole arc, at the detail you have.** Everything the project intends goes
into the backlog, from the founding document's first stage to its last. What varies is
how much each piece says, not whether it exists. Near work carries a concrete
destination. Far work carries the goal it serves, what is known now, and what has to
be learned before it can be pinned down. The reason is that goals and requirements
change as the project is built, so a far ticket written in the confident voice of a
near one is fiction, and a session that pulls it later will build the fiction. The
remedy is to match the voice to the knowledge, not to leave the work out: a backlog
missing five of six stages does not fail loudly either, it just has no plan for most of
the project.

**Unknowns are resolved up front, by their own tickets.** Where a stage cannot be
pinned down because something has not been learned, the learning is a ticket, ranked
ahead of the work it gates. That ticket answers its question and writes the tickets
that follow from the answer. It does not also build; a ticket that investigates and
builds in one body forces the builder to stop and plan mid-work, which is the
interruption this rule exists to prevent. The foundation is still what comes out
concrete first; that is a consequence of where the knowledge is, not a rule to plan to.

**The foundation is built as reusable bricks.** The first layer has to support the
scale and scope of the project's whole goals, so its parts are built to be used from
many places, not cast against one caller. This is the code laws' composability, applied
at planning time: a foundational unit is planned with one purpose and with its second
consumer already named.

**Every epic has checkpoints a person can verify.** The climb has to pass through
points where someone can see the work working, close enough together that the project
is never far from one. The preferred checkpoint is in vivo, the functionality exercised
directly in the application as it will actually be used. A demo is a bolt placed
mid-climb when the application cannot yet show the work and the gap to the next in vivo
checkpoint has grown too long. Demos are not required and no epic has one by default.
When one is built it is built to the same quality as everything else, labelled as a
demo, exercises more than the happy path, and carries an explicit note that the project
learns from its mistakes rather than building on it.

**The backlog stands without the conversation that produced it.** The sessions that
pull from it were not here. Nothing in it may point back to a discussion.

**The requester approves the slate before any ticket exists.** Seeding a backlog is
writing the project's agenda for weeks. The requester adjusts it first, and adjustment
is the product, not friction. This lives in the skill's setup step, not the craft.

## Deliberately absent

Guidance on the size of a ticket. Every attempt so far has come out prescriptive, and
prescriptive size rules produce boundaries that are artificial and wrong: a floor turns
into confetti, a ceiling turns into arbitrary splits. The concept we want is closer to
"cut the carcass at the joints, but bundle up the smaller cuts," and it is not yet
stated well enough to be a rule. Until it is, the craft says nothing about size at all.
Do not add a softer version of a size rule in the meantime.

## Relationship to the other media

The ticket skill says how one ticket is written. This skill says which tickets to write
and in what shape. Rules from one must not be copied into the other. A backlog rule
about what to plan is not a ticket rule, and a ticket rule about what a description
carries is not a backlog rule.
