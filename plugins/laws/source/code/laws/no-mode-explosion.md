## [LAW:no-mode-explosion] - every switch is a debt

<!-- rung: S -->
**New flags, options, and modes require a documented cap and an exit plan. The
default path stays canonical.**

A mixing board with five labeled switches is an instrument; one with fifty unlabeled
switches is a haunted house. Modes multiply *combinatorially* - each flag doubles the
states the code can be in, and flags × permutations = the surface you must reason
about and test. Values can be reasoned about algebraically; modes must be enumerated
one by one.

<!-- rung: M -->
The temptation arrives as: *"just add a flag - it's backwards compatible."* Backwards
compatible and forwards costly: the flag never leaves, its interactions with the
next flag were never designed, and the default path slowly stops being the path
anyone actually runs. Refuse it, or price it honestly: owner, default, cap, deletion
date. A flag no one plans to delete is a mode you have adopted forever.

<!-- rung: S -->
Diagnostic: *who deletes this flag, and when?*

<!-- rung: S -->
Instance of `[LAW:one-type-per-behavior]` and `[LAW:dataflow-not-control-flow]`: a mode is
variability that escaped the data and lodged in the structure.
