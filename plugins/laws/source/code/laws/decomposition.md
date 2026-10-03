## [LAW:decomposition] - carve at the joints

<!-- rung: S -->
**Divide the program along the natural joints of the problem domain, so that each
part has one describable purpose and can be understood - and reused - alone, and
carries the name the domain gives that part.**

A skilled butcher barely needs force: the knife finds the joint and the joint gives.
An unskilled one saws across bone, dulls the blade, and mangles both halves. Problem
domains have joints - places where two concerns genuinely separate - and module
boundaries that fall on them feel effortless forever after, while boundaries that cut
across bone make every future change a sawing motion through the wrong material.

The joints come with names. A cut that lands on a real joint of the domain has a name
an expert already knows - *ledger*, *parser*, *scheduler*, *reconciliation*
(`[LAW:domain-language]`).

<!-- rung: M -->
The temptation arrives as: *"I'll just put it in this file for now - I can move it
later."* Later never comes, and "for now" is how a module becomes "where things go."
Refuse it. The redirect: before adding, state the module's purpose in one sentence.
If the sentence needs an "and," you are holding two modules; cut at the "and" now,
while the cut is one file and not forty callers.

<!-- rung: S -->
Diagnostic: *can you say what this unit is for in one plain sentence with no
conjunction, in words the domain already has?*

<!-- rung: S -->
Primary law of `[FRAMING:parts-and-seams]` - the "how you cut" face. Everything in
the boundary corollaries (`[LAW:locality-or-seam]`, `[LAW:one-way-deps]`,
`[LAW:no-shared-mutable-globals]`) is this law meeting a specific situation.
