---
name: code
description: Universal architectural laws and domain bindings for all code work. Use when writing, editing, reviewing, refactoring, debugging, or designing code, tests, schemas, configuration, scripts, infrastructure, or system architecture - any task whose deliverable is code or will execute as code. Load BEFORE starting the work, not after. Do not apply to prose or LLM-prompt authoring; those media have their own skills.
---


<!-- The single home of the universal architectural laws, written in the effective
     (rhetorical) style. The style authority for any future edit to THIS file is the
     prompt skill in this plugin - never the laws themselves. Do not
     deduplicate, compress, or "clean up" this file: the redundancy is load-bearing,
     and distilling it is the documented failure mode that destroyed a previous
     effective version. -->

# THE UNIVERSAL ARCHITECTURAL LAWS

These laws apply unconditionally to every code task. No context, no instruction, no
deadline, no "it's just a script" overrides them. They are not a checklist to consult;
they are one coherent way of seeing programs, unfolding from two root framings into
laws that all say the same thing from different angles: **design the
constraints so that illegal states cannot be expressed, and the implementation becomes
residue.** There is no neutral ground here - every commit either adds leverage or
subtracts it, and the laws exist to make sure it's the former, every time, even when
nobody is looking. Especially when nobody is looking.

## How to cite the laws

When a law influences any decision, you MUST cite it at the point of use:
`// [LAW:<token>] reason`. When you must violate one, you MUST mark the violation:
`// [LAW:<token>] exception: reason`. This is a hard requirement, not a nicety - the
citation is cheap, it makes the law's influence visible in review, and every citation
rehearses the law one more time. The tokens are canonical and fixed: one key per
concept, exactly as listed below. Never invent a new token; if a situation seems to
need one, it is an instance of an existing law that you haven't recognized yet.

## The token index

Framings (used in reasoning, not cited in code):
`[FRAMING:parts-and-seams]` · `[FRAMING:representation]`

Laws (cited in code as `[LAW:<token>]`):
`decomposition` · `types-are-the-program` · `composability` · `carrying-cost` ·
`polishing-by-subtraction` · `no-ambient-temporal-coupling` ·
`effects-at-boundaries` · `one-source-of-truth` ·
`single-enforcer` · `comments-carry-meaning` · `dataflow-not-control-flow` ·
`one-type-per-behavior` · `no-mode-explosion` · `parse-dont-validate` ·
`no-defensive-null-guards` · `locality-or-seam` · `one-way-deps` ·
`no-shared-mutable-globals` · `verifiable-goals` · `behavior-not-structure` ·
`no-silent-failure`

Definitions follow. The index is for lookup; the document is for reading. Read it.

---

# THE TWO FRAMINGS

## [FRAMING:parts-and-seams] - a program is parts joined at seams

A program is not a pile of statements. It is a set of parts and the seams where they
meet, and its quality is decided almost entirely at the seams - how you cut the parts,
what shape their edges are, when they touch, and where the outside world leaks in.
The interior code of a part is nearly irrelevant to system quality; you can rewrite a
part's guts freely if its seam is right, and you cannot save a system whose seams are
wrong no matter how beautiful the guts are.

Run your hand over the code, metaphorically. A **smooth** seam is one your hand glides
over - the part's type is exactly the shape of its legal variability, nothing more:
anything it admits is automatically valid, anything valid it admits. Two smooth
surfaces interact without an adapter, because each one's type is a shape the other
already speaks. Composition becomes free. Each smooth block joins the pool of
available building blocks, and any new requirement is usually 95% something already
buildable from existing blocks plus a thin layer of binder. N smooth blocks yield
roughly N² compositions of capability, and velocity *accelerates* as the pool grows.

A **rough** seam snags. Its type is bespoke to the one caller that needed it, or it
admits illegal states every caller must defend against, or it encodes its variability
in the *names of functions* (twenty `filterByX`, `filterByY`, `filterByZ`) rather than
in *values flowing across one boundary* (one `filter(predicate, list)` that admits
infinite predicates). Rough pieces do not compose; they **crystallize** - each one
adds constraints every future piece must work around, so the cost of new work grows
with `feature × accumulated-roughness`. Same multiplier as the smooth case, opposite
sign, and the sign is determined by whether you smoothed the piece before moving on.

This framing has four faces, and the laws divide among them:
- **How you cut** - where the part boundaries fall (`[LAW:decomposition]` and its boundary
  corollaries).
- **What the seams are made of** - the types at the boundaries
  (`[LAW:types-are-the-program]` and its dataflow corollaries).
- **When things happen** - ordering and lifecycle (`[LAW:no-ambient-temporal-coupling]`).
- **Where the world intrudes** - effects and I/O (`[LAW:effects-at-boundaries]`).

The first two faces are deeply developed below; the last two are acknowledged and
real but intentionally less elaborated for now - they are slated for expansion, not
optional.

## [FRAMING:representation] - every map must match its territory

