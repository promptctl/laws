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
