# Observability, written at law altitude

**2026-09-13, draft. Not in the craft.** This is `design-docs/observability.md`
rewritten in the shape and register of a law entry in laws:code, so the owner can judge
the wording against the real thing before any of it enters the craft. The brainstorm
doc stays the source of intent; this file is the candidate expression. The token below
is proposed, not canonical, and nothing here is citable until the owner approves it.
The retrofit procedure appears once, as a binding section shared by every domain, which
answers the brainstorm doc's last open question by example.

---

## [LAW:nothing-unseen] - fly by instruments

**A running system must expose enough of itself that its state can be reconstructed
from its outputs alone - for questions nobody thought to ask in advance - in all three
of its conditions: when it is working, when it is not, and when nobody yet knows
which. Instrumentation is built into the layer every unit of work passes through, from
the first commit, and is subject to every other law. What happens unseen did not
reliably happen.**

A pilot can fly by sight until the cloud comes. Inside cloud, the only aircraft that
survives is the one whose panel was built and trusted long before it was needed:
altitude, attitude, heading, fuel, each on its own instrument, each reading *zero* when
the quantity is zero and *dead* when the instrument has failed - and the pilot can tell
those two apart. A system with no panel flies fine in daylight. Every system enters
cloud eventually: the traffic pattern shifts, a dependency degrades quietly, a job runs
against an empty table for a week. The question the law asks is not "does it work" but
"how would you know."

The static laws close the space of what can *exist*: illegal states unrepresentable,
one source per fact, papers checked at the border. This law is their dynamic twin. For
every state the type system cannot forbid - a retry storm, a cache that never hits, a
job that ran and did nothing - the runtime must *expose* it. Static laws close the
space of what can exist; this one closes the space of what can happen unseen. That is
also why it is not a clause of `[LAW:no-silent-failure]`: fail-loud covers the moment
of failure, and this law covers the whole run, including the runs that succeed and the
runs whose outcome nobody can name.

The boundary of this law is the built system at runtime. Observability of an agent's
own work, of the verification instruments, of claim status in a document - those are
real concerns with other homes, and this law does not reach them.

**Three conditions, and the third is the one that kills.** Working and broken are the
conditions everyone instruments for. The third - *unknown* - is where systems die
quietly, and it has one tell: **zero and absent are different facts, and both must be
visible.** A job that processed nothing emits `items_processed=0`. A job that never ran
emits nothing. If your telemetry cannot separate those two, then "no news" means
either "all quiet" or "the reporter is dead," and you will read it as the first every
time until the day it was the second. Absence of a signal is itself a signal, and the
instrument that reports absence has to exist before the absence does.

**One wide event per unit of work is the source of truth; everything else is a view.**
Every request, every job run, every command invocation emits one structured record
carrying everything known about it - who, what, how long, which branch, how many
retries, which config won - under one correlation ID. Metrics are aggregates over those
records; traces are those records with parent IDs; log lines are fields on them.
Three independently maintained copies of the same facts are `[LAW:one-source-of-truth]`
violated three ways, and they will disagree at exactly the hour you need them to
agree.

**Instrumentation lives in the substrate, not at the call site.** Google's Dapper
worked because it sat in the RPC library and every service got tracing for free; the
instrumentation nobody has to remember is the instrumentation that is actually there.
So it goes in the middleware, the base client, the job runner, the command dispatcher -
the one layer every unit of work already passes through - and it is `[LAW:single-enforcer]`
for telemetry: one place emits, and a log line hand-placed inside a function is a
duplicate checkpoint that will drift from the canonical one. This is also the whole
mechanism behind "from the beginning." Bolted-on observability is thin, inconsistent,
and missing where it is needed, and every practitioner who has retrofitted one says
so. Put it in the substrate on day one and it cannot be forgotten on day two hundred.

**The system explains its decisions, not only its outcomes.** Which of three config
sources won. Which branch of the union was taken. Why the retry fired. A dry-run, a
plan, an `--explain` that shows what the system *will* do before it does it. A record
that says only "succeeded" is a photograph of the landing with no flight recorder.

**Telemetry is code.** It is typed, tested, versioned, and named by one convention.
It gets no exemption from any other law: the outbound edge where events leave the
process is a boundary, and `[LAW:parse-dont-validate]` applies there - redaction of
secrets happens at that one checkpoint, not scattered through call sites. And it obeys
`[LAW:no-silent-failure]` in the one way that does not take the aircraft down with the
panel: **a telemetry failure is itself telemetry.** When the exporter is unreachable,
the request does not crash; the dropped events are counted and surfaced, and the work
continues. Nothing fails silently, which is fail-loud's entire intent, and the hot path
never depends on the telemetry pipeline being up.

Now disarm the proverbs that will be quoted at you.

