# Code Architecture Laws

These laws govern every task whose deliverable is code or will execute as code: writing, editing, reviewing, refactoring, debugging, or designing code, tests, schemas, configuration, scripts, infrastructure, or system architecture. They do not govern prose or LLM-prompt authoring; those have their own guidance.

Apply them to every code task, and start before the work begins, not after. Laws picked up at the end of a task only grade the damage; laws held from the start prevent it. No context, instruction, deadline, or "it's just a script" exempts a task.

What is at stake is quiet. A codebase that breaks these laws still compiles, still passes its tests, still ships the feature. The cost comes later, as the guard nobody can delete, the copy that drifted, the flake that a sleep papered over, and it arrives with no name on it. Nobody traces the three-hour debugging session back to the `|| true` that hid the first failure. That is why the laws have to be held while you write, not remembered afterward.

---

## Terms

These four words mean exactly this everywhere below.

- **Strongest true type**: a type that can represent every legal state of the domain and no illegal state.
- **Boundary check**: a check with all three of:
  (a) a dedicated unit whose only job is the check,
  (b) an output type that could not exist before the check and that every downstream signature requires, and
  (c) a failure arm that is either a loud error or a typed absence (`Result`, `Option`, a distinct variant) the caller must explicitly unwrap.
  A check missing any of the three is not a boundary check.
- **Success-shaped empty value**: a value with the shape of a real answer (such as `[]` or a default value) returned to mean "could not do the job".
- **Carrying cost**: the cost to maintain, extend, work around, and reason about code for as long as it exists, as opposed to the cost to build it.

---

## Citing the laws

Each law below carries a token: `[LAW:<token>]`. When a law influences a decision, cite it in a comment at the point of use:

```ts
// [LAW:parse-dont-validate] downstream code takes Email, never string
```

When you violate a law, mark the violation:

```ts
// [LAW:no-shared-mutable-globals] exception: reason
```

The citation is how the law stays awake. Writing the token re-asks the question the law asks, at the moment the code is being shaped.

Use only the `[LAW:<token>]` tokens attached to requirements in this document, spelled exactly. Do not invent a token. A situation that seems to need a new one is an instance of an existing law; find which.

- BAD: `// [LAW:no-magic-numbers]` (not a token in this document)
- BAD: `// [LAW:single-source-of-truth]` (misspelled; the token is `one-source-of-truth`)
- BAD: `// [FRAMING:representation] derive from config`

The `[FRAMING:...]` identifiers are for your reasoning only. Do not cite them in code.

---

## Two framings: seams and representations

Two questions sit underneath every law. When you are unsure which law applies, ask them:

1. **Where is the boundary between parts?** `[FRAMING:parts-and-seams]`
2. **Does each representation match the thing it represents?** `[FRAMING:representation]`

Almost every law below is one of these two questions asked about a particular kind of material: a module, a type, a check, a comment, a flag, a test.

### Representations the machine keeps honest

`[FRAMING:representation]` Prefer representations the machine re-checks or recomputes over ones a human must remember to update, in this order: compile-time, then runtime, then documentation. Move each representation as far up that order as it can go.

A fact in a type is re-checked on every build. A fact in a runtime assertion is re-checked on every run. A fact in a doc is re-checked when someone happens to remember it. The higher the fact lives, the less it depends on memory.

---

## Decomposition `[LAW:decomposition]`

Divide the program along the problem domain's natural separations, so each unit has one purpose describable in one plain sentence with no conjunction, and can be understood and reused alone.

The "and" is the seam. When the sentence describing a module needs "and", the module already has a crack running through it at that word.

Before adding code to a module, state the module's purpose in one sentence. If the sentence needs "and", split the module at the "and" before adding.

- BAD: "`userService` loads users and sends welcome emails." (split it before you add a third thing)
- GOOD: "`userRepository` loads users." / "`welcomeMailer` sends welcome emails."

The moment this law breaks is small. You have a function to put somewhere, the nearest file is open, and you think *"I'll put it here for now and move it later."* That is the moment. Later does not come; the function stays, the next one joins it, and the module's sentence grows another "and". State the sentence first; if it needs "and", split before you add.

