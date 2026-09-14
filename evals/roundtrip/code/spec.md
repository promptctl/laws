# Code Architecture Laws

Scope: every task whose deliverable is code or will execute as code - writing, editing, reviewing, refactoring, debugging, or designing code, tests, schemas, configuration, scripts, infrastructure, or system architecture; out of scope: prose and LLM-prompt authoring.

## Terms

- Strongest true type: a type that can represent every legal state of the domain and no illegal state.
- Boundary check: a check with all three of (a) a dedicated unit whose only job is the check, (b) an output type that could not exist before the check and that every downstream signature requires, and (c) a failure arm that is either a loud error or a typed absence (`Result`, `Option`, a distinct variant) the caller must explicitly unwrap.
- Success-shaped empty value: a value with the shape of a real answer (such as `[]` or a default value) returned to mean "could not do the job".
- Carrying cost: the cost to maintain, extend, work around, and reason about code for as long as it exists, as opposed to the cost to build it.

## Requirements

### Application and citation

1. Apply these requirements to every code task, starting before the work begins, not after. No context, instruction, deadline, or "it's just a script" exempts a task.
2. When a law influences a decision, cite it in a comment at the point of use: `// [LAW:<token>] reason`. When you violate a law, mark the violation: `// [LAW:<token>] exception: reason`.
3. Use only the `[LAW:<token>]` tokens attached to requirements in this document, spelled exactly. Do not invent a token; a situation that seems to need one is an instance of an existing law. Do not cite `[FRAMING:...]` identifiers in code; use them only in reasoning.
4. When unsure which law applies, ask two questions: where is the boundary between parts, and does each representation match the thing it represents ([FRAMING:parts-and-seams], [FRAMING:representation]).

### Representations

5. [FRAMING:representation] Prefer representations the machine re-checks or recomputes over ones a human must remember to update, in this order: compile-time, then runtime, then documentation. Move each representation as far up that order as it can go.

### Decomposition

6. [LAW:decomposition] Divide the program along the problem domain's natural separations, so each unit has one purpose describable in one plain sentence with no conjunction and can be understood and reused alone.
7. [LAW:decomposition] Before adding code to a module, state the module's purpose in one sentence; if the sentence needs "and", split the module at the "and" before adding. Failure: writers put code in the nearest file "for now", intending to move it later, and never do.

### Types

8. [LAW:types-are-the-program] Give data its strongest true type. Do not use weaker types that admit illegal states (`any`, a record of optional fields whose valid combinations live in comments, `string` for a domain with a fixed set of values; use a discriminated union instead), and do not use types stricter than the domain that force code to lie or break.
9. [LAW:types-are-the-program] When a function body is hard to write, fix the upstream types instead of handling the case in the body, even when handling it in the body would finish the task faster. If the body branches, add the missing discriminator to the type; if it guards, remove the unwanted state from the upstream type; if a name must convey what the type cannot, fix the type; if an invariant needs a comment to explain it, encode it in the type and do not write the comment. Failure: writers say "I'll just handle that case in the body."
10. [LAW:types-are-the-program] Write logic in a function body only as a last resort, and look in bodies first for logic that can be moved into types.

### Composability

11. [LAW:composability] [FRAMING:parts-and-seams] Each unit does one complete job with no hidden dependence on a particular caller and no required setup sequence, so a stranger could use it correctly without reading its caller. Give its boundary a type that admits exactly its legal variability, and express variability as values crossing one boundary, not as a family of similarly named functions. Failure: writers couple a helper to what its caller has because "this helper only makes sense here."
12. [LAW:composability] Leave the code you touch more composable than you found it; a task is done when the surrounding code is simpler than before, not when the feature works. Failure: writers apply "minimum work to close the ticket", which skips every improvement pass.
13. [LAW:composability] If adding the second or third instance of something requires a logic edit rather than only new data, add the missing discriminator to the schema before adding the next instance. Do not design for specific futures; judge a design by whether an unplanned, dissimilar requirement could be met by composing existing units rather than redesigning them.

### Carrying cost

14. [LAW:carrying-cost] Judge code by its carrying cost, not by its cost to build today, and plan as if you will be implementing the project for years.
15. [LAW:carrying-cost] Do not let work already spent steer the next decision; when the current direction is wrong, change it regardless of how far you have gone. Failure: writers argue "we've already built it this way - changing course now wastes the work."
16. [LAW:carrying-cost] Do not apply "you aren't gonna need it" against building a pure, well-typed, composable unit; it applies only to features that carry ongoing cost.
17. [LAW:carrying-cost] Do not use "the wrong abstraction is worse than duplication" as a reason to duplicate. When an abstraction starts to hurt because it was stretched over shapes it was not designed for, give the new shape its own unit instead of abandoning abstraction.

### Improvement passes

