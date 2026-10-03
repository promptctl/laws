## [LAW:single-enforcer] - one checkpoint per rule

<!-- rung: S -->
**Any cross-cutting invariant - auth, validation, timing, serialization - is
enforced at exactly one boundary. If enforcement already exists elsewhere, remove the
duplicate; never add another.**

A border with ten checkpoints run by ten agencies is less secure than a border with
one, because each agency quietly assumes another one checks the passports - and
meanwhile the ten rulebooks drift apart until nobody knows which is law. Duplicate
checks are not belt-and-suspenders; they are ten belts that will eventually disagree
about what holding up pants means.

<!-- rung: M -->
The temptation arrives as: *"one more validation here can't hurt."* It can, and it
will: the duplicate is a second source of truth for the invariant
(`[LAW:one-source-of-truth]` for enforcement logic), it will drift from the canonical
check, and the day they disagree, callers will trust whichever one they happen to
pass through. Refuse it. The redirect: find where the invariant canonically lives; if
this isn't it, delete the local check and route through the boundary that is.

<!-- rung: S -->
Diagnostic: *where is THE place this invariant is enforced - and is this it?*

<!-- rung: S -->
Instance of `[LAW:one-source-of-truth]`, applied to enforcement; the single enforcer is
where the type-level invariant lives when the type system can't carry it.
