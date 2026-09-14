# Observability: runtime introspection as a law

**2026-09-07, owner direction; brainstorm record, not yet a law. Shape decisions
added 2026-09-13.** Observability will become a universal law in laws:code. This file
records what the owner asked for, what the broader industry has settled on, the claims
strong enough to carry into the law, and the decisions that fix its shape. The law's
wording is not written here; it gets proposed separately and approved before it enters
the craft.

## What the owner asked for

Runtime observability of the resulting application, exclusively. Logging, metrics,
telemetry, and the systems for introspecting the project both while it is being built
and while it is running, so that its behavior can be understood.

Three states must all be understandable, not just the second:

1. when the system is working,
2. when it is not working,
3. when nobody yet knows whether it is working or not.

Two constraints on the law itself:

- It must be integrated from the beginning of a project. Bolted on later, it is thin,
  inconsistent, and missing where it is needed.
- It must obey every other law. Telemetry is code; it gets no exemption from single
  source of truth, boundary validation, or fail-loud.

Readings that were considered and rejected for this law: observability of the agent's
own work (evidence versus claims of "done"), observability of verification instruments
(tests that cannot fail), and visible claim status in documents. Those are real
concerns with other homes. This law is about the built system at runtime.

## Why it is its own law

The existing architectural laws are mostly static: make illegal states
unrepresentable, single source of truth, validate at the boundary. They close the
space of what can exist. Observability is the dynamic twin. For every state the type
system cannot forbid, the runtime must expose it. Static laws close the space of what
can exist; observability closes the space of what can happen unseen.

That is also why it does not fold into fail-loud. Fail-loud covers the moment of
failure. Observability covers the whole run, including the runs that succeed and the
runs whose outcome is unknown.

## The claims strong enough to be law

These are the industry's most law-shaped positions, restated as properties. The law
should state properties; mechanisms (which library, which backend, which three
pillars) are binding-level detail.

- **State is inferable from outputs, including for questions not asked in advance.**
  This is the control-theory definition and the one the industry converged on. A
  system you can only ask pre-planned questions of is monitored, not observable.
- **One wide event per unit of work is the source of truth. Everything else is a
  view.** Metrics, logs, and traces are three storage formats for the same facts.
  Keeping three independent copies is three sources of truth that will disagree. This
  is the single-source-of-truth law applied to telemetry.
- **Instrumentation lives in the substrate, not at each call site.** Google's Dapper
  worked because it sat in the RPC library and every service got it for free. The
  instrumentation nobody has to remember is the instrumentation that is actually
  there. This is also the mechanism behind "from the beginning": put it in the
  framework, the middleware, the base client, and it cannot be forgotten.
- **Zero and absent are distinct, and both must be visible.** A job that processed
  nothing emits a count of zero. A job that never ran emits nothing. A reader must be
  able to tell those apart, and the absence of a signal must itself be a signal.
- **The system explains its decisions, not only its outcomes.** Dry-run, explain, and
  plan modes let a reader see what the system will do and why before it does it.
  Which config source won, which branch was taken, why a retry happened.
- **Telemetry is code.** It is tested, versioned, and named by convention. It is
  subject to every other law.

## Concrete failures the law fires on

A law is only as good as the situations that trigger it. These are the shapes it must
catch:

- A script exits 0 having processed zero items, and nothing distinguishes "all done"
  from "did nothing."
- A catch-all swallows an exception and continues. The failure count reads zero
  because nothing counted.
- A retry loop succeeds on the fourth attempt. Nobody learns that three attempts
  failed.
- A cache with no hit-rate surface. You cannot tell whether it works or whether you
  are paying for two copies.
- A background job whose only status is running or not running.
- A config value read from one of three possible places, with no way to ask which one
  won.

## How the industry handles it

This section is reference depth for whoever writes the law or its bindings. Dates are
approximate and from memory.

### Definition and lineage

Kalman, 1960: a system is observable if its internal state can be reconstructed from
its outputs. Twitter's SRE team borrowed the word around 2013; Honeycomb's founders
made it a movement around 2016. Their definition stuck: you can ask any new question
about the system's behavior without shipping new code.

The distinction that carries the most weight is monitoring versus observability.
Monitoring answers known questions with pre-aggregated data: dashboards, thresholds,
alerts configured in advance. Observability answers unknown questions with raw,
high-cardinality data sliced after the fact. Monitoring catches the failures you
predicted; observability catches the ones you did not.

"Three pillars" (logs, metrics, traces) comes from a 2017 Peter Bourgon post and Cindy
Sridharan's 2018 O'Reilly book, and is still the common vocabulary. The now widely
accepted critique is that the pillars are three storage formats for the same facts.

### The consensus stack