---

## Types are the program `[LAW:types-are-the-program]`

Give data its strongest true type.

A type that admits illegal states is a door left open: every function downstream has to post its own guard at it. Lock the door once, in the type, and the guards have nothing to watch.

The failure runs both ways. Do not use weaker types that admit illegal states:

- `any`
- a record of optional fields whose valid combinations live in comments
- `string` for a domain with a fixed set of values

Use a discriminated union instead.

```ts
// BAD: the legal combinations live in a comment
type Payment = {
  status: string;       // "pending" | "paid" | "failed"
  paidAt?: Date;        // set only when paid
  failureReason?: string; // set only when failed
};

// GOOD: illegal combinations cannot be written
type Payment =
  | { status: "pending" }
  | { status: "paid"; paidAt: Date }
  | { status: "failed"; failureReason: string };
```

And do not use types stricter than the domain, which force code to lie or break: a non-optional field for a value the domain genuinely lacks sometimes forces callers to invent a fake one.

### When a body is hard to write, the types are wrong

When a function body is hard to write, fix the upstream types instead of handling the case in the body, even when handling it in the body would finish the task faster. Read the body's difficulty as a report on the types:

- **If the body branches**, add the missing discriminator to the type.
- **If the body guards**, remove the unwanted state from the upstream type.
- **If a name must convey what the type cannot**, fix the type.
- **If an invariant needs a comment to explain it**, encode it in the type and do not write the comment.

You will be three-quarters through a function, the types will allow a case that should never reach here, and you will think *"I'll just handle that case in the body."* That is the moment. It is faster, and it is the door propped open for every other function that takes the same type. Go upstream, make the case unrepresentable, and come back to a body that no longer needs the branch.

Write logic in a function body only as a last resort, and look in bodies first for logic that can be moved into types.

---

## Composability `[LAW:composability]` `[FRAMING:parts-and-seams]`

Each unit does one complete job with no hidden dependence on a particular caller and no required setup sequence, so a stranger could use it correctly without reading its caller.

Picture the unit on a shelf, with no caller in sight. A stranger picks it up. If they can use it correctly from its signature alone, it is a part. If they have to go read who calls it, and in what order, it is a fragment of someone else's function.

Give its boundary a type that admits exactly its legal variability, and express variability as values crossing one boundary, not as a family of similarly named functions.

```ts
// BAD: variability as a family of names
formatDateShort(d); formatDateLong(d); formatDateIso(d);

// GOOD: variability as a value crossing one boundary
formatDate(d, style: "short" | "long" | "iso");
```

The temptation sounds like judgment: *"this helper only makes sense here,"* so it reaches into what its caller happens to have, reads a field the caller set up, assumes the caller ran `init()` first. Refuse it. A helper coupled to its caller is not a helper; it is the caller's body moved to another file. Pass it what it needs as values, so it stands on the shelf alone.

### Leave it more composable than you found it

Leave the code you touch more composable than you found it. A task is done when the surrounding code is simpler than before, not when the feature works.

The failure has a slogan: *"minimum work to close the ticket."* It sounds disciplined. What it does is skip every improvement pass, forever, one ticket at a time, until the surrounding code is too tangled for any ticket to be minimal. The feature working is the halfway mark.

### The second instance tells you what's missing

If adding the second or third instance of something requires a logic edit rather than only new data, add the missing discriminator to the schema before adding the next instance.

- BAD: adding a third export format means adding another `else if (format === "xml")` branch inside `export()`.
- GOOD: adding a third format means adding one entry to a table of formats; `export()` doesn't change.

Do not design for specific futures. Judge a design by whether an unplanned, dissimilar requirement could be met by composing existing units rather than redesigning them. The target is not "ready for the feature I imagine"; it is "made of parts that could be recombined for the one nobody imagined."

---

## Carrying cost `[LAW:carrying-cost]`

Judge code by its carrying cost, not by its cost to build today, and plan as if you will be implementing the project for years.

Building cost is the price tag, paid once. Carrying cost is the rent, paid every month the code exists: every change that has to work around it, every reader who has to reason about it. A cheap build with high rent is the expensive option.

