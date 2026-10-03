## [LAW:polishing-by-subtraction] - a pass that grew the code was a patch

<!-- rung: S -->
**Improving code removes material. A pass that adds - another guard, another helper,
another case, a comment explaining the mess - is patching, not polishing. The smooth
version is *smaller* than the rough one, because the constraints absorbed the work the
sprawl was doing.**

Sculpture is the model, and it is the same stone you already worry smooth: the figure
was always in the block, and the work is removing everything that is not it. There is
no pass where the sculptor adds stone.

This law is unusually checkable, and that is the point of having it. Most laws need
judgment to apply; this one has a number. If iteration two is longer than iteration
one, you did not polish it, whatever the commit message says. Count before you claim.

WRONG - the "cleanup" pass, every addition locally defensible:

```ts
+ if (cfg.retries == null) cfg.retries = 3;   // "safer"
+ function normalizeConfig(cfg) { ... }       // "clearer"
+ // retries defaults to 3 when unset         // "documented"
```

RIGHT - the same pass, done by subtraction:

```ts
- if (cfg.retries == null) cfg.retries = 3;
- // retries defaults to 3 when unset
  type Config = { retries: number }
  // The caller cannot omit it. Nothing to default, nothing to normalize,
  // nothing to explain - the pass ends smaller than it started.
```

Now disarm the proverb that will be quoted at you. **"Explicit is better than
implicit"** is correct where it was coined - against magic, against behavior hidden in
a decorator or an ambient global - and it is not a license to grow. It governs *where a
fact lives*, not how many lines it takes to say. A discriminated union is more explicit
than a chain of guards **and** shorter than it; `retries: number` is more explicit than
a defaulting branch plus a comment describing the default. When explicitness gets cited
to justify the longer version, ask whether the fact actually moved somewhere more
visible or merely got stated more times. Repetition is not explicitness.

<!-- rung: M -->
The temptation arrives as: *"this version is clearer, even if it's a bit longer."*
Refuse it. Clarity is the alibi every bloated pass uses - nobody has ever added forty
lines and called it obfuscation. The redirect: if the code needed explaining, the need
*is* the finding. Ask which constraint you failed to lift, and lift it; the clearer
version you are reaching for is usually the shorter one you have not found yet. And
this failure never announces itself - each pass is defensible alone, no single one is
to blame, and the codebase only ever grows.

<!-- rung: S -->
Diagnostic: *did this pass leave less code than it found - and if not, what constraint
did I fail to lift?*

<!-- rung: S -->
Instance of `[LAW:types-are-the-program]` - the discipline that follows once constraints do
the work - and the enforcement arm of `[LAW:carrying-cost]`, which is why growth is never
free.
