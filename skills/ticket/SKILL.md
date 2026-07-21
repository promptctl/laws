---
name: ticket
description: Craft reference for breaking work into epics and issues another agent will build — backlog planning, decomposing a feature or fix, writing or splitting tickets, defining acceptance criteria. Use BEFORE you create or groom tickets. The reader of a ticket is a cold executor with a bounded, degrading context who builds one ticket and then forgets everything; the whole craft follows from that fact. This is not prompt-writing (a prompt is read once, next to its decision; a ticket waits in a backlog and is pulled cold, and it must also be sized and sequenced) and it is not code or prose — do not carry those standards in, or ticket craft out.
---

<!-- The home of ticket craft, written in the effective (rhetorical) style. The style
     authority for any future edit to THIS file is the prompt skill in this plugin —
     never the tickets it teaches you to write, never the code skill. Do not
     deduplicate, compress, or "clean up" this file: the redundancy is load-bearing.
     This skill is tracker-agnostic (lit / Jira / GitHub) and teaches ticket CRAFT.
     Tool operation — the buttons to create, rank, or link an item — is the tracker's
     to document; but any mechanic that is itself craft (rank as ordering, detail vs
     pull-distance, the criterion) is stated here in full even if lit also states it. -->

# Writing tickets for an agent to execute

You are breaking work into pieces another agent will build. Not a plan you will
follow yourself — a backlog of tickets that get pulled, one at a time, by an executor
you will never meet and cannot brief.

Everything here descends from one fact about that executor. Learn it first, in the
body, because every rule below is just this fact wearing a different coat:

**The executor arrives cold, works from a context that fills and clouds as it goes,
finishes one ticket, and then forgets everything.** Cold: nothing you read, decided,
or felt while planning is in its head — no hallway conversation, no "obviously we
meant," no memory of the epic's shape. Clouding: its working memory is a glass of
water, clear at the first pour and silty at the brim; the agent that starts sharp
ends dull, and the dull end is where bugs ship. Forgets: when the ticket closes, that
glass is emptied. The next ticket is built by a new stranger, just as cold.

So a ticket is a message to an amnesiac who has your job and none of your context,
who will read it once, act on it while slowly going blind, and never get to ask you
what you meant. Write every ticket as if you will not be there — because you will
not.

`[TICKET:cold-executor]` — this is the root. When any rule below feels arbitrary,
trace it back here and it stops being arbitrary.

The failure is silent. A bad ticket does not throw. It produces an agent that
confidently builds the wrong thing, or builds the right thing badly in its dull final
third, or sits in the tracker wiring dependencies until nothing can be pulled — and
nobody attributes the wasted session to the ticket, because the ticket "looked fine."
You are engineering infrastructure that fails in a room you are not in. Amplitude is
the price.

---

## Epics and issues: cheap, plural, one sharp pass each

An **epic** is a whole chunk of work — a feature, a fix, a migration, the entire
thing a stakeholder would name. An **issue** is one slice of that chunk, sized so a
single cold executor builds it start-to-done in one sharp pass. The epic is the
destination; the issues are the steps that walk there, each one leaving the ground
solid enough to take the next step.

Make as many as the work honestly needs. Epics and issues are cheap — cheaper than a
session spent thrashing because the work was lumped into three giant tickets nobody
could finish sharp. The instinct to keep the backlog "clean" with a few big items is
the enemy: **split until each issue is one sharp pass, then split once more if you
hesitated.** Ten honest issues that each build something and hand off clean beat three
heroic ones that each die dull two-thirds through.

The temptation, in your own planning voice: *"This is really all one piece of work —
I'll make it one ticket and let the executor figure out the order."* Refuse it. You
have the whole epic in your head right now, sharp and cold-free; the executor will
have one ticket and a clouding glass. The decomposition is the gift you can give it
that it cannot give itself. Spend your clarity now so it does not have to manufacture
clarity later, on a worse context than yours.

- BAD: one ticket, "Build user authentication."
- GOOD: an epic "User authentication," split into ordered issues — schema + migration
  for credentials; signup endpoint that persists and returns a session; login endpoint
  that verifies and issues; middleware that gates a protected route — each building
  something that runs and can be checked, each handing the next a working system.