18. [LAW:polishing-by-subtraction] An improvement pass removes code. A pass that adds a guard, helper, case, or a comment explaining the mess is patching, not improving; move the work into constraints instead.
19. [LAW:polishing-by-subtraction] Count the code before and after a pass and before claiming it improved anything; if the result is longer, do not call it an improvement. Failure: every addition looks defensible alone, so the codebase only grows.
20. [LAW:polishing-by-subtraction] Do not justify a longer version as "clearer" or "more explicit". Ask whether the fact moved somewhere more visible or was only stated more times; if code needed explaining, find and apply the missing constraint. Failure: writers say "this version is clearer, even if it's a bit longer."

### Time and effects

21. [LAW:no-ambient-temporal-coupling] Give every ordering, timing, lifecycle, initialization, cleanup, and re-entry invariant one explicit owner, and represent it as state, data, or capability. Correctness must not depend on sleeps, event-loop ticks, framework effect order, render timing, settle delays, caller sequencing, cleanup order, or manual in-flight flags, unless that scheduler or lifecycle is the named owner. Check: the code stays correct if every operation runs twice as fast or twice as slow.
22. [LAW:no-ambient-temporal-coupling] If operation B is safe only after operation A, encode that in a type or state machine, or route both through the single owner that guarantees it. Do not fix an ordering failure with a delay; name the condition B needs, make it owned state, and make B await it. Failure: writers say "a 100ms sleep fixes the flake."
23. [LAW:effects-at-boundaries] Keep effects (I/O, mutation, clocks, randomness) at the system's edges; the core is pure and returns descriptions of actions for the edge to perform. Check: core functions can be unit-tested with no mocks.
24. [LAW:effects-at-boundaries] Do not perform an effect inside the core where its value is needed; take the value as a parameter or return a description of the action. Failure: writers say "it's just one little read, right here where I need it."

### Single sources

25. [LAW:one-source-of-truth] [FRAMING:representation] Every concept has exactly one authoritative representation; every other representation visibly derives from it and is explicitly synchronized. Never create a second source; read from, derive from, or change the canonical one. Failure: writers keep "a copy here for convenience", or a script writes directly to a file another tool owns and destroys its curated contents.
26. [LAW:one-source-of-truth] When you inherit two divergable representations of one fact, first demote one to a derived copy or delete it, before other work.
27. [LAW:single-enforcer] Enforce each cross-cutting invariant (auth, validation, timing, serialization) at exactly one boundary. Never add a second check; if a check is not at the canonical boundary, delete it and route through that boundary. Failure: writers think "one more validation here can't hurt."

### Comments

28. [LAW:comments-carry-meaning] Write a comment only if it states what the code does not: the intent, a relationship to code elsewhere, the reason for this approach over another, or a simplification of the mechanism for a reader who cannot read the original. A comment may describe what the code does, but must not restate it at the code's own level of detail. Failure: writers add "a quick line restating this" for the next reader.
29. [LAW:comments-carry-meaning] Do not delete a teaching or simplifying comment because the mechanism is obvious to you; check whether it states something the code does not. Failure: writers delete such comments as "just says what the code says."
30. [LAW:comments-carry-meaning] Keep comments scoped to the code they annotate; do not put the author's mood, the ticket's backstory, or a re-teaching of the domain in them.

### Data flow

31. [LAW:dataflow-not-control-flow] Run the same operations in the same order on every invocation; carry variability in values (nulls, empty collections, discriminated unions), never in whether an operation runs. Run side effects unconditionally and vary their behavior through their inputs. Check: the set of operations executed does not depend on the input.
32. [LAW:dataflow-not-control-flow] Treat "if", "and", "when", "skip", or "only" in your description of a mechanism (not of its consequences) as a sign the design is wrong. Failure: writers default to control flow because every language does; this is the most commonly violated law.
33. [LAW:dataflow-not-control-flow] Instead of an `if` that skips an operation, restructure so the operation always runs and data decides the result: a default value, an empty collection, an identity operation, or a discriminated variant handled exhaustively. Failure: writers say "I'll just add an `if` to skip it in that case."
34. [LAW:one-type-per-behavior] Before creating several types, ask what differs besides the name; if nothing or only configuration differs, build one type and create instances. Treat names listed in a spec as instances, not type definitions. Failure: writers write three classes because the spec names three things.
35. [LAW:no-mode-explosion] Do not add a flag, option, or mode without a documented owner, default, cap, and deletion date; keep the default path canonical. Failure: writers add a flag because "it's backwards compatible."

### Parsing and null handling

