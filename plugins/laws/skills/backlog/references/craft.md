# Planning a backlog

A backlog is the project's agenda. You write it in one session, from a founding
document and what the project knows so far, and it is pulled from by many later
sessions that were not here. Each of those sessions takes the top ticket and builds it,
trusting that it was planned by someone who knew what they were doing. The craft here
is about earning that trust: plan the whole arc at the detail you have, plan it in a
shape that serves the whole project, and give every piece a way to prove itself to a
person.

This applies equally to seeding an empty backlog and to extending one after work has
landed. Both are the same act from a different position.

## Plan the whole arc, at the detail you have

Everything the project intends goes into the backlog, first stage to last. What
varies is how much each ticket says. Near work carries a destination you could stake a
claim on today. Far work carries the goal it serves, what is known now, and what has
to be learned before its destination can be stated. Both are in the backlog. Neither
pretends to be the other.

The reason is that goals and requirements change as a project is built. Things are
learned at every step, and some of them change what the next step should be. A far
ticket written in the same confident voice as a near one is fiction, and it does not
fail tonight. It fails weeks later when a session with no memory of this one pulls
it, reads a confident destination, and builds it. So the test for each ticket is not
"do I know the destination?" but "does what this ticket claims match what we actually
know?" A ticket that says where it ends, and why, without a guess: write it that way.
A ticket whose end depends on something not yet learned: write it with the destination
stated as far as it can be, name the thing that has to be learned, and name the ticket
that will learn it. The tell is a hedge. An "if" about a result nobody has seen, a
"probably" about a shape nobody has measured, belongs only in a ticket that also names
the question ticket resolving it. A hedge in a ticket that reads as ready is a guess
wearing a confident voice.

What has to be learned is its own ticket. It asks one question, and when it is
answered the far tickets that named it get sharpened; new tickets are written only
for work the answer revealed that nothing had planned. It does not also build. A
ticket that investigates and builds in one body makes the builder stop and plan
halfway through, which is the interruption the backlog exists to prevent. It is
placed where it will be pulled before the work it gates: in the earliest epic that
can answer it, or in its own epic ranked ahead of the gated one. Never inside the far
epic it unblocks, where it sits at the top of a list nobody reaches. Resolve the
unknowns first, so the work behind them runs uninterrupted.

The foundation comes out concrete first because that is where the knowledge is. That
is a consequence, not a category to plan and stop at. When it lands, more is known,
the questions ahead get answered, and the far tickets get sharpened.

- BAD: "Measure the scaling constant across three models," written as if the constant
  were established. The project has not shown it exists in one model. The voice is
  borrowed from the founding document's hopes.
- BAD: "Build the period detector, then investigate whether the return map has a
  single hump, and file whatever follows." Two kinds of work in one body. The builder
  finishes the detector and is now planning instead of building.
- GOOD: "Determine whether the return map has a single hump, using the loop runner on
  the founding document's first template. Record the answer and sharpen the scaling
  measurement ticket from it." One question, its answer, and the far ticket it
  sharpens. Ranked in the foundation epic, right after the loop runner it needs.
- GOOD: "A loop runner that takes any template, any model, and any knob value, runs
  the loop for N steps from a given start, and records every state." Every word of
  that is known today.
- GOOD, far: "Scaling measurement across models. Serves the founding document's stage
  four (path). Not yet pinnable: depends on whether the constant appears in one model
  (see the single-hump question ahead of this). Sharpen once that is answered."

The temptation arrives as honesty: *"I don't know how that stage will go, so I'll
leave it out and we'll add it when we know more."* Nobody adds it. There is no ticket
marking the gap, so no session sees a gap, and the backlog quietly plans one stage of
six. Leaving it out is not honest; the honest move is a ticket that says exactly how
little is known.

## Build the foundation as bricks

The first layer has to support the full scale and scope of the project's goals, which
means its parts will be used from places nobody has planned yet. So each foundational
unit is planned as a brick, not a cast fitting. A brick knows nothing about the wall it
ends up in, and that ignorance is what makes it usable in any wall. A cast fitting is
molded against one joint, fits that joint perfectly, and fits nothing else ever.

