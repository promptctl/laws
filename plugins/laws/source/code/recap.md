# THE RECAP - carry this out the door

**Partitioning** - `[LAW:decomposition]` cuts at the joints; `[LAW:locality-or-seam]`,
`[LAW:one-way-deps]`, and `[LAW:no-shared-mutable-globals]` keep the cuts honest
under change, under dependency, and under sharing.

**Truthfulness** - `[LAW:types-are-the-program]` makes the compiler the mapkeeper;
`[LAW:one-source-of-truth]`, `[LAW:single-enforcer]`, and `[LAW:comments-carry-meaning]`
allow each fact, each invariant, and each meaning exactly one authoritative home;
`[LAW:domain-language]` gives each concept the name the world already uses, so code,
docs, and comments speak one tongue; and `[LAW:parse-dont-validate]` keeps a checked
fact checked - the proof lives in the type, so nobody inland ever asks again.

**Contact with the world** - `[LAW:no-ambient-temporal-coupling]` turns time into owned
state; `[LAW:effects-at-boundaries]` keeps the fire in the hearth.

**The composability payoff** - `[LAW:dataflow-not-control-flow]`,
`[LAW:one-type-per-behavior]`, and `[LAW:no-mode-explosion]` push variability into
values so that `[LAW:composability]` can turn N blocks into N² capability - and
`[LAW:carrying-cost]` is why the payoff, not the build price, is the number that
matters. `[LAW:polishing-by-subtraction]` is how you know a pass got you there: it left
less code than it found. `[LAW:escape-local-minima]` is what you do when the cheap
on-pattern choice is the one you are reaching for: the work pauses and the escape
becomes the work.

**Observable correctness** - `[LAW:verifiable-goals]` gives done a shape,
`[LAW:behavior-not-structure]` tests the contract not the plumbing,
`[LAW:no-silent-failure]` guarantees that when reality disagrees, you hear it - and
`[LAW:nothing-unseen]` guarantees there is a panel to hear it on, reading zero when
it is zero and dead when it is dead, built before the cloud.

Run your hand over the code before you leave it. Anything that snags - a bespoke
type, a guard with no else, a papers-check far from any border, a comment doing a
type's job, a copy that can drift, a coined name for a thing the domain already named,
a flag with no deletion date, an error told to be quiet, a job whose "did nothing" and
"never ran" look alike, an "until we have X" in a comment or commit - is a rough bit,
and the task is not done while your hand still catches. When
you are uncertain which law applies, return to the two framings and ask: **where is
the seam, and is the map true?**
