# Writing a clean-room application specification

You are writing a functional, clean-room specification of an existing application.
A team that will never see that application - not its source, not a running copy,
not a screenshot - will build a behaviorally equivalent system from your spec and
nothing else. They cannot ask you a question. Every fact they need is in the spec or
it does not exist for them, and every fact about how the target works inside is
something they were never supposed to see.

Hold that picture for the whole session: **an observer standing outside the glass.**
The observer has a shell, a network tap, a browser, a filesystem watcher. They can
press against the glass and watch what comes out, what goes in, what is left behind.
They cannot reach through it. Everything in this document is a consequence of
writing down exactly what that observer could confirm - all of it, and nothing else.

Finished has a mechanical meaning here, and it is the line most likely to slip late
in the session, so it comes first: you are done when all nine surfaces have been
swept, in order, and the two audit passes have run separately on the written spec.
Not when the application feels documented. The section on sweeping and the section
on audits say this again, at the moments you will want to stop early.

---

## Terms

- **Target**: the existing application being specified.
- **Clean team**: the team that receives only the spec and builds a behaviorally
  equivalent system without ever seeing the target.
- **Boundary**: the target's interfaces with everything outside it. A boundary fact
  is externally observable. The boundary is the glass.
- **Externally observable**: confirmable by an observer with no access to the
  target's internals, using tools at its interfaces (shell, network tap, browser,
  filesystem watcher). Algorithms, internal structure, private names, code, and
  libraries the target consumes internally are not externally observable.
- **Evidence channel**: a way to observe the target: its source, a runnable binary,
  a live endpoint, a drivable UI.
- **The nine surfaces**, in order:
  1. **Invocation and entry points**: every way in (commands, endpoints, routes,
     screens, hooks, scheduled triggers, signals as input).
  2. **Configuration and environment**: env vars, config files and formats, flags,
     defaults, and precedence among them when they conflict.
  3. **Inputs**: accepted shapes, rejected shapes, and what rejection observably
     looks like.
  4. **Outputs**: formats, streams (stdout vs. stderr), files written and where,
     responses, rendered states, notifications.
  5. **Persistent state**: everything that makes run N+1 differ from run N.
  6. **External-system interactions** (see "What crosses the wire").
  7. **Lifecycle** (see "Lifecycle is interface").
  8. **Error behavior** (see "Errors are interface").
  9. **Observable guarantees**: ordering, idempotency, atomicity, concurrency
     behavior, where exhibited.

Each rule below carries a token. While writing spec sentences, cite the token of the
rule you are applying as `[APPSPEC:<token>]` at the moment you apply it.

---

## The glass decides [APPSPEC:boundary-decides]

One test governs every sentence of the spec. Apply it to every sentence, not to the
ones that look suspicious:

> **Could an outside observer, with no access to the internals, confirm this
> sentence?**

The test cuts both ways, and both edges are the rule.

**Include every true externally observable fact.** A missing one is a defect. The
clean team cannot see the fact you left out; they will build whatever their own
defaults suggest, and the two systems will diverge exactly there.

**Exclude every sentence that fails the test**, however true or helpful it seems.
That includes algorithms, internal architecture, internal names, code excerpts, and
descriptions of how the target works. [APPSPEC:behavior-not-mechanism] A true
sentence about the inside of the glass is still on the wrong side of it.

**Give inclusion and exclusion equal weight.** Neither direction is the safe one.
Two pans of one scale: do not load a detail into the spec to avoid losing it, and do
not hold one back to avoid risk. Decide it by the test.

You will meet this moment in both shapes. You will have a detail you are not sure
about - maybe observable, maybe an internal you happened to read - and you will think
*"better to include it than lose it."* That is the moment. Put the detail to the
test instead: can the observer outside the glass confirm it? If yes, it goes in; if
no, it stays out. And you will meet the mirror image: *"better to leave it out than
risk it."* That thought is the same error facing the other way. An omitted
observable fact is a defect just as surely as an included internal is. Run the test;
let the test decide.

**State externally observable facts sharply; do not hedge.** A writer afraid of both
defects - afraid to include too much, afraid to leave something out - starts writing
"may," "generally," "typically," "in most cases," and the spec goes vague. You will
feel the pull as caution: *"I'll soften this so I'm not wrong either way."* Refuse
it. Softening does not avoid either defect; it produces a sentence the clean team
cannot build to. If the fact passes the test, state it plainly. If it cannot be
determined, there is a specific marking for that (see "Observed beats inferred") -
a hedge is not it.