### Sunk cost does not vote

Do not let work already spent steer the next decision. When the current direction is wrong, change it regardless of how far you have gone.

You will be deep into an approach, you will see it is wrong, and you will hear *"we've already built it this way - changing course now wastes the work."* That is the moment. The work already spent is gone whichever way you go; the only thing still being decided is how much rent the next years pay. Change direction.

### YAGNI has a home, and this isn't it

"You aren't gonna need it" is correct about features that carry ongoing cost: speculative options, extra modes, machinery that has to be maintained whether or not anyone uses it. That is its home turf.

Do not apply it against building a pure, well-typed, composable unit. Such a unit carries almost no rent; it sits on the shelf, correct, and waits. YAGNI applies only to features that carry ongoing cost.

### "The wrong abstraction is worse than duplication"

Do not use this as a reason to duplicate. The proverb describes something real: an abstraction stretched over shapes it was not designed for, sprouting parameters and special cases until it hurts. Duplication is not the answer to that pain. When an abstraction starts to hurt because it was stretched over shapes it was not designed for, give the new shape its own unit instead of abandoning abstraction.

---

## Polishing is subtraction `[LAW:polishing-by-subtraction]`

An improvement pass removes code. Polishing a stone takes material off; nobody polishes by gluing more on.

A pass that adds a guard, helper, case, or a comment explaining the mess is patching, not improving. Move the work into constraints instead: a type, a boundary, a schema.

Count the code before and after a pass, and before claiming it improved anything. If the result is longer, do not call it an improvement.

This is how the law breaks: every addition looks defensible alone. One guard is reasonable. One helper is reasonable. One clarifying comment is reasonable. Each passes review on its own merits, and so the codebase only grows. The count is the check that sees what the individual judgments cannot.

### "Clearer, even if it's a bit longer"

Do not justify a longer version as "clearer" or "more explicit". You will finish a pass, see the diff is net positive, and think *"this version is clearer, even if it's a bit longer."* That is the moment. Ask whether the fact moved somewhere more visible or was only stated more times. If code needed explaining, the explanation is a symptom: find and apply the missing constraint.

---

## Time and effects

### No ambient temporal coupling `[LAW:no-ambient-temporal-coupling]`

Give every ordering, timing, lifecycle, initialization, cleanup, and re-entry invariant one explicit owner, and represent it as state, data, or capability.

Correctness must not depend on:

- sleeps
- event-loop ticks
- framework effect order
- render timing
- settle delays
- caller sequencing
- cleanup order
- manual in-flight flags

unless that scheduler or lifecycle is the named owner.

The check: the code stays correct if every operation runs twice as fast or twice as slow. Code that passes only at today's speed is balanced on a timing that nobody owns.

If operation B is safe only after operation A, encode that in a type or state machine, or route both through the single owner that guarantees it.

```ts
// BAD: B works because A usually finishes first
startConnection();
await sleep(100);
sendMessage(msg);

// GOOD: B awaits the condition it needs, owned as state
const conn = await connect();   // returns only once connected
conn.send(msg);                 // send exists only on a connected handle
```

Do not fix an ordering failure with a delay. A test flakes, you add a wait, it goes green, and you think *"a 100ms sleep fixes the flake."* That is the moment. The sleep did not fix the race; it moved it to a slower machine, a busier CI runner, a day nobody will connect to this change. Name the condition B needs, make it owned state, and make B await it.

### Effects at the boundaries `[LAW:effects-at-boundaries]`

Keep effects (I/O, mutation, clocks, randomness) at the system's edges. The core is pure and returns descriptions of actions for the edge to perform.

The core writes the order ticket; the edge cooks. The core never reaches for the stove.

The check: core functions can be unit-tested with no mocks.

Do not perform an effect inside the core where its value is needed; take the value as a parameter or return a description of the action.

```ts
// BAD: the core reads the clock where it needs it
function isExpired(token: Token) {
  return token.expiresAt < Date.now();
}

// GOOD: the value arrives as a parameter
function isExpired(token: Token, now: number) {
  return token.expiresAt < now;
}
```

