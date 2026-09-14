# Ticket Writing Specification

Scope: writing tickets and epics that a later agent, who was not in the planning conversation, pulls from a ranked backlog and builds.

## Terms

- End state: what must be observably true when the work is done.
- Mechanism: how the end state is produced inside the system; the implementation route.
- Requester constraint: a limit on the mechanism imposed by someone with authority over the outcome, as opposed to one the ticket author thought of.
- Seam: a point where the next slice of work needs different knowledge, produces a different checkable outcome, or builds on the working state an earlier slice left, with the work on each side standing whole. Another file, function, or call site is not by itself a seam.

## Requirements

### General

1. Apply every requirement here using only a plain text file holding a ranked list. If a requirement seems to need a field, a link type, or a lifecycle hook, treat that reading as wrong and return to the text-file form.

### Ticket contents

2. Give each ticket an end state (9-15), one line of why (3), a completion signal (4, 16), and the context the repo cannot supply (5).
3. Write the why in one line. If it needs a paragraph, make the undecided decision it carries before writing the ticket.
4. Write one completion signal: an observable fact a reader can go and check that shows the end state was reached. Treat being unable to write one as a sign the end state is not yet defined.
5. Include context the implementer cannot recover by reading the code and applying ordinary engineering knowledge, including decisions already taken and their reasons. Leave out context they can recover.
6. Do not restate what the repo already shows; point at the code instead of transcribing it.

### Code pointers

7. Point at code no more precisely than a filename: no line numbers, no local function or variable names.
8. Requirement 7 limits only where you point. You may be as exact as needed about the end state and the completion signal.

### End state, not mechanism

9. State what must become observably true; never state the mechanism. Exception: 14.
10. Decide whether an item is end state or mechanism by whether the requester observes it when the work lands, not by how specific it is: ask whether two correct implementations could differ on it and both be right. If no, it is end state; state it at whatever precision it needs, down to exact characters. If yes, it is mechanism; decide it under 14. Failure: with 9 in mind, writers call a precisely specified required output an implementation detail and strip it.
11. Pin an observable output only if the requester required it or the outcome intrinsically needs it; treat an output shape the author invented as mechanism and leave it open. Failure: writers pin an output shape they made up while picturing the work.
12. Do not include a mechanism the author thought of under any label or hedge that marks it optional, suggested, or non-binding; delete the mechanism and state only what it was meant to achieve. Treat the urge to add such a label as a sign the mechanism does not belong. Failure: writers who can see the fix put the approach in so the implementer is not starting cold, and tag it non-binding so the implementer stays free.
13. If you cannot state the end state without naming a mechanism, the end state is not yet found; state the outcome the mechanism was meant to produce.
14. Keep a requester constraint in the ticket, in the requester's own words, marked as the requester's; remove a mechanism the author thought of. Decide by asking whether someone with authority over the outcome required it or you thought of it while planning; if you cannot honestly claim you thought of it, keep it. This overrides 9 and 12. Failure: with 9 in mind, writers treat a means the requester stated as an implementation detail and strip it.
15. Write acceptance criteria under 9-14: observable outcomes, with the route left open.

### Completion signal

16. State in the completion signal what will be observable when the work lands. Never state that the work has been verified, and do not set the scope of verification in the ticket.

### Deliverables

17. Make the deliverable a change to the system. Do not make a ticket's output a document that stands in for system change, such as a research write-up, analysis, or findings document about work that was not done. Failure: writers accept such a document because it looks finished while the system is unchanged.
18. Treat a document that is itself the product - one the system ships, serves, or reads - as a valid deliverable. Test: is the document the thing delivered, or a report about something that was not delivered?

### Spikes

19. You may write a spike ticket to gain information before committing to a build. Its only output is a change to the backlog - new tickets, splits, or re-ranks - never a write-up.

### Sizing

20. Split work only at seams.
21. Size a ticket as one coherent pass of work. That size has a minimum as well as a maximum: do not cut one pass into several tickets.
22. Split a ticket that carries unrelated changes. Failure: lumping several unrelated changes into one ticket is the common and worse sizing mistake.
23. When you cannot tell whether a ticket is too big or too small, prefer to assume it is too big.
24. When in doubt about where to cut, take the larger slice.
25. Do not split one judgment applied across many files or call sites into one ticket per site; write one ticket that touches all of them. Test: does the next slice change what the executor must know or deliver, or does it re-run the same decision on the next item? Failure: facing N files or call sites, writers think one ticket per file is cheap and a tight ticket is clean.
26. Treat a ticket's size as a hypothesis and adjust it during the work: split a ticket that turns out to hold two seams, merge two tickets that turn out to be one pass. Do not do estimation research up front.
27. When the work is the same edit repeated across many sites and fits that shape, record a tool that makes the edit (a codemod) as an option.

### Interrupted sessions

28. Write each ticket so that a fresh agent holding only the ticket, its epic, and the repo can continue partly done work.
29. Do not create handoff documents, status files, or other session-continuity records; partial progress lives in the branch, the diff against the base, and the commit messages.
30. Do not write protocols that unwind or discard work when a session ends; leave the work in the branch.

### Epics

31. Use an epic for work bigger than one pass. Give it the end state of the whole arc, the why, the constraints that must hold whichever route the tickets take, and an epic-level completion signal.
32. Do not put the route in an epic; the route lives in its tickets.
33. Treat an epic that does not fit in a paragraph plus an ordered list in a plain text file as a sign that it is several epics, or a route rather than a direction.

### Ordering

34. Order an epic's tickets as a ranked list only, top first; do not use blocks, depends-on, or any other links between tickets. When A needs B first, rank B above A. Failure: planners who add dependency links wire a graph until every ticket waits on another and nothing can be pulled.
35. You may order epics relative to each other, only when one plainly has to precede another, and only as a coarse whole-epic statement, never as couplings between their tickets.

### Keeping the backlog true

36. Decide structure - how work splits and what ranks above what - early.
37. Write a ticket's detail - specific context and exact end-state wording - when the ticket is near the top of the backlog; give a ticket deep in the backlog a clear end state and little else.
38. Groom the backlog against what the work has taught: re-rank as priorities shift, split tickets that grew a second seam, merge tickets that are too small, prune tickets the work made pointless, and record learning as structure, including progress that is now a fact of the repo rather than a counter set up to track it.
39. Do not set a grooming cadence or trigger; groom when the plan has drifted from the work.