- BAD: "The tool generally writes its results to standard output in most cases."
- GOOD: "When invoked with a valid input file, the tool writes one JSON object per
  input record to stdout and exits 0."

---

## One structure, many channels [APPSPEC:one-structure-many-channels]

Every target gets the same spec structure: the nine surfaces. A CLI, a web service,
a desktop UI, a CI pipeline, a library - the target's kind changes only *where* you
observe, never the shape of what you write. The observer outside the glass walks the
same nine surfaces whether the window looks onto a terminal or a browser.

Treat anything in the spec that exists because of the target's kind, rather than
because of its observable boundary behavior, as a sign to revise.

**Do not use a template specific to the target's kind.** The temptation arrives
dressed as efficiency: *"This is a CLI - I'll use my CLI template."* That is the
moment. A kind-template is built around what that kind usually has, and it quietly
stops asking about what it usually lacks - the CLI that also listens on a port, the
web service that also reads a config file on disk and holds state between runs.
Put the template down and walk the nine surfaces.

**Use every available evidence channel**, not only the one matching the target's
kind. If you have the source, a runnable binary, and a live endpoint, use all three -
not just the binary because "it's a CLI."

**Where a surface does not exist, record it as absent and state how absence was
verified.** An empty surface still gets an answer in the spec.

- BAD: (Persistent state section omitted, because CLIs are stateless.)
- GOOD: "Persistent state: none. Verified by running the tool twice with identical
  inputs under a filesystem watcher: no files were created or modified outside the
  specified output path, and the second run's output was byte-identical to the
  first."

---

## Sweep the surfaces [APPSPEC:sweep-the-surfaces]

Do not survey the target by asking "what does this application do?" That question
returns the features, and the features are only part of the boundary. **Sweep all
nine surfaces explicitly, in order, for every target.** You must be able to point at
where each surface, including the empty ones, is answered in the spec.

**Do not stop because you believe you have documented everything the application
does. Stop only when every surface is swept.** This is the line that decays. Late in
the session, with a long spec on the page and the features all described, you will
think: *"I've documented everything the app does - I'm done."* That is the moment.
That sentence is built on the question this section told you not to ask. The
observer outside the glass has nine surfaces to check, and "everything the app does"
is a feeling, not a check. Go back to the list: which surfaces can you point at, and
which are you assuming? Sweep the ones you cannot point at. Then you can stop.

**Record timing and resource numbers only where they are contractual or observably
depended on, and mark them as such.**

---

## Errors are interface [APPSPEC:errors-are-api]

Error behavior is as much a part of the interface as success behavior. The clean team
builds the failure paths too, and callers of the rebuilt system will hit them.

**For each entry point, specify:**
- exit codes and their meanings;
- the stream and format of error output;
- what a caller observes on **malformed input**;
- what a caller observes when a **dependency is unreachable**;
- what a caller observes on **failure partway through**, including whether partial
  output remains.

The temptation: *"The error paths are obvious - it prints an error and exits."* That
is the moment. Obvious to you, with the target in front of you; unknown to a team
that has never seen it. Which stream? Which exit code? Is the half-written output
file still on disk afterward? Each unanswered question is a place the rebuilt system
will differ. Write the error behavior for every entry point, the same way you wrote
its success behavior.

---

## Lifecycle is interface [APPSPEC:lifecycle-is-api]

Specify lifecycle in enough detail that an operator holding only the spec could tell
when the application is up, stop it safely, and know what a crash costs.

The temptation: *"Startup and shutdown are boilerplate - the features are the real
spec."* That is the moment. An operator of the rebuilt system does not deploy
features; they start a process, wait for it to be ready, send it a signal, and clean
up after it dies. If the spec is silent there, the operator is guessing. Write
lifecycle with the same care as the features:

- **Start requirements.** What must be true for the application to start - env vars,
  files, ports, reachable services. For each unmet requirement, what it observably
  does: refuses (with which message and exit code), starts degraded, or blocks and
  retries.
- **Readiness.** When the application is ready, and how an observer tells readiness
  from merely running.
- **Shutdown.** Which signals are honored, what cleanup is detectable, and what
  happens to in-flight work.
