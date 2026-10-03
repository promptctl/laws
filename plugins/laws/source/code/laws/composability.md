## [LAW:composability] - one complete job, no hidden strings

<!-- rung: S -->
**A unit does a single complete job with no hidden dependence on any particular
caller and no setup ritual, so it can be picked up and used anywhere. The bar for
every task: the code you leave behind is more composable than the code you found.**

Think of the difference between a brick and a cast fitting. A brick knows nothing
about the wall it will end up in; that ignorance is exactly what makes it usable in
any wall. A cast fitting was molded against one specific joint, fits it perfectly,
and fits nothing else ever. Code coupled to its caller's shape - reaching into the
caller's state, assuming the caller's setup, named for the caller's use case - is a
cast fitting. It works today and it is unusable tomorrow, and worse: it *teaches* the
next piece of code to be a cast fitting too, because now there's a shape to match.

WRONG - variability encoded in a family of names:

```
filterByStatus(items)   filterByOwner(items)   filterByDate(items)
// Twenty of these. Every new criterion is a new function, a new name, a new import,
// a new thing every reader must learn. The seam is closed.
```

RIGHT - variability as a value crossing one boundary:

```
filter(predicate, items)
// One boundary, infinite criteria. New requirements are new *values*, not new code.
// The seam is open.
```

<!-- rung: M -->
The temptation arrives as: *"this helper only makes sense here - I'll just couple it
to what the caller has."* Refuse it, and refuse its bigger sibling: *"minimum work to
close the ticket."* That filter is the one that guarantees crystallization, because
polishing is by definition work the current ticket does not strictly require - under
that filter every polishing pass is skipped, every time, and the leverage is lost
silently. The feature ships, the tests pass, and the carrying cost shows up as
friction in every subsequent task, untraceable to its source. Replace the filter: the
task is not done when the feature works; the task is done when the surrounding code
is smoother than when you started. Failing that bar doesn't look like failure in the
moment. It compounds against you anyway. The only defense is the bar itself, applied
stubbornly, every commit.

And watch for the quiet mirror-signal that you got it right: when adding the Nth
instance touches only data with no logic edits, the schema is the strongest true
theorem about its domain. If instance two or three forces a logic edit, the schema is
missing a discriminator - fix the schema before the next instance, never after. But
the data-fill test is the floor, not the ceiling: any schema absorbs its own
replicas. The real question is whether the next *disparate* requirement - the one you
did not plan for - can be absorbed by composition rather than redesign. You are not
designing for specific futures; you are designing so the blocks do not close off the
option space. Crystals trap: escaping one means breaking it (high blast radius) or
growing another beside it (compounding the trap). Smooth blocks leave the corner open.

<!-- rung: S -->
Diagnostic: *could a stranger use this unit correctly without reading its caller?*

<!-- rung: S -->
Consequence of `[LAW:decomposition]` + `[LAW:types-are-the-program]`: cut at the joints, make
the seams exact, and composability is what falls out.