**"We have dashboards."** Dashboards are monitoring, and monitoring answers questions
you thought to ask in advance, with data pre-aggregated to answer only those. It
catches the failures you predicted. This law is about the ones you did not: raw,
high-cardinality records you can slice by a dimension you had no reason to name until
the incident named it for you. A system you can only ask pre-planned questions of is
monitored, not observable.

**"Logging is noise."** It is, when it is scattered log lines at pixel resolution -
that is the failure of a *call-site* practice, not of observability. One wide event per
unit of work is the opposite of noise: it is the smallest complete record, emitted once,
from one place. Volume is the symptom of instrumenting in the wrong layer.

**"That's an ops concern / a library choice."** Which backend, which SDK, which
exporter - those are binding-level detail and mostly settled (OpenTelemetry is the
consensus). Whether the system *can be understood from its outputs* is a property of
the code's shape, decided by whoever writes the substrate, and no backend can add it
afterward.

FORBIDDEN shapes - on sight, these are bugs:
- A script exits 0 having processed zero items, and nothing distinguishes "all done"
  from "did nothing."
- A catch-all swallows an exception and continues; the failure count reads zero
  because nothing counted.
- A retry loop succeeds on the fourth attempt and nobody learns that three failed.
- A cache with no hit-rate surface - you cannot tell whether it works or whether you
  are paying for two copies.
- A background job whose only visible states are running and not running.
- A config value read from one of three possible places, with no way to ask which one
  won.

WRONG - the daylight script, silent in cloud:

```python
def sync(items):
    for item in items:
        try:
            push(item)
        except Exception:
            pass          # "transient, it'll get picked up next run"
    return 0
# Ran against an empty list for nine days. Ran against a dead endpoint for three more.
# Exit code 0 every time. Nobody could tell either from a good night.
```

RIGHT - the same script, instrumented in the run wrapper, one record per run:

```python
@run_event("sync")             # substrate: every job gets this, none remembers to
def sync(items, run):
    for item in items:
        run.attempt(push, item)   # counts attempts, failures, retries - per run
    # exit: {"job":"sync","items":0,"pushed":0,"failed":0,"duration_ms":4}
    # items=0 is a fact. No record at all is a different fact. Both are visible.
```

The temptation arrives in two voices. The first, on new code: *"I'll get it working
first and add logging after."* Refuse it. "After" produces exactly the thin,
inconsistent bolt-on the law exists to prevent, because instrumentation added once the
shape is set goes where the incidents were, not where the work flows. The redirect:
the first thing built is the layer every unit of work passes through, and the event
goes in there before the first unit does. The second voice, on existing code: *"the
codebase already exists - I'll add metrics around the part that broke."* Refuse that
too; a metric at the incident site is a call-site instrument, which is the shape that
goes missing. The redirect is the same substrate, arrived at from the other side: find
the layer every unit of work already passes through and instrument there, and where no
such layer exists - three hand-rolled HTTP clients, requests assembled inline - build
it first. In a retrofit, instrumentation lands in the substrate or the substrate is
built; the bindings below carry the order of work.

Diagnostic: *if this ran at 3 a.m. and did nothing, could anyone tell that from it not
having run - and could they say, from the outputs alone, why it did what it did?*

Dynamic twin of `[LAW:types-are-the-program]` - the type closes what can exist, the
panel closes what can happen unseen - and an instance of `[FRAMING:representation]`: the
telemetry is the map of the run, an absent map is not a blank territory, and a map
drawn at the call site is one that drifts. Sibling of `[LAW:no-silent-failure]` and
`[LAW:verifiable-goals]`: loud failure and a checked "done" are what make the panel
worth reading.

---

## Domain bindings for `[LAW:nothing-unseen]`

Bindings sharpen the law for a domain; they never weaken it. The law says
instrumentation lives in the substrate. Each binding names what the substrate *is*.

**Services**
- The substrate is the request middleware and the base outbound client. One wide event
  per request, correlation ID propagated on the wire (W3C Trace Context).
- Measure at the boundary the code owns: rate, errors, duration - the RED triple - and
  saturation of anything that can fill.
- "Is it working" is a service-level objective over user-visible behavior; alert on
  the symptom the user sees, never on a cause.
- A path nobody has hit yet is in the unknown condition. Synthetic probes exercise it
  on a schedule so the panel reads something before a user does.
- The process exposes its own introspection surface - a metrics endpoint, a health
  probe, a profiling endpoint - so a running instance can be asked, not only read.

**CLI**
- The substrate is the entry point and the command dispatcher. One event per
  invocation: command, arguments as parsed, exit code, duration.
- `--dry-run` / `--explain` are the decision surface: what the command will do and
  which inputs decided it, before it acts.
- Exit codes are a contract; the event and the exit code say the same thing.

