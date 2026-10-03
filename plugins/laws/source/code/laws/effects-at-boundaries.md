## [LAW:effects-at-boundaries] - keep the fire in the hearth

<!-- rung: S -->
**Separate pure computation from side effects. Effects - I/O, mutation, clocks,
randomness - live at the system's edges; the pure core computes *descriptions* of
actions and hands them outward to be performed.**

Fire in the hearth cooks dinner; fire anywhere else burns the house down. An effect
is the same: performed at a named edge it is the whole point of the program, but one
`fetch` or `now()` or file-write buried in the core makes the entire core untestable
without mocks, unreorderable, uncacheable, and unrepeatable - the impurity doesn't
stay in the function that commits it, it infects every caller transitively.

<!-- rung: M -->
The temptation arrives as: *"it's just one little read, right here where I need
it."* Refuse it. The redirect: take the value as a parameter, or return a description
of the action ("write these bytes to this path") and let the edge execute it. The
core stays a pure function from inputs to decisions; the edges stay a thin layer
where all the danger is gathered in one auditable place.

<!-- rung: S -->
Diagnostic: *could you unit-test this function with no mocks at all?*

<!-- rung: S -->
The "where the world intrudes" face of `[FRAMING:parts-and-seams]`; instance of
`[LAW:types-are-the-program]` - a hidden effect is an input or output the signature lies
about.
