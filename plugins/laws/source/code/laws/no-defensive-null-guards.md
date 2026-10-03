## [LAW:no-defensive-null-guards] - fix the front door, fire the guards

<!-- rung: S -->
**Null checks are valid only at real boundaries or where a value explicitly
represents optionality. If a value should never be null, the fix is making it
never-null - not adding a guard that silently skips the work.**

A house whose front door doesn't lock does not need a guard posted at every interior
door; it needs the front door fixed. Scattered null guards are the interior guards:
each one is a confession that some upstream type permits a state that should not
exist, and each one *hides* that bug instead of fixing it - because a null guard
without an `else` containing real, necessary behavior is control flow in disguise:
it skips the work silently instead of failing loudly, and the absence travels
downstream to detonate somewhere far from its cause.

The boundary exception is structural, not rhetorical. A boundary is a place you can
point to on the map, never a claim you make in a comment: the three legs of
`[LAW:parse-dont-validate]` - dedicated unit, proving output type, loud or typed
failure arm - are what a boundary *is*. A check with all three legs is not an
exception to this law at all; it is a parser, living where parsers live. What this
law forbids is the inland guard - the absence check inside a function whose job is
something else - and no comment, however persuasive, can move a guard to the border.
If you find yourself writing prose to establish that this one is a boundary, you have
already learned that it isn't: real boundaries are self-evident from shape, and
arguments are what guards wear when they want to pass as boundaries.

WRONG:
```ts
function render(user?: User) {
  if (user) {                    // no else - where does the null GO?
    drawHeader(user.name);
  }
}
// Callers see nothing. The header just silently isn't there. The bug is now
// invisible, unreproducible, and three layers away from its cause.
```

RIGHT:
```ts
function render(user: User) {    // the signature states the precondition
  drawHeader(user.name);
}
// The caller that "might not have a user" is the checkpoint (`[LAW:parse-dont-validate]`)
// - IT resolves the optionality once (fetch, redirect, or explicit EmptyState), and
// everything below breathes typed, guaranteed air.
```

<!-- rung: M -->
The temptation arrives as: *"it crashed on null once - I'll add a check."* Refuse it.
The check doesn't fix the bug; it launders the bug into silence. The redirect: ask
*why* the value could be null. Broken initialization order? Fix the order. A missing
invariant? Encode it. Genuinely optional in the domain? Then say so in the type - a
discriminated value the body must handle by structure, exhaustively - not with a
skip-shaped `if`.

<!-- rung: S -->
Diagnostic: *why can this be null - and should it be able to?*

<!-- rung: S -->
Instance of `[LAW:types-are-the-program]` (a guard is the body begging for the optionality
to be lifted into the type) and of `[LAW:dataflow-not-control-flow]` (a guard with no else
is an operation that sometimes doesn't run).
