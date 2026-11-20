# Code laws, distilled

A reading companion to the [code laws](plugins/laws/skills/code/SKILL.md), with one entry per canonical law in source order. Related terms indicate connections, not necessarily exact synonyms.

- **Divide code at the natural boundaries of the problem domain.** (`decomposition`)
  - Give each unit one purpose that can be described in a plain sentence using the domain's vocabulary.
  - Each part should be understandable and reusable independently; boundaries should separate concerns that genuinely change for different reasons.
  - Related: separation of concerns, single responsibility principle, high cohesion, domain-driven design, locality-or-seam

- **Design types to admit every legal state and exclude every illegal state.** (`types-are-the-program`)
  - Put the strongest true constraints into the data model so the implementation follows from them.
  - When code needs compensating guards or branches, ask which invariant or discriminator belongs in the types instead.
  - Related: make illegal states unrepresentable, type-driven development, algebraic data types, design by contract, refinement types

- **Build units that do one complete job and compose without hidden dependencies.** (`composability`)
  - A unit should work without knowing a particular caller's state or requiring an undocumented setup ritual.
  - Each change should leave behind building blocks that are easier to combine into future capabilities.
  - Related: compositional design, loose coupling, explicit dependencies, reusable components, decomposition

- **Judge code by the ongoing cost of keeping it.** (`carrying-cost`)
  - Count the future effort of understanding, maintaining, extending, and working around a decision, rather than just today's implementation effort.
  - Ignore sunk effort when choosing the next step; abandon an expensive direction even if substantial work has already gone into it.
  - Related: total cost of ownership, technical debt, lifecycle cost, sunk cost fallacy, composability

- **Polish code by removing the machinery that better constraints make unnecessary.** (`polishing-by-subtraction`)
  - Move invariants into the model until redundant guards, helpers, cases, and explanations can disappear.
  - A refinement pass that grows the code is a patch under this law; keep looking for the constraint that would make the solution smaller.
  - Related: subtractive design, simplicity, negative code, types-are-the-program, carrying-cost

- **Make ordering and lifecycle explicit, with one owner.** (`no-ambient-temporal-coupling`)
  - Represent initialization, cleanup, sequencing, and re-entry rules as state, data, or capabilities.
  - Correctness must not depend on incidental execution order, fortunate timing, or callers remembering a ritual.
  - Related: temporal coupling, explicit state machines, typestate, structured concurrency, resource lifecycle management

- **Keep side effects at the boundaries and computation pure inside.** (`effects-at-boundaries`)
  - Isolate I/O, mutation, clocks, and randomness from the logic that decides what should happen.
  - Let the pure core produce descriptions of actions for an outer layer to execute, making its inputs and outputs explicit.
  - Related: functional core imperative shell, ports and adapters, pure functions, effect isolation, dependency injection

- **Give each concept one authoritative representation.** (`one-source-of-truth`)
  - Derive other representations from that authority and make any required synchronization explicit.
  - If two copies can disagree without a clear authority deciding which is correct, redesign their relationship.
  - Related: single source of truth, DRY, normalization, derived state, representation invariants

- **Use the names the domain already gives its concepts.** (`domain-language`)
  - Choose terms an expert in the subject would recognize without translation.
  - Preserve the project's established names and spelling, with finer subsystem vocabulary remaining consistent with the broader domain.
  - Related: ubiquitous language, domain-driven design, domain modeling, naming consistency, one-source-of-truth

- **Enforce each cross-cutting invariant at one boundary.** (`single-enforcer`)
  - Give rules such as authorization, validation, timing, and serialization one authoritative enforcement point.
  - Route through that point and remove duplicate checks that could drift into conflicting versions of the rule.
  - Related: complete mediation, centralized policy enforcement, invariant ownership, DRY, parse-dont-validate

- **Write comments that add a view the code cannot provide.** (`comments-carry-meaning`)
  - Explain intent, tradeoffs, relationships, or a simplification that helps readers understand a dense mechanism.
  - Use the domain's vocabulary and remove comments that merely echo the code at the same level of detail.
  - Related: rationale comments, intent documentation, abstraction levels, domain-language, one-source-of-truth

- **Keep the operation sequence stable and put variability in the flowing values.** (`dataflow-not-control-flow`)
  - Run the same operations in the same order; express differences through values such as empty collections and discriminated unions.
  - Invoke side-effect operations unconditionally and vary their behavior through inputs instead of guarding whether they execute.
  - Related: dataflow programming, declarative pipelines, algebraic data types, types-are-the-program, one-type-per-behavior