Diagnostic: could a cold agent pull the top issue right now and finish it sharp,
without reading your mind or the four issues below it? If not, you have not
decomposed — you have relabeled.

---

## Size to one sharp pass, with headroom [TICKET:one-sharp-pass]

An issue is the largest slice one executor can carry from start to *verified done* in
a single pass and still finish **sharp** — with enough clarity and context left over
to check its own work, not just to produce it. Not "as much as fits." As much as
fits *with headroom*, because the last stretch of a too-full ticket is built by the
dull agent, and dull is where the defect goes in unseen.

You size by imagining the finish, not the start. Anyone can begin a huge ticket
crisply. The question is the *end*: when the executor writes the final line and turns
to verify, is the glass still clear enough to see a mistake? If the honest answer is
"it would be running on fumes by then," the ticket is too big — split it, and let two
agents each finish sharp instead of one finishing blind.

The temptation: *"It's all connected — splitting here just adds overhead, and one
capable agent can hold the whole thing."* Refuse it. It can hold the whole thing at
the start. It cannot hold the whole thing at the finish, and the finish is what
ships. The overhead of one more ticket is a minute of your planning. The overhead of
a ticket finished dull is a defect discovered three sessions later by someone cold.

- BAD: "Implement the billing system" — one issue, executor is silt by the time it
  reaches refunds.
- GOOD: "Add the charge endpoint and prove it against a live test card" — one issue,
  finished with clarity to spare, and the refund flow is the next ticket, pulled fresh.

Diagnostic: picture the executor at the *last* acceptance check of this ticket. Sharp,
or fumes? If you cannot honestly say sharp, split.

(This section sizes the *work* — how big a slice one ticket cuts. How much *detail*
the ticket's description carries is a second, separate sizing, and it gets its own
section next.)

---

## Detail is written just in time, not up front [TICKET:detail-just-in-time]

Two things get decided when you plan an epic, and they have opposite shelf lives.
**Structure is durable — decide it now.** How the epic splits, how many issues, what
each one builds, their rank: that is the decomposition, it is the gift only you (with
the whole thing in your head, cold-free) can give, and it does not rot — a split is a
split next week. **Detail is perishable — decide it late.** The sharp acceptance
criterion, the reading-pointers, the exact end-state prose: how much of that a ticket
carries scales with how close it is to being pulled.

A ticket at the bottom of the backlog gets a title and a line of intent, and no more.
A ticket about to rise to the top gets fleshed out — criterion sharpened, pointers made
current, sized to one pass. The reason is the same rot that sets the filename ceiling:
detail written now, against the code and plan as they stand today, is stale by the time
a cold agent pulls it weeks and refactors later, and the bottom-of-backlog ticket may
be re-ranked, re-split, or deleted before anyone touches it. Detail written far ahead
is detail written to be thrown away.

So: **sketch the whole epic thin, then groom each ticket sharp as it approaches the
pull.** Split up front — structure lasts. Flesh just in time — prose rots.

The temptation: *"I have the entire epic clear in my head right now — I should fully
spec every ticket while I've got it, top to bottom."* Refuse it, but only for the
*detail*. Capture the structure completely, yes — the splits and the ranks, now, while
it is sharp. But do not pour paragraphs of acceptance criteria into the ticket ranked
ninth: it will be re-groomed against a changed codebase before it is ever pulled, and
every sentence you write today is a sentence that rots or gets deleted. Your clarity is
best spent on the *shape* of the whole and the *detail* of the next.

- BAD: an epic where all twelve issues are fully specified with exact criteria on day
  one; by the time issue nine is pulled, half its detail contradicts the code.
- GOOD: twelve issues split and ranked on day one, each a title and an intent; issue one
  fully fleshed, and each next issue groomed sharp just before it rises to the top.

Diagnostic: is the detail on this ticket proportional to how soon it will be pulled? A
richly specified ticket ranked last is polish that will rot; a thin ticket at the top
is a cold agent with nothing to go on. Match the depth to the distance.

