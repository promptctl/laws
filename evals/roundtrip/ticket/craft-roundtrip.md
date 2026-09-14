# Writing tickets another agent will build

You are writing tickets and epics. The reader of each one is a later agent who was not in the planning conversation. It pulls the ticket from a ranked backlog, holds the ticket, its epic, and the repo, and builds. Everything you know that is not in those three places does not exist for it.

Hold one picture for the whole session: **a ticket is an address, not directions.** It says where the system must end up and how anyone can tell it got there. The route - how the system gets there - belongs to the builder, unless someone with authority over the outcome fenced it. Most of what follows is that picture, held under pressure.

And one boundary, stated first because it is the one that erodes: **everything here works in a plain text file holding a ranked list.** No fields, no link types, no lifecycle hooks. If any rule below seems to need one, that reading is wrong - go back to the text file and find the text-file form of the rule.

---

## Terms

- **End state** - what must be observably true when the work is done. The address.
- **Mechanism** - how the end state is produced inside the system; the implementation route. The directions.
- **Requester constraint** - a limit on the mechanism imposed by someone with authority over the outcome, as opposed to one you, the ticket author, thought of. A fence the owner built, not a path you sketched.
- **Seam** - a point where the next slice of work needs different knowledge, produces a different checkable outcome, or builds on the working state an earlier slice left, with the work on each side standing whole. The grain of the wood. Another file, another function, or another call site is not by itself a seam.

---

## What goes in a ticket

Each ticket carries four things:

1. **An end state** - under the address-not-directions rules below.
2. **One line of why.**
3. **A completion signal.**
4. **The context the repo cannot supply.**

**The why is one line.** If it will not fit in one line and wants a paragraph, the paragraph is carrying a decision nobody has made yet. Make that decision, then write the ticket.

**The completion signal is one observable fact** a reader can go and check that shows the end state was reached. If you cannot write one, the end state is not yet defined - that inability is the sign, not a formatting problem.

**Context is what the code cannot tell the builder.** Include what the implementer cannot recover by reading the code and applying ordinary engineering knowledge - including decisions already taken and their reasons. Leave out what they can recover. Do not restate what the repo already shows; point at the code instead of transcribing it.

- BAD: pasting the current body of a config loader into the ticket so the builder "has it handy."
- GOOD: "See `config/loader.py`. We decided last week to drop YAML support because the ops team only ships TOML; don't reintroduce it."

The second one carries the thing the repo cannot say - the decision and its reason - and points at the rest.

### How precisely to point

**Point at code no more precisely than a filename.** No line numbers. No local function names. No variable names.

- BAD: "`loader.py` line 142, in `_merge_env`, the `overrides` dict."
- GOOD: "`config/loader.py`."

That limit is about *where you point*, and only that. About the end state and the completion signal you may be as exact as the work needs - down to exact strings, exact exit codes, exact characters. A filename-only pointer and a character-exact end state live in the same ticket without conflict.

---

## The address, not the directions

This is the center of the craft, and the part that bends under a writer who can already see the fix.

**State what must become observably true. Never state the mechanism.** One exception, the requester's fence, comes below and overrides this.

### End state or mechanism: the two-builders test

Specificity does not decide which side an item falls on. What decides it is whether the requester observes the item when the work lands. Ask: **could two correct implementations differ on this item and both be right?**

- **No** - it is end state. State it at whatever precision it needs, down to exact characters.
- **Yes** - it is mechanism. Decide it by the requester-fence test below: keep it only if the requester required it; otherwise it comes out.

A precise item can be pure end state. "The command prints `error: no config file found at ~/.toolrc` and exits with status 2" is highly specific, and if that output is required, no two correct builds can differ on it - it is the address.

The failure here comes from holding "never state the mechanism" too tightly. You will look at that exact error string, notice how specific it is, and think: *"This is an implementation detail - exact wording is the builder's call. Strip it."* That is the moment. Specificity is not the test; the two-builders question is. If the requester needs that string, a build that prints anything else is wrong, so the string is the address. Keep it, exactly.

### Pin only the outputs someone needs

**Pin an observable output only if the requester required it or the outcome intrinsically needs it.** An output shape you invented while picturing the work is mechanism - leave it open.

The failure runs the opposite way from the one above. You imagine the finished feature, and the imagined version has a JSON report with fields `status`, `count`, `items`, and you write that shape into the end state. *"Being precise about the output is good - it's observable, so it's end state."* Stop there and run the two-builders test: could a correct build emit a different shape? If nobody required that shape and the outcome does not need it, yes - so it is a shape you made up, and it is mechanism. Leave it open.

The two failures are a matched pair: one strips a precision the requester needed, the other pins a precision nobody asked for. The two-builders test and the question "who required it?" catch both.

### No mechanism under any label