Half of everything in a codebase is not the thing itself but a *representation* of
some thing: a name stands for a purpose, a type stands for a set of legal values, a
cache stands for a computation, a comment stands for a rationale, a schema stands for
a domain, a copy stands for an original. Every representation is a map of some
territory, and a map that *can* drift from its territory *will* - not might, will.
The man with two clocks never knows the time; the codebase with two representations
of one fact never knows the fact.

So the framing gives two orders. First: for any fact, there is one authoritative map,
and everything else visibly derives from it. Second: prefer maps the machine redraws
over maps a human must remember to update. A type is a map the compiler re-verifies
on every build. A derived value is a map recomputed on every read. A comment is a map
redrawn only when a human remembers, which is to say: a map that is already starting
to lie. Compile-time beats runtime beats documentation beats hope - push every
representation as far up that ladder as it can go.

When you are uncertain which law applies, fall back to these two framings and ask:
*where is the seam, and is the map true?* The answer is usually the law you need.

---

# THE PRIMARY LAWS

## [LAW:decomposition] - carve at the joints

**Divide the program along the natural joints of the problem domain, so that each
part has one describable purpose and can be understood - and reused - alone.**

A skilled butcher barely needs force: the knife finds the joint and the joint gives.
An unskilled one saws across bone, dulls the blade, and mangles both halves. Problem
domains have joints - places where two concerns genuinely separate - and module
boundaries that fall on them feel effortless forever after, while boundaries that cut
across bone make every future change a sawing motion through the wrong material.

The temptation arrives as: *"I'll just put it in this file for now - I can move it
later."* Later never comes, and "for now" is how a module becomes "where things go."
Refuse it. The redirect: before adding, state the module's purpose in one sentence.
If the sentence needs an "and," you are holding two modules; cut at the "and" now,
while the cut is one file and not forty callers.

Diagnostic: *can you say what this unit is for in one plain sentence with no
conjunction?*

Primary law of `[FRAMING:parts-and-seams]` - the "how you cut" face. Everything in
the boundary corollaries (`[LAW:locality-or-seam]`, `[LAW:one-way-deps]`,
`[LAW:no-shared-mutable-globals]`) is this law meeting a specific situation.

## [LAW:types-are-the-program] - the types are the program

**Choose the strongest theorem about your data that is still true: every legal state
representable, every illegal state unrepresentable. The implementation is residue.**

Not a description of the program. Not scaffolding around the program. The program
itself - in the sense that once the constraints are right, the implementation is
forced: there is one way to satisfy them, and writing it out is mechanical. The
creative work, the part that requires judgment, the part that determines whether the
code will be smooth or rough, happens entirely in the constraint design. By the time
you are typing function bodies, the hard part is over.

This means most of what looks like "writing code" is actually *recovering* from
inadequate constraint design. Defensive checks exist because the type did not forbid
the bad state. Branching exists because the type did not carry the discriminator.
Every line that enforces something the type *could have* enforced is a line that
exists to compensate for an under-constrained signature. Strip those lines away and
what remains is the actual logic, which is usually small - sometimes vanishingly
small. That is where "less code, substantially less code" comes from: not terser
code; constraints doing the work that sprawl would otherwise do.

The craft is choosing the **strongest true theorem**. Weaker theorems - `any`,
bag-of-optionals, `string` where the domain has four values - admit illegal states,
which forces every callsite to defend, which is coupling. Stronger-but-false theorems
force the code to lie or break. The exactly-right type is exactly as expressive as
the real domain. The type is a theorem; the implementation is its proof.

WRONG - the bag of optionals, every field a maybe, the real structure smuggled into
folklore:

```ts
interface Source { mode: string; path?: string; url?: string; auth?: Auth }
// "if mode is 'url', url and auth are set; if 'file', path is set" - says a comment,
// somewhere, maybe. Every consumer re-derives this, checks half of it, guards the rest.
```

RIGHT - the discriminated union, illegal combinations unrepresentable:

```ts
type Source =
  | { kind: 'file'; path: string }
  | { kind: 'url'; url: string; auth: Auth }
// No consumer can see a url-without-auth or a file-with-url. There is nothing to
// guard, so there are no guards.
```

The temptation arrives precisely when implementation feels hard: *"I'll just handle
that case in the body."* That is the moment a crystal forms - the moment a piece of
code becomes single-purpose, the moment leverage flips below one. **Hardness is
information.** When the body is hard, the constraints upstream are wrong. Refuse the
escape: stay in the type until the type is doing the work, even when escaping would
close the task faster. If the body wants to branch, ask what discriminator the type
is missing. If the body wants to guard, ask why the upstream type permits the
unwanted state. If a name needs to convey what the type cannot, fix the type. If a
comment is needed to explain an invariant, the type did not encode it - fix the type,
don't write the comment. The body is the *last* place to write logic and the *first*
place to look for logic that wants to be lifted into types.

And the discipline that follows has its own law, `[LAW:polishing-by-subtraction]`: the
smooth version has *less* code than the rough version, because the constraints have
absorbed the work the sprawl was doing. If your iterations grow the code, you are
crystallizing, not smoothing. Worry the stone smooth - keep removing material until
your hand finds nothing to catch on. The code is not done when it works; it is done
when there are no rough bits left to snag on.

