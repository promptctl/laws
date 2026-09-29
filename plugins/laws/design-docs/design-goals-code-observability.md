# Design goals: the `code-observability` skill

This skill carries the domain bindings for `[LAW:nothing-unseen]` - what a fully observable system looks like, the smallest shape that already satisfies the law, what the shared layer is in each domain, what its event carries, how coverage grows across a codebase that has no shared layer, and the constraints every binding has to survive. The law itself lives in the `code` skill and is not restated here. The owner split the two on 2026-09-18 (`design-docs/observability-north-star.law.md` req. 16-17, `design-docs/observability-skill.spec.md`): the entry in laws:code is short enough to sit in every code session's standing context, and the bindings have one home, loaded only when a session is writing or retrofitting instrumentation.

## What it's optimizing for

**The shared layer named, per domain, so nobody instruments a call site.** The law says instrumentation lives in the one layer every unit of work already passes through. This skill says what that layer *is*: request middleware and the base outbound client for a service, the entry point and dispatcher for a CLI, the run wrapper for a script or job, the migration runner for a schema, the correlation ID crossing every hop for a distributed system. A session that knows the layer's name has nowhere else to put the instrument.

**An end state a senior engineer would recognize, so nobody aims lower.** The owner's target (2026-09-27) is instrumentation at the standard of a large engineering organization, reached incrementally. Most sessions have never seen that standard, so the skill states it as properties of a running system - one event per unit of work with a trace ID that crosses hops; metrics, traces, and logs as views over it; rate, errors, duration, and saturation at every owned boundary; objectives on user-visible symptoms with alerts only on those and on missing heartbeats; an introspection surface per process; the event schema as a type with tests; redaction at one edge; telemetry failures counted. It reads as a checklist of what is still missing, not as a tool list.

**A floor that needs no backend, so the shape ships in the first commit.** Observability is a property of the code's shape; the sink is a config value. The smallest shape that satisfies the law is a wrapper on the shared layer, an event type, a call that adds a fact to the current event, and one export edge that speaks OTLP to an address read from config and appends JSONL to a file when that address is absent or unreachable. A repo with only the file sink is fully observable; pointing the edge at a store later changes nothing in the code. This is what makes "from the first commit" possible before any infrastructure exists.

**A default field set, so no repo designs names.** The inconsistency of bolt-ons comes from each retrofit inventing its own names, and "settle the names first" stalls a session that has never named telemetry. The skill hands every codebase the same starting fields; a codebase adds to them and never renames them or runs a parallel set.

**Coverage that grows with each change, the way test coverage does.** Existing code is where the law is most often broken, and the tempting move is a metric at the incident site. The skill replaces that with a fixed order: settle names and units, inventory the shared layers, consolidate where none exists and instrument the one copy, wrap every job, fold ad-hoc log lines in as the code is touched. That order is the order coverage grows across many changes, not a program one session runs to completion: each change instruments the units of work it touches and stops. The done criterion is the law's forbidden shapes walked as an audit; in this repo that audit is `sheriff-is-in-town` and the remediation is `form-a-posse`, so the skill defines no loop of its own.

**One retrofit order that keeps each step cheap.** Existing code is where the law is most often broken, and the tempting move is a metric at the incident site. The skill replaces that with a fixed order: settle names and units, inventory the shared layers, consolidate where none exists and instrument the one copy, wrap every job, fold ad-hoc log lines in as the code is touched. The done criterion is the law's forbidden shapes walked as an audit; in this repo that audit is `sheriff-is-in-town` and the remediation is `form-a-posse`, so the skill defines no loop of its own.

**Bindings that survive contact with production.** Cardinality, sampling, redaction, and overhead are where instrumentation gets ripped out and the system goes back to being unobserved. Each has one rule here, stated so the binding is built to it rather than fixed after.

## What it deliberately avoids, and why

**It never restates the law.** A binding that seems to conflict with the law has been misread; the skill cites the token and sharpens, never widens or relaxes. Restating would be a second source for the law's text.

**It names no infrastructure and no library.** This repo is used by people with their own stacks. The skill says OTLP to a configured address with a file fallback, because that is the public consensus shape; which collector, which stores, which hostname, and which client package belong to the consumer's own environment skill. A user who wants a shared client library builds it outside this repo.

**It carries no workflow.** Whether a ticket is done, when a review runs, and what a session does first are the consumer's process; this skill states what the code looks like and in what order coverage grows, and nothing about tickets or sessions.

**It carries no lineage or survey.** Both live in `design-docs/observability.md`; a session doing instrumentation work does not need Kalman or the three pillars in context.

**It is held beside `code`, never beside `prompt`.** It is a code-medium skill under the same compatibility policy as `code`.
