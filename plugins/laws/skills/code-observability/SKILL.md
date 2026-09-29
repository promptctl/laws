---
name: code-observability
description: Domain bindings for [LAW:nothing-unseen] - what a fully observable system has, the smallest shape that satisfies the law before any backend exists (the floor, with its default field set), what the shared layer is in each domain (service, CLI, script or job, migration, distributed hop), what its one event carries, the order coverage grows in across a codebase that has no shared layer, and the constraints every binding must survive (cardinality, sampling, redaction, overhead). Load when writing or reviewing instrumentation, logging, metrics, tracing, or telemetry; when deciding what a new service, CLI, or job must emit; on first contact with a codebase whose units of work emit nothing; when retrofitting observability onto an existing codebase; or when acting on a [LAW:nothing-unseen] finding. Held beside laws:code; the law itself lives there and is not restated here.
---

# Where the panel goes

`[LAW:nothing-unseen]` says instrumentation lives in the layer every unit of work
passes through, from the first commit; that zero and absent are different facts; and
that the instrumentation of a change ships with the change, as its tests do. This
skill says what that layer *is*, domain by domain, what the smallest shape that
satisfies the law looks like, what a finished panel looks like, and in what order
coverage grows when the codebase already exists. It sharpens the law; it never relaxes
it. A binding that seems to conflict with the law has been misread.

Two objections arrive the moment the work starts. Both are answered by the same
sentence, and it is the one to keep active.

**"Logging is noise."** It is, when it is scattered log lines at pixel resolution -
and that is the failure of a *call-site* practice, not of observability. One wide event
per unit of work is the opposite of noise: the smallest complete record, emitted once,
from one place. Volume is the symptom of instrumenting in the wrong layer, and the cure
is the layer, never fewer facts.

**"That's an ops concern, a library choice."** The law already settles this:
observability is a property of the code's shape, not of the sink, and which sink is a
configuration value. What this skill adds is who decides the shape and what is left
over once it is decided. The shape is decided by whoever writes the shared layer, and
no backend can add it afterward. Which backend, which SDK, which exporter - those are
binding-level detail, and mostly settled. The shared layer is yours to write. That is
the work.

---

## What a fully observable system has

This is the end state, stated as properties of a running system rather than as a
list of tools, because a tool can be installed without any of these being true. Read
it as a checklist of what is still missing. Everything below this section is how each
line is reached.

- **One wide event per unit of work**, under a trace ID that crosses every hop the
  unit takes. Every request, job run, command invocation, and migration leaves exactly
  one record, and the record says everything known about it.
- **Metrics, traces, and logs are views over those events.** A metric is an aggregate
  over them; a trace is them with parent IDs; a log line is a field on one. No view is
  maintained on its own.
- **Rate, errors, duration, and saturation at every boundary the system owns** - each
  inbound edge, each outbound client, each queue and pool that can fill.
- **Objectives on user-visible symptoms**, and alerts only on those and on missing
  heartbeats. Nothing pages on a cause; a cause is what the event is read for after the
  page.
- **An introspection surface per process** - a metrics endpoint, a health probe, a
  profiling endpoint - so a running instance can be asked, not only read.
- **The event schema is a type**, and tests assert the event and its fields the way
  they assert a return value: a unit of work that runs under test produced its record,
  and the record carries the facts the code claims it carries.
- **Redaction at one export edge.** Secrets leave the process through one checkpoint,
  and nowhere else.
- **Telemetry failures are counted and surfaced.** An exporter that could not deliver
  is a fact on the record, never a gap in the record.

A codebase with none of these is in cloud with no panel. A codebase with the first
one has a panel; the rest are the instruments being added to it.

---

## The floor: the smallest shape that satisfies the law

The law says the event goes into the shared layer before the first unit of work passes
through, and that this does not wait for a backend. This is the shape that makes that
possible. It ships in the first commit, before any store, collector, or dashboard
exists, and it has four parts:

1. **A wrapper on the shared layer** that opens the event when the unit of work
   begins and closes it when the unit ends - on success, on failure, and on the
   exception nobody caught.
2. **An event type**: the record as a type, with the default fields below, so the
   schema is checked by the compiler and asserted by the tests.