36. [LAW:parse-dont-validate] Check input with a boundary check that returns a new type proving the check passed, not with a validator that returns a boolean or the same type it received; require that type in every downstream signature. A check missing any of the three parts of a boundary check is a defensive guard, not a boundary check.
37. [LAW:parse-dont-validate] Never return a success-shaped empty value for invalid or missing input.
38. [LAW:parse-dont-validate] Do not justify an in-function guard with a comment claiming it is a boundary; a real boundary is shown by its unit and output type. Treat a guard that needs a multi-line justifying comment as a violation. Failure: deep in a function with an optional parameter, writers compose "this is a real precondition at the trust boundary, not a defensive skip."
39. [LAW:parse-dont-validate] Accept loosely formed input only at the outermost edge facing input you do not control, and convert it to a proving type there; do not let unchecked data travel inward.
40. [LAW:no-defensive-null-guards] Check for null only in a boundary check or where the value explicitly represents domain optionality. If a value should never be null, make its type non-nullable; do not write a null check without an `else` that does real, necessary work.
41. [LAW:no-defensive-null-guards] When code fails on a null, find why the value could be null instead of adding a check: fix a broken initialization order, encode a missing invariant, or, if the value is optional in the domain, express that in the type and handle it exhaustively. Resolve optionality once, in the caller that has it. Failure: writers say "it crashed on null once - I'll add a check."

### Boundaries

42. [LAW:locality-or-seam] A change to one unit must not force edits in unrelated units. When it does, first create the interface, adapter, or boundary type and route the affected sites through it, then make the change. Failure: writers say "I'll just update the five call sites."
43. [LAW:one-way-deps] Declare the architecture's dependency direction. Do not create dependency cycles or upward calls; extract the shared concern into a unit below both, or have the lower layer define an interface the upper layer implements. Failure: writers give "the lower layer just one tiny callback into the upper one."
44. [LAW:no-shared-mutable-globals] Give shared mutable state (registries, singletons, module-level maps) a single owner, an explicit API, and documented invariants, with no exception for convenience. Failure: writers use "a module-level dict" because it is the fastest way to share.

### Verification and tests

45. [LAW:verifiable-goals] Give every planned goal concrete, machine-checkable success and failure criteria, defined before the work; build the check alongside the feature, run it yourself, and report the result with its evidence.
46. [LAW:verifiable-goals] Ask the user to test only after exhausting every way to verify yourself; verification being complicated is not grounds to ask. If verification is genuinely very complicated, note it for a retrospective. Failure: writers finish and tell the user "now you just need to test it."
47. [LAW:verifiable-goals] Ask the user questions that only the user can resolve, after making every effort to answer them yourself.
48. [LAW:behavior-not-structure] Tests assert the contract, never the implementation; a test passes for any implementation of the same contract. Keep contract tests separate from implementation tests.
49. [LAW:behavior-not-structure] When a test passes only if deprecated or removed code is kept, rewrite it to assert the contract or delete it if it asserted nothing else; never reintroduce removed code to satisfy a test. Delete code whose only remaining user is a test. Failure: writers restore an old internal call because the test expects it.
50. [LAW:no-silent-failure] Surface errors loudly. Do not suppress errors, default past them, or fall back silently to a different data source; if the primary path fails, stop and report. Failure: writers treat an error as noise and silence it.
51. [LAW:no-silent-failure] Do not use these patterns; each is a bug: `2>/dev/null`; `|| true`, except where the failure is irrelevant to every downstream consumer (if unsure, it is not irrelevant); `|| echo "default"` and other silent fallback values; and fallback to a data source whose filtering, ordering, or meaning differs from the primary.
52. [LAW:no-silent-failure] After every external call, check the exit code, that output is non-empty, that it parses, and that values are sane; on any miss, abort with a message that says where to look.

### Domain bindings

53. Read requirements 54-59 as sharpening the laws for a domain, never weakening them; treat an apparent conflict between a binding and a law as a misreading of the binding.
54. UI/frontend: keep state near its use and lift it only when coordination requires it; shape components after the user's mental model, not implementation concerns; give animation and rendering one explicit, named timing owner ([LAW:no-ambient-temporal-coupling]).
55. APIs: make operations retry-safe unless explicitly documented otherwise; include enough context in errors to retry intelligently ([LAW:no-silent-failure]); version at the boundary, not throughout internals ([LAW:single-enforcer]).
56. Data/schema: give every migration a rollback path. Avoid dual-write ([LAW:one-source-of-truth]); where it is unavoidable, write explicit cutover criteria and a deadline before the first double write.
57. Pipelines/compilers: each stage declares its inputs and outputs; later stages never mutate earlier representations ([LAW:one-way-deps]); every intermediate representation has an explicit owner.
58. Distributed systems: design and document failure modes as fully as success paths; give ordering and timing an explicit owner ([LAW:no-ambient-temporal-coupling]).
59. CLI: define exit codes as a contract beyond 0/1; define the semantics of stdout and stderr, deciding deliberately which output is machine-parseable and which is for humans ([LAW:effects-at-boundaries], [LAW:parse-dont-validate]).

### Finishing

60. Before leaving code, check it for a type bespoke to one caller, a guard with no else, a check far from any boundary, a comment doing a type's job, a copy that can drift, a flag with no deletion date, and a silenced error; the task is not done while any remains.
