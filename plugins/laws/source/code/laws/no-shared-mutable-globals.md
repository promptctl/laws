## [LAW:no-shared-mutable-globals] - the commons needs an owner

<!-- rung: S -->
**Shared mutable state - registries, singletons, module-level maps - requires a
single owner, an explicit API, and documented invariants. No exceptions for
"convenience."**

A shared kitchen where nobody owns the knives: everything is everywhere, nothing is
sharp, and nobody can cook without first searching. A bare mutable global is an
unconstrained type - anything can write, anything can read, in any order, and no
signature anywhere admits that it happens. Every function that touches it has a
secret parameter and a secret return value the type system never sees.

<!-- rung: M -->
The temptation arrives as: *"a module-level dict is the fastest way to share this."*
Fastest to write, slowest to ever debug. Refuse it. The redirect: give the state one
owner with an explicit API; the API is the type the global was missing, and the
documented invariants are its theorem.

<!-- rung: S -->
Diagnostic: *who owns writes to this - and would their signature reveal it?*

<!-- rung: S -->
Instance of `[LAW:types-are-the-program]` (the API is the constraint made manifest), on the
boundary face of `[LAW:decomposition]`.