3. **One call that adds a fact to the current event** - the only thing code inside the
   unit of work ever does about telemetry. It does not emit; it annotates. The wrapper
   emits.
4. **One export edge** through which every event leaves the process.

The export edge speaks OTLP to an address read from configuration. When that address
is absent, or set and unreachable, the edge appends the event as JSONL to a local file
instead. An event written to the file is not dropped - it is still a complete record,
still sliceable, still there at 3 a.m. - so this sharpens the law's *a telemetry
failure is itself telemetry* rather than restating it: the count of what the exporter
could not deliver is the count of file records whose `sink` field reads `file`, and
when the address was set and unreachable the record's `sink_error` carries the error.
The outage is visible on the record itself. That matters for the single-event job that
runs once and exits: it will never emit the later "N events dropped" event that a
long-running service could, so the fact has to ride on the one record it does emit.

The OpenTelemetry SDK is the usual source of the event and trace primitives and of
the OTLP exporter, in any language; the export edge is the codebase's own, wrapping the
SDK exporter with the file fallback above, which the stock exporter does not have.
That is the whole of what this skill names. Which collector receives the OTLP, which
store it lands in, what hostname the address resolves to, and whether the codebase
shares a client library with its neighbors are the consumer's own environment, and
belong in the consumer's own guidance, not here. A public tool cited as the example of
a primitive - `absent()` below - is not a deployment.

**The default field set.** Every codebase starts from the same names, so no one
designs them, and the inconsistency of bolt-ons - each retrofit inventing its own
vocabulary - never gets a chance to start:

- `event` - the name of the unit of work.
- `trace_id` - the correlation ID that crosses every hop.
- `service` - which process emitted it.
- `started_at` - when the unit began.
- `duration_ms` - how long it took.
- `outcome` - how it ended.
- `error` - the error when it did not end well; absent otherwise.
- `sink` - `otlp` or `file`: where this record went.
- `sink_error` - present only when `sink` is `file` because the address was set and
  unreachable; it carries the exporter's error.
- `counts` - an object whose keys are the unit of work's counts, including the zeros.
  Items seen, items pushed, items failed, rows touched, attempts made. A count of zero
  is written as zero; it is the fact that separates *ran and did nothing* from *never
  ran*.

A codebase adds fields to this set. It never renames one of these, and it never runs
a parallel set beside them - two names for the same fact is
`[LAW:one-source-of-truth]` violated on the panel itself.

A repo with only the file sink is fully observable. Pointing the edge at a store
later changes a configuration value and nothing in the code.

---

## The shared layer, per domain

**Services**
- The shared layer is the request middleware and the base outbound client. One wide
  event per request, correlation ID propagated on the wire (W3C Trace Context).
- Measure at the boundary the service owns: rate, errors, duration - and the
  saturation of anything that can fill.
- "Is it working" is a service-level objective over user-visible behavior. Alert on
  the symptom the user sees, never on a cause.
- A path nobody has hit yet is in the unknown condition. Synthetic probes exercise it
  on a schedule so the panel reads something before a user does.
- The process exposes its own introspection surface - a metrics endpoint, a health
  probe, a profiling endpoint - so a running instance can be asked, not only read.

**CLI**
- The shared layer is the entry point and the command dispatcher. One event per
  invocation: command, arguments as parsed, exit code, duration.
- `--dry-run` / `--explain` are the decision surface: what the command will do and
  which inputs decided it, before it acts.
