# Writing tickets an agent pulls and builds

A ticket is written while you plan and read much later, when it is pulled from the
backlog. By then the codebase has moved, and the agent reading it wasn't in the
conversation where the work was decided. The ticket has to carry what that agent
can't reconstruct from the repo in front of it, and stay quiet about everything the
repo already says.

Everything here is exercisable with a plain text file holding a ranked list. If a
rule seems to need a field, a link type, or a lifecycle hook, the rule is wrong — go
back to the text file.

---

## What a ticket carries

Four things, and a short list of anything that survives the move:

- **The destination** — what should be true when the work is done. Not the steps to
  get there; the state that ends it. The route is the implementer's to find against
  the code as it actually is, which is not the code you were picturing while you
  wrote this.
- **One line of why.** The destination tells the agent where to arrive; the why tells
  it which arrival counts when the obvious reading of the destination turns out
  ambiguous — and it usually does. One line. If it needs a paragraph, the ticket is
  carrying a decision that hasn't been made yet; make it.
- **A done-claim** — one observable signal that the destination was reached. "The
  page loads at https://example.com." "The old export endpoint returns 404." "`build`
  produces a single binary." Something a reader could go check without having to
  reread your mind. A destination you can't write a done-claim for is a destination
  you haven't finished defining.
- **The context that won't survive the trip** — the bug report, the requirement, the
  vendor's API change, the decision already taken and its reason. These live in
  heads, chat logs, and closed conversations, not in the repo. If the agent can't
  recover it by reading the code and applying what any competent engineer knows, it
  goes in the ticket. If it can, it doesn't.

That last line generalizes: **do not restate what the repo already shows.** Copy a
function's current behavior into the ticket and either the copy stays identical — you
spent tokens to say what the code already says — or it drifts, the code changing while
the ticket doesn't, and now there are two clocks and the agent has to work out which
one is calibrated. Point at the code; don't transcribe it.

### Code pointers

Point no more precisely than a filename. Not a line number, not a local function or
variable name. Those are coordinates, and coordinates rot the instant someone edits
above them or renames the symbol — and someone will, because the whole premise is
that the code moves between writing and reading. A stale coordinate sends the reader
to the wrong spot with false confidence, which is worse than no pointer at all.

This caps precision on *where*, and nothing else. Be as exact as you like about
*what must become true* — the destination and done-claim stay sharp. "The retry
logic in `client.go` should back off exponentially" points well and ages well. "Fix
the bug at `client.go:214`" points sharply today and lies next week.

---

## The destination, never the mechanism `[TICKET:end-state-not-mechanism]`

The destination says what must become observably true. It never says how to make it
true. That line is the whole reason a ticket is pulled by a thinking agent instead of
executed by a script: the *how* is the implementer's to find, against the code as it
actually is, with the whole repo in front of them and the planning-time picture
nowhere in sight. When you write the mechanism into the ticket you are answering a
question the implementer is far better positioned to answer than you were — and worse,
you are answering it *first*, so your answer sits at the top of their context as an
anchor. They will build your guess instead of the right thing, and the judgment the
ticket existed to invite never fires. A ticket that carries its own solution has spent
the reader's thinking for them and spent it wrong.

Here is the exact move to catch, because it wears a badge that says it is safe. The
author writes a real mechanism — "a PreToolUse hook on the Skill tool that detects an
already-active medium and blocks a second" — feels the prescription in it, and staples
on a label: *"candidate direction, not prescriptive."* The label changes nothing. The
mechanism is already in the reader's context, already the most concrete and specific
thing in the ticket, already the path of least resistance. A disclaimer is a
"non-flammable" sticker on a can of gasoline: the sticker does not change what is in
the can, and the first spark reads the contents, not the label. Every variant of the
sticker is the same can — *"one option would be…," "e.g. you could…," "as a starting
point,"* *"the implementer might…."* The presence of the specific mechanism is the
leak; no amount of framing seals it. If you find yourself reaching for the sticker,
that reflex is the tell that you already know the payload doesn't belong in the
ticket — so delete the payload, not doubt about it. Strip the mechanism entirely and
state only what its presence was supposed to achieve.

The temptation, in your own voice, at the moment you write the destination: *"I can
see how to fix this — I'll drop the approach in so the implementer isn't starting
cold, and I'll tag it non-binding so they stay free."* That is the sticker being
reached for. The freedom you think the tag preserves is already gone the instant the
mechanism is on the page; concreteness outvotes disclaimers every time. Write the end
state and stop. If you genuinely cannot state the destination without naming a
mechanism, you have not finished finding the destination — the outcome you actually
want is hiding one level up from the fix you jumped to.

