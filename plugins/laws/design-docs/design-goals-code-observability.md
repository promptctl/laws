# Design goals: the `code-observability` skill

This skill carries the domain bindings for `[LAW:nothing-unseen]` - what the shared layer is in each domain, what its event carries, how to retrofit a codebase that has no shared layer, and the constraints every binding has to survive. The law itself lives in the `code` skill and is not restated here. The owner split the two on 2026-09-18 (`design-docs/observability-north-star.law.md` req. 16-17, `design-docs/observability-skill.spec.md`): the entry in laws:code is short enough to sit in every code session's standing context, and the bindings have one home, loaded only when a session is writing or retrofitting instrumentation.

## What it's optimizing for

**The shared layer named, per domain, so nobody instruments a call site.** The law says instrumentation lives in the one layer every unit of work already passes through. This skill says what that layer *is*: request middleware and the base outbound client for a service, the entry point and dispatcher for a CLI, the run wrapper for a script or job, the migration runner for a schema, the correlation ID crossing every hop for a distributed system. A session that knows the layer's name has nowhere else to put the instrument.

**One retrofit order that keeps each step cheap.** Existing code is where the law is most often broken, and the tempting move is a metric at the incident site. The skill replaces that with a fixed order: settle names and units, inventory the shared layers, consolidate where none exists and instrument the one copy, wrap every job, fold ad-hoc log lines in as the code is touched. The done criterion is the law's forbidden shapes walked as an audit; in this repo that audit is `sheriff-is-in-town` and the remediation is `form-a-posse`, so the skill defines no loop of its own.

**Bindings that survive contact with production.** Cardinality, sampling, redaction, and overhead are where instrumentation gets ripped out and the system goes back to being unobserved. Each has one rule here, stated so the binding is built to it rather than fixed after.

## What it deliberately avoids, and why

**It never restates the law.** A binding that seems to conflict with the law has been misread; the skill cites the token and sharpens, never widens or relaxes. Restating would be a second source for the law's text.

**It carries no lineage or survey.** Both live in `design-docs/observability.md`; a session doing instrumentation work does not need Kalman or the three pillars in context.

**It is held beside `code`, never beside `prompt`.** It is a code-medium skill under the same compatibility policy as `code`.
