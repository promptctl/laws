# Planning a backlog

A backlog is the project's agenda. You write it in one session, from a founding
document and what the project knows so far, and it is pulled from by many later
sessions that were not here. Each of those sessions takes the top ticket and builds it,
trusting that it was planned by someone who knew what they were doing. The craft here
is about earning that trust: plan only what is known, plan it in a shape that serves
the whole project, and give every piece a way to prove itself to a person.

This applies equally to seeding an empty backlog and to extending one after work has
landed. Both are the same act from a different position.

## Plan the work you know how to do

A ticket goes into the backlog only if its destination can be stated with confidence
today, from what is already known. Not what will probably be true after the next layer
lands. Not what the founding document hopes for. What you could stake a claim on now.

The reason is that goals and requirements change as a project is built. Things are
learned at every step, and some of them change what the next step should be. A ticket
written past the edge of what is known is not an early plan, it is fiction, and it does
not fail tonight. It fails weeks later when a session with no memory of this one pulls
it, reads a confident destination, and builds the fiction. Nobody traces that back to
the night the backlog was seeded.

So the test for each candidate is: can I write where this ends, and why, without
guessing at something we have not yet learned? If writing it requires an "if" about a
result that does not exist yet, or a "probably" about a shape nobody has seen, it is
not written. It waits.

What falls out of this test is the foundation. The first layer of a project is the part
that is already known how to build, so the first slate is naturally the foundation and
nothing above it. That is a consequence, not a rule to apply. Do not plan "the
foundation" as a category and stop; plan what is known and notice that it is the
foundation. When it lands, more is known, and the backlog is extended from that new
position with the same test.

- BAD: "Measure the scaling constant across three models." The project has not yet
  shown that the constant exists in one model, or that the measurement it plans will
  see it. The destination is borrowed from the founding document's hopes.
- BAD: "Investigate whether the return map has a single hump." An investigation is not
  a destination; it is the admission that the destination is unknown. If the work is
  finding out, it is not yet plannable as a build ticket.
- GOOD: "A loop runner that takes any template, any model, and any knob value, runs the
  loop for N steps from a given start, and records every state." Every word of that is
  known today. What the runner will reveal is not, and nothing here depends on it.

The temptation arrives as thoroughness: *"the founding doc lays out six stages, and a
backlog with only the first one looks thin."* Thin is correct. A backlog that plans the
first stage well and stops is a backlog every later session can trust. One that plans
all six is one where five are guesses wearing the same confident voice as the one that
is not, and the pulling session cannot tell them apart.

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
