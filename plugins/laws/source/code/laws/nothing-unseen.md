## [LAW:nothing-unseen] - fly by instruments

<!-- rung: S -->
**A running system must expose enough of itself that its state can be reconstructed
from its outputs alone - for questions nobody thought to ask in advance - in all three
of its conditions: when it is working, when it is not, and when nobody yet knows
which. Instrumentation is built into the layer every unit of work passes through, from
the first commit, and is subject to every other law. The instrumentation of a change is
part of the change, as its tests are: the units of work the change touches emit their
event, and the facts the change introduces land on that event, in the same change.
What happens unseen did not reliably happen.**

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
visible.** A job that processed nothing emits `counts.items=0`. A job that never ran
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

**Instrumentation lives in the substrate, not at the call site.** The instrumentation
nobody has to remember is the instrumentation that is actually there. So it goes in the
middleware, the base client, the job runner, the command dispatcher - the one layer
every unit of work already passes through - and it is `[LAW:single-enforcer]` for
telemetry: one place emits, and a log line hand-placed inside a function is a
duplicate checkpoint that will drift from the canonical one. Telemetry per call site
where a shared layer exists is the tell. This is also the whole mechanism behind "from
the beginning." Bolted-on observability is thin, inconsistent, and missing where it is
needed, and every practitioner who has retrofitted one says so. Put it in the substrate
on day one and it cannot be forgotten on day two hundred.

**The system explains its decisions, not only its outcomes.** Which of three config
sources won. Which branch of the union was taken. Why the retry fired. A dry-run, a
plan, an `--explain` that shows what the system *will* do before it does it. A record
that says only "succeeded" is a photograph of the landing with no flight recorder.

**Telemetry is code.** It is typed, tested, versioned, and named by one convention.
It gets no exemption from any other law: the outbound edge where events leave the
process is a boundary like any other, with one checkpoint (`[LAW:single-enforcer]`),
and `laws:code-observability` says what that checkpoint does. And it obeys
`[LAW:no-silent-failure]` in the one way that does not take the aircraft down with the
panel: **a telemetry failure is itself telemetry.** When the exporter is unreachable,
the request does not crash; the dropped events are counted and surfaced, and the work
continues. Nothing fails silently, which is fail-loud's entire intent, and the hot path
never depends on the telemetry pipeline being up.

**Observability is a property of the code's shape, not of the sink.** The panel is the
instruments and the wiring that feeds them; where the readings get written down
afterward is a detail of the hangar. A system whose export edge appends every event to
a local file is fully observable: every fact about every run exists, under its
correlation ID, and can be sliced by a dimension nobody has named yet, the moment
someone opens the file. A system wired to a trace store, with instruments hand-placed
at last quarter's incident sites, is blind, and the store cannot show what the code
never emitted. Which sink the edge writes to is a configuration value, changed without
touching the code. Whether there is anything to write is decided by the code's shape,
and no configuration can change that. So the voice that says *"there's no backend yet -
I'll instrument once it exists"* has the dependency backwards: the backend is the last
thing to arrive and the one thing the shape does not wait on. Build the edge, point it
at a file, and the day the store exists is a config change and nothing else.

**"We have dashboards."** Dashboards are monitoring, and monitoring answers questions
you thought to ask in advance, with data pre-aggregated to answer only those. It
catches the failures you predicted. This law is about the ones you did not: raw,
high-cardinality records you can slice by a dimension you had no reason to name until
the incident named it for you. A system you can only ask pre-planned questions of is
monitored, not observable.

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
    # exit, one record per run:
    # {"event":"sync","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",
    #  "service":"inventory-sync","started_at":"2026-09-29T03:00:00Z",
    #  "duration_ms":4,"outcome":"ok",
    #  "sink":"file","sink_error":"connection refused",
    #  "counts":{"items":0,"attempts":0,"pushed":0,"failed":0,"retries":0}}
    # counts.items=0 is a fact. No record at all is a different fact. Both are visible.
    # sink=file with sink_error set: the exporter was down; the record exists anyway.
```

<!-- rung: M -->
The temptation arrives as: *"I'll get it working first and add logging after."* Refuse
it. "After" produces exactly the thin, inconsistent bolt-on the law exists to prevent,
because instrumentation added once the shape is set goes where the incidents were, not
where the work flows. The redirect: the first thing built is the layer every unit of
work passes through, and the event goes in there before the first unit does. The same
voice, on a change to code that already runs, says *"I'll ship the feature and file the
instrumentation as a follow-up."* Refuse that too, for the reason you would refuse to
file the tests as a follow-up: the follow-up is the task that never lands, and the
change flies into cloud with no panel. The units of work the change touches emit their
event, and the facts the change introduces - the new count, the new branch, the new
config source - land on that event, in the same change. What the shared layer is in
each domain, the floor a codebase stands up first, and the order coverage grows in when
the codebase already exists, are `laws:code-observability`'s job. Load it on two
triggers: when you are writing instrumentation or retrofitting it, and on first contact
with a codebase whose units of work emit nothing. The second trigger is the one that
gets missed: a session doing feature work in an uninstrumented codebase is not writing
instrumentation, would never think to load the bindings, and is exactly the session
that has to stand the floor up before its change can fly.

<!-- rung: S -->
Diagnostic: *if this ran at 3 a.m. and did nothing, could anyone tell that from it not
having run - and could they say, from the outputs alone, why it did what it did?*

<!-- rung: S -->
Dynamic twin of `[LAW:types-are-the-program]` - the type closes what can exist, the
panel closes what can happen unseen - and an instance of `[FRAMING:representation]`: the
telemetry is the map of the run, an absent map is not a blank territory, and a map
drawn at the call site is one that drifts. Sibling of `[LAW:no-silent-failure]` and
`[LAW:verifiable-goals]`: loud failure and a checked "done" are what make the panel
worth reading.
