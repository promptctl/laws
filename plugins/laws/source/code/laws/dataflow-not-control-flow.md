## [LAW:dataflow-not-control-flow] - the riverbed does not move

<!-- rung: S -->
**Software structure mirrors data flow, not control flow. The same operations execute
in the same order on every invocation; variability lives in the values - nulls, empty
collections, discriminated unions - never in whether operations run. Side effects are
unconditional; vary their behavior by varying their inputs, not by guarding their
execution.**

The river varies every day - volume, speed, sediment - and the riverbed does not.
That is the shape of good software: a fixed bed of operations, with all the day-to-day
difference carried by what flows through. When you reach for an `if` that skips an
operation, you are carving a new channel in the bed itself - encoding variability in
control flow - and every such channel is a permanent, untyped fork every future reader
must hold in their head. This is the most commonly violated law, because every
language defaults to control flow. Fight the default.

There is a tell, and it fires *before* you write the code - listen to your own
design sentence: **if your description of the mechanics contains "if," "and," "when,"
"skip," or "only," it is almost certainly the wrong solution.** (Describing the
*consequences* of a simple mechanism is different; the tell is conditionals in the
*mechanics*.) This applies to nearly everything, save perhaps the last inch of UI
rendering or some deep hairy algorithm - so rare it isn't worth writing the exception.

The battle-tested example, preserved because it happened:

WRONG:
> The real problem: a viewport should behave as its own render target. When you set a
> viewport and clearTarget([r,g,b,a]), the clear should fill that viewport - not the
> whole surface. The viewport IS the target. That means the fix is in the engine:
> when a render pass has a viewport AND uses loadOp: clear, clear only the viewport
> region (via a scissored clear or by drawing a fill quad internally in the engine).
> The DSL fixture shouldn't need to know or care about this - clearTarget within a
> viewport just works.

Why wrong: **WHEN** a render pass has a viewport **AND** uses loadOp clear **ONLY**
the viewport region - conditionals in the mechanics. A single implementation like
this radiates complexity: every other piece of code must know these details and work
around them, and the piece itself becomes nearly impossible to modify or replace.

RIGHT:
> I'm overcomplicating this. Each render pass always has a viewport (default = full
> surface). The scissor rect always matches the viewport. The clear always clears the
> viewport region. Same code path every time - no conditionals on "does this pass
> have a viewport." The implementation: the engine always uses loadOp: Load on the
> GPU attachment, always sets scissor to the viewport, and draws a fill rect with the
> clear color when the pass specifies clear. loadTarget skips the fill rect. The only
> branch is clear vs load - which is the entire point of that enum.

Why right: control flow is smooth and predictable; surrounding code doesn't design
around special cases it doesn't own; the unit is easy to reason about and easy to
replace without impacting others. Notice the shape of the fix: **always** replaced
**when/and/only**, and the one remaining branch is the domain's own enum - the
discriminator the type was supposed to carry all along.

<!-- rung: M -->
The temptation arrives as: *"I'll just add an `if` to skip it in that case."* Refuse
it. The redirect: restructure so the operation always runs and the data decides what
happens - a default value, an empty collection, an identity operation, a
discriminated variant handled exhaustively.

<!-- rung: S -->
Diagnostic: *does the set of operations executed depend on the input? It shouldn't -
only the values flowing through them should.*

<!-- rung: S -->
Instance of `[LAW:types-are-the-program]`: variability in values is variability the type
carries and the compiler checks; variability in whether code runs is invisible to
the type system, forever.
