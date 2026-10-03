## [LAW:locality-or-seam] - a change should not pucker the sleeve

<!-- rung: S -->
**Changes to X must not force edits in unrelated Y. When they do, the seam is
missing: create the interface or adapter first, then make the change.**

Pull one thread on a well-made garment and you get a longer thread; pull one on a
badly-made garment and the sleeve puckers. When editing the parser forces edits in
the renderer, the two are sewn with one thread - there is no boundary type carrying
the variability between them, so the variability propagates as edits instead of
values.

<!-- rung: M -->
The temptation arrives as: *"I'll just update the five call sites."* Five today,
nine next quarter, and every update is a chance to miss one. Refuse it. The redirect:
the ripple is telling you what type is missing. Create the seam - the interface, the
adapter, the boundary type - and route the five sites through it; the *next* change
of this kind is then one edit. The seam *is* the type.

<!-- rung: S -->
Diagnostic: *why does this change ripple? Name the missing boundary type.*

<!-- rung: S -->
Instance of `[LAW:decomposition]` (the joint was missed) and
`[LAW:types-are-the-program]` (the missing seam is a missing type).