**OpenTelemetry** is the standard. It merged OpenTracing and OpenCensus in 2019 under
the CNCF and is the second-largest CNCF project after Kubernetes. It provides a
vendor-neutral API, an SDK per language, a wire protocol (OTLP), a collector between
applications and backends, and semantic conventions that name attributes consistently.
Context propagates via the W3C Trace Context header. The practical rule: instrument
once with OpenTelemetry, export anywhere, swap vendors without touching code.

**Wide events** are the primitive. Stripe's canonical log lines (Brandur Leach, 2019)
emit one structured event per unit of work carrying everything known about it, dozens
of fields, high cardinality allowed. Charity Majors' "Observability 2.0" (2023)
generalizes it: store the wide events once and derive metrics, logs, and traces as
views. A trace is wide events with parent IDs. A metric is an aggregate over them.

**Structured logging** is the floor. Key-value or JSON, machine-parseable, one event
per line, and a correlation ID that ties every line of a request together.
Twelve-factor says the process writes to stdout and does not route or rotate its own
logs.

**What to measure** has three overlapping heuristics:

- Google SRE's four golden signals: latency, traffic, errors, saturation.
- Tom Wilkie's RED for services: rate, errors, duration.
- Brendan Gregg's USE for resources: utilization, saturation, errors.

**SLOs** are how the industry answers "is it working." A service level indicator
measures user-visible behavior. A service level objective is the target. An error
budget is the distance from breaching it. Alerts fire on budget burn rate, not on
causes. Rob Ewaschuk's "alert on symptoms, not causes" reorganized alerting around
this.

**Distributed tracing** descends from Google's Dapper paper (2010) through Zipkin and
Jaeger into OpenTelemetry. Dapper's lesson, cited everywhere: it lived in the RPC
library, so every service got it for free at under one percent overhead.

### The build-time side

Introspecting the project while it is being built is real but scattered across the
industry. The pieces:

- Debug endpoints: Go's `/debug/pprof` and expvar, Prometheus `/metrics`, Kubernetes
  liveness and readiness probes.
- Verbosity and explanation flags: `--verbose`, `--trace`, `--dry-run`, `--explain`,
  SQL `EXPLAIN ANALYZE`, Terraform plan, Nix `--show-trace`. Systems that explain
  their own decisions before or instead of acting.
- Attach-to-running-process introspection. Erlang and Elixir are the standout: the
  runtime ships `observer`, live tracing, and a REPL into the running node. Nothing
  else in mainstream use matches it.
- Local telemetry stacks: Jaeger all-in-one, Grafana's LGTM image, `otel-tui`. The
  production pipeline runs on the developer's machine during development.
- Continuous profiling (Pyroscope, Parca) and eBPF tools (Pixie, Cilium) that observe
  without code changes.

Honeycomb calls the practice observability-driven development: instrument as you
write, and a deploy is not done until you have looked at the telemetry it produced.
That is the closest the industry comes to "integrated from the beginning" as a stated
practice rather than a regret.

### The "unknown whether it is working" case

The least discussed of the three states and the most important. The industry's
answers:

- Absence is a signal. Prometheus has an `absent()` function specifically to alert
  when a metric stops arriving. Dead-man's switches and heartbeat services
  (Healthchecks.io, Cronitor) exist because no news means the reporter died, not that
  nothing happened.
- Counters that count zero. A job that processed zero items emits `items_processed=0`,
  which is distinguishable from not running.
- Synthetic probes. Exercise the path on a schedule and observe, instead of waiting
  for a user to hit it.
- SLOs turn "I don't know" into a number with a confidence interval, which is the
  only honest way to say "probably working."

## Tensions the law has to survive

- **Cardinality cost.** Metrics explode with labels. This is the real reason for the
  wide-events-versus-metrics fight, and it is a billing problem before it is a design
  problem.
- **Sampling.** Head sampling loses the interesting traces. Tail sampling requires
  buffering. Neither is free.
- **Secrets in telemetry.** Logs leak tokens and personal data constantly.
  OpenTelemetry ships redaction processors because the problem is universal.
- **Overhead.** Dapper's budget was under one percent. Instrumentation that slows the
  hot path gets ripped out.
- **Retrofitting.** Every practitioner who writes about this says the same thing:
  bolted-on observability is thin, inconsistent, and missing where it is needed. This
  is the empirical support for the "from the beginning" requirement. Existing code
  still has to be retrofitted; the section below says how without producing a bolt-on.
- **Fail-loud versus the hot path.** Telemetry obeys fail-loud, and instrumentation
  that breaks the hot path gets ripped out. These collide when the exporter is down:
  crashing the request because a log line could not be shipped turns a logging outage
  into a service outage. Resolved 2026-09-13: a telemetry failure is itself
  telemetry. Dropped events are counted and surfaced, and the work continues. Nothing
  fails silently, which is fail-loud's intent, and the hot path never depends on the
  telemetry pipeline being up.

