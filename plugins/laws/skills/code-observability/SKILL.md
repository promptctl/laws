---
name: code-observability
description: Domain bindings for [LAW:nothing-unseen] - what the shared layer is in each domain (service, CLI, script or job, migration, distributed hop), what its one event carries, the order of work for retrofitting a codebase that has no shared layer, and the constraints every binding must survive (cardinality, sampling, redaction, overhead). Load when writing or reviewing instrumentation, logging, metrics, tracing, or telemetry; when deciding what a new service, CLI, or job must emit; when retrofitting observability onto an existing codebase; or when acting on a [LAW:nothing-unseen] finding. Held beside laws:code; the law itself lives there and is not restated here.
---

# Where the panel goes

`[LAW:nothing-unseen]` says instrumentation lives in the layer every unit of work
passes through, from the first commit, and that zero and absent are different facts.
This skill says what that layer *is*, domain by domain, and in what order to build it
when the codebase already exists. It sharpens the law; it never relaxes it. A binding
that seems to conflict with the law has been misread.

Two objections arrive the moment the work starts. Both are answered by the same
sentence, and it is the one to keep active.

**"Logging is noise."** It is, when it is scattered log lines at pixel resolution -
and that is the failure of a *call-site* practice, not of observability. One wide event
per unit of work is the opposite of noise: the smallest complete record, emitted once,
from one place. Volume is the symptom of instrumenting in the wrong layer, and the cure
is the layer, never fewer facts.

**"That's an ops concern, a library choice."** Which backend, which SDK, which
exporter - those are binding-level detail and mostly settled (OpenTelemetry is the
consensus). Whether the system *can be understood from its outputs* is a property of
the code's shape, decided by whoever writes the shared layer, and no backend can add it
afterward. The shared layer is yours to write. That is the work.

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

## Retrofitting a codebase that already exists

The temptation on existing code: *"I'll add metrics around the part that broke."*
Refuse it. A metric at the incident site is a call-site instrument, which is the shape
that goes missing - it covers last week's failure and nothing else, and the next
retrofit invents its own names beside it. The redirect is the shared layer, arrived at
from the other side, in this order, because each step is what makes the next one cheap:

1. **Fix the names first.** Attribute names, event names, and units are settled before
   the first instrument lands. The inconsistency of bolt-ons comes from each retrofit
   inventing its own.
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

Done is the law's FORBIDDEN list, walked as an audit: each shape found is a ticket,
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