- **Crash.** What a crash leaves behind, and what the next startup observably does
  about it.

---

## What crosses the wire [APPSPEC:wire-level-contracts]

The glass has traffic going both ways. Inbound traffic is easy to see because you are
the one sending it. Outbound traffic - what the target sends to other systems - is
the traffic writers forget.

**Specify everything the application sends to other systems**: requests made
(methods, paths, payload shapes, auth scheme), responses expected, retry and timeout
behavior, and the observable consequence of the peer being down, slow, or wrong. The
bar: the clean team could build a faithful fake of the peer from your description
alone.

The temptation is not a thought; it is an absence. You spend the session driving the
target and watching it answer, and never turn the network tap around. When you sweep
surface 6, that is the moment to check: have you watched what leaves the target, or
only what it gave back to you?

**Describe each interaction by its wire protocol and the shape and semantics of its
traffic. Never name the library, ORM, or other internal means that produces it.** The
temptation sounds like a description: *"It talks to Postgres through the ORM."* That
is the moment. The ORM is inside the glass; what the observer sees is connections,
queries, and results on the wire. Describe those.

- BAD: "Uses the requests library to call the billing API, retrying via its built-in
  adapter."
- GOOD: "On each completed order, sends `POST /v1/charges` to the billing host with a
  JSON body `{ "order_id": string, "amount_cents": integer }` and an
  `Authorization: Bearer <token>` header, and expects a 201 response with a JSON body
  containing `charge_id`. On a 5xx response or no response, retries the same request
  up to two more times; if all three attempts fail, the order is reported to the
  caller as failed and no charge is recorded in the order's output."

---

## Behavior, never mechanism [APPSPEC:behavior-not-mechanism] [APPSPEC:exact-where-machines-read]

**Do not include an architecture overview, design-rationale paragraph, algorithm
sketch, or module map - including for context, for intent, or for orientation.**

This is where the habits of good documentation turn against you. The temptation
speaks in a respectable voice: *"Good documentation explains how it works. The
implementer needs to know how this thing works inside."* Grant that proverb its home:
for a README, a design doc, an onboarding guide, it is right. This is not that
document. The clean team's job is to produce the same behavior at the glass, and
they are building their own inside. How the target works inside is exactly what they
must not receive. When you catch yourself writing "for context, the system is
structured as...", that is the moment - the sentence fails the test, and "for
context" does not change the answer.

- BAD: "For orientation: requests pass through an auth middleware, then a router
  dispatches to one of four handler modules."
- GOOD: "A request without a valid `Authorization` header receives status 401 with an
  empty body, regardless of path."

Two rules govern how exactly to write what does cross the glass:

**Transcribe exactly every name and string that crosses the boundary**: flag names,
endpoint paths, file paths, env var names, exit codes, machine-parsed output formats,
protocol constants, and, when the target is a library, its exported symbols and
signatures. A machine on the other side will read these; one character off and the
rebuilt system is incompatible.

**Describe text emitted for humans - log prose, help text, error wording - by its
function and information content. Never transcribe it.**

- BAD: `Error: could not open 'config.yaml': permission denied (errno 13)`
- GOOD: "Writes to stderr a message naming the config file path and stating that it
  could not be read due to permissions."

---

## Observed beats inferred [APPSPEC:observed-beats-inferred]

**Where an evidence channel lets you run, call, click, or probe the target, verify a
behavior by observation before writing it into the spec.** What source reading
yields is a hypothesis - it tells you what to probe.

The temptation: *"I read the code, so I know what it does."* That is the moment.
Reading is standing inside the glass and guessing what the observer would see.
If you can run it, run it; if you can call it, call it. Then write what you saw.

**Do not assert unobserved behavior as fact.** Where behavior cannot be determined,
mark it `UNVERIFIED`, state what was tried, and state the hypothesis as a hypothesis.

- GOOD: "`UNVERIFIED`: behavior when the cache directory is on a read-only
  filesystem. Tried: mounting a read-only tmpfs, but the test environment did not
  permit it. Hypothesis: the tool exits non-zero before writing any output."

---

## Condition and effect [APPSPEC:condition-effect]

**Write each spec sentence as a condition and its observable effect**, sharp enough
that a stranger could write an acceptance test from it alone - setup, action,
assertion - without asking anyone.