At planning time this is two checks on every foundational ticket. First, the unit's
purpose is one sentence with no "and" in it. If the sentence needs an "and," the ticket
holds two units, and the cut goes at the "and." Second, the ticket names the unit's
second consumer. A unit with only one caller in sight is a cast fitting by definition,
whatever its code looks like, because there is nothing to keep it honest. If you cannot
name a second consumer from the project's own goals, either the unit is not foundational
or it has been shaped too tightly around its first use.

- BAD: "A bisection routine that finds where the steering knob flips the loop into
  period two." Cast against one knob and one transition. The next knob and the next
  transition get their own routine, and the project ends up with a family of them.
- GOOD: "A bisection over any knob that locates the value where an orbit's period
  changes, given a period detector." One boundary. Every knob and every transition is a
  new value crossing it, not new code. Second consumer: the noise-scaling measurement,
  which bisects on temperature.

This is the code laws' composability, applied before any code exists. The laws govern
how the brick is built; this craft governs that a brick is what gets planned.

## Every epic proves itself where a person can see it

An epic is not done when its tickets are closed. It is done when a person has watched
the work work. So every epic carries a checkpoint: something user-verifiable, ideally
visual, that exercises what the epic built. The checkpoints have to come close enough
together that the project is never far from one. A long stretch of tickets with nothing
to look at is a stretch where drift goes unnoticed.

The checkpoint is comprehensive. It covers more than the single happy path. Edge cases,
the empty input, the value at the boundary, the case the founding document says will
probably break. A checkpoint that shows only the good path proves only that the good
path exists.

The preferred checkpoint is in vivo: the functionality run directly in the application,
the way it will actually be used. Most work can be verified this way, and it is
verified this way by default, because the application is the thing being built and
watching it is the only test that cannot be fooled by a harness.

A demo is a bolt placed mid-climb. When the application cannot yet show the work, and
the distance to the next in vivo checkpoint has grown too long to climb unprotected,
you build something a person can look at. Demos are not required, no epic has one by
default, and an epic whose work the application can already show does not get one.
When a demo is the right call, spending real effort on it is encouraged, and these
rules hold:

- It is built to the same quality as everything else. A demo built carelessly teaches
  carelessness to whoever reads it next.
- It is labelled as a demo, in the ticket and in the code, so that no later session
  mistakes it for the foundation.
- It exercises more than the happy path, like any checkpoint.
- Its ticket says, in so many words, that the project learns from the demo's mistakes
  rather than building on it. This line exists because a working demo is the most
  tempting thing in a repository to build on, and a fresh session will do exactly that
  unless the ticket tells it not to.

- BAD: an epic of four tickets whose done state is "tests pass." Nobody has seen
  anything. The next epic stacks on it blind.
- BAD: a demo ticket that says "build a quick script to show the loop running." Quick
  is the tell. It will be built quickly, it will be wrong in small ways, and the next
  session will import it.
- GOOD: an epic whose last ticket is "run the loop from the command line against the
  pinned model with a template and knob value, and print each state; a person runs it
  on the empty template, on a template that returns its input unchanged, and on the
  founding document's first real template, and sees the expected orbit in each case."
  In vivo, comprehensive, and someone watches it.

## The backlog stands without the conversation that produced it

The sessions that pull from this backlog were not in the room. "As discussed," "per the
plan," "the approach we agreed on" are dead references the moment this session ends,
and a ticket that leans on one leans on nothing. Every epic carries, in its own text,
why it exists in terms of the project's goals, and every ticket carries what a stranger
needs to start. Where the founding document already says something, point at it by
path; do not restate it and do not assume it was read.

The check, before writing anything to the tracker: read the slate as a stranger who
cloned the repo this morning. Anything that only makes sense to someone who was here
tonight gets rewritten until it makes sense to them.