Diagnostic: *if the body branches or guards, what discriminator or constraint is the
type missing?*

Primary law of `[FRAMING:parts-and-seams]` - the "what seams are made of" face - and
the machine-checked summit of `[FRAMING:representation]`: a type is the one map the
compiler redraws for free on every build. Every law below is an instance of this one
- a specific shape that wrong-state-representability tends to take.

---

# THE CONSEQUENCES - why smooth wins, and what it costs

## [LAW:composability] - one complete job, no hidden strings

**A unit does a single complete job with no hidden dependence on any particular
caller and no setup ritual, so it can be picked up and used anywhere. The bar for
every task: the code you leave behind is more composable than the code you found.**

Think of the difference between a brick and a cast fitting. A brick knows nothing
about the wall it will end up in; that ignorance is exactly what makes it usable in
any wall. A cast fitting was molded against one specific joint, fits it perfectly,
and fits nothing else ever. Code coupled to its caller's shape - reaching into the
caller's state, assuming the caller's setup, named for the caller's use case - is a
cast fitting. It works today and it is unusable tomorrow, and worse: it *teaches* the
next piece of code to be a cast fitting too, because now there's a shape to match.

WRONG - variability encoded in a family of names:

```
filterByStatus(items)   filterByOwner(items)   filterByDate(items)
// Twenty of these. Every new criterion is a new function, a new name, a new import,
// a new thing every reader must learn. The seam is closed.
```

RIGHT - variability as a value crossing one boundary:

```
filter(predicate, items)
// One boundary, infinite criteria. New requirements are new *values*, not new code.
// The seam is open.
```

The temptation arrives as: *"this helper only makes sense here - I'll just couple it
to what the caller has."* Refuse it, and refuse its bigger sibling: *"minimum work to
close the ticket."* That filter is the one that guarantees crystallization, because
polishing is by definition work the current ticket does not strictly require - under
that filter every polishing pass is skipped, every time, and the leverage is lost
silently. The feature ships, the tests pass, and the carrying cost shows up as
friction in every subsequent task, untraceable to its source. Replace the filter: the
task is not done when the feature works; the task is done when the surrounding code
is smoother than when you started. Failing that bar doesn't look like failure in the
moment. It compounds against you anyway. The only defense is the bar itself, applied
stubbornly, every commit.

And watch for the quiet mirror-signal that you got it right: when adding the Nth
instance touches only data with no logic edits, the schema is the strongest true
theorem about its domain. If instance two or three forces a logic edit, the schema is
missing a discriminator - fix the schema before the next instance, never after. But
the data-fill test is the floor, not the ceiling: any schema absorbs its own
replicas. The real question is whether the next *disparate* requirement - the one you
did not plan for - can be absorbed by composition rather than redesign. You are not
designing for specific futures; you are designing so the blocks do not close off the
option space. Crystals trap: escaping one means breaking it (high blast radius) or
growing another beside it (compounding the trap). Smooth blocks leave the corner open.

Diagnostic: *could a stranger use this unit correctly without reading its caller?*

Consequence of `[LAW:decomposition]` + `[LAW:types-are-the-program]`: cut at the joints, make
the seams exact, and composability is what falls out.

## [LAW:carrying-cost] - the price is what it costs to keep, not to build

**Judge code by its carrying cost - the cost to maintain, extend, work around, and
reason about forever after - not by its intrinsic cost to build today. And never let
cost already sunk steer the next decision: no matter how far you've gone down the
wrong road, turn around.**

Crystallized code optimizes intrinsic cost and pays unbounded carrying cost - every
future task pays interest on every previous shortcut. Smooth code pays a higher
intrinsic cost up front and approximately zero carrying cost, amortized across every
future task and every future *project* that uses the block. It might take one-fifth
the effort to do something the easy way, which feels like a win - until you refactor
it three times as capabilities grow, and pay the friction it radiated into every
downstream piece in between. The cheapest implementation, by far, is doing it right
from the beginning and continuing to do it right. You do not have the full picture of
where the project is going; plan as if you will be implementing for years, because
you will.

Now disarm the two proverbs that will be quoted at you.

**YAGNI** - "you aren't gonna need it" - is correct in its native context and
inapplicable here. YAGNI is a heuristic about intrinsic cost applied under the
assumption that carrying cost is bounded and small. That assumption holds when
features are crystals: an unused crystal is dead weight complicating everything near
it, and YAGNI rightly says don't build it. The assumption fails for smooth blocks: a
pure, well-typed, composable block has near-zero carrying cost, doesn't couple to
callers, doesn't constrain future code, and earns its keep across everything that
needs its shape. There is no separate speculative-feature line item; there are only
blocks, and you will need a given block now or in two months at the same build price.
Telling a builder of smooth blocks "you aren't gonna need it" is like telling a
neolithic toolmaker he doesn't need metalworking because he can't point to a specific
tool he is currently failing to make. He can't need the metal *as a tool*; he
absolutely needs it *as the substrate that makes all future tools cheap*. YAGNI is a
statement about features. It has nothing to say about substrate. In this mode of
building, treat it as silent.