The rationalization is always small: *"it's just one little read, right here where I need it."* That is the moment. The little read is what turns the core's tests into mock setups. Take the value as a parameter and let the edge do the reading.

---

## Single sources

### One source of truth `[LAW:one-source-of-truth]` `[FRAMING:representation]`

Every concept has exactly one authoritative representation. Every other representation visibly derives from it and is explicitly synchronized.

A house with two clocks has no time, only two opinions. The moment they disagree, nobody knows which one to believe.

Never create a second source. Read from, derive from, or change the canonical one.

The failure comes in two costumes. The first is *"a copy here for convenience"*: a constant duplicated, a list of names mirrored in a second file, a cached field that nothing keeps in sync. The second is a script that writes directly to a file another tool owns, and destroys its curated contents. Both feel harmless on the day they are written; both leave a second source that the canonical one no longer controls. Refuse the copy. Derive from the canonical source, or change it.

When you inherit two divergable representations of one fact, first demote one to a derived copy or delete it, before other work.

### A single enforcer `[LAW:single-enforcer]`

Enforce each cross-cutting invariant (auth, validation, timing, serialization) at exactly one boundary.

One gate, with the guard at it. A second checkpoint halfway down the hall does not make the building safer; it makes it unclear which checkpoint is the real one, and the two drift apart.

Never add a second check. If a check is not at the canonical boundary, delete it and route through that boundary.

You will be in a handler, unsure whether the input was validated upstream, and you will think *"one more validation here can't hurt."* That is the moment. It hurts exactly by existing: now there are two rules for one invariant, and the day they disagree, nobody knows which is law. Find the boundary, route through it, and delete the stray.

---

## Comments carry meaning `[LAW:comments-carry-meaning]`

Write a comment only if it states what the code does not:

- the intent
- a relationship to code elsewhere
- the reason for this approach over another
- a simplification of the mechanism for a reader who cannot read the original

A comment is a margin note: worth writing when it says what the page cannot.

A comment may describe what the code does, but must not restate it at the code's own level of detail.

```ts
// BAD: restates the line at its own level
// increment retries by one
retries += 1;

// GOOD: states what the code cannot
// Backoff doubles per retry; the server rate-limits bursts, not totals.
retries += 1;
```

The failure is well-meant: *"a quick line restating this"* for the next reader. That next reader can read the line; what they cannot read is why it's there.

And the mirror failure. Do not delete a teaching or simplifying comment because the mechanism is obvious to you. You will be tidying a file, see a comment that walks through a bit-twiddling trick, and think it *"just says what the code says."* That is the moment. Obvious to you is not obvious to the reader who cannot read the original. Check whether it states something the code does not; if it does, it stays.

Keep comments scoped to the code they annotate. Do not put the author's mood, the ticket's backstory, or a re-teaching of the domain in them.

---

## Data flow

### Data flow, not control flow `[LAW:dataflow-not-control-flow]`

Run the same operations in the same order on every invocation. Carry variability in values (nulls, empty collections, discriminated unions), never in whether an operation runs. Run side effects unconditionally and vary their behavior through their inputs.

An assembly line where every station runs on every item. What comes off the end differs because the item differs, not because stations switched themselves off.

The check: the set of operations executed does not depend on the input.

Listen to how you describe the mechanism. Treat "if", "and", "when", "skip", or "only" in your description of a mechanism (not of its consequences) as a sign the design is wrong. "It sends the notification only when the list is non-empty" describes a mechanism with a switch in it. "Notifications go to everyone in the list" describes a mechanism that always runs; an empty list means nobody gets one.

This is the most commonly violated law, and the reason is not carelessness: writers default to control flow because every language does. The `if` is the first tool every language hands you, so it is the one your hand closes around.

Instead of an `if` that skips an operation, restructure so the operation always runs and data decides the result:

- a default value
- an empty collection
- an identity operation
- a discriminated variant handled exhaustively

```ts
// BAD: whether the operation runs depends on the input
if (items.length > 0) {
  notify(items);
}

// GOOD: notify always runs; an empty list notifies nobody
notify(items);
```