One kind of *how*-shaped sentence stays, and the difference is who authored it. This
is the exception, and it is louder-than-it-looks important, because the anti-mechanism
rule above is the loudest voice in this document and it will try to eat this paragraph
whole. A constraint the **requester actually imposed** — "implement XYZ using tmux,"
"must run on the subscription, not the API," "must be Opus," "must not touch the public
schema" — is not a mechanism you invented; it is a boundary on the solution space that
the world imposed and the implementer cannot discover by reading the code. That
survives the trip and belongs in the ticket, in the requester's own words. An
**author-invented mechanism** — the hook, the retry strategy, the data structure you
happened to picture — is a guess dressed as a requirement; it goes. The test is sharp:
did someone with authority over the outcome *require* this, or did you *think of* it
while planning? Keep what was required; strip what was thought of.

The two are not the same substance wearing different labels — they came into being in
different places, and *that origin is the whole distinction*. The requester's "using
tmux" was handed to you from outside; you could not have deleted it and still been
faithful to what you were asked. Your own "a token-bucket limiter" was minted in your
head this session; deleting it costs the ticket nothing the implementer can't rebuild
better. Think of it as provenance, not phrasing: a required constraint is *load-bearing
input* the world will still be enforcing when the ticket is pulled; an invented
mechanism is *scaffolding you erected* and can tear down without touching the building.
Same grammatical shape, opposite origin, opposite fate.

Here is the failure this paragraph exists to stop, because it is the one that actually
happens. You will be holding a directive that reads, in the requester's own words,
*"implement XYZ using tmux."* The anti-mechanism rule will be fresh and loud in your
context, and you will hear yourself think: *"'using tmux' is an implementation detail —
the rule says strip the mechanism and state only the end state, so out it goes."* Stop.
That is the rule firing on the wrong target. You did not invent tmux; the requester
handed it to you, and stripping it silently overwrites their requirement with your
guess that the medium is free to choose — the exact opposite of what they said. The
anti-mechanism rule was built to catch mechanism *you* thought up; it was never a
license to overrule the requester. When the *how* came from the requester, carrying it
in is not a mechanism leak — it is fidelity, and dropping it is the real defect.

- BAD: requester said "implement XYZ using tmux," ticket says "XYZ works" with tmux
  stripped out — the anti-mechanism rule over-firing on a requester constraint; the
  implementer is now free to pick a medium the requester already ruled out, and the
  requirement is gone with no record it ever existed.
- GOOD: "XYZ works; must be implemented using tmux (requester constraint)." — the end
  state, plus the boundary the world imposed, kept in the requester's own words.
- BAD: requester said nothing about how; ticket says "XYZ works via a token-bucket
  limiter" — a mechanism *you* minted, pinned for no reason; strip it.

Two questions, asked in this order, decide every case without reconstructing the
conversation: **(1) Is this a *how*?** If no, it stays regardless. **(2) If yes — did
it come from the requester, or from me?** From the requester: keep it, verbatim, and
mark it as theirs. From me: strip it. You never have to remember the original chat to
answer question 2 — it is answerable from one fact you always have at hand: whether
*you* are the one who thought of it. If you cannot honestly claim authorship of the
mechanism, it is not yours to remove.

Acceptance criteria obey the same law. They state observable outcomes and stay
maximally open on the route to them.

- BAD: "Add a PreToolUse hook on the Skill tool to block a second active medium.
  (Candidate direction, not prescriptive.)" — a mechanism with a sticker; the reader
  builds the hook.
- BAD: "Refactor `client.go` to use a token-bucket limiter." — the outcome wanted is
  bounded request rate; the limiter is one way there, pinned for no reason.
- GOOD: "Two media cannot be active at once; starting a second while one is live is
  refused with a clear message. Must work on the subscription, not the API." — the
  end state and the requester's real constraint, nothing about how.
- GOOD: requester said "implement XYZ using tmux" → "XYZ works; must be implemented
  using tmux (requester constraint)." — a requester-supplied *how* is not a mechanism
  leak; it is the boundary the world imposed, and stripping it would delete the
  requirement, not clean up the ticket.

---

## The done-claim is a claim, not a verification

The done-claim says what will be observable when the work lands. It does not say the
work has been checked, because the agent that builds a thing is not the one that can
confirm it. Write the signal; never write "verified done." Verification is a separate
activity — adversarial review, integration, a human looking — and its breadth is set
per situation, not baked into a ticket. A ticket that certifies its own completion is
asserting the one thing its reader is in no position to assert.