- **Represent identical behavior with one type and multiple instances.** (`one-type-per-behavior`)
  - Different names or configuration values do not justify separate types with the same behavior.
  - Identify what varies, expose it as data, and instantiate the shared type with those values.
  - Related: parameterization, configuration as data, parametric design, DRY, dataflow-not-control-flow

- **Bound flags and modes, and plan their removal.** (`no-mode-explosion`)
  - Every new flag, option, or mode needs a documented cap and an exit plan, including who removes it and when.
  - Keep the default path canonical so alternative paths do not become a permanent multiplication of behaviors to maintain.
  - Related: feature flag lifecycle, configuration complexity, combinatorial explosion, carrying-cost, dataflow-not-control-flow

- **Parse input into a type that preserves the proof of its validity.** (`parse-dont-validate`)
  - Use a dedicated boundary unit whose output type establishes the checked facts; downstream code requires that type and does not recheck them.
  - Failed parsing must surface as an error or an explicit typed alternative, never a success-shaped empty value.
  - Related: parse don't validate, smart constructors, refinement types, proof-carrying data, single-enforcer

- **Fix impossible nulls at their source instead of guarding past them.** (`no-defensive-null-guards`)
  - Null checks belong at real input boundaries or where absence is an intentional part of the domain.
  - If a required value can be absent, repair its construction and type rather than silently skipping the work that needs it.
  - Related: null safety, non-nullable types, explicit optionality, parse-dont-validate, types-are-the-program

- **Keep changes local by introducing the missing seam.** (`locality-or-seam`)
  - A change to one concern should not require edits to unrelated concerns.
  - When a change ripples, establish the interface or adapter that separates those concerns before proceeding.
  - Related: information hiding, change locality, low coupling, adapter pattern, decomposition

- **Declare one dependency direction and prohibit cycles.** (`one-way-deps`)
  - Dependencies must follow the architecture's declared direction; lower layers must not depend upward.
  - Resolve cycles by extracting a shared concern or introducing an interface owned by the lower layer and implemented above it.
  - Related: acyclic dependencies principle, dependency inversion, layered architecture, directed acyclic graph, decomposition

- **Give shared mutable state one owner and an explicit API.** (`no-shared-mutable-globals`)
  - Registries, singletons, and module-level maps require controlled writes and documented invariants.
  - Access should reveal ownership and mutation responsibilities rather than relying on ambient availability or convenience.
  - Related: state encapsulation, explicit ownership, information hiding, controlled mutation, explicit dependencies

- **Define concrete success criteria and verify them yourself.** (`verifiable-goals`)
  - Give each goal a machine-checkable distinction between success and failure before claiming it is done.
  - Run the checks and report evidence; asking the user to perform verification is a last resort after exhausting your own options.
  - Related: acceptance criteria, executable specifications, definition of done, evidence-based verification, behavior-not-structure

- **Test observable contracts rather than implementation structure.** (`behavior-not-structure`)
  - A different implementation that preserves the same behavior should still pass the tests.
  - Update or remove tests that depend on retired internals instead of restoring obsolete code to satisfy them.
  - Related: black-box testing, contract testing, behavioral testing, refactoring-safe tests, implementation independence

- **Surface failures instead of disguising them as success.** (`no-silent-failure`)
  - Do not suppress errors, default past them, or silently substitute a different data source when the primary path fails.
  - Stop the failed work and report enough context to identify the problem; preserve the distinction between failure and a legitimate empty result.
  - Related: fail fast, error transparency, explicit error handling, fault visibility, parse-dont-validate

- **Make runtime behavior reconstructable from the system's outputs.** (`nothing-unseen`)
  - Instrument the shared layer every unit of work passes through, starting with the first commit; each change adds its new facts to that instrumentation.
  - Emit correlated records rich enough for unanticipated questions and distinguish success, failure, zero work, and no run; telemetry failures must be visible without taking down the work.
  - Related: observability, structured events, distributed tracing, wide events, correlation IDs, no-silent-failure

- **Escape a known architectural trap instead of extending it with another cheap patch.** (`escape-local-minima`)
  - When the defense is “this does not make things worse until we have X,” pause the current task and make finding and implementing the real escape the priority.
  - Record where the task stopped, plan the escape at the top of the backlog, and hand it to a fresh session; complete realignment before resuming the paused work.
  - Related: local optimization, local minima, architectural remediation, carrying-cost, polishing-by-subtraction, no-mode-explosion