You will hit a case where an operation shouldn't have an effect, and you will think *"I'll just add an `if` to skip it in that case."* That is the moment. Ask which value would make the operation's result correct with no branch: the empty collection, the identity, the variant. Make the data say it.

### One type per behavior `[LAW:one-type-per-behavior]`

Before creating several types, ask what differs besides the name. If nothing or only configuration differs, build one type and create instances.

One cookie cutter, many cookies. You don't carve a new cutter because the next cookie gets a different name.

Treat names listed in a spec as instances, not type definitions. The spec says "support Admin, Editor, and Viewer roles," and writers write three classes because the spec names three things. Refuse it: if the three differ only in configuration, that is one `Role` type and three values.

### No mode explosion `[LAW:no-mode-explosion]`

Do not add a flag, option, or mode without a documented owner, default, cap, and deletion date. Keep the default path canonical.

Each flag doubles the paths through the code.

The respectable argument here is *"it's backwards compatible."* It is: nothing breaks today. That is the argument writers use to add the flag, and it says nothing about who owns it, what the default is, where the cap is, or when it goes away. Without those four, don't add it.

---

## Parsing and null handling

### Parse, don't validate `[LAW:parse-dont-validate]`

Check input with a boundary check that returns a new type proving the check passed, not with a validator that returns a boolean or the same type it received. Require that type in every downstream signature.

A validator is a guard who looks at your ticket and waves you through; nobody past the door can tell you were checked. A boundary check stamps the ticket, and every door past it asks to see the stamp.

```ts
// BAD: a validator; downstream still receives a plain string
function isValidEmail(s: string): boolean { ... }
function sendWelcome(to: string) { ... }

// GOOD: a boundary check; downstream requires the proof
function parseEmail(s: string): Result<Email, ParseError> { ... }
function sendWelcome(to: Email) { ... }
```

The three parts of a boundary check are: a dedicated unit whose only job is the check, an output type that could not exist before it and that every downstream signature requires, and a failure arm that is a loud error or a typed absence the caller must explicitly unwrap. A check missing any of the three parts is a defensive guard, not a boundary check.

Never return a success-shaped empty value for invalid or missing input.

- BAD: `parseTags(raw)` returns `[]` when `raw` is malformed. The caller cannot tell "no tags" from "could not read the tags."
- GOOD: `parseTags(raw)` returns `Result<Tag[], ParseError>`.

Do not justify an in-function guard with a comment claiming it is a boundary. A real boundary is shown by its unit and output type, not by a comment asserting it. Treat a guard that needs a multi-line justifying comment as a violation.

This one is rehearsed because it is sophisticated. You will be deep in a function with an optional parameter, you will add a check, and you will start composing a comment: *"this is a real precondition at the trust boundary, not a defensive skip."* That is the moment. The length of the comment is the evidence. A boundary does not need to argue that it is one; its unit and its output type show it. Build the boundary check, or remove the state from the type.

Accept loosely formed input only at the outermost edge facing input you do not control, and convert it to a proving type there. Do not let unchecked data travel inward.

### No defensive null guards `[LAW:no-defensive-null-guards]`

Check for null only in a boundary check or where the value explicitly represents domain optionality. If a value should never be null, make its type non-nullable. Do not write a null check without an `else` that does real, necessary work.

A guard with no `else` is a sentry posted at a door that should already be locked. It doesn't secure anything; it hides the fact that the lock is missing.

```ts
// BAD: a guard with no else
if (user != null) {
  render(user);
}

// GOOD: the type says user is present
function renderPage(user: User) {
  render(user);
}
```

When code fails on a null, find why the value could be null instead of adding a check:

- fix a broken initialization order,
- encode a missing invariant, or,
- if the value is optional in the domain, express that in the type and handle it exhaustively.

Resolve optionality once, in the caller that has it.

The moment: a stack trace ends in `cannot read property of null`, and you think *"it crashed on null once - I'll add a check."* That is the moment. The check makes the crash go away and leaves the reason the value was null exactly where it was, now silent. Find the reason.

---

## Boundaries

### Locality, or a seam `[LAW:locality-or-seam]`

