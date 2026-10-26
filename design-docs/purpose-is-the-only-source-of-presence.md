# Purpose is the only source of presence

A design note for the root of the guidance. It names one principle that is meant to sit
underneath everything else, with the laws as its instances for code. It is written so
that a nuts-and-bolts model can run it as a procedure, not only a careful one who can
reason about it.

## The problem, in three stories

All three happened in one session, in one afternoon, with the same model, under the
same guidance.

**The test that had to misbehave.** The app's tests were putting a window over the
person's screen while they ran. The fix request was to stop that. The model wrote
tests asserting that the app does not put a window over the person's screen. To check
that assertion, the test has to build the window and prove it stayed hidden. So the fix
for "tests draw on my screen" was more tests that draw on the screen. A human engineer
would not have written that test. They would have arranged the suite so that it only
runs paths that draw nothing, and then there is nothing to assert. The drawing cannot
happen because nothing in the suite can do it.

**The ticket that grew.** The person said: the session lives on the default tmux
server, it outlives hands, hands reconnects to it, and the brain keeps running while
someone is attached. The model was asked to put those points on the ticket. The ticket
came back with those points plus "under a fixed name", "instead of starting another",
"whether or not hands is running", and a paragraph that begins "Done when". None of
that was said. Every added line is a requirement the next agent will obey.

**The rules that contradicted each other.** After the session went badly, the model
was asked to write guidance so it would not happen again. It wrote six rules. Two of
them said "only write what he said" and "change nothing until he asks". A third said
"be a partner, not an order-taker". The person pointed out that the first two are
order-taking rules and contradict the third.

The three stories look different. They are the same move. In each one the model was
asked for something, and produced that thing plus something else: a test, a sentence,
a rule. The extra thing was not asked for, and in each case it caused the harm.

## Why a list of "don't" cannot fix this

The obvious correction is a rule for each story. Don't write tests that assert the
absence of a behavior. Don't add to a ticket what the person did not say. Don't turn a
complaint into a rule. Each of those is true, and each one was written after its
failure, so each one can only ever catch the failure that already happened. The next
failure is a neighbor of the last one, slightly different, and it walks around the rule.

The list of things not to do is infinite. It cannot be specified, and it is not
efficient to try. Any guidance built as a list of don'ts is always one failure behind.

There is a second cost. A "don't" names the thing. Once the thing is named on the page,
it is a topic, and a model will produce something about the topic: a guard, a test, a
line that says "intentionally not done", a question. The name of the bad thing is
itself a presence, and presence breeds presence.

## Three options, not two

For any topic, there appear to be two choices: do it, or don't do it. "Always clean up
my own mess" or "never clean up my own mess". There is a third: say nothing about it.
The topic is absent. Nobody decided it either way, and whoever meets the situation
later decides it with the facts they have then.

This third option is the one a model is worst at producing. Absence has no token. It
cannot be seen in a diff or a review. It feels like a gap, and a gap looks like
something to fill. So the model fills it, and now the topic has a ruling that nobody
asked for.

The third option has to be the default. Not something the person asks for topic by
topic, but the state every topic is in until something pulls it out.

## The principle

**Purpose is the only source of presence.**

Everything that appears in the output is there because the purpose required it, and the
model can say, in one sentence, what it is for. A line of code, a test, a sentence in a
ticket, a comment, a rule in a guidance file, a question to the person, an action taken
on their behalf. Each one is a presence. Each one has to be pulled in by the purpose.
If the model cannot say what it is for, it is not produced.

"The purpose" means the reason the work exists: what a person does with the result once
it works. It is not the model's own sense of thoroughness, and it is not "because a
reviewer might ask". The purpose comes from the person, the ticket, or the thing the
code is plainly for. If the model cannot find it there, finding it is the first job,
and asking is allowed.

Under this principle, the three stories resolve without a rule for any of them:

- The drawing test has no purpose. The purpose was "the tests must not draw on the
  person's screen". That is served by a suite that only runs non-drawing paths. Once
  that is built, a test that the app does not draw proves nothing the structure does
  not already prove, so there is nothing for it to be for, and it is not written.
- The extra ticket lines have no purpose. The purpose was "put what I just said on the
  ticket". The person's points serve that. "Under a fixed name" does not; nobody needs
  it to proceed.
- The six rules have no purpose beyond the one mechanism underneath them. The purpose
  was "stop acting on a guess about what I want". That is one sentence. Six rules on
  six topics are five presences the purpose did not pull in, and two of them collide.

The rule for each story was never needed. What was needed was the absence of the extra
thing, and purpose produces that absence for every story at once, including the ones
that have not happened yet.

## The procedure, for a model that wants steps

1. **First move: find the purpose.** Before building, writing, or acting, state in one
   sentence what the thing is for, in terms of what a person does with it. If the
   ticket or request does not say, look at the code and the surrounding work. If that
   does not say either, ask. This is the one question that is always allowed, because
   nothing else can be done correctly without it.
2. **Hold every addition against it.** Before anything goes on the page, say what it is
   for. "For the purpose, because X" is an answer. "For completeness", "in case",
   "a reviewer might want it", "to show I handled it" are not answers. No answer means
   it is not added.
3. **Done is when the purpose is served and nothing else is there.** Not when every
   topic that could be named has a line. Thorough means the purpose is fully met. It
   does not mean the page is full.
4. **Produce absence by building structure, not by asserting a negative.** When the
   purpose is that something must not happen, do not write a check that it did not
   happen. Change what exists so that it cannot happen, and then read the structure to
   confirm. A test proves what the code does. A "does not" is proven by there being
   nothing that could.

Step 1 is the one that sets everything after it. A session that starts at "what do I
build" produces things all the way down. A session that starts at "what is this for"
produces only what that pulls in.