---

## Every ticket builds something real [TICKET:builds-something-real]

A ticket's output is a change to the system that leaves it in a new, working,
checkable state. Code that runs. A migration that applied. A behavior that now
happens and can be observed. **Never a document as the deliverable.** No
"investigate" tickets, no "design the approach" tickets, no "write up the plan"
tickets — those produce paper, and paper is not a state the next cold agent can build
on, because the next agent arrives cold and will not carry your paper in its head
anyway.

The one exception is exactly the one your goal names: an issue whose *job* is to break
down an epic into more issues. That output — new tickets in the backlog — is real
structure the next agent pulls from. Splitting the work is building the backlog.
Everything else must move the system, not describe it.

The temptation: *"I don't understand this area yet — I'll make a ticket to research it
first, then a ticket to build it."* Refuse it. The research ticket's output is a
document, and the build agent arrives cold and re-reads the area anyway; you have paid
for the reading twice and shipped nothing the first time. (Where research *does* go is
its own section below — it is a verb, not a ticket.)

- BAD: "Research caching options and document a recommendation." Output: a wiki page
  no cold agent will trust without re-checking.
- GOOD: "Add a read-through cache to the profile endpoint; a cache hit serves without
  touching the database." Output: a system that now caches, and a check that proves it.

Diagnostic: when this ticket closes, is the system materially different and can I point
at the difference? If the only artifact is words, it is not a ticket.

---

## Give it a checkable criterion [TICKET:checkable-criterion]

Every issue carries one acceptance criterion the cold executor can check *without
asking anyone* — because there is no one to ask. Machine-checkable is the bar: a test
that passes, an endpoint that returns the right shape, a command whose output is now
different, a behavior observable from outside. The criterion is how a stranger with no
memory of your intent knows, on its own, that it is done — and knows it is done
*right*, not just done doing things.

This is not the global "definition of done" — tests green, linter clean, merged. That
lives once, for the whole project, and every ticket inherits it silently; do not
restate it on each ticket. The acceptance criterion is *this ticket's* specific proof,
the one thing that is true after and was not true before.

The temptation: *"'Login works' is clear enough — the executor will know."* Refuse it.
"Works" is a region so wide the dull agent is already standing in it and will declare
victory from inside it. A criterion with no edge cannot be failed, and a criterion
that cannot be failed cannot be passed — it can only be asserted.

- BAD: "User authentication works correctly."
- GOOD: "POST /login with valid credentials returns 200 and a session token; with
  invalid credentials returns 401; the token authenticates a subsequent GET /me."

Diagnostic: could the executor be *wrong* about whether this criterion is met? If not
— if "done" is a matter of the agent's opinion rather than an observable fact — it is
not yet a criterion.

---

## Write the destination, not the route — plus one line of why [TICKET:end-state-and-why]

A ticket states the end state the system should reach, not the steps to get there. The
executor is a capable builder standing in the actual code, which has moved since you
planned; it will find a better route than the one you would have scripted, and it
should be free to. A ticket that reads as a numbered to-do list handcuffs the one
agent who can actually see the terrain, and when step 3 turns out wrong against the
real code, the list has no answer and the cold agent has no way to recover your intent.

So also write **one line of why** — the goal the end state serves. Intent is what lets
the better-informed executor do the right thing when your literal words turn out
wrong. The *what* can rot against a moving codebase; the *why* survives, and a builder
who knows the why can re-derive a correct *what* on the spot. A ticket with a
destination but no purpose is a bearing with no reason — follow it off a cliff and it
was still "correct."

The temptation: *"I know exactly how to do this — I'll just write the steps."* Refuse
it. You know how to do it against the code as it was in your head. Write where the
system must end up and why it matters; let the agent standing in the real code choose
the road.

- BAD: "1. Open auth.js. 2. Add a function checkToken. 3. Call it in the router. 4.
  Add a try/catch."
- GOOD: "Protected routes reject requests without a valid session token (401), so that
  an expired login cannot reach user data. Verify: a request with no token to any
  /account route returns 401."