**"The wrong abstraction is worse than duplication"** - also correct at home, also
misapplied here. The real comparison is wrong vs. *right* abstraction, and the right
one is forced by the laws, not guessed. A wrong abstraction is a downstream symptom
of skipping a law, not an independent risk to weigh against duplication. And the cost
runs *opposite* to the folk wisdom: going from one abstraction to several specialized
variants is easy - each variant inherits the shape. Going from many divergent
implementations back to one abstraction is hard - every caller has adapted to the
specific implementation it sees, and unification must undo all of it. When an
abstraction does start to hurt, that is mode-explosion in disguise
(`[LAW:no-mode-explosion]`): it wasn't caused by abstracting, it was caused by *stretching*
one abstraction over shapes it wasn't designed for. The fix is to fork - give the new
shape its own home - not to swear off abstraction.

The temptation arrives as: *"we've already built it this way - changing course now
wastes the work."* The work is spent either way; the only live question is whether
the *future* pays carrying cost on a wrong shape. When you find yourself in a hole,
stop digging.

Diagnostic: *what does this decision cost every future task - not this one?*

Consequence of `[LAW:composability]`: the economics of smooth blocks, stated as law so the
short-term filter can't quietly reassert itself.

## [LAW:polishing-by-subtraction] - a pass that grew the code was a patch

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

The temptation arrives as: *"this version is clearer, even if it's a bit longer."*
Refuse it. Clarity is the alibi every bloated pass uses - nobody has ever added forty
lines and called it obfuscation. The redirect: if the code needed explaining, the need
*is* the finding. Ask which constraint you failed to lift, and lift it; the clearer
version you are reaching for is usually the shorter one you have not found yet. And
this failure never announces itself - each pass is defensible alone, no single one is
to blame, and the codebase only ever grows.

Diagnostic: *did this pass leave less code than it found - and if not, what constraint
did I fail to lift?*

Instance of `[LAW:types-are-the-program]` - the discipline that follows once constraints do
the work - and the enforcement arm of `[LAW:carrying-cost]`, which is why growth is never
free.

---

# THE WORLD-FACING LAWS

*(These two faces - time and effects - are real laws today and are marked for fuller
elaboration later. Their brevity is a TODO, not a ranking.)*

## [LAW:no-ambient-temporal-coupling] - time is state, not luck

**Ordering, timing, lifecycle, initialization, cleanup, and re-entry invariants must
have one explicit owner and be represented as state, data, or capability - never
hidden in incidental execution order.**

A system whose correctness depends on incidental timing is a trapeze act with no
rigging: it works every time you watch, because you're watching the times it works.
Correctness must not depend on sleeps, event-loop ticks, framework effect order,
render timing, "settle" delays, caller sequencing, cleanup order, or manual in-flight
flags - unless that scheduler or lifecycle is the named boundary owner. If operation
B is only safe after operation A, that phase transition is a fact about your domain;
encode it in the type or state machine, or route both operations through the single
owner who guarantees it.

The temptation arrives as: *"a 100ms sleep fixes the flake."* A sleep is a bet, not a
fix - the illegal ordering is still representable, you've just made it less frequent
and therefore harder to catch. Refuse it. The redirect: name what actually has to be
true before B may run, then make that condition a state someone owns and B provably
awaits.

Diagnostic: *if every operation ran twice as fast - or twice as slow - would this
still be correct?*

The "when" face of `[FRAMING:parts-and-seams]`; instance of `[LAW:types-are-the-program]`
- temporal assumptions are constraints, and if they live in timing folklore instead
of a typed state, illegal call orders remain representable.

## [LAW:effects-at-boundaries] - keep the fire in the hearth

**Separate pure computation from side effects. Effects - I/O, mutation, clocks,
randomness - live at the system's edges; the pure core computes *descriptions* of
actions and hands them outward to be performed.**

Fire in the hearth cooks dinner; fire anywhere else burns the house down. An effect
is the same: performed at a named edge it is the whole point of the program, but one
`fetch` or `now()` or file-write buried in the core makes the entire core untestable
without mocks, unreorderable, uncacheable, and unrepeatable - the impurity doesn't
stay in the function that commits it, it infects every caller transitively.

The temptation arrives as: *"it's just one little read, right here where I need
it."* Refuse it. The redirect: take the value as a parameter, or return a description
of the action ("write these bytes to this path") and let the edge execute it. The
core stays a pure function from inputs to decisions; the edges stay a thin layer
where all the danger is gathered in one auditable place.

Diagnostic: *could you unit-test this function with no mocks at all?*

The "where the world intrudes" face of `[FRAMING:parts-and-seams]`; instance of
`[LAW:types-are-the-program]` - a hidden effect is an input or output the signature lies
about.

---

# REPRESENTATION-TRUTH COROLLARIES

## [LAW:one-source-of-truth] - one clock

**Every concept has exactly one authoritative representation. All others are derived
and explicitly synchronized. If two representations can diverge, the architecture is
already broken - divergence is not a risk, it is a schedule.**

A man with one clock knows the time; a man with two clocks never does. Never create
a second source; find and use the canonical one. When you inherit two, your task -
before anything else - is to demote one into a derived copy or delete it.