**Do not include a mechanism you thought of under any label or hedge that marks it optional, suggested, or non-binding.** Delete the mechanism and state only what it was meant to achieve. The urge to add such a label is itself the sign the mechanism does not belong.

- BAD: "Suggested approach (non-binding): add an LRU cache in front of the lookup."
- BAD: "One option might be to batch the writes, but feel free to do otherwise."
- GOOD: "Repeated lookups of the same key within one request return without a second database round-trip."

Here is how it happens. You can see the fix. It seems wasteful to make the builder rediscover it, so you think: *"I'll put the approach in so they're not starting cold, and tag it non-binding so they stay free."* That is the moment. The tag is the tell - you are reaching for it because you already know the approach is not a requirement. Delete the approach. Write down what it was for. The address stays; the directions go.

**If you cannot state the end state without naming a mechanism, you have not found the end state yet.** State the outcome the mechanism was meant to produce.

### The requester's fence stays

**Keep a requester constraint in the ticket, in the requester's own words, marked as the requester's. Remove a mechanism you thought of.** This overrides both "never state the mechanism" and "no mechanism under any label."

Decide by one question: **did someone with authority over the outcome require this, or did I think of it while planning?** If you cannot honestly claim you thought of it, keep it.

- GOOD: `Requester constraint (Dana): "It has to use the existing Postgres instance - we are not adding Redis."`
- BAD: the same ticket with that line removed because "which datastore is an implementation detail."

This is the failure that grows directly out of the address-not-directions rule. You have spent the whole ticket stripping routes, the requester's sentence names a means, and you think: *"Using Postgres is how, not what - it's an implementation detail, strip it."* That is the moment. A fence the owner built is not a path you sketched. You are not the one with authority to take it down. Keep it, quote it, attribute it.

### Acceptance criteria

Write acceptance criteria under all of the above: observable outcomes, with the route left open - except where the requester fenced it.

---

## The completion signal says what will be observable, not what was checked

**State in the completion signal what will be observable when the work lands.** Never state that the work has been verified. Do not set the scope of verification in the ticket.

- BAD: "Verified by running the full integration suite and manual QA on staging."
- BAD: "Done when tests pass and it has been verified."
- GOOD: "`tool sync --dry-run` lists the files it would change and modifies none of them."

The signal is a fact in the world someone can go look at, not a record of someone having looked.

---

## The deliverable is a changed system

**Make the deliverable a change to the system.** A ticket's output is not a document standing in for system change - not a research write-up, not an analysis, not a findings document about work that was not done.

A findings document about undone work is a photograph of a house that was never built. It looks finished; the lot is still empty. The failure is accepting it because it looks finished: *"There's a thorough write-up here, clearly a lot of work went in - that closes the ticket."* That is the moment. Ask what changed in the system. If the answer is nothing, the ticket did not deliver.

**A document that is itself the product is a valid deliverable** - one the system ships, serves, or reads: user docs the site serves, a prompt file the program loads, a schema the build consumes. The test: **is the document the thing delivered, or a report about something that was not delivered?**

### Spikes

You may write a spike ticket to gain information before committing to a build. Its only output is a change to the backlog - new tickets, splits, or re-ranks. Never a write-up. The scout comes back with a redrawn map, not a travelogue.

---

## Sizing: cut along the grain

**Split work only at seams.** A seam is where the next slice needs different knowledge, produces a different checkable outcome, or builds on the working state the previous slice left - with each side standing whole. A different file is not a seam. A different function is not a seam.

**A ticket is one coherent pass of work.** That size has a floor as well as a ceiling: do not cut one pass into several tickets.

**Split a ticket that carries unrelated changes.** Of the sizing mistakes, lumping several unrelated changes into one ticket is the common one and the worse one. You will be writing a ticket for a logging fix, remember the flaky test and the stale README section, and think: *"These are all small, I'll fold them in, one ticket is less overhead."* That is the moment. Split the unrelated changes into their own tickets.

**When you cannot tell whether a ticket is too big or too small, prefer to assume it is too big.**

**When in doubt about where to cut, take the larger slice.**

### One judgment across many sites is one ticket

**Do not split one judgment applied across many files or call sites into one ticket per site.** Write one ticket that touches all of them. The test: **does the next slice change what the builder must know or deliver, or does it re-run the same decision on the next item?** Re-running the same decision is not a seam.

- BAD: "Migrate `api/users.py` to the new error type." "Migrate `api/orders.py` to the new error type." ... (fourteen tickets)
- GOOD: "Every handler under `api/` returns errors as the new error type."

The pull toward the bad version is quiet. Facing fourteen files, you think: *"One ticket per file is cheap, and a tight ticket is clean."* That is the moment. Each of those fourteen tickets asks the builder the same question fourteen times. The grain of the work runs through the decision, not between the files. One ticket.

