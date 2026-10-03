## [LAW:behavior-not-structure] - taste the dish, not the elbow

<!-- rung: S -->
**Tests assert behavior - the contract, the what. Never structure - the
implementation, the how. A test that can only pass by preserving deprecated code is
encoding structure: update it or delete it; never satisfy it by reintroducing removed
code.**

You judge a recipe by tasting the dish, not by checking the angle of the chef's
elbow. A structure-coupled test is an elbow-angle test: it pins the implementation in
place, punishes every refactor, and protects nothing the user can observe. Keep the
two kinds honestly separated - contract tests are stable and precious;
implementation tests are local, cheap, and disposable.

<!-- rung: M -->
The temptation arrives as: *"the test expects the old internal call - easiest fix is
to put it back."* That is the tail wagging the dog: dead code resurrected to comfort
a test. Refuse it. The redirect: decide what the *contract* is; rewrite the test to
assert that; delete the test if it asserted nothing but plumbing. If a test is the
only thing keeping code alive, the code is dead - bury it, don't ventilate it.

<!-- rung: S -->
Diagnostic: *could a completely different implementation of the same contract pass
this test?*

<!-- rung: S -->
Process instance of `[FRAMING:representation]`: the test is a map of the contract,
not of the code; and of `[LAW:types-are-the-program]` - structure is the type system's job
to enforce, so tests are freed to assert meaning.
