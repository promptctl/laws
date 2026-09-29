# `laws:code-observability` - skill specification

Scope: what the skill must contain - what a fully observable system looks like, the
smallest shape that satisfies the law, how to find the shared layer in each domain, what
each domain's event carries, how coverage grows across a codebase that has no shared
layer, and the constraints every binding has to survive. The law itself is specified in
`design-docs/observability-north-star.law.md` and is never restated here. The lineage
and industry survey stay in `design-docs/observability.md`.

This specifies content, not wording. Bracketed line numbers cite
`design-docs/observability-law.md` unless another file is named.

## Terms

- Unit of work: one request, job run, command invocation, or migration.
- Event: the one structured record a unit of work emits, carrying everything known about
  it under one correlation ID.
- Shared layer: the one layer every unit of work already passes through, such as request
  middleware, a base outbound client, a job runner, or a command dispatcher.

## Requirements

### Relation to the law

1. Cite `[LAW:nothing-unseen]` and do not restate it. Requirements 2-32 sharpen the law
   for one domain or one phase of the work and never relax it; a binding that seems to
   conflict with the law has been misread. [173-174; `code/SKILL.md`:1030-1033]

### Objections raised during the work

2. Treat high telemetry volume as the symptom of instrumenting at call sites rather than
   in the shared layer, not as a reason to drop the one event per unit of work. Failure:
   "logging is noise" is offered as an argument against instrumenting. [97-100]
3. Do not treat observability as settled by the choice of backend, SDK, or exporter;
   those are binding-level detail, while whether the system can be understood from its
   outputs is a property of the code's shape and is decided by whoever writes the shared
   layer. Failure: observability is dismissed as an ops concern or a library choice.
   [102-106]

### The end state

3a. State, as properties of a running system and not as a tool list, what a fully
    instrumented system has, so a session that has never seen that standard can read it
    as a checklist of what is still missing: (a) one wide event per unit of work under a
    trace ID that crosses every hop; (b) metrics, traces, and logs as views over those
    events; (c) rate, errors, duration, and saturation at every boundary the system owns;
    (d) objectives on user-visible symptoms, with alerts only on those and on missing
    heartbeats; (e) an introspection surface per process; (f) the event schema as a type,
    with tests that assert the event and its fields the way tests assert a return value;
    (g) redaction at one export edge; (h) telemetry failures counted and surfaced.
    Requirements 4-32 are how each property is reached. [owner target 2026-09-27]

### The floor

3b. State the smallest shape that satisfies the law and ships in the first commit before
    any backend exists: a wrapper on the shared layer that opens and closes the event, an
    event type, one call that adds a fact to the current event, and one export edge.
    [owner decision 2026-09-27]
3c. Make the export edge speak OTLP to an address read from configuration, and append
    JSONL to a local file when that address is absent or unreachable, counting the drop
    on the next event. A codebase with only the file sink is fully observable; pointing
    the edge at a store later is a configuration change, not a code change. Failure: the
    shape waits on the infrastructure. [law req. 11, 11a]
3d. Name the OpenTelemetry SDK as the usual source of the floor in any language, and name
    nothing else: no collector, no store, no hostname, no client library. Those belong to
    the consumer's own environment guidance. Failure: a public skill carries one user's
    infrastructure. [owner decision 2026-09-28]
3e. Give every codebase the same starting field set, so no session designs names:
    `event`, `trace_id`, `service`, `started_at`, `duration_ms`, `outcome`, `error`, and a
    `counts` object whose keys are the unit of work's counts including zeros. A codebase
    adds fields; it never renames these and never runs a parallel set. [owner decision
    2026-09-29; sharpens requirement 23]

### Services

4. The shared layer is the request middleware and the base outbound client: one event per
   request, with the correlation ID propagated on the wire using W3C Trace Context.
   [177-179]
5. Measure at the boundary the service owns: rate, errors, and duration, plus the
   saturation of anything that can fill. [180-181]
6. Express "is it working" as a service-level objective over user-visible behavior, and
   alert on the symptom the user sees, never on a cause. [182-183]
7. Exercise paths no user has hit yet with synthetic probes on a schedule, so they report
   before a user reaches them. [184-185]
8. Expose an introspection surface from the process - a metrics endpoint, a health probe,
   a profiling endpoint - so a running instance can be asked, not only read. [186-187]

### CLI

9. The shared layer is the entry point and the command dispatcher: one event per
   invocation carrying the command, the arguments as parsed, the exit code, and the
   duration. [189-190]
10. Make `--dry-run` / `--explain` the decision surface: what the command will do and
    which inputs decided it, before it acts. [191-192]