When the work is the same edit repeated across many sites and fits that shape, record a tool that makes the edit - a codemod - as an option.

### Size is a hypothesis

**Treat a ticket's size as a hypothesis and adjust it during the work.** Split a ticket that turns out to hold two seams. Merge two tickets that turn out to be one pass. Do not do estimation research up front.

---

## Interrupted sessions: the branch is the notebook

**Write each ticket so that a fresh agent holding only the ticket, its epic, and the repo can continue work that is partly done.**

**Do not create handoff documents, status files, or other session-continuity records.** Partial progress lives in the branch, the diff against the base, and the commit messages. The branch is the notebook; nothing else is.

- BAD: `PROGRESS.md` - "Done: steps 1-3. Next: step 4. Notes for next session: ..."
- BAD: a status line appended to the ticket after each session.

**Do not write protocols that unwind or discard work when a session ends.** Leave the work in the branch.

- BAD: "If you cannot finish, reset the branch to base before stopping."

---

## Epics: a direction, not a route

**Use an epic for work bigger than one pass.** Give it:

- the end state of the whole arc,
- the why,
- the constraints that must hold whichever route the tickets take,
- an epic-level completion signal.

**Do not put the route in an epic.** The route lives in its tickets. The epic is the address for the whole arc; the tickets are where the work gets divided.

**If an epic does not fit in a paragraph plus an ordered list in a plain text file, treat that as a sign** that it is several epics, or a route rather than a direction.

---

## Ordering: a queue, not a wiring diagram

**Order an epic's tickets as a ranked list only, top first.** No blocks, no depends-on, no other links between tickets. When A needs B first, rank B above A. That is the whole mechanism of dependency here: position in the list.

- BAD: `T4 - blocked by T2, T3; depends on T1`
- GOOD: T1 ranked above T2, T2 above T3, T3 above T4.

The failure is a planner's instinct toward rigor: *"T4 really does need T2 - I'll record the dependency so nobody pulls it too early."* That is the moment. Planners who add dependency links wire a graph until every ticket waits on another and nothing can be pulled. A queue at a counter always has someone at the front. Rank B above A and stop.

**You may order epics relative to each other** - only when one plainly has to precede another, and only as a coarse whole-epic statement, never as couplings between their tickets.

- GOOD: "Epic: storage migration comes before Epic: multi-region."
- BAD: "Multi-region ticket 3 waits on storage ticket 5."

---

## Keeping the backlog true

**Decide structure early** - how work splits and what ranks above what.

**Write a ticket's detail when it is near the top of the backlog** - the specific context and the exact end-state wording. A ticket deep in the backlog gets a clear end state and little else.

**Groom the backlog against what the work has taught:**

- re-rank as priorities shift,
- split tickets that grew a second seam,
- merge tickets that are too small,
- prune tickets the work made pointless,
- record learning as structure - including progress that is now a fact of the repo, recorded as that fact rather than as a counter set up to track it.

**Do not set a grooming cadence or a trigger.** Groom when the plan has drifted from the work.

---

## Recap - read this when you are deep in a ticket

- Everything works in a plain text file holding a ranked list. A rule that seems to need a field, a link type, or a hook has been misread.
- Each ticket: an end state, one line of why, one checkable completion signal, and only the context the repo cannot supply. Point at code by filename, no finer.
- **An address, not directions.** Two-builders test: if two correct builds could not differ on it, it is end state - state it exactly. If they could, it is mechanism - out, unless the requester fenced it.
- Do not strip a precise output the requester needed. Do not pin an output shape you invented.
- No mechanism under a "suggested" or "non-binding" label. The urge to add the label is the sign.
- The requester's fence stays, in their words, marked as theirs. When you cannot honestly claim you thought of it, keep it.
- The completion signal says what will be observable - never that it was verified, never the scope of verification.
- The deliverable is a changed system. A report about undone work is a photograph of an unbuilt house. A document the system ships, serves, or reads is a real deliverable. A spike changes only the backlog.
- Cut along the grain: split only at seams; one pass per ticket, with a floor as well as a ceiling; split unrelated changes apart; one judgment across many sites is one ticket. Unsure of size, prefer to assume too big; unsure where to cut, take the larger slice. Size is a hypothesis.
- The branch is the notebook: no handoff files, no status records, no unwind-on-exit protocols.
- An epic is a direction - end state, why, route-independent constraints, signal. No route. One that will not fit in a paragraph plus an ordered list is a sign of several epics, or of a route.
- A queue, not a wiring diagram: rank B above A; no links between tickets. Epics may be ordered coarsely, whole-epic only, when one plainly must come first.
- Structure early, detail near the top, groom when the plan drifts from the work - no cadence.