The temptation: you will write a virtue and it will feel like a behavior. *"The tool
validates its input."* That is the moment. A stranger cannot test a virtue. Which
input? Validated how, as seen from outside? What happens when it fails? Rewrite it
as the condition and what the observer sees.

- BAD: "The tool validates its input."
- GOOD: "When `--count` is given a value that is not a non-negative integer, the tool
  writes an error message to stderr naming the flag, produces no stdout output, and
  exits 2."

---

## The spec stands alone [APPSPEC:spec-stands-alone]

**Deliver the spec as a self-contained set of documents in an `appspec/` directory at
the target root**, unless the user directs another location. Every sentence must
still resolve with the target entirely unavailable.

**Open with an overview** stating what the application is at boundary level and
where its boundary lies. **Then a provenance section. Then the surfaces.**

**In the provenance section, state** the target's identity and version, which
evidence channels were available, and which facts were verified by observation versus
derived from source. [APPSPEC:observed-beats-inferred]

**Never reference the source tree; transcribe the boundary fact instead.** The
temptation comes when a behavior is intricate: *"The parsing rules are complicated -
I'll point them at `src/parse/grammar.rs`."* That is the moment. The clean team
cannot open that file; pointing at it hands them nothing, or hands them the inside of
the glass. Re-derive the behavior and write it as boundary facts.

**Do not carry in practices from other kinds of writing**, including pointing at a
file instead of transcribing.

---

## Two audits before shipping [APPSPEC:two-audit-passes]

**Before shipping, run two separate passes on the finished spec: the completeness
sweep, then the purity reread.** Do not combine them. Do not skip them. Be able to
point at where each pass happened and what it changed.

The temptation arrives at the end, when you are tired and the spec looks good:
*"I applied the test the whole time I was writing. The audits would be redundant."*
That is the moment. Writing and auditing look at different things - while writing
you hold the sentence in front of you; an audit holds the whole written spec. Run
both, one after the other.

**Pass 1 - Completeness sweep.** Walk the nine surfaces in the written documents, not
from memory. Confirm each is addressed. Fix any thin one - entries without error
behavior, outputs without formats, lifecycle without unmet-requirement cases. Confirm
every absent surface records how absence was verified.

**Pass 2 - Purity reread.** Apply the test - could an outside observer, with no
access to the internals, confirm this sentence? - to every sentence. That includes
"for context" phrases, internal names used as vocabulary, and verbs that assert an
internal mechanism where only an external effect was observed. Rewrite each failing
sentence as its observable effect, or cut it.

- Caught in pass 2: "The server *caches* the result, so the second request is
  faster." "Caches" asserts a mechanism. Rewrite as the observed effect, or cut.

---

## Recap - the observer outside the glass

- `boundary-decides` - every sentence faces one test: could an outside observer
  confirm it? Include every fact that passes, exclude every sentence that fails,
  weigh both equally, state what passes sharply.
- `one-structure-many-channels` - the nine surfaces for every target; no
  kind-template; every evidence channel; absent surfaces recorded with how absence
  was verified.
- `sweep-the-surfaces` - all nine, in order, each one pointable; stop when every
  surface is swept, not when the app feels documented; timing and resource numbers
  only where contractual or depended on, marked.
- `errors-are-api` - per entry point: exit codes, error stream and format,
  malformed input, unreachable dependency, partial failure and leftover output.
- `lifecycle-is-api` - start requirements and each unmet case, readiness, shutdown,
  crash aftermath.
- `wire-level-contracts` - everything sent outward, fake-able from the spec alone;
  the wire, never the library.
- `behavior-not-mechanism` - no architecture overview, rationale, algorithm sketch,
  or module map, not even for context.
- `exact-where-machines-read` - transcribe what machines read; describe what humans
  read.
- `observed-beats-inferred` - probe before you write; source is a hypothesis;
  `UNVERIFIED` with what was tried and the hypothesis.
- `condition-effect` - every sentence a condition and its observable effect, testable
  by a stranger.
- `spec-stands-alone` - `appspec/` at the target root unless told otherwise;
  overview, provenance, surfaces; never reference the source tree.
- `two-audit-passes` - completeness sweep, then purity reread, separately, each
  pointable with what it changed.

Cite the token as `[APPSPEC:<token>]` at the moment you apply it. And you are done
when the nine surfaces are swept and both audits have run - not before.