Diagnostic: does the ticket say where to arrive and why, rather than which turns to
take? If it reads like driving directions, rewrite it as a destination.

---

## The filename ceiling: never more specific than a filename [TICKET:filename-ceiling]

This one is a **wall, not a principle**, and the difference is the point. A principle
invites judgment, and an agent will always find a judgment call that lets it write
just a little more specificity "because this time it's stable." So there is no
judgment here: **a ticket may name a file. It may not go finer than a file.** No line
numbers, no "the function on line 40," no exact variable names, no the-third-branch-of-
the-if. A filename, and no deeper.

The reason is rot, and rot is fast. Between the moment you write the ticket and the
moment a cold agent pulls it, the code moves — line 40 is now line 62, `checkToken`
got renamed, the branch got refactored away. A filename survives a lot of that; a line
number is a lie the instant someone adds an import. And a specific-but-wrong pointer is
*worse* than none: the cold executor, having no memory to contradict it, trusts your
stale line number and edits the wrong place with confidence. Vagueness makes it look;
false precision makes it look away.

The temptation: *"This line number / this exact symbol is genuinely stable — it'll save
the executor a search, and it won't move."* Refuse it — not because you're wrong this
once, but because the wall only works if it never opens. The instant "it's stable this
time" is an allowed thought, every over-specification finds a reason to call itself the
exception, and the ceiling is gone. Name the file. Let the agent, standing in the
current code, find the line. It has to look at the file anyway; trust it to read.

- BAD: "In auth.js line 40, rename the `tok` variable and add validation before the
  return on line 47."
- GOOD: "In auth.js, tokens are accepted without validation; validate them before use."

Diagnostic: is anything in this ticket more specific than a filename? Delete the excess
precision. Every time, no exceptions — that is what makes it a ceiling.

---

## Rank is the order; do not wire dependencies inside an epic [TICKET:rank-is-order]

Inside an epic, issues are ordered by **rank** — a simple top-to-bottom priority — and
rank is the *only* ordering. You do not add explicit dependency links between issues in
the same epic. Treat them as all implicitly depending on the ones above: you build top
issue first, then the next, and the natural flow of the work is the rank order you gave
them. That is the loose sequencing every backlog already assumes; make it the sole
mechanism and stop.

This is a wall against a watched pathology. Turn an agent loose with a dependency graph
and it will wire issue to issue to issue — B needs A, C needs B, D needs A and C,
"actually E should block on B too" — until the graph is a knot and *nothing is
pullable*, because every ready ticket is waiting on another ready ticket in a cycle the
agent talked itself into. The agent mistakes drawing dependencies for doing work. Rank
cannot deadlock: it is a list, a list always has a top, and the top is always pullable.

Explicit dependencies are for **across epics only** — epic B genuinely cannot start
until epic A ships. That is a real, coarse, rare link, and it never forms a knot
because it is between whole chunks, not within one. Inside the chunk: rank, and only
rank.

The temptation: *"These two issues are related — I'll add a dependency so they're built
in the right order."* Refuse it. If they must be built in an order, *that is what rank
is*. Put the one first. Adding a dependency link to express "first" is how the knot
starts — you reach for a graph edge when a list position was the whole answer.

- BAD: within one epic, issue C `depends-on` B, B `depends-on` A, D `depends-on` B and
  C — a graph an agent will keep growing until the queue jams.
- GOOD: within one epic, issues ranked A > B > C > D. Same order, no edges, always
  pullable.

Diagnostic: am I adding a dependency between two issues in the same epic? Stop — set
their rank instead. Is this dependency between two whole epics? Then it may be real.

---

## Research is a verb, not a deliverable [TICKET:research-is-a-verb]

Agents need to learn the terrain — that is not in question. What is forbidden is
research as a *thing produced*. Research is something you *do*, and it has exactly two
legitimate places to go, because the cold executor makes every other place useless:

1. **Into the backlog** — as structure. You investigated and now you can split the epic
   better, re-rank the issues, groom a vague ticket into a sharp one, or *pre-seed* a
   ticket with reading-direction: "the relevant logic lives in `billing/charges.js` —
   read it before starting; you can skip the legacy `payments/` tree." That direction
   is real value the next agent uses. But it inherits the **filename ceiling**: point at
   *where to look*, never bake in *what you concluded*. "Read charges.js" survives; "the
   bug is the off-by-one on the retry counter" is a stale answer the cold agent will
   trust over its own eyes.
2. **Into the code** — as building. The executor reads the area *while* building it,
   because it has to understand what it changes. That reading is done by the agent that
   uses it, in the context that needs it, and thrown away when the ticket closes —
   exactly where reading belongs.

There is **no spike** — no ticket whose output is "I read some things and now I
understand." An LLM spike transfers nothing: the agent that reads is not the agent that
builds (it forgot everything at the ticket boundary), so the build agent arrives cold
and re-reads regardless. You paid for a session and got a document the next stranger
won't trust. Splitting an epic is *not* a counterexample — it looks like "research"
but its output is backlog structure, which is sink 1. The tell is the output: cognition
that becomes tickets or code is work; cognition that becomes a standalone document to
be read later is a spike, and there is no reader for it.

The temptation: *"I need to understand X before anyone can build it — I'll make a spike
to figure it out."* Refuse it. Understanding does not survive the ticket boundary. Turn
what you learn into a sharper split, a re-rank, or a reading-pointer on the build
ticket — or let the build agent learn it live. Never park it in a document and call
that progress.

- BAD: "Spike: investigate the current caching layer and write up how it works."
- GOOD: split the epic using what you learned, and on the top build ticket add: "the
  cache lives in `lib/cache.js` — read it first; the invalidation path is the part that
  matters here."

Diagnostic: does this cognition end as a ticket, a re-rank, a reading-pointer, or code?
Good. Does it end as a document someone is supposed to read later? That reader is cold
and won't — kill it.

---

## Groom the backlog: keep the memory true [TICKET:groom-the-backlog]

Here is what the amnesia makes true, said outright at last: **the backlog is the only
memory that survives the executor.** The glass empties at every ticket boundary — but
the backlog does not. It is the one place project knowledge persists across a hundred
cold strangers, the memory the executors have *because they have none of their own*. So
it is not a plan you write once and walk away from. It is a living memory, and living
memory decays. Grooming is tending it — keeping it true, so each cold pull inherits
fact and not a six-week-old assumption wearing fact's clothes.

An ungroomed backlog does not announce its rot. It sits there looking planned while the
code moves out from under it: pointers go stale, a criterion stops matching the
behavior it was written against, a rank still reflects the priorities of launch day.
Then a cold agent pulls the top ticket and — with no memory to contradict it — trusts
every stale word and builds, confidently, against a world that is gone. This is the
filename ceiling's lesson at backlog scale: a missing ticket makes the agent look, a
stale ticket makes it look away. False memory is worse than none.

Grooming is not one act; it is the standing maintenance that keeps the memory honest,
and you already hold every tool it needs:

- **Re-rank** — priorities moved since you planned; the top of the backlog must mean
  "pull this next" *today*, not on the day you wrote it. `[TICKET:rank-is-order]`
- **Re-split** — you learned a ticket is bigger than one sharp pass; cut it now, before
  a cold agent inherits work that finishes dull. `[TICKET:one-sharp-pass]`
- **Re-sharpen** — the ticket rising toward the top gets its detail fleshed and its
  pointers made current. That is grooming's detail-move, and it *is*
  `[TICKET:detail-just-in-time]`.
- **Prune** — a ticket the work outgrew, a fix some refactor already made, a duplicate:
  delete it. A dead ticket left in the queue is a landmine for the next stranger who
  pulls it and builds something no longer wanted.
- **Absorb** — what you learn becomes structure here, never a document.
  `[TICKET:research-is-a-verb]`

The temptation: *"I planned the backlog carefully — the tickets are written, agents can
pull from here. Touching it again is overhead."* Refuse it. You did not build a
monument; you built a memory, and a memory you stop tending is a memory that starts
lying. The overhead of a grooming pass is minutes. The cost of skipping it is a cold
agent three weeks out, building hard against your stale assumptions, and no one in the
room able to say why the output came back wrong.