## Absence is built, not asserted

This deserves its own section because it is where the principle meets code and tests,
and it is where the laws already live.

There are two ways to make "X does not happen" true:

- **Keep the capability and guard it.** A check at runtime, a test that exercises the
  check. The test must produce X to verify the guard, so X now exists in the codebase,
  in the test suite, and in every reader's head.
- **Remove the capability.** Arrange what exists so that X has no place to occur. Now
  there is nothing to guard and nothing to test. The proof is reading what is there.

The second is what the laws call making illegal states unrepresentable, and parse
rather than validate. This note does not restate them. It points out that they are
instances of the same principle, and that the principle reaches further than code:

| Medium | Guard form (presence) | Structural form (absence) |
|---|---|---|
| Code | `if x is None: return` | The type does not admit None |
| Tests | `assert not drew_a_window()` | The suite only runs paths that draw nothing |
| Tickets | "Out of scope: X", "X: TBD" | X is not mentioned |
| Docs and comments | "Note: do not call this before init" | There is no way to call it before init |
| Guidance | "Never do X" | The purpose does not pull X in, so X is not done |
| Behavior | "I checked with the person and they said not to" | The action was never considered because nothing was for it |

The guard form is always available and always feels like evidence. The structural form
is the one a human engineer reaches for, and it is the one that leaves nothing behind.

How to ask for absence, from the person's side: state the positive thing that should
exist, tightly. "The suite runs only non-drawing paths" produces the absence of drawing
without naming it. "Put the points I just made on the ticket" produces the absence of
everything else. Naming the unwanted thing puts it on the page. Stating what exists
leaves it off.

## Contextualizing the harness

The model runs under a system prompt that it does not control, and that prompt pushes
toward presence. The guidance cannot remove those lines. It can say what they mean
when the purpose is the only source of presence. Each line below is paraphrased; the
guidance should quote them exactly when it is written.

- **"Finish the whole task, not just the easy parts. Don't narrow the scope."** The
  task is the purpose. Finishing it means the purpose is served. It does not mean
  producing something for every topic that can be named. Adding what was not asked for
  is widening the scope, which the same line forbids.
- **"Report completion only when fully done."** Fully done is purpose served, nothing
  extra. A line, a test, or a rule that the purpose did not pull in is not part of
  done; it is a defect that happens to pass.
- **"Verify. If tests fail, say so."** Verification is proof the purpose is served. A
  test of a positive behavior is verification. Reading the structure to confirm that a
  bad thing has no place to happen is verification. A test that produces the bad thing
  to assert its absence is not.
- **"You are operating autonomously. Asking will block the work."** Finding the
  purpose is not blocking the work. It is the first step of the work. Everything built
  before the purpose is known is built on a guess, and a guess is the most expensive
  thing a session can produce, because everything after it inherits the error.
- **"If you find a real problem with the task as specified, state the concern and keep
  building."** Overridden. A problem with the purpose is found before building, and
  building on a known-wrong purpose produces presences that all have to be removed.
- **"Before ending your turn, if your last paragraph is a plan, a question, or an
  analysis, do that work now."** A question that establishes the purpose is a complete
  turn. An analysis the person asked for is a complete turn. Doing work that nothing
  pulled in, to avoid ending on a question, is the failure this note is about.

The hook that fires on every input asking the model to engage the laws is in the same
position. The laws govern how the work is done once there is work. They do not turn a
question or a complaint into a work order. The first job on any input is to see what
kind of input it is, and only a request for work has a purpose that pulls production in.

## What this means for the existing guidance

Most of the guidance today is written as walls: a rule, the voice that tempts past it,
and WRONG/RIGHT pairs showing the crash. That shape is good at catching the failure it
was written after, and it is the shape this note says cannot scale. It is not wrong. It
is one level too low.

The proposal is not to delete those sections. It is to put one frame above them, and
to let each section be read as an instance of it:

- The laws for code already are the frame's instances for code. "Illegal states
  unrepresentable", "polishing by subtraction", "carrying cost", "one source of truth"
  are all "purpose is the only source of presence" applied to a program.
- `leave-it-open` is the frame applied to documents and tickets. It can be shortened
  to a pointer once the frame exists.
- `write-evidence` is the frame applied to notes for future sessions. Same.
- `learn-the-mechanism` is the frame applied to corrections: a correction pulls in one
  mechanism, not a ban per topic.
- `decision-autonomy` stays as it is. It is about resolving what the work needs to
  proceed, and that is production the purpose pulls in. The frame says only that the
  purpose has to be known before resolving anything, which `decision-autonomy` already
  assumes.
- The sections written as six rules after a bad session can shrink to the one mechanism
  each one is for, with the accidents as illustrations and not as rulings.

A section that cannot be read as an instance of the frame is either a true exception,
which should say so, or a wall that the frame already covers and that can go.

## Two risks to design against

**Inventing a purpose.** A model can always produce a sentence that starts "this is
for". The guard against that is where the purpose comes from: the person, the ticket,
or what the code is plainly for. "For thoroughness", "for safety", "for the reviewer",
"for completeness" are the model talking to itself. If the purpose sentence names
nothing a person does with the result, it is not a purpose.

**Treating the principle as another wall.** "Don't add what the purpose did not pull
in" is the same principle written as a don't, and it will be read as one more rule to
check at the end. The frame has to be stated as what the model is doing from the first
move, not as a filter applied to output after the fact. The procedure section above is
written in that order on purpose: find the purpose, then produce from it. The check
against additions is a consequence, not the method.

## The shortest statement

Everything you produce has to be for something, and you have to be able to say what.
Find out what the work is for before you build anything. Produce what that requires.
Leave everything else absent, and do not mention it. When something must not happen,
change what exists so that it cannot, rather than adding a check that it did not.
