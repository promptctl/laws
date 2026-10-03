## [LAW:parse-dont-validate] - parse, don't validate

<!-- rung: S -->
**Validation checks a fact and throws the proof away. Parsing checks the fact and
keeps it - in the type. That one-word difference decides whether a question stays
answered or gets asked again in every function it passes through.**

The image to hold is `[LAW:single-enforcer]`'s border checkpoint, followed inland. Raw
input is a traveler; the checkpoint is the one place on the map where papers are
checked. The traveler leaves the checkpoint
with a stamp - a new type that says, to everyone inland, *already checked*. Inland
code reads the stamp from the signature and never asks again. So when you find a
papers-check deep inland - an `if (!x) return ...` in the middle of a function doing
real work - the border has leaked: either the checkpoint doesn't exist, or it exists
but hands back the same unstamped type it received, so nobody downstream can tell
checked from unchecked, and every function posts its own guard just in case.

A validator returns the same type it was given - `validate(input): boolean` - and the
knowledge that the check passed lives nowhere; the next function down cannot tell
checked input from unchecked. So it checks again. A parser returns a *different* type
than it was given - `parse(input: unknown): Author` - and the output type IS the
proof. Downstream signatures demand `Author`, so unvalidated data cannot even reach
them; the check cannot be repeated, because inland there is nothing left to check.
`[LAW:single-enforcer]` by construction, not by discipline.

Three legs make a real boundary - visible in the shape of the code, not asserted about
it:

1. **A dedicated unit.** Validation is a job, and a job gets its own unit -
   `[LAW:decomposition]` applied to validation. The crossing is that unit's entire reason to
   exist. It is not the first line of a function whose job is something else.
2. **A proving output type.** The unit returns a type that could not have existed
   before the check. Everything downstream requires that type in its signature, which
   makes re-checking structurally impossible, not merely unnecessary.
3. **A loud or explicitly-typed failure arm.** When the check fails, the caller finds
   out: an error, or a typed absence (`Result`, `Option`, a distinct variant) the
   caller must consciously unwrap. Never the success-shaped empty value.

Missing a leg? Then it is not a boundary check. It is a defensive guard wearing the
exception as a costume.

**The answer-shaped void.** `if (!authorLogin) return [];` - that empty array is an
answer-shaped void: it has the exact shape of a real answer ("there are zero
pushbacks") while meaning something else entirely ("I could not do my job"). Two
different facts collapsed into one value the caller can never pull apart again. A
success-shaped early return does not handle the bad input; it launders it into
plausible output and forwards the confusion downstream, where it surfaces weeks later
as a report quietly missing rows - and nothing points back here. Absence is
information; a boundary that maps absence onto the same value as emptiness destroys
information at the exact moment its job was to establish it.

**The real price of the one-line guard.** The inline guard bills itself as one line.
Count what it actually costs: one more exit path through a function already carrying
its real logic - an undeclared mode threaded through the return value,
`[LAW:no-mode-explosion]` at function scale; a return value with two meanings (invalid
input vs. genuinely empty), forever; an obligation on every reader at every call site
to trace which caller states can reach the guard; and the forfeiture of the type fix
that would have deleted the question everywhere at once.

<!-- rung: M -->
You will be deep in a function, the parameter will be optional, and you will hear
yourself compose: *"This is a real precondition at the trust boundary, not a
defensive skip."* Stop at that sentence - it is the tell, not the license. It is prose
certifying what only code shape can certify, and a citation written over a violation
reads exactly like a citation written over compliance, so the eloquence is evidence
of nothing. If the boundary is real, you can point at its unit and its stamped type.
If you can only argue for it in a comment, you are inland, holding a guard.

The confession heuristic: a guard that needs a multi-line justifying comment is
self-reporting - the comment mass is the carrying cost made visible. A legitimate
boundary check needs no defense, because its position is its defense: the dedicated
unit and the proving type say everything the comment was trying to.

"Be liberal in what you accept" has a home: the outermost edge of the system, facing
input you genuinely do not control. Accept liberally there, at the checkpoint - and
then stamp. Liberality governs what the checkpoint tolerates on the way in, never how
far unstamped data travels inland.

WRONG - the guard, the costume, the void:

```ts
function pairPushbacks(comments, { findingReviewIds = [], authorLogin } = {}) {
  // "A real precondition at the trust boundary, not a defensive skip: ..."
  if (!authorLogin) return [];
  ...
}
```

The bag-of-optionals signature admits the illegal call, so the body compensates for
the under-constrained type (`[LAW:types-are-the-program]`); the comment argues for a
boundary the shape denies; the `[]` is an answer-shaped void.

RIGHT - the checkpoint upstream, the stamp inland:

```ts
// the one unit whose job is the crossing - fails loudly or returns a typed absence
function requireAuthor(pr: RawPr): Author { ... }

function pairPushbacks(comments: Comment[], author: Author, findingReviewIds: ReviewId[]): Pair[] {
  // no guard: Author cannot be absent - the question was deleted, not deferred
  ...
}
```

The signature now refuses the illegal call instead of surviving it. Nothing inland
checks papers, because inland there are no papers left to check - only the stamp.

<!-- rung: S -->
Diagnostic: *does the check return a type that could not have existed before it ran -
or the same type it was given?*

<!-- rung: S -->
Instance of `[LAW:types-are-the-program]` - the stamped type is the strongest true theorem
about input that has crossed the border - and the structural test behind
`[LAW:no-defensive-null-guards]`' boundary exception: its three legs are what that law
means by a real boundary.