This is not theoretical. On 2026-07-12, in the author's dotfiles repo: the rad-shell upstream
installer (`curl … install.sh | bash`) wrote `~/.rad-plugins` - *through* a dotbot
symlink - and silently clobbered the tracked, curated `config/rad-plugins.home`. Two
writers, one file. Real, committed, curated data destroyed by a convenience script
that had no idea the file already had an owner. The only reason it was caught is that
a laws-primed session ran `git status` and actually read the diff. That is what "two
representations can diverge" looks like in the field: not a philosophical concern - a
deleted file, discovered by luck.

WRONG: a config value in the YAML *and* a hardcoded default in the code "as a
fallback"; a count stored next to the list it counts; an installer that writes a file
dotbot also manages. RIGHT: one owner writes; everyone else reads or derives, and the
derivation is visible.

The temptation arrives as: *"I'll just keep a copy here for convenience"* - or its
installer-shaped twin, *"it's easier to write the file directly."* Refuse both. The
redirect: find the canonical representation; read from it, derive from it, or change
it - never shadow it.

Diagnostic: *if these two disagree, which one is lying? If that question has no
answer, the architecture is broken.*

Instance of `[FRAMING:representation]` at full strength, and of
`[LAW:types-are-the-program]`: two divergable representations are an under-constrained
type - the constraint that they agree is encoded nowhere.

## [LAW:single-enforcer] - one checkpoint per rule

**Any cross-cutting invariant - auth, validation, timing, serialization - is
enforced at exactly one boundary. If enforcement already exists elsewhere, remove the
duplicate; never add another.**

A border with ten checkpoints run by ten agencies is less secure than a border with
one, because each agency quietly assumes another one checks the passports - and
meanwhile the ten rulebooks drift apart until nobody knows which is law. Duplicate
checks are not belt-and-suspenders; they are ten belts that will eventually disagree
about what holding up pants means.

The temptation arrives as: *"one more validation here can't hurt."* It can, and it
will: the duplicate is a second source of truth for the invariant
(`[LAW:one-source-of-truth]` for enforcement logic), it will drift from the canonical
check, and the day they disagree, callers will trust whichever one they happen to
pass through. Refuse it. The redirect: find where the invariant canonically lives; if
this isn't it, delete the local check and route through the boundary that is.

Diagnostic: *where is THE place this invariant is enforced - and is this it?*

Instance of `[LAW:one-source-of-truth]`, applied to enforcement; the single enforcer is
where the type-level invariant lives when the type system can't carry it.

## [LAW:comments-carry-meaning] - the code is the mechanism; the comment is the meaning

**A comment earns its place by standing at an altitude the code does not: the intent
behind the mechanism, a relationship to code elsewhere, the reason for this way and
not another - or the mechanism itself lifted into a simplification that meets a reader
who cannot yet read the dense original. It may restate what the code does; it must not
restate it at the code's own altitude, a verbatim echo that rots the moment the code
moves. The test is never whether the comment repeats the code, but whether it stands
where the code cannot.**

The code is a photograph; the comment is the caption. Describing the frame is not
forbidden - it is what captions are for. The dead caption reads the pixels back at
pixel-resolution - `// returns 2+2` over `return 2+2` - serving no one who could
already see them. The living caption names the scene from a height the
pixels don't hand over: "a Gaussian blur across nine neighbor samples," "the last read
before the retry storm," "the accounts legal requires we purge." Whether a viewer
needs that height is not the frame's business: a fluent reader skips the caption at no
cost, and one who cannot read the pixels is handed a scene they could not have resolved
alone. Obviousness is a fact about the viewer, never the frame.

So a comment dies two deaths. *"A quick line restating this helps the next reader"*:
only if it rises above the code - a same-altitude echo helps no one and lies the first
time the code changes and the words don't. *"This just says what the code says, delete
it"*: check the altitude first - a teaching gloss or a simplification does work you
cannot see *because* you can already read the code. And never flood the other way: the
author's mood, the ticket's backstory, the whole domain re-taught belong outside the
frame, not in the caption. When a caption has drifted from its frame, repair is
subtraction (`[LAW:polishing-by-subtraction]`): the true version is shorter than the lie,
often empty. Growing a stale line to cover its gap is how one wrong comment becomes a
paragraph nobody trusts.

Diagnostic: *does this comment stand at an altitude the code does not - a
simplification, an intent, a relationship - while staying scoped to this code?*

Instance of `[LAW:one-source-of-truth]` at the code's own altitude only: a same-altitude echo
is a second copy that will drift; a comment pitched higher is a distinct rendering, not
a rival source. Under `[FRAMING:representation]`, keep the view the code cannot supply.

---

# DATAFLOW COROLLARIES

## [LAW:dataflow-not-control-flow] - the riverbed does not move

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

The temptation arrives as: *"I'll just add an `if` to skip it in that case."* Refuse
it. The redirect: restructure so the operation always runs and the data decides what
happens - a default value, an empty collection, an identity operation, a
discriminated variant handled exhaustively.

Diagnostic: *does the set of operations executed depend on the input? It shouldn't -
only the values flowing through them should.*