- Exit codes are a contract (laws:code's CLI binding); the event and the exit code say
  the same thing.

**Scripts and background jobs**
- The shared layer is the run wrapper: one summary event at exit with every count,
  including zero. This is the cheapest binding there is, and it closes the unknown
  condition for the whole codebase.
- A scheduled job also emits a heartbeat, and the absence of the heartbeat is alerted
  on (`absent()` in Prometheus, a dead-man's switch anywhere else). No heartbeat means
  the reporter died, not that nothing happened.
- Status is never a boolean. Running, idle, last run at, last run's counts, last
  failure and why.

**Data and schema**
- The shared layer is the migration runner. One event per migration: rows touched,
  duration, which step, rollback taken or not.
- A pipeline stage declares its inputs and outputs (laws:code's pipelines binding); its
  event records the counts on both sides, so a stage that consumed 10,000 and produced
  0 is a visible fact, not a quiet one.

**Distributed systems**
- The trace is the wide event with parent IDs. The correlation ID crosses every hop or
  the record is broken at that hop.
- Failure modes are instrumented the way success paths are - designed, not appended
  (laws:code's distributed binding) - because a failure mode with no signal is the
  unknown condition by construction.

**Caches, retries, config - in any domain**
- A cache exposes hits, misses, and evictions, or it is two copies with a hope.
- A retry loop records every attempt on the unit of work's event; the fourth-attempt
  success carries the three failures with it.
- A config value read from several sources records which one won, on the event, so
  the question "which config is live" has an answer without a debugger.

---

## How coverage grows across a codebase that already exists

The temptation on existing code: *"I'll add metrics around the part that broke."*
Refuse it. A metric at the incident site is a call-site instrument, which is the shape
that goes missing - it covers last week's failure and nothing else, and the next
retrofit invents its own names beside it. The redirect is the shared layer, arrived at
from the other side, in this order, because each step is what makes the next one cheap:

1. **Fix the names first.** Attribute names, event names, and units are settled before
   the first instrument lands - starting from the default field set above, not from a
   blank page. The inconsistency of bolt-ons comes from each retrofit inventing its
   own.
2. **Inventory the shared layers** the bindings above name for the domains present.
   Each gets the wide event and the correlation ID. Coverage grows with the number of
   shared layers, not call sites, which is why this step alone covers most of a
   codebase.
3. **Where no shared layer exists, consolidate first.** Three hand-rolled HTTP clients,
   requests assembled inline: collapse the copies into one client or one runner, then
   instrument that. Instrumenting each copy cements the duplication -
   `[LAW:one-source-of-truth]` applied to the retrofit itself.
4. **Wrap every job and script** in the run wrapper and its summary event, including
   zero.
5. **Fold ad-hoc log lines into the event** as the code around them is touched. No
   sweep deletion; no new metric that duplicates a log line.

This is the order coverage grows in across many changes. It is not a program that one
change runs to completion, and the second temptation is to read it as one: *"the
whole codebase needs this, and I can't do the whole codebase, so I'll leave it."* That
reading produces either a sweep that touches every file or, seeing the sweep as the
only move, nothing at all - and nothing at all is what the codebase has now. The order
binds across the codebase's history, not within one change. A change stands up the
floor if it is absent, does the steps that reach the units of work it touches - in
that order - instruments those units with the facts the change introduces, and stops.
The job you touched gets its run wrapper; the three clients your feature calls get
consolidated and the one client instrumented; the log lines in the function you
rewrote get folded in; the rest of the codebase waits for the change that touches it.
Coverage grows the way test coverage grows: with each change, at the edges the change
reached, never as a separate project.

Done is the law's FORBIDDEN list, walked as an audit: each shape found is a defect,
and the retrofit is done when none of them can happen unseen. In this repo that audit
is `sheriff-is-in-town` and the remediation is `form-a-posse`; this skill defines no
audit loop of its own. The tell for a bad retrofit is telemetry per call site where a
shared layer exists.

---

## What every binding must survive

- **Cardinality has a bill.** Wide events tolerate high cardinality; metric labels do
  not. Derive metrics from events; never put a user ID in a label.
- **Sampling loses something either way.** Head sampling drops the interesting traces,
  tail sampling buffers. Choose one on purpose and record the choice on the event.
- **Secrets leak through telemetry constantly.** The outbound edge where events leave
  the process is a boundary, and `[LAW:parse-dont-validate]` applies there: redaction
  is a single checkpoint at that edge, never a per-call-site scrub.
- **Overhead is budgeted**, with under one percent as the reference. Instrumentation
  that slows the hot path gets ripped out, and once it is ripped out the system is
  back in cloud.

The code this produces cites `// [LAW:nothing-unseen] reason` at the point of use, as
laws:code requires of every law. The lineage and the industry survey behind these
bindings are in `design-docs/observability.md`.