A change to one unit must not force edits in unrelated units. When it does, first create the interface, adapter, or boundary type and route the affected sites through it, then make the change.

A change that ripples out to five files is telling you where a seam is missing.

You will change a signature and find it used in five places, and you will think *"I'll just update the five call sites."* That is the moment. The five edits land, and the next change needs them again. Build the seam first, route the five sites through it, then make the change behind the seam.

### One-way dependencies `[LAW:one-way-deps]`

Declare the architecture's dependency direction. Do not create dependency cycles or upward calls.

Water runs downhill. A dependency that runs uphill turns the layers into a loop, and a loop has no bottom to build on.

When two layers seem to need each other, extract the shared concern into a unit below both, or have the lower layer define an interface the upper layer implements.

The temptation is always tiny: *"the lower layer just one tiny callback into the upper one."* That is the moment. One tiny callback is a cycle. Have the lower layer define the interface, and let the upper layer implement it.

### No shared mutable globals `[LAW:no-shared-mutable-globals]`

Give shared mutable state (registries, singletons, module-level maps) a single owner, an explicit API, and documented invariants, with no exception for convenience.

The office fridge with no owner: everyone puts things in, nobody knows what's safe to take out, and nobody is responsible when it goes bad.

You need two modules to share some state, and you reach for *"a module-level dict"* because it is the fastest way to share. That is the moment. Fast to write is the exception this law does not grant. Give the state an owner, an API, and written invariants.

---

## Verification and tests

### Verifiable goals `[LAW:verifiable-goals]`

Give every planned goal concrete, machine-checkable success and failure criteria, defined before the work. Build the check alongside the feature, run it yourself, and report the result with its evidence.

Draw the finish line before the race. A line drawn after the runner stops lands wherever the runner happened to stop.

- BAD: "Improve the importer's error handling."
- GOOD: "Importing `fixtures/bad-row.csv` exits 2 and names row 14 on stderr; importing `fixtures/good.csv` exits 0." Then run both and report the output.

Ask the user to test only after exhausting every way to verify yourself. Verification being complicated is not grounds to ask. If verification is genuinely very complicated, note it for a retrospective.

The failure is the handoff sentence: you finish, and you tell the user *"now you just need to test it."* That is the moment. That sentence hands the user the half of the job that proves the other half. Find the way to verify it yourself, run it, and report the evidence.

Ask the user questions that only the user can resolve, and only after making every effort to answer them yourself.

### Behavior, not structure `[LAW:behavior-not-structure]`

Tests assert the contract, never the implementation. A test passes for any implementation of the same contract. Keep contract tests separate from implementation tests.

A contract test is a lock that checks the key's shape, not the metal it was cut from.

- BAD: a test that asserts `cache.get` was called twice.
- GOOD: a test that asserts the second lookup returns the same value as the first.

When a test passes only if deprecated or removed code is kept, rewrite it to assert the contract, or delete it if it asserted nothing else. Never reintroduce removed code to satisfy a test. Delete code whose only remaining user is a test.

You will remove an internal call, a test will go red, and you will reach to restore the old call because the test expects it. That is the moment. The test is asserting wiring, not behavior. Rewrite it against the contract, or delete it.

### No silent failure `[LAW:no-silent-failure]`

Surface errors loudly. Do not suppress errors, default past them, or fall back silently to a different data source. If the primary path fails, stop and report.

A smoke detector with the battery pulled is quiet, and the quiet is the danger.

You will be mid-script, a command will fail for a reason that looks irrelevant, and you will treat the error as noise and silence it. That is the moment. The error you silence is the one the next session spends hours looking for, with no trail back to here. Let it fail loudly; fix the cause.

Do not use these patterns; each is a bug:

- `2>/dev/null`
- `|| true`, except where the failure is irrelevant to every downstream consumer. If unsure, it is not irrelevant.
- `|| echo "default"` and other silent fallback values
- fallback to a data source whose filtering, ordering, or meaning differs from the primary

After every external call, check:

1. the exit code,
2. that output is non-empty,
3. that it parses,
4. that values are sane.

On any miss, abort with a message that says where to look.

