## [LAW:no-ambient-temporal-coupling] - time is state, not luck

<!-- rung: S -->
**Ordering, timing, lifecycle, initialization, cleanup, and re-entry invariants must
have one explicit owner and be represented as state, data, or capability - never
hidden in incidental execution order.**

A system whose correctness depends on incidental timing is a trapeze act with no
rigging: it works every time you watch, because you're watching the times it works.
Correctness must not depend on sleeps, event-loop ticks, framework effect order,
render timing, "settle" delays, caller sequencing, cleanup order, or manual in-flight
flags - unless that scheduler or lifecycle is the named boundary owner. If operation
B is only safe after operation A, that phase transition is a fact about your domain;
encode it in the type or state machine, or route both operations through the single
owner who guarantees it.

<!-- rung: M -->
The temptation arrives as: *"a 100ms sleep fixes the flake."* A sleep is a bet, not a
fix - the illegal ordering is still representable, you've just made it less frequent
and therefore harder to catch. Refuse it. The redirect: name what actually has to be
true before B may run, then make that condition a state someone owns and B provably
awaits.

<!-- rung: S -->
Diagnostic: *if every operation ran twice as fast - or twice as slow - would this
still be correct?*

<!-- rung: S -->
The "when" face of `[FRAMING:parts-and-seams]`; instance of `[LAW:types-are-the-program]`
- temporal assumptions are constraints, and if they live in timing folklore instead
of a typed state, illegal call orders remain representable.