**Scripts and background jobs**
- The substrate is the run wrapper: one summary event at exit with every count,
  including zero. This is the cheapest binding and it closes the third condition
  for the whole codebase.
- A scheduled job also emits a heartbeat; the absence of the heartbeat is alerted on
  (`absent()` in Prometheus, a dead-man's switch anywhere else). No heartbeat means
  the reporter died, not that nothing happened.
- Status is never a boolean. Running, idle, last run at, last run's counts, last
  failure and why.

**Data and schema**
- The substrate is the migration runner. One event per migration: rows touched,
  duration, which step, rollback taken or not.
- A pipeline stage declares its inputs and outputs (pipelines binding); the event
  records the counts on both sides, so a stage that consumed 10,000 and produced 0
  is a visible fact, not a quiet one.

**Distributed systems**
- The trace is the wide event with parent IDs; the correlation ID crosses every hop
  or the record is broken at that hop.
- Failure modes are instrumented like success paths - designed, not appended - because
  a failure mode with no signal is the unknown condition by construction.

**Caches, retries, config**
- A cache exposes hits, misses, and evictions, or it is two copies with a hope.
- A retry loop records every attempt on the unit of work's event; the fourth-attempt
  success carries the three failures with it.
- A config value read from several sources records which one won, on the event, so
  the question "which config is live" has an answer without a debugger.

**Retrofitting an existing codebase** - one shared procedure, in the order that keeps
each step cheap and the result consistent:
1. Inventory the chokepoints the domain binding names. Each gets the wide event and the
   correlation ID. Coverage grows with the number of chokepoints, not call sites, which
   is why this step alone covers most of a codebase.
2. Where there is no chokepoint, consolidate first: collapse the copies into one client
   or one runner, then instrument that. Instrumenting each copy cements the duplication
   (`[LAW:one-source-of-truth]` applied to the retrofit itself).
3. Give every job and script the run wrapper and its summary event, including zero.
4. Fold existing ad-hoc log lines into the wide event as the code around them is
   touched. No sweep deletion; no new metric that duplicates a log line.
5. Fix attribute names, event names, and units before the first instrument lands; the
   inconsistency of bolt-ons comes from each retrofit inventing its own.
   The done criterion is the FORBIDDEN list, walked as an audit; each shape found is a
   ticket, and the retrofit is done when none of them can happen unseen. In this repo
   that audit is the sheriff and the remediation is the posse; no new skill is needed.
   The tell for a bad retrofit is telemetry per call site where a shared layer exists.

**What every binding must survive**
- Cardinality has a bill. Wide events tolerate high cardinality; metric labels do not.
  Derive metrics from events; never put a user ID in a label.
- Sampling loses something either way: head sampling drops the interesting traces,
  tail sampling buffers. Choose one on purpose and record the choice on the event.
- Secrets leak through telemetry constantly. Redaction is a single checkpoint at the
  outbound edge, never a per-call-site scrub.
- Overhead is budgeted, and Dapper's budget - under one percent - is the reference.
  Instrumentation that slows the hot path gets ripped out, and once it is ripped out
  the system is back in cloud.

---

## The lineage, for whoever writes the bindings

Kept short here; the full survey is in `design-docs/observability.md`. Kalman, 1960: a
system is observable when its internal state can be reconstructed from its outputs.
Honeycomb's restatement, around 2016: you can ask a new question without shipping new
code. The three pillars (logs, metrics, traces; Bourgon 2017, Sridharan 2018) are the
common vocabulary, and the accepted critique is that they are three storage formats for
the same facts. Stripe's canonical log lines (2019) and Charity Majors' "Observability
2.0" (2023) are the wide-event primitive. OpenTelemetry is the consensus API, SDK, wire
protocol, and semantic-convention set. Google SRE's four golden signals, RED, and USE
say what to measure. SLOs and error budgets are how the industry turns "unknown" into a
number with a confidence interval. Dapper (2010) is the substrate lesson. Honeycomb's
observability-driven development is the closest stated practice to "from the
beginning": a deploy is not done until you have looked at the telemetry it produced.
The build-time side is scattered but real: debug endpoints (`/debug/pprof`, `/metrics`,
liveness probes), explain flags (`--dry-run`, `EXPLAIN ANALYZE`, `terraform plan`),
attach-to-process introspection (Erlang's `observer` is the standout), local telemetry
stacks that run the production pipeline on the developer's machine, and continuous
profiling that observes without code changes.

---

## In the recap

Under **Observable correctness**, alongside the three already there:
`[LAW:verifiable-goals]` gives done a shape, `[LAW:behavior-not-structure]` tests the
contract not the plumbing, `[LAW:no-silent-failure]` guarantees that when reality
disagrees you hear it - and `[LAW:nothing-unseen]` guarantees there is a panel to hear
it on, reading zero when it is zero and dead when it is dead, built before the cloud.