- WRONG done-claim: "Auth refactor complete and verified working."
- RIGHT done-claim: "Logging in with a valid password reaches the dashboard; an
  invalid one shows the error banner."

The second is checkable by anyone; the first is a promise about a check that hasn't
happened.

---

## What counts as a deliverable

The deliverable is a change to the system. Hold that line at two specific edges:

**Documents that stand in for system change are not deliverables.** A ticket whose
output is a research write-up, an analysis, a "findings" doc *about* work that was
never done has produced reading material, not a changed system. This is the tempting
substitute because a document always looks finished — it has a beginning and an end
and reads as complete — while the underlying system is exactly as it was. Ban it.

**A document that is the product is a real deliverable.** A README that ships, user
docs the project serves, a config file the system reads — here the document is the
system change. The line is sharp: is the document the thing being delivered, or a
report about a thing that wasn't? Ship the first; never ship the second.

---

## Spikes

A spike — buy information before committing to a build — is allowed, with exactly one
shape of output: **a change to the backlog.** New tickets, splits, re-ranks. The
learning lands as structure the next pull can act on, and you can check it — the
backlog is different than it was, in a way you can point at. A spike that outputs a
write-up instead is the write-up-as-deliverable trap again: "we now understand X" is
unfalsifiable. If the exploration taught you something real, it cashes out as tickets.

---

## Sizing

Split work only at real seams — a point where the system stands whole on one side and
the next slice begins on fresh terrain, where you could stop, have something coherent,
and pick up later without holding a dozen loose threads in your head. Cutting anywhere
else leaves a ragged edge: half a change on each side of the line, neither piece
standing on its own.

"One coherent push" is the size you're aiming for, and the phrase misleads in one
direction only: it sounds like a ceiling — *don't exceed a single pass* — when it is a
**range with a floor as well** `[TICKET:one-sharp-pass]`. A push has a smallest honest
size, below which you are no longer cutting work into pieces; you are cutting one piece
into paperwork. Both walls are real, and you have to feel both when you hold the knife.

Both directions of mis-sizing cost you, and they cost differently:

- **Too big** and quality decays before the finish — the end of a long slog gets less
  care than the start, and the last mile is where correctness usually lives. A lumped
  ticket that carries three unrelated changes is the common failure, and it is the
  worse one; when you cannot tell which way you've erred, this is the way to bet.
  "Build the entire billing system" is the shape of it: not one push but an epic whose
  invoicing, payment-capture, and dunning arcs each need different knowledge and land a
  different checkable outcome. That splits. Split heroic tickets down — the ceiling is
  the wall you'll hit first and hit most.
- **Too small** and the per-ticket overhead swamps the work. Every ticket has a fixed
  tax — orienting to where the code is, deciding it's done, landing it — and a backlog
  of confetti is mostly tax. When in doubt, take the larger slice; the seams are
  further apart than they look.

### Cut where the executor's context changes, not at every boundary you can see

The tax is the cheap half of the over-slicing cost. The expensive half is this: **a
seam is a change in the executor's context, not a line you can see in the file tree**
`[TICKET:cut-where-context-changes]`. Cut where the next slice needs *different
knowledge*, or produces a *different checkable outcome*, or has to *build on the
now-working state* an earlier slice left behind — not merely because there is another
file, another function, another call site. Most boundaries you can point at aren't seams.

Here is the trap, because it looks exactly like good decomposition. The work is: strip
one coercive voice from five short prompt-template files — one standard, understood
once, applied five times. Five files is five visible boundaries, and each file, taken
alone, "stands whole on one side." So the seam rule as a file test greenlights four
tickets, one seam per file, and it feels tidy. It is not decomposition. It is one
ticket photocopied five times. Each cold executor re-derives the same standard from
scratch, re-reads the same corner of the repo to orient, and — this is the cost that
draws blood — renders the same judgment slightly differently, so the five files come
back in five inconsistent voices. **A split that forces two executors to re-derive the
same judgment is not a smaller ticket. It is the same ticket, run twice, worse.** That
is the floor announcing itself.

The rehearsed temptation, so you catch it in the act: you'll be looking at N files or
N call sites, and you'll think *"one seam per file — splitting is cheap, and a tight
ticket is a clean ticket."* Stop there. Ask the floor's question, not the ceiling's:
*does the next slice change the executor's context — or does it just re-run the same
decision on the next name in a list?* One judgment applied in one motion is **one
ticket that happens to touch many files** — not many tickets that share a judgment.