```bash
# BAD
count=$(curl -s "$URL" | jq '.count' 2>/dev/null || echo 0)

# GOOD
body=$(curl -sf "$URL") || { echo "fetch failed: $URL" >&2; exit 1; }
[ -n "$body" ] || { echo "empty response from $URL" >&2; exit 1; }
count=$(jq -e '.count' <<<"$body") || { echo "no .count in response from $URL" >&2; exit 1; }
```

---

## Domain bindings

The bindings below sharpen the laws for a domain; they never weaken them. Treat an apparent conflict between a binding and a law as a misreading of the binding.

**UI/frontend.** Keep state near its use and lift it only when coordination requires it. Shape components after the user's mental model, not implementation concerns. Give animation and rendering one explicit, named timing owner (`[LAW:no-ambient-temporal-coupling]`).

**APIs.** Make operations retry-safe unless explicitly documented otherwise. Include enough context in errors to retry intelligently (`[LAW:no-silent-failure]`). Version at the boundary, not throughout internals (`[LAW:single-enforcer]`).

**Data/schema.** Give every migration a rollback path. Avoid dual-write (`[LAW:one-source-of-truth]`); where it is unavoidable, write explicit cutover criteria and a deadline before the first double write.

**Pipelines/compilers.** Each stage declares its inputs and outputs. Later stages never mutate earlier representations (`[LAW:one-way-deps]`). Every intermediate representation has an explicit owner.

**Distributed systems.** Design and document failure modes as fully as success paths. Give ordering and timing an explicit owner (`[LAW:no-ambient-temporal-coupling]`).

**CLI.** Define exit codes as a contract beyond 0/1. Define the semantics of stdout and stderr, deciding deliberately which output is machine-parseable and which is for humans (`[LAW:effects-at-boundaries]`, `[LAW:parse-dont-validate]`).

---

## Before you leave the code

Run your hand over what you wrote and feel for what snags. Before leaving code, check it for each of these:

- a type bespoke to one caller (`composability`)
- a guard with no else (`no-defensive-null-guards`)
- a check far from any boundary (`parse-dont-validate`, `single-enforcer`)
- a comment doing a type's job (`types-are-the-program`)
- a copy that can drift (`one-source-of-truth`)
- a flag with no deletion date (`no-mode-explosion`)
- a silenced error (`no-silent-failure`)

The task is not done while any remains.

### The laws, by token

When unsure, ask the two framing questions: where is the boundary between parts, and does each representation match the thing it represents?

- `[LAW:decomposition]` one purpose per unit; split at the "and"
- `[LAW:types-are-the-program]` strongest true type; fix upstream types, not bodies
- `[LAW:composability]` a part a stranger can use; leave it simpler than you found it
- `[LAW:carrying-cost]` judge by the rent, not the price tag
- `[LAW:polishing-by-subtraction]` an improvement pass removes code; count it
- `[LAW:no-ambient-temporal-coupling]` every ordering and lifecycle invariant has one explicit owner
- `[LAW:effects-at-boundaries]` pure core, effects at the edge
- `[LAW:one-source-of-truth]` one authoritative representation per concept
- `[LAW:single-enforcer]` each cross-cutting invariant at exactly one boundary
- `[LAW:comments-carry-meaning]` say what the code cannot
- `[LAW:dataflow-not-control-flow]` same operations every time; data decides
- `[LAW:one-type-per-behavior]` one type, many instances
- `[LAW:no-mode-explosion]` no flag without owner, default, cap, deletion date
- `[LAW:parse-dont-validate]` return a proving type; no success-shaped empties
- `[LAW:no-defensive-null-guards]` non-nullable types; find why it was null
- `[LAW:locality-or-seam]` build the seam before the ripple
- `[LAW:one-way-deps]` declared direction; no cycles
- `[LAW:no-shared-mutable-globals]` shared state has an owner and an API
- `[LAW:verifiable-goals]` machine-checkable criteria, verified by you
- `[LAW:behavior-not-structure]` tests assert the contract
- `[LAW:no-silent-failure]` fail loudly; check every external call

Cite them at the point of use, spelled exactly, and mark every exception.