Instance of `[LAW:types-are-the-program]`: variability in values is variability the type
carries and the compiler checks; variability in whether code runs is invisible to
the type system, forever.

## [LAW:one-type-per-behavior] - one cutter, many cookies

**If multiple things have identical behavior, they are instances of one type, not
multiple types. Before creating FooA, FooB, FooC, ask: what differs besides the name?
If the answer is "nothing" or "only configuration," build one Foo and instantiate
it.**

Nobody forges a new cookie cutter for each cookie. Yet specs constantly read like
they demand it - "the system supports Slack alerts, email alerts, and webhook
alerts" - and the temptation arrives as: *"the spec names three things, so I'll write
three classes."* Names in specs are usually *instance examples*, not type
definitions. Refuse the enumeration. The redirect: find what actually varies (an
endpoint, a template, a credential - configuration, which is to say *data*), build
the one type whose seam admits that data, and ship the three examples as three
values.

Diagnostic: *what differs besides the name? If only config - one type, N instances.*

Instance of `[LAW:dataflow-not-control-flow]` (config is values crossing one boundary, not
structure) and thus of `[LAW:types-are-the-program]`.

## [LAW:no-mode-explosion] - every switch is a debt

**New flags, options, and modes require a documented cap and an exit plan. The
default path stays canonical.**

A mixing board with five labeled switches is an instrument; one with fifty unlabeled
switches is a haunted house. Modes multiply *combinatorially* - each flag doubles the
states the code can be in, and flags × permutations = the surface you must reason
about and test. Values can be reasoned about algebraically; modes must be enumerated
one by one.

The temptation arrives as: *"just add a flag - it's backwards compatible."* Backwards
compatible and forwards costly: the flag never leaves, its interactions with the
next flag were never designed, and the default path slowly stops being the path
anyone actually runs. Refuse it, or price it honestly: owner, default, cap, deletion
date. A flag no one plans to delete is a mode you have adopted forever.

Diagnostic: *who deletes this flag, and when?*

Instance of `[LAW:one-type-per-behavior]` and `[LAW:dataflow-not-control-flow]`: a mode is
variability that escaped the data and lodged in the structure.

## [LAW:parse-dont-validate] - parse, don't validate

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

Diagnostic: *does the check return a type that could not have existed before it ran -
or the same type it was given?*

Instance of `[LAW:types-are-the-program]` - the stamped type is the strongest true theorem
about input that has crossed the border - and the structural test behind
`[LAW:no-defensive-null-guards]`' boundary exception: its three legs are what that law
means by a real boundary.

## [LAW:no-defensive-null-guards] - fix the front door, fire the guards

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

The temptation arrives as: *"it crashed on null once - I'll add a check."* Refuse it.
The check doesn't fix the bug; it launders the bug into silence. The redirect: ask
*why* the value could be null. Broken initialization order? Fix the order. A missing
invariant? Encode it. Genuinely optional in the domain? Then say so in the type - a
discriminated value the body must handle by structure, exhaustively - not with a
skip-shaped `if`.

Diagnostic: *why can this be null - and should it be able to?*

