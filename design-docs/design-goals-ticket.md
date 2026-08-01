# Design goals: the `ticket` skill

This skill governs breaking work into epics and tickets that another agent will build - decomposing a feature or fix, writing or splitting tickets, defining acceptance criteria, ordering a backlog. It exists to make a ticket that still works when it is pulled: written while you plan, read much later, against code that has moved, by an agent who wasn't in the planning conversation.

## What it's built on

Much of the craft follows from one plain fact the skill states up front: a ticket is written early and read late, against a codebase that has changed in between, by an agent with none of the planning conversation. So the ticket has to carry what that agent can't reconstruct from the repo, and stay quiet about everything the repo already says.

That framing is a deliberate replacement. An earlier version of this craft was measured to perform worse than empty context, and the suspected cause was framing the ticket's reader as a cold, amnesiac executor - which produced fear-sized tickets and ceremony. The current craft was rewritten from scratch to build on the plain write-early/read-late fact instead of that frame. Avoiding the amnesiac-executor framing is itself a goal here, not just a stylistic choice.

## The goals, and the choices that serve them

**A ticket carries only what the repo can't supply.** Four things: the destination (what's true when the work is done), one line of why, a done-claim (one observable signal the destination was reached), and any context the implementer can't recover from the code or general engineering knowledge. The concrete rule that enforces this: don't restate what the repo already shows. Copy a function's current behavior into the ticket and either the copy stays identical - you spent tokens saying what the code says - or it drifts, and now the reader has two records and has to work out which one is current. Point at the code; don't transcribe it.

**Pointers stay coarse so they don't rot.** The skill caps `where` at a filename - no line numbers, no local function or variable names. A line number sends the reader to the wrong spot the first time code moves above it. This caps precision on location only; the destination and done-claim stay as sharp as you like about *what must become true*.

**Done is checkable by someone other than the builder.** The done-claim is a claim about what will be observable ("the old export endpoint returns 404"), never a certification ("complete and verified working"). The skill's reason: the agent that builds a thing can't confirm it. Verification is a separate activity whose breadth is set per situation, so it's kept out of ticket text entirely.

**The deliverable is a change to the system.** The skill draws the line at documents: a research write-up or findings doc that stands in for work never done is banned, because a document always reads as finished while the system is unchanged. A document that ships as the product - a README, user docs, a config the system reads - is a real deliverable. Spikes follow the same logic: allowed, with exactly one output shape, a change to the backlog (new tickets, splits, re-ranks), because that's checkable and a write-up isn't.

**Size at seams, and lean larger.** Split only where the system stands whole on one side and the next slice begins on fresh terrain. Both directions of mis-sizing are called out as real costs: too big and quality decays before the finish; too small and the fixed per-ticket tax (orienting, deciding it's done, landing it) swamps the work. When in doubt, take the larger slice. This is the design answer to the complaint that started the rewrite - over-splitting. A size is treated as a hypothesis steered during the work, not a promise, and the skill rejects up-front estimation research as costing more than the miss it prevents.

**Ordering is a ranked list and nothing else.** Within an epic: top is next, work down. No "blocks," no "depends on," no link graph. The stated reason is an observed failure - give tickets dependency links and planning turns into wiring edges until nothing is pullable. A ranked list can't lock; when A needs B, B ranks above A and the rank carries that truth. Cross-epic ordering exists but stays coarse and rare.

**Detail is written near the pull; structure is decided early.** The skill separates the two because they age differently. Structure (how work splits, what ranks above what) is durable. Detail (exact wording, specific context) is perishable because the code it describes keeps moving, so a ticket deep in the backlog wants a clear destination and little else. Grooming is keeping the plan true against what the work taught - re-rank, re-split, merge slivers, prune dead tickets - with no encoded cadence; a plan that has drifted is the only signal.

**Epics hold direction, not route.** An epic carries the destination, the why, the constraints that must hold whichever route the tickets take, and an epic-level done-claim. It does not carry the route - that lives in the tickets and re-plans as the work teaches the terrain. The size test is concrete: an epic fits in a paragraph plus an ordered list in a plain text file. If it needs nested phases or a diagram, it's several epics, or a route pretending to be a direction.

**Everything is exercisable with a plain text file holding a ranked list.** This is a standing constraint across all of the above: if a rule seems to need a custom field, a link type, or a lifecycle hook, the skill treats the rule as wrong. It assumes no tracker features.

## What it deliberately avoids, and why

- **The cold/amnesiac-executor framing and its water-glass imagery.** This is the suspected cause of the earlier version underperforming empty context - it produced fear-sized tickets and ceremony. Replaced by the plain write-early/read-late fact.

- **Handoff documents and session-continuity apparatus.** A meaningful share of tickets stop mid-stream, and the skill treats that as normal. But the state of partly-done work already lives in the repo - the branch, the diff, the commit messages. A separate status file would be a second record to disagree with the first. The resume test is deliberately minimal: a fresh agent with only the ticket, its epic, and the repo can carry the work forward.

- **Protocols that unwind or discard work at session end.** Rejected as self-refuting: whatever stopped this session leaves the next one starting from the same place with the same capacity, so discarding progress just means someone re-does it.

- **Verification invariants at session boundaries, and any "verified done" in a ticket.** The builder can't assert its own completion, so that assertion is kept out of ticket text.

- **Temporary counters, ratchet gates, and measurement scaffolding for migrations.** Progress markers are facts of the repo (a module deleted, a call-site count that dropped), not apparatus stood up to watch a number climb. The skill notes agents over-invest in this scaffolding. Gates belong only as permanent system rules.

- **Numeric triggers.** "More than N call sites," a target ticket-per-session count, a grooming cadence - the skill declines all of these. A number is a coordinate, and coordinates rot the same way a line number does. The codemod-instead-of-many-tickets idea is captured as an option with no numeric trigger; "one ticket per session" is described as an outcome of good sizing, never a target.

- **Dependency-graph ordering inside an epic** (locks the backlog, above) and **"kinds of facts" taxonomies or claims about agent trust psychology** - both dropped as either harmful or unsupported.