## Retrofitting existing codebases

Proposed 2026-09-13, not yet owner-approved. Most code that will meet this law
already exists, so the law needs a stance on retrofits that produces something other than the thin bolt-on the industry warns
about. The stance follows from the substrate claim: a retrofit does not add telemetry
at call sites. It instruments the layer every unit of work already passes through, and
where no such layer exists it builds one first. That turns "add metrics to this
codebase" into two questions per domain: which layer does every unit of work pass
through, and if none does, what consolidation would create one.

The work, in the order that keeps each step cheap and the result consistent:

1. **Inventory the chokepoints.** The HTTP framework, the database client, the
   outbound client, the job runner, the command dispatcher. Each one gets the wide
   event and the correlation ID. Coverage grows with the number of chokepoints, not
   the number of call sites, which is why this step alone covers most of a codebase.
2. **Consolidate where there is no chokepoint.** Three hand-rolled HTTP clients, or
   requests assembled inline across the codebase, have no layer to instrument.
   Instrumenting each copy cements the duplication and yields the inconsistent
   bolt-on. The first move is to collapse the copies into one client, then instrument
   that. This is single source of truth applied to the retrofit itself.
3. **Give every job and script a summary event.** One structured line at exit with
   counts, including zero. This is the cheapest step and it closes the third state
   for the whole codebase: a job that ran and did nothing becomes distinguishable
   from a job that never ran.
4. **Fold existing log lines into the wide event over time.** Ad-hoc logging is not
   deleted in a sweep, and it is not the source of truth either. As the code around
   a log line is touched, its facts become fields on the unit of work's event. A
   metric that duplicates an existing log line is a second source of truth and is
   not added.
5. **Fix the naming convention before the first instrument lands.** The
   inconsistency of bolt-ons comes from each retrofit inventing its own names.
   Attribute names, event names, and units are settled once, up front.

The done criterion is the list of concrete failures above, used as an audit. Walk
the codebase for those six shapes: the zero-item exit 0, the swallowing catch-all, the
silent retry, the cache without a hit rate, the job that is only running or not, the
config value with no winner. Each one found is a ticket. The retrofit is done when
none of them can happen unseen.

In this repo's tooling that audit already has a home. Once the law has a token, the
sheriff audit cites it and produces the findings, and the posse skill implements them.
Retrofitting is the law plus the existing audit-and-remediation loop; it needs no
skill of its own. The audit's tell for a bad retrofit is telemetry added per call site
where a shared layer exists, because that is the shape that goes missing.

Where the guidance lives: the law carries one sentence, that in a retrofit
instrumentation lands in the substrate or the substrate is built first. The ordered
procedure is binding-level, since the chokepoints differ by domain. The six failure
shapes feed the sheriff.

## Where it goes

The recommended home is a new law token in laws:code, with domain bindings that say
what "observable" means concretely for a CLI, a service, a script, a schema migration.
Framed as the dynamic twin of the unrepresentable-states law.

Rejected placements:

- A clause under the existing fail-loud law. Wrong altitude; fail-loud is the moment of
  failure, this is the whole run.
- A design goal. That would steer how the laws are written, not what they say.
- A cross-craft principle. The other readings (agent process, verification, documents)
  were explicitly excluded from this law.

## Shape decisions, 2026-09-13

Three questions were open before wording. The owner settled them as follows.

- **The law names the three states directly.** Zero-versus-absent is the mechanism
  for the third state, but a reader who has not seen the states will not know why the
  distinction matters. The law opens with one line naming working, not working, and
  unknown, and zero-versus-absent appears as the tell for the third. It costs one
  sentence.
- **"From the beginning" is expressed through the substrate claim, as a place, not a
  library.** The law says instrumentation lives where the code already passes: the
  layer every unit of work goes through. Each binding names that layer for its
  domain. For a service it is the middleware and the base client; for a CLI, the
  entry point and command dispatch; for a script, the run wrapper that emits the
  summary event at exit; for a migration, the runner. The sheriff's tell is telemetry
  added per call site instead of in the shared layer.
- **The binding text cites specific laws by concept.** Single source of truth for
  "one wide event, everything else derived." Boundary validation for the outbound
  edge, which is where redaction lives. Unrepresentable states as the twin. Fail-loud
  with the resolution recorded under tensions: a telemetry failure is itself
  telemetry. The wording author maps these concepts to the current law tokens; this
  document names concepts, not tokens, so it does not go stale when a token is
  renamed.

Also decided: the fail-loud collision under tensions. The retrofit section above is a
proposal from the same date, awaiting owner review.

## Still open

- The law's wording. Proposed separately, approved before it enters the craft.
- Whether the retrofit procedure belongs in each domain binding or in a single
  binding-level section that every domain shares, with per-domain chokepoint lists.