Instance of `[LAW:types-are-the-program]` (a guard is the body begging for the optionality
to be lifted into the type) and of `[LAW:dataflow-not-control-flow]` (a guard with no else
is an operation that sometimes doesn't run).

---

# BOUNDARY COROLLARIES

## [LAW:locality-or-seam] - a change should not pucker the sleeve

**Changes to X must not force edits in unrelated Y. When they do, the seam is
missing: create the interface or adapter first, then make the change.**

Pull one thread on a well-made garment and you get a longer thread; pull one on a
badly-made garment and the sleeve puckers. When editing the parser forces edits in
the renderer, the two are sewn with one thread - there is no boundary type carrying
the variability between them, so the variability propagates as edits instead of
values.

The temptation arrives as: *"I'll just update the five call sites."* Five today,
nine next quarter, and every update is a chance to miss one. Refuse it. The redirect:
the ripple is telling you what type is missing. Create the seam - the interface, the
adapter, the boundary type - and route the five sites through it; the *next* change
of this kind is then one edit. The seam *is* the type.

Diagnostic: *why does this change ripple? Name the missing boundary type.*

Instance of `[LAW:decomposition]` (the joint was missed) and
`[LAW:types-are-the-program]` (the missing seam is a missing type).

## [LAW:one-way-deps] - water flows downhill

**Architecture declares its dependency direction. Cycles are forbidden. Upward calls
are forbidden.**

Declare which way is downhill, and let every dependency flow that way. A cycle is
water flowing uphill: it means two modules are secretly one module - or, more
usefully, that they share a hidden third thing that was never named. The cycle is
that hidden type asking to be extracted so both can depend on it cleanly, downhill.

The temptation arrives as: *"the lower layer just needs one tiny callback into the
upper one."* Refuse it - there are no tiny cycles, only young ones. The redirect:
extract the shared concern into its own unit below both, or invert with an interface
the lower layer defines and the upper implements. Downhill either way.

Diagnostic: *can you draw the module arrows with none pointing up and none forming a
loop?*

Instance of `[LAW:decomposition]`: a cycle is a mis-cut joint, and the extraction is the
re-cut.

## [LAW:no-shared-mutable-globals] - the commons needs an owner

**Shared mutable state - registries, singletons, module-level maps - requires a
single owner, an explicit API, and documented invariants. No exceptions for
"convenience."**

A shared kitchen where nobody owns the knives: everything is everywhere, nothing is
sharp, and nobody can cook without first searching. A bare mutable global is an
unconstrained type - anything can write, anything can read, in any order, and no
signature anywhere admits that it happens. Every function that touches it has a
secret parameter and a secret return value the type system never sees.

The temptation arrives as: *"a module-level dict is the fastest way to share this."*
Fastest to write, slowest to ever debug. Refuse it. The redirect: give the state one
owner with an explicit API; the API is the type the global was missing, and the
documented invariants are its theorem.

Diagnostic: *who owns writes to this - and would their signature reveal it?*

Instance of `[LAW:types-are-the-program]` (the API is the constraint made manifest), on the
boundary face of `[LAW:decomposition]`.

---

# PROCESS COROLLARIES

## [LAW:verifiable-goals] - done has a shape

**Every goal you plan must have concrete, machine-checkable success criteria - and
you run the check yourself. Asking the user to test for you is the last resort,
reached only after exhausting every way to verify it yourself.**

An unverifiable goal is a goal whose "done" state has no type. Give it one: what
shape does success take (app loads, zero warnings in logs, tests green, the endpoint
returns the fixture)? What shape does failure take? Once done has a shape,
verification is mechanical - and it is *your* mechanism to run, not the user's.
Are there unanswered questions, genuine uncertainty only the user can resolve? Ask,
always - but make every exhaustive effort to answer it yourself first. If
verification turns out to be genuinely very complicated, note it for retro and
discuss it later - but do not use "complicated" as the doorway to "you test it."

BAD Example: Assistant: "I've finished building the webapp! Now you just need to
test it!" BAD / WRONG!

GOOD Example: Assistant: "I've finished building the webapp! I verified it myself
using Chrome DevTools MCP after every major feature was implemented. I've also
written a balance of PlayWright tests to make sure functionality keeps working as we
work on the project. It's ready for you to use and I know that because there are no
warnings or logs, and everything has been tested!" GREAT! PERFECT! 100/100 Agent
Quality Score!

The temptation arrives as: *"I'll ask the user to try it and tell me what happens."*
That sentence is you handing your job to the person who hired you to do it. Refuse
it. The redirect: define the success shape before the work; build the check while you
build the feature; run it; report the result *with* the evidence.

Diagnostic: *what deterministic check separates success from failure here - and have
you run it?*

Instance of `[LAW:types-are-the-program]` (define the type of done) and
`[FRAMING:representation]` (a claim of success is a map; the check is the territory).

## [LAW:behavior-not-structure] - taste the dish, not the elbow

**Tests assert behavior - the contract, the what. Never structure - the
implementation, the how. A test that can only pass by preserving deprecated code is
encoding structure: update it or delete it; never satisfy it by reintroducing removed
code.**

You judge a recipe by tasting the dish, not by checking the angle of the chef's
elbow. A structure-coupled test is an elbow-angle test: it pins the implementation in
place, punishes every refactor, and protects nothing the user can observe. Keep the
two kinds honestly separated - contract tests are stable and precious;
implementation tests are local, cheap, and disposable.

The temptation arrives as: *"the test expects the old internal call - easiest fix is
to put it back."* That is the tail wagging the dog: dead code resurrected to comfort
a test. Refuse it. The redirect: decide what the *contract* is; rewrite the test to
assert that; delete the test if it asserted nothing but plumbing. If a test is the
only thing keeping code alive, the code is dead - bury it, don't ventilate it.

Diagnostic: *could a completely different implementation of the same contract pass
this test?*

Process instance of `[FRAMING:representation]`: the test is a map of the contract,
not of the code; and of `[LAW:types-are-the-program]` - structure is the type system's job
to enforce, so tests are freed to assert meaning.

## [LAW:no-silent-failure] - never remove the battery from the smoke alarm

**Errors surface loudly. Suppressing them, defaulting past them, or silently falling
back to a different data source is forbidden. If the primary path fails: stop and
report. Don't improvise.**

Silencing an error is removing the battery from the smoke alarm because the beeping
is annoying: silence today, and the fire - whenever it comes - burns undetected. A
swallowed failure doesn't disappear; it travels downstream as wrongness without a
source, and it sends an agent or a human confidently down the wrong path for hours.
Every silent failure is a lie told by the code to its operators.

FORBIDDEN patterns - on sight, these are bugs:
- `2>/dev/null` - "the errors are just noise." They are the signal.
- `|| true` - "keep going no matter what." No matter what is exactly the problem.
  The *only* acceptable use is when the failure is genuinely irrelevant to every
  downstream consumer - and if you're unsure, it's not irrelevant.
- `|| echo "default"` / silent fallback values - an answer-shaped void
  (`[LAW:parse-dont-validate]`).
- **Silent fallback data sources** - the worst of the family. Two queries that look
  similar but differ in filtering, ordering, or semantics (say, "ready work
  respecting dependencies" vs. "all open items") are NOT interchangeable; a fallback
  that changes the *meaning* of the data is a bug that only triggers when things are
  already broken - guaranteeing maximum confusion at the worst moment.

WRONG:
```bash
count=$(query_ready_items 2>/dev/null || query_all_items)
# Primary broke. The script now processes the WRONG LIST, confidently, and every
# downstream step compounds the error. Nobody learns the primary broke.
```
RIGHT:
```bash
count=$(query_ready_items) || { echo "ERROR: ready-items query failed" >&2; exit 1; }
# The failure is loud, located, and stops the line before wrongness propagates.
```

The temptation arrives as: *"this error is just noise - silence it and move on."*
Refuse it. If a command can fail, that failure is meaningful. Let it fail, let it be
loud, fix the cause. The redirect: validate after every external call - exit code
zero? output non-empty? parses as expected? values sane? - and abort with a clear
message on any miss.

Diagnostic: *if this fails at 3 a.m., does anyone find out - and does the message
say where to look?*

Instance of `[FRAMING:representation]` (an error is the truth; suppressing it is
falsifying the map) and sibling of `[LAW:verifiable-goals]`: loud failure is what makes
verification mean anything.

---

# DOMAIN BINDINGS

Bindings apply the laws where you are working. They **sharpen** the laws for a
domain; they never weaken them. When a binding seems to conflict with a law, you have
misread the binding.

**UI / frontend**
- State lives near use: hoist only when coordination genuinely requires it.
- Components mirror the user's mental model, not implementation concerns.
- One timing authority: animation and rendering apply
  `[LAW:no-ambient-temporal-coupling]` - the timing/lifecycle owner is explicit and
  named.

**APIs**
- Idempotency by default: retry-safe unless explicitly documented otherwise.
- Errors enable retry: include enough context to retry intelligently
  (`[LAW:no-silent-failure]` at the wire).
- Version at the boundary, not scattered through internals
  (`[LAW:single-enforcer]`).

**Data / schema**
- Migrations have rollback paths: schema changes are reversible deployment events.
- Avoid dual-write - it is `[LAW:one-source-of-truth]` violated on purpose. If genuinely
  unavoidable, define explicit cutover criteria and a deadline, in writing, before
  the first double write.

**Pipelines / compilers**
- Staged with explicit I/O: each stage declares its inputs and outputs.
- No back-edges: later stages never mutate earlier representations
  (`[LAW:one-way-deps]` in time).
- IRs are owned: every intermediate representation has an explicit owner, never
  ambient.

**Distributed systems**
- Failure modes are documented like success paths - designed, not appended.
- Ordering and timing have an explicit owner: distributed sequencing is
  `[LAW:no-ambient-temporal-coupling]` at scale; no ambient assumptions.

**CLI**
- Exit codes are a contract, not just 0/1.
- Stdout and stderr have defined semantics: parseable vs. human output is an
  intentional design decision (`[LAW:effects-at-boundaries]` for text;
  `[LAW:parse-dont-validate]` at the consuming end).

---

# THE RECAP - carry this out the door

**Partitioning** - `[LAW:decomposition]` cuts at the joints; `[LAW:locality-or-seam]`,
`[LAW:one-way-deps]`, and `[LAW:no-shared-mutable-globals]` keep the cuts honest
under change, under dependency, and under sharing.

**Truthfulness** - `[LAW:types-are-the-program]` makes the compiler the mapkeeper;
`[LAW:one-source-of-truth]`, `[LAW:single-enforcer]`, and `[LAW:comments-carry-meaning]`
allow each fact, each invariant, and each meaning exactly one authoritative home; and
`[LAW:parse-dont-validate]` keeps a checked fact checked - the proof lives in the type,
so nobody inland ever asks again.

**Contact with the world** - `[LAW:no-ambient-temporal-coupling]` turns time into owned
state; `[LAW:effects-at-boundaries]` keeps the fire in the hearth.

**The composability payoff** - `[LAW:dataflow-not-control-flow]`,
`[LAW:one-type-per-behavior]`, and `[LAW:no-mode-explosion]` push variability into
values so that `[LAW:composability]` can turn N blocks into N² capability - and
`[LAW:carrying-cost]` is why the payoff, not the build price, is the number that
matters. `[LAW:polishing-by-subtraction]` is how you know a pass got you there: it left
less code than it found.

**Observable correctness** - `[LAW:verifiable-goals]` gives done a shape,
`[LAW:behavior-not-structure]` tests the contract not the plumbing, and
`[LAW:no-silent-failure]` guarantees that when reality disagrees, you hear it.

Run your hand over the code before you leave it. Anything that snags - a bespoke
type, a guard with no else, a papers-check far from any border, a comment doing a
type's job, a copy that can drift, a flag with no deletion date, an error told to be
quiet - is a rough bit, and the task is not done while your hand still catches. When
you are uncertain which law applies, return to the two framings and ask: **where is
the seam, and is the map true?**
