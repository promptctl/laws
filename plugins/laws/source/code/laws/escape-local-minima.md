## [LAW:escape-local-minima] - if you are not part of the solution, you are part of the problem

<!-- rung: S -->
**Every law can be satisfied more than one way. When the cheapest way is defended as
"doesn't make anything worse, until we have X", you are choosing a local minimum - and
the moment you recognize that, the current work pauses and escaping the minimum
becomes the work. A cheap fix that needs no such defense is just a fix.**

A local minimum is a shape the code settles into where every step out costs more than
staying, so no single change ever justifies leaving - and the code stays there forever.
It is reached one reasonable choice at a time: each one cheap, each one on-pattern, each
one making nothing strictly worse. That is precisely its defense. "Doesn't make anything
worse" was true of every step that got you here, which is why you are here.

Recognize it by its phrasing. The first half sounds like: *"this is cheap, it follows
the existing pattern, it doesn't make anything worse, so it's fine until we have X."*
The second half, if it comes, sounds like: *"when we have X, we'll do Y to fix this
properly."* The first half alone is the pattern; you do not yet know Y, and the
procedure below starts at finding it. Both halves together flip every verdict under
every law against the "doesn't make anything worse" case: you have just named the real
fix and chosen not to do it. Code that only "doesn't make anything worse" is code being carried, and
carrying it is the cost - `[LAW:carrying-cost]` is the price of what you keep, not what
you build.

When you recognize the pattern, the amount of work it implies is not an input. The
procedure is mandatory:

1. **Pause the current work.** Comment the ticket with where it stops and what is in
   play, and groom the backlog so the work is picked up again after the escape lands.
2. **Plan the escape.** If you know what Y is, Y is the work. If you do not, step zero
   is finding Y: file a ticket to investigate and let the session that pulls it spawn
   a minion on a worktree, so the finding consumes neither the session that noticed
   nor the one that plans. The plan is a ticket or an epic,
   ranked to the top, structured so the paused work resumes after it. It ends with a full law realignment across everything
   the escape touches, with no leftovers - that may mean nested epics, and they are
   worked, not filed and forgotten. `[LAW:polishing-by-subtraction]` is slow here and
   that is the pace: the escape subtracts the minimum, it does not patch over it.
3. **Hand off to a fresh session** with the escape as its next work. Each session
   carries its own task and nothing else; trust the process to bring the paused work
   back.

Cite this law where its decision lands: on the paused ticket's comment and on the
escape ticket, and in code only as an exception when the minimum is knowingly kept.
Every ticket filed under it carries the label `escape-local-minima`, the token spelled
as a label: that is how the pattern is found again, counted, and documented wherever
it recurs.

<!-- rung: M -->
The temptation arrives sounding like prudence: *"YAGNI - don't build the big thing on
spec."* YAGNI is about features with real carrying cost. It has nothing to say about
the substrate the laws already require, and it is not a reason to keep carrying a
shape you have already named as wrong.

<!-- rung: S -->
Diagnostic: *have I just said "until we have X" or "when we have X, we'll do Y"?* If
yes, you are describing a local minimum from inside it.

<!-- rung: S -->
Instance of `[LAW:no-mode-explosion]`, `[LAW:one-source-of-truth]`, and
`[LAW:polishing-by-subtraction]`: the local minimum is where one more mode, one more
copy, or one more patch was the cheapest move, every time.
