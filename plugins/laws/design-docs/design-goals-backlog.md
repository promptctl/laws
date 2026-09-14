# Design goals: the backlog skill

The backlog skill is for deciding what work goes into a project's backlog, and what
stays out. It governs the set of tickets as a whole: which work is planned now, what
shape that work takes, and how each piece proves itself. It does not govern how a
single ticket is written; that is the ticket skill's job.

## What it is for

A backlog is the project's agenda. It is written in one session and pulled from by
many later sessions that were not in the room when it was planned. The skill exists so
that those later sessions find work they can build, in a shape that serves the
project's whole scope, and not a plan written past what anyone knew at the time.

The skill serves seeding an empty backlog and extending one after a layer of work has
landed. Both are the same act: from where the project stands now, plan the next work
we know how to do. Seeding is the first turn of that cycle, not a one-time plan for
the whole project.

It is distinct from inventing work by reading a codebase for unfinished migrations or
missing features. That is what the fill-backlog skill does. This skill starts from what
the project intends, usually a founding document, and plans forward from what is known.

## The ideas it carries

**Plan the work we know how to do.** A ticket is written only when its destination can
be stated with confidence today, from what we already know. Work whose shape depends on
something not yet learned is not planned. The reason is that goals and requirements
change as the project is built, so a ticket written past our knowledge is not early, it
is fiction, and a session that pulls it later will build the fiction. The foundation of
a project is not the rule; it is what falls out of the rule, because the foundation is
the part we already know how to build. When that lands, more is known, and the backlog
is extended from the new position.

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
