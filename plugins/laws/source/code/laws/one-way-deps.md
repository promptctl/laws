## [LAW:one-way-deps] - water flows downhill

<!-- rung: S -->
**Architecture declares its dependency direction. Cycles are forbidden. Upward calls
are forbidden.**

Declare which way is downhill, and let every dependency flow that way. A cycle is
water flowing uphill: it means two modules are secretly one module - or, more
usefully, that they share a hidden third thing that was never named. The cycle is
that hidden type asking to be extracted so both can depend on it cleanly, downhill.

<!-- rung: M -->
The temptation arrives as: *"the lower layer just needs one tiny callback into the
upper one."* Refuse it - there are no tiny cycles, only young ones. The redirect:
extract the shared concern into its own unit below both, or invert with an interface
the lower layer defines and the upper implements. Downhill either way.

<!-- rung: S -->
Diagnostic: *can you draw the module arrows with none pointing up and none forming a
loop?*

<!-- rung: S -->
Instance of `[LAW:decomposition]`: a cycle is a mis-cut joint, and the extraction is the
re-cut.