- BAD: four tickets — "de-voice `intro.md`," "de-voice `plan.md`," "de-voice
  `review.md`," "de-voice `close.md`" — one standard, four cold re-derivations, four
  chances to drift.
- GOOD: one ticket — "strip the coercive second-person voice from the prompt templates
  in `templates/`; done when none of them address the reader as 'you must.'" One
  standard held once, applied consistently, checkable in one look.

The proverb that will be quoted against this is *"small tickets are good tickets,"* and
it has a home: small is right when each small piece is a genuinely *different* push —
different knowledge, different outcome, standing on the last one's result. It is wrong
the instant "small" is bought by handing the *same* push to more executors. Granularity
that multiplies the work count while dividing nothing real is not discipline; it is a
backlog talking to itself.

A size is a hypothesis, not a promise. You're guessing how far one coherent push
reaches, and you steer that guess during the work — splitting when a ticket turns out
to hide two seams, merging when two turn out to be one motion. Don't buy the guess with
estimation research up front; the work itself is the only instrument that measures it.

When the work is the same edit repeated across many sites, the better artifact is
often a tool that makes the edit — a codemod — rather than a ticket per site or one
ticket enumerating them all. Capture that as an option when the shape fits.

---

## Sessions end before the work does

A meaningful share of tickets — figure at least one in ten — stop mid-stream: the
session ends, the ticket isn't done. This is normal, not failure, and the ticket has
to survive it. The test: a fresh agent holding only the ticket, its epic, and the
repo can pick the work up and carry it forward.

Notice what's on that list — ticket, epic, repo — and what isn't. The state of
partly-done work already lives in the repo, in media built for exactly this: the
branch, the diff against the base, the commit messages left along the way. So you
don't need — and shouldn't invent — handoff documents, status files, or any
session-continuity apparatus. Adding them means maintaining a second record of
progress beside the one the repo already keeps truthfully, and a second record is a
second clock to disagree with the first.

And don't write protocols that unwind or discard work when a session runs out. The
reasoning refutes itself: whatever made this session stop leaves the next one
starting from the same place with the same capacity, so throwing away the progress
just means someone re-does it. Leave the work where it lies, in the branch, for the
next pull to continue.

---

## Epics

Some work is bigger than one pass and needs something to hold its direction while the
individual tickets come and go. That's an epic. It carries:

- the destination — what's true when the whole arc is done;
- the why;
- the constraints that must hold no matter which route the tickets take — the things
  that stay fixed while the path flexes;
- an epic-level done-claim: the observable signal that the arc, not one ticket,
  landed.

What an epic does *not* carry is the route. The route lives in the tickets, and it
re-plans as the work teaches you the terrain — an epic whose steps are all pinned in
advance is a plan that can't learn.

The size test for an epic: it fits in a paragraph plus an ordered list, in a plain
text file. If it needs more than that — sub-structures, nested phases, a diagram —
it's not one epic; it's several, or it's a route masquerading as a direction.

---

## Ordering within an epic

Order the tickets in an epic as a ranked list. That is the entire ordering
mechanism: top is next, work down. Nothing else — no "blocks," no "depends on," no
graph of links between tickets.

The failure that ranking prevents is specific and observed: give tickets dependency
links and the planning turns into wiring a graph, edge after edge, until every ticket
waits on another and nothing is pullable — a backlog that has locked itself. A ranked
list can't lock. There is always a top, always something to pull. When A genuinely
needs B first, B ranks above A and the list carries that truth without a single link.
The rank *is* the dependency, stripped to the one bit a puller needs: what's next.

Ordering between epics exists but stays coarse — this whole epic broadly before that
one — and it's rare. Reach for it only when one arc plainly has to precede another,
and even then keep it to the coarse statement, not a web of couplings.

---

## Keeping the backlog true

Two properties age at different rates, so treat them differently. **Structure** — how
work splits, what ranks above what — is durable; decide it early and it holds.
**Detail** — the specific context, the exact destination wording — is perishable,
because the code it describes keeps moving; write it near the pull, when the ticket
is close to the top and the detail still matches the world. A ticket deep in the
backlog wants a clear destination and little else; filling in its particulars now
just buys detail that has to be rewritten before anyone reads it.

Grooming is keeping the plan true against what the work has taught: re-rank as
priorities shift, split a ticket that grew a second seam, merge slivers back
together, prune tickets the work made pointless, and turn what you learned into
structure — including progress that's now simply a fact of the repo (a module
deleted, a call-site count that's dropped) rather than a counter you stood up to
watch it climb. There's no cadence and no trigger to encode; a plan that has drifted
from the work is the only signal, and you'll see it when you look.