11. Treat exit codes as a contract, and make the event and the exit code say the same
    thing. This sharpens the existing CLI binding in laws:code ("Exit codes are a
    contract, not just 0/1") and does not replace it. [193; `code/SKILL.md`:1063]

### Scripts and background jobs

12. The shared layer is the run wrapper: one summary event at exit carrying every count,
    including counts of zero. [196-198]
13. Make a scheduled job emit a heartbeat and alert on the heartbeat's absence; a missing
    heartbeat means the reporter died, not that nothing happened. [199-201]
14. Never expose a job's status as a boolean: expose running, idle, last run time, the
    last run's counts, and the last failure with its reason. [202-203]

### Data and schema

15. The shared layer is the migration runner: one event per migration carrying rows
    touched, duration, which step, and whether a rollback was taken. [206-207]
16. Record on a pipeline stage's event the counts on both sides of its declared inputs
    and outputs, so a stage that consumed input and produced nothing is a visible fact.
    This sharpens the existing pipelines binding in laws:code ("Staged with explicit
    I/O"). [208-210; `code/SKILL.md`:1048-1050]

### Distributed systems

17. Carry the correlation ID across every hop; a hop that drops it breaks the record
    there. [213-214]
18. Instrument failure modes the way success paths are instrumented, as part of their
    design rather than appended afterward. This sharpens the existing distributed binding
    in laws:code ("Failure modes are documented like success paths"). [215-216;
    `code/SKILL.md`:1054-1055]

### Caches, retries, and config

19. Make a cache expose its hits, misses, and evictions. [219]
20. Record every attempt of a retry loop on the unit of work's event, so a success after
    failed attempts carries those failures with it. [220-221]
21. When a config value can be read from several sources, record on the event which
    source won. [222-223]

### How coverage grows across an existing codebase

21a. State that requirements 23-27 are the order coverage grows across many changes,
    not a program one session runs to completion: each change stands up the floor if it
    is absent, instruments the units of work it touches with the facts it introduces,
    and stops. Coverage grows the way test coverage grows. Failure: a session either
    launches a whole-repo retrofit or, seeing that as the only move, does nothing.
    [owner decision 2026-09-27; law req. 11b]
22. Do not instrument the part that broke; carry out requirements 23-27 in order.
    Failure: on existing code, writers add a metric at the incident site, which is a
    call-site instrument and the shape that goes missing. [151-157, 225-226]
23. First, fix attribute names, event names, and units before the first instrument
    lands, starting from requirement 3e's field set rather than a blank page. [236-237; moved from fifth to first on 2026-09-27 because the draft's own
    wording, "before the first instrument lands", puts it ahead of every other step]
24. Second, inventory the shared layers requirements 4, 9, 12, and 15 name for the
    domains present, and give each one the event and the correlation ID. [227-229]
25. `[LAW:one-source-of-truth]` Third, where no shared layer exists - three hand-rolled
    HTTP clients, requests assembled inline - consolidate the copies into one client or
    one runner and then instrument it; instrumenting each copy cements the duplication.
    [230-232, 154-156]
26. Fourth, give every job and script the run wrapper of requirement 12 and its summary
    event, including zero. [233]
27. Fifth, fold existing ad-hoc log lines into the event as the code around them is
    touched: no sweep deletion, and no new metric that duplicates a log line. [234-235]
28. Make the done criterion the law's forbidden shapes (north-star requirement 12),
    walked as an audit: each shape found is a ticket, and the retrofit is done when none
    of them can happen unseen. In this repo the audit is `sheriff-is-in-town` and the
    remediation is `form-a-posse`; the skill defines no audit loop of its own. [238-240]

### What every binding must survive

29. `[LAW:parse-dont-validate]` The outbound edge where events leave the process is a
    boundary: redact secrets at that one checkpoint, never scattered through call sites.
    Failure: secrets leak through telemetry constantly. [80-81, 248-249]
30. Keep high cardinality on events and derive metrics from them; a metric label never
    carries a user ID. [244-246]
31. Choose head or tail sampling on purpose, and record the choice on the event.
    [246-247]
32. Budget instrumentation overhead, with under one percent as the reference. Failure:
    instrumentation that slows the hot path gets ripped out, and once it is ripped out
    the system is unobserved again. [250-252]

### What the skill does not carry

32a. Carry no workflow: nothing about tickets, sessions, reviews, or when a unit of work
    is done. Those are the consumer's process. [owner decision 2026-09-27]

### The artifact

33. Write the skill at `plugins/laws/skills/code-observability/SKILL.md`, with
    frontmatter `name: code-observability` and a description that states when to load it.
    [repo convention: `plugins/laws/skills/*/SKILL.md`]
34. Trigger the description on: writing or reviewing instrumentation, logging, metrics,
    tracing, or telemetry; deciding what a new service, CLI, or job must emit;
    first contact with a codebase whose units of work emit nothing; retrofitting an
    existing codebase; and acting on a `[LAW:nothing-unseen]` finding.
    Because the bindings live here rather than in laws:code, this description is the only
    path a session holding laws:code has to them. [decision, not from the source]
35. This is a code-medium skill: it may be held beside laws:code, and must not be stacked
    with laws:prompt. [`.claude/skills/laws/SKILL.md` rule 1]
36. Carry no lineage or industry survey; cite `design-docs/observability.md` for both.
    [256-274]
37. Have the code this skill produces cite `// [LAW:nothing-unseen] reason` at the point
    of use, as laws:code requires of every law. [`code/SKILL.md`:27-29]