Disarm the one proverb that will be turned against grooming — and it is your own
`[TICKET:detail-just-in-time]`: *"detail is written just in time, so I should leave the
backlog alone until each ticket is pulled."* No. Just-in-time governs how much *detail*
a far-off ticket carries; it says nothing that licenses letting the backlog's *truth*
rot. Re-ranking, pruning the dead, re-splitting the oversized — that is not premature
detail, it is keeping the memory accurate, and it comes due the moment the world moves,
not the moment the ticket is pulled.

- BAD: plan the whole backlog once at kickoff, never revisit it; three months in, half
  the tickets point at renamed files and the ranks reflect priorities two pivots stale
  — and every cold agent pulls that rot as gospel.
- GOOD: keep the top of the backlog honest as the work moves — re-rank to what matters
  now, prune what died, re-split what grew, sharpen what is about to be pulled — so the
  next stranger inherits a memory that is still true.

Diagnostic: if a cold agent pulled the top ticket *right now*, would it inherit the
current world or a stale one? The gap between the backlog and reality is the grooming
you owe.

---

## The tool versus the craft

This skill is about what makes a ticket *good* — the craft — and it holds whether the
backlog lives in lit (the house tracker), Jira, or GitHub Issues. It assumes a tracker
exists; it does not teach you to *operate* one. The button-pushing — the exact command
to create an item, the field where rank goes, how to file a cross-epic dependency — is
lit's to document, and lit documents it.

But where a mechanic *is* craft, it is stated here in full, even if lit states it too —
rank as the sole intra-epic ordering, detail scaled to pull-distance, the criterion
that proves done. Those are not lit trivia that happen to overlap; they are what makes
the ticket good, and a principle you need at the moment you are writing a ticket does
not belong one application away. Better said twice than missing when it counts.

---

## The recap — the walls, in the executor's own light

You are writing for a **cold executor** `[TICKET:cold-executor]`: it arrives with none
of your memory, works from a glass that clouds as it fills, finishes one ticket, and
forgets. Every rule is that fact in another coat:

- `[TICKET:one-sharp-pass]` — size an issue to the largest slice one executor finishes
  *sharp*, with headroom to check its own work. Picture the finish, not the start.
- `[TICKET:detail-just-in-time]` — split the whole epic up front (structure lasts);
  flesh each ticket's detail only as it nears the pull (prose rots). Depth scales with
  distance.
- `[TICKET:builds-something-real]` — every ticket leaves the system in a new working,
  checkable state. Never a document as the deliverable. (The one exception: a ticket
  whose output is more tickets.)
- `[TICKET:checkable-criterion]` — one machine-checkable proof per issue, that a
  stranger can verify with no one to ask. Distinct from the global definition of done.
- `[TICKET:end-state-and-why]` — write the destination, not the route, plus one line of
  intent so a better-informed builder can serve the goal when your literal words rot.
- `[TICKET:filename-ceiling]` — never more specific than a filename. A wall, not a
  principle, because false precision rots fast and the cold agent trusts it over its
  own eyes.
- `[TICKET:rank-is-order]` — inside an epic, rank is the only ordering; no dependency
  links (they deadlock). Explicit dependencies cross epics only.
- `[TICKET:research-is-a-verb]` — research goes into the backlog (splits, re-ranks,
  reading-pointers under the filename ceiling) or into the code (learned while
  building). Never a standalone document. There is no spike for an amnesiac.
- `[TICKET:groom-the-backlog]` — the backlog is the only memory that survives the cold
  executor; keep it true. Re-rank, re-split, re-sharpen, prune, absorb — as the world
  moves, not once at kickoff. A stale ticket is a lie the next stranger can't catch.

Decompose an epic into ordered vertical slices that each build something real, each
carry a checkable criterion, each sized to one sharp pass, ordered by rank alone.
Cheap, plural, one at a time. Cite the token when a rule shapes a ticket you write —
naming the wall at the moment you build to it is how it stays a wall.
