## [LAW:carrying-cost] - the price is what it costs to keep, not to build

<!-- rung: S -->
**Judge code by its carrying cost - the cost to maintain, extend, work around, and
reason about forever after - not by its intrinsic cost to build today. And never let
cost already sunk steer the next decision: no matter how far you've gone down the
wrong road, turn around.**

Crystallized code optimizes intrinsic cost and pays unbounded carrying cost - every
future task pays interest on every previous shortcut. Smooth code pays a higher
intrinsic cost up front and approximately zero carrying cost, amortized across every
future task and every future *project* that uses the block. It might take one-fifth
the effort to do something the easy way, which feels like a win - until you refactor
it three times as capabilities grow, and pay the friction it radiated into every
downstream piece in between. The cheapest implementation, by far, is doing it right
from the beginning and continuing to do it right. You do not have the full picture of
where the project is going; plan as if you will be implementing for years, because
you will.

Now disarm the two proverbs that will be quoted at you.

**YAGNI** - "you aren't gonna need it" - is correct in its native context and
inapplicable here. YAGNI is a heuristic about intrinsic cost applied under the
assumption that carrying cost is bounded and small. That assumption holds when
features are crystals: an unused crystal is dead weight complicating everything near
it, and YAGNI rightly says don't build it. The assumption fails for smooth blocks: a
pure, well-typed, composable block has near-zero carrying cost, doesn't couple to
callers, doesn't constrain future code, and earns its keep across everything that
needs its shape. There is no separate speculative-feature line item; there are only
blocks, and you will need a given block now or in two months at the same build price.
Telling a builder of smooth blocks "you aren't gonna need it" is like telling a
neolithic toolmaker he doesn't need metalworking because he can't point to a specific
tool he is currently failing to make. He can't need the metal *as a tool*; he
absolutely needs it *as the substrate that makes all future tools cheap*. YAGNI is a
statement about features. It has nothing to say about substrate. In this mode of
building, treat it as silent.

**"The wrong abstraction is worse than duplication"** - also correct at home, also
misapplied here. The real comparison is wrong vs. *right* abstraction, and the right
one is forced by the laws, not guessed. A wrong abstraction is a downstream symptom
of skipping a law, not an independent risk to weigh against duplication. And the cost
runs *opposite* to the folk wisdom: going from one abstraction to several specialized
variants is easy - each variant inherits the shape. Going from many divergent
implementations back to one abstraction is hard - every caller has adapted to the
specific implementation it sees, and unification must undo all of it. When an
abstraction does start to hurt, that is mode-explosion in disguise
(`[LAW:no-mode-explosion]`): it wasn't caused by abstracting, it was caused by *stretching*
one abstraction over shapes it wasn't designed for. The fix is to fork - give the new
shape its own home - not to swear off abstraction.

<!-- rung: M -->
The temptation arrives as: *"we've already built it this way - changing course now
wastes the work."* The work is spent either way; the only live question is whether
the *future* pays carrying cost on a wrong shape. When you find yourself in a hole,
stop digging.

<!-- rung: S -->
Diagnostic: *what does this decision cost every future task - not this one?*

<!-- rung: S -->
Consequence of `[LAW:composability]`: the economics of smooth blocks, stated as law so the
short-term filter can't quietly reassert itself.
