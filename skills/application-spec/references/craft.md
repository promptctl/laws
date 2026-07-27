<!--
  Style authority for future edits to this file: skills/prompt/references/craft.md
  (far-end regime — amplitude, images, rehearsed temptations, disarmed proverbs,
  negative examples, stakes register). The specifications this file teaches are NOT
  its style authority: a spec is exact and stated-once; this guidance must keep
  firing deep in a long session. Cut only what is wrong, never what repeats.
-->

# Writing a clean-room application spec

You are about to spend a long session producing one artifact: a functional,
clean-room specification of an existing application. A team that has never seen
the target — and never will — receives your spec and nothing else, and builds a
behaviorally equivalent system from it. You are on the contaminated side: you have
read the source, run the binary, probed the endpoints. The spec is the only thing
that crosses to the clean side, and it makes one trip. That is mechanics, not
drama — but it is the mechanics everything below follows from.

## The boundary test [APPSPEC:boundary-decides]

**The application's boundary decides every sentence of the spec, in both
directions.** A fact observable from outside — an invocation form, an output
shape, an exit code, a request the app sends elsewhere — belongs in the spec;
leaving it out is a defect (the reimplementation silently diverges). A fact
visible only from inside — an algorithm, an internal structure, a private name, a
line of code — must not appear; including it is a defect (the clean-room guarantee
is void). Two directions of one test, applied to every sentence:

> **Could an outside observer, with no access to the internals, confirm this
> sentence?** Yes → it is spec, and if true and missing, the spec is incomplete.
> No → it is not spec, no matter how helpful it feels.

The image to keep in hand all session: **the app is a sealed case with ports.**
You stand at the case with instruments — a shell, a network tap, a browser, a
filesystem watcher. Anything an instrument at a port can read is a boundary fact:
record it. Anything that requires opening the case is a gear: leave it inside. The
whole craft is *every port, no gears*.

Hold the directions with equal weight. Contamination and omission are symmetric,
ordinary defects with real costs: a leaked gear voids the legal premise; a missed
port ships a different application. Neither calls for dread — a writer frightened
into hedging produces a vague spec, which fails the mission as surely as a
contaminated one. Sharp facts you are entitled to, state sharply: `exits 3` and
`refuses to start without $DATABASE_URL` are outside-observable, and saying them
plainly is the job, not a risk. The test is a level held against a shelf — use it
constantly; fear it never.

The temptation is the instinct that one direction is "safe": *"this detail is
borderline — better to include it than lose it"* (or its twin, *"better to leave
it out than risk it"*). Refuse both; there is no safe direction, only the test.
Borderline is not a category — it is a sentence you haven't tested yet.

- BAD: "Uploads are processed in parallel by a worker pool." (a gear, asserted as
  useful context)
- GOOD: "Two uploads submitted concurrently both complete; completion order is
  not guaranteed (both orders observed)."

Diagnostic: for the sentence you just wrote — which instrument, at which port,
confirms it?

## One structure, every target [APPSPEC:one-structure-many-channels]

The target may be a repo, a CLI, a UI, a SaaS, a CI system — anything with a
boundary. **The kind of target never changes what the spec looks like; it only
changes where you stand to observe.** Source, a runnable binary, a live endpoint,
a drivable UI are **evidence channels** — ways of holding instruments to the case
— and you use *every channel available*, not the one matching the target's genre
(a repo usually gives source *and* a runnable build: use both). The spec's
structure — the sweep below — is invariant. Same case, same ports, different
instruments: a CLI's port is argv/stdin/stdout, a service's is HTTP, a UI's is
what a user can do and see.

The temptation arrives dressed as efficiency: *"this is a CLI — I'll use my CLI
template."* Refuse it. Per-kind templates are the named anti-pattern: a template
encodes one kind's blind spots (the CLI template has no slot to catch the daemon's
socket; the web template no line for exit codes), and the next target is always a
hybrid it never imagined. The universal sweep plus every-channel evidence covers
all kinds with zero forks. Where a surface doesn't exist — no persistent state,
say — record it as absent: absence at a port is itself a boundary fact.

- BAD: a spec organized as "Commands" because the target is a CLI, with lifecycle
  and external interactions nowhere because the template had no slot for them.
- GOOD: the same surface sections for every target, with "Persistent state: none;
  runs independent (verified by diffing the filesystem across two runs)" where a
  surface is empty.

Diagnostic: does anything in your spec exist because of what *kind* of thing the
target is, rather than what its boundary observably does?

## Completeness is a sweep, not a brainstorm [APPSPEC:sweep-the-surfaces]

A feature list is finished when you run out of ideas; a sweep is finished when the
enumeration is. This is the completeness direction of the boundary test made
procedural: don't ask "what does this app do?" — walk the ports in fixed order and
interrogate each. Sweep these surfaces, explicitly, every time, for every target:

1. **Invocation and entry points** — every way in: commands, endpoints, routes,
   screens, hooks, scheduled triggers, signals-as-input.
2. **Configuration and environment** — env vars, config files and formats, flags,
   defaults, and precedence among them when they conflict.
3. **Inputs** — accepted shapes *and rejected shapes*, and what rejection
   observably looks like.
4. **Outputs** — formats, streams (stdout vs. stderr), files written and where,
   responses, rendered states, notifications.
5. **Persistent state** — everything observable *across* runs: whatever makes run
   N+1 differ from run N.
6. **External-system interactions** — everything sent outward and expected back
   (own section below).
7. **Lifecycle** — startup, readiness, shutdown, crash (own section below).
8. **Error behavior** — the whole unhappy path (own section below).
9. **Observable guarantees** — ordering, idempotency, atomicity, concurrency
   behavior, where exhibited. Record timing and resource numbers only where
   contractual or observably depended on, and mark them as such — otherwise the
   clean team inherits accidental constants as requirements.

This enumeration is the requester's own list — "all APIs, including application
startup requirements, when it shuts down, when it throws errors, and any
interactions with external systems, along with all functional requirements" —
fixed into a walk so none of it is covered only if you happen to think of it. The
temptation, deep in the session, is fatigue in a reasonable voice: *"I've
documented everything the app does — I'm done."* Refuse it. "Everything it does"
is a claim about your imagination; "every surface swept" is a claim about a
checklist. The port you skip because nothing came to mind is exactly where the
reimplementation diverges — silently, because nobody on the clean side knows to
ask.

- BAD: rich coverage of the five features the writer explored; nothing anywhere
  on configuration precedence or what persists between runs.
- GOOD: nine surface sections, each populated with observed facts or explicitly
  recording verified absence.

Diagnostic: can you point at where each of the nine surfaces was answered —
including the empty ones?

## Error behavior is API [APPSPEC:errors-are-api]

**What the application does when things go wrong is as much its interface as what
it does when they go right.** Exit codes and their meanings; the shape of error
output — which stream, what format; behavior on malformed input, on an unreachable
dependency, on partial failure — three of five items processed, then what? Every
one is read by an instrument at a port; every one is spec. The case has no "good
news" and "bad news" ports — the boundary doesn't distinguish, and neither may
you. A happy-path-only spec specifies a different, simpler application, and the
clean team will faithfully build that simpler one.

The temptation: *"the error paths are obvious — it fails, it prints an error, who
needs that written down."* Refuse it. "It fails" is where the contract hides:
*which* exit code — callers branch on it; *which* stream — pipelines depend on it;
does the half-written output file remain — the next run depends on it. If it were
obvious, every application would fail the same way, and none do.

- BAD: "Invalid input is rejected with an error message."
- GOOD: "Given a config file that is not valid YAML, the process writes one
  diagnostic line to stderr identifying the file path, writes nothing to stdout,
  creates no output files, and exits 2."

Diagnostic: for each entry point, does the spec state what a caller observes on
malformed input, on an unreachable dependency, and on failure partway through?

## Lifecycle is API [APPSPEC:lifecycle-is-api]

The boundary exists in time as well as space: **the application's first and last
observable acts are boundary facts.** What must be true for it to start — env
vars, files, ports, reachable services — and, just as contractually, what it
observably does when each requirement is unmet: refuse with which message and exit
code? start degraded? block and retry? When is it *ready*, and how does an
observer tell readiness from merely running? How does it shut down — which signals
honored, what cleanup detectable, what happens to in-flight work? What does a
crash leave behind, and what does the next startup observably do about it?

The temptation: *"startup and shutdown are boilerplate — the interesting behavior
is in the features."* Refuse it. To every operator, supervisor, and calling
script, lifecycle *is* the interface. A reimplementation that becomes ready at a
different moment, or drops in-flight work on SIGTERM where the original drained
it, is observably a different application, and fails in production in ways feature
tests never see.

- BAD: "The service starts up and connects to the database."
- GOOD: "On start with `$DATABASE_URL` unset, writes one diagnostic line to
  stderr and exits 1 without binding its port. Set but unreachable: binds the
  port, returns 503 from `/healthz`, retries until connected. On SIGTERM: stops
  accepting connections, completes in-flight requests, exits 0."

Diagnostic: could an operator with only your spec supervise this application —
know when it is up, how to stop it safely, and what a crash costs?

## External interactions are wire-level contracts [APPSPEC:wire-level-contracts]

The boundary carries traffic in both directions, and outbound is the direction
writers forget: **everything the application itself sends to other systems, what
it expects back, and what it does when the other side misbehaves.** The other
system is an outside observer too — it sees requests, queries, messages, files; it
never sees your app's libraries. Record what the peer would see and send: requests
made (methods, paths, payload shapes, auth scheme), responses expected, retry and
timeout behavior, the observable consequence of the peer being down, slow, or
wrong. Put the tap on the wire and transcribe the traffic.

The temptation: *"it talks to Postgres through the ORM — that's the
interaction."* Refuse it. The ORM is a gear; "uses library X" is a fact about the
inside of the case. The clean team may pick a different library, or none, and be
exactly equivalent — *provided the traffic matches*. Name the wire protocol and
the traffic's shape and semantics, never the machinery. (Where the target *is* a
library, its exported symbols are the port itself — see the exactness rule below;
libraries a target consumes internally are gears, always.)

- BAD: "Fetches user data using axios with the shared apiClient wrapper."
- GOOD: "Each sync cycle sends `GET /v2/users?since=<ISO-8601 timestamp>` with
  `Authorization: Bearer <token from $API_TOKEN>`; expects a JSON array of
  objects with `id`, `email`, `updated_at`. On any 5xx, retries up to 3 times
  with backoff, then skips the cycle; a 401 terminates the process, exit 4."

Diagnostic: could the clean team build a faithful fake of the peer from your
description alone?

## Behavior, never mechanism [APPSPEC:behavior-not-mechanism]

This is the purity direction of the boundary test, and the place your best
instincts turn against you. No algorithms. No internal architecture. No internal
names. No code excerpts. No "how it works" narration. If confirming a sentence
requires opening the case, it is not spec — however true, however useful it feels.

Here is the counter-proverb to disarm, arriving with the authority of every
documentation genre you know: **"good documentation explains how it works."**
Grant it its home turf — for ordinary docs it is exactly right; maintainers
deserve mechanism, and a README that hides its architecture is a bad README. But
this genre *inverts* it. The clean team's entire legal standing is that they never
learned how the original works inside; depth past the boundary is not thoroughness
here — it is the one thing the deliverable exists to exclude. In this genre the
architecture overview is not a favor to the reader. It is the defect.

Which is why the most dangerous temptation of the session is the most
respectable-sounding one: *"the implementer needs to know how this works inside —
I'll add a short architecture overview for context."* Refuse it, and recognize its
costumes: the "design rationale" paragraph, the algorithm sketch "so they
understand the intent," the module map "just for orientation." Each is
contamination wearing helpfulness. The implementer needs the boundary completely;
give them that, and the inside is theirs to invent.

**The exactness split** [APPSPEC:exact-where-machines-read] draws the line. Names
and strings that *cross* the boundary are contract and must be transcribed
exactly: flag names, endpoint paths, file paths, env var names, exit codes,
machine-parsed output formats, protocol constants, and — when the target is a
library — its exported symbols and signatures, because those are its ports. A
machine parses these, and `--out-dir` is not `--output-dir`. But text emitted for
*humans* — log prose, help text, error wording — is described by function and
information content, never transcribed: "emits a diagnostic to stderr naming the
missing field," not the sentence itself. Function is specifiable; expression is
precisely what clean-room exists to not copy. Exact where a machine reads,
functional where a human does.

- BAD: "The dedupe module keeps a rolling Bloom filter keyed on normalized URLs,
  so duplicates within a window are skipped."
- GOOD: "Submitting an item whose URL matches one submitted in the same run
  (after case-folding the host and stripping the fragment — verified by
  observation) produces no second output record and no error."

Diagnostic: does confirming the sentence require anything but an instrument at a
port — and does a machine parse each literal string in it at the boundary?

## Observed beats inferred [APPSPEC:observed-beats-inferred]

The boundary test has a verb, and the verb is *observe*. Reading source yields
hypotheses; running the application yields facts. Source is a legitimate evidence
channel — it tells you where the ports are and what to probe — but reading a gear
and predicting the signal is not reading the signal, and code lies to hasty
readers: the dead branch, the config override you missed, the framework default
that flips the behavior, version skew against the deployed thing. Wherever a
channel exists to run, call, click, or probe, verify by observation before the
sentence goes in.

The temptation: *"I read the code, so I know what it does."* Refuse it — this is
how confident falsehoods enter a spec, and a confident falsehood is the worst
artifact a spec can contain: an omission the clean team can discover as a gap, but
a false statement they will *build on*, and the divergence surfaces months later
with your sentence as its source. Where behavior cannot be determined, mark it
`UNVERIFIED`, state what was tried, and state the hypothesis as a hypothesis. An
honest `UNVERIFIED` is the spec doing its job; a guess wearing declarative grammar
is the spec failing its one duty — to be the thing the clean side can trust.

- BAD: "Retries three times on failure." (source read, never exercised; the retry
  wrapper is behind a flag that defaults off)
- GOOD: "UNVERIFIED: source suggests failed sends are retried; could not induce a
  send failure against the sandbox endpoint to confirm count or backoff. Observed
  only that a single failure does not terminate the process."

Diagnostic: for each sharp claim — exit code, format, guarantee — was it
*observed*, and does the provenance section say so?

## Every sentence is a test waiting to run [APPSPEC:condition-effect]

The unit of spec prose is **condition → observable effect**, sharp enough that the
clean team could turn it into an acceptance test without asking anyone — and they
can ask no one; the spec makes one trip, and no follow-up question crosses after
it. This is the boundary test at the grain of a sentence: a boundary fact *is* an
experiment — set up the condition at a port, read the effect at a port — and a
spec sentence is that experiment written down.

The temptation: *"'the tool validates its input' — that's true, and it covers
it."* Refuse it. True and useless: it names a virtue, not a behavior. Which
inputs? Rejected how? Detectable by what? A sentence that cannot fail as a test
cannot guide an implementation — the clean team nods and still invents the actual
behavior, which makes it theirs, not the original's. Vagueness is not caution; it
is omission in better clothes, and costs what a skipped port costs.

- BAD: "Handles concurrent access safely."
- GOOD: "Two processes invoked simultaneously on the same state directory: one
  acquires the lock and proceeds; the other writes one line to stderr containing
  the lock file path and exits 11 without modifying the directory."

Diagnostic: could a stranger write the acceptance test from this sentence alone —
setup, action, and assertion all present?

## The spec stands alone [APPSPEC:spec-stands-alone]

The deliverable is a self-contained set of documents — by default an `appspec/`
directory at the target root, overridable if the user directs — that survives
being handed over with *nothing else attached*. It opens with an overview stating
what the application is at boundary level and where its boundary lies; then a
**provenance section**: target identity and version, which evidence channels were
available, what was verified by observation versus derived from source; then the
surfaces. The artifact is the one courier across the boundary — one trip, no
luggage following later.

So: **no references into the source tree — ever.** The temptation: *"this parser
is intricate — I'll just point them at `src/parser/grammar.js` rather than
re-derive it all."* Refuse it, and note that this refusal *inverts* a habit the
rest of this plugin teaches. Elsewhere, point-don't-transcribe is right — a
filename beats a copied excerpt when your reader can open the file. Here the
medium flips the rule: your reader is forbidden from opening the file. A pointer
into the source is a door in the boundary wall, broken twice — it invites the
clean team through (voiding their clean status the moment they follow it) and it
fails the handoff (the spec no longer stands alone). Transcribe the boundary fact
exactly; point at nothing. Craft from other media does not carry in.

- BAD: "Accepted expression syntax: see `src/parser/grammar.js`."
- GOOD: "Accepted expression syntax (verified against the running tool):
  identifiers `[a-z_][a-z0-9_]*`, infix `+ - * /` with usual precedence,
  parentheses for grouping; any other token yields exit 2 and a stderr diagnostic
  naming the offending character's position."

Diagnostic: delete the entire target from the universe — repo, binary,
deployment. Does every sentence of the spec still resolve?

## Two audits before you ship [APPSPEC:two-audit-passes]

The boundary test turned into a shipping procedure: one pass per direction, both
mandatory, against the finished spec.

**The completeness sweep.** Walk the nine surfaces again — the actual documents,
not your memory of writing them. Is each addressed? Is any *thin* — entries
without error behavior, outputs without formats, lifecycle without its
unmet-requirement cases? Is every absent surface recorded with how absence was
verified? Thin sections are where you were tired; the sweep doesn't get tired.

**The purity reread.** Every sentence against the one question: could an outside
observer confirm this? Hunt the respectable leaks — the "for context" phrase, the
internal name that slipped in as vocabulary, the mechanism verb ("caches,"
"indexes," "queues") asserting a gear where only a signal was observed. Rewrite
each as its observable effect, or cut it.

Two separate passes, two mindsets — the sweep hunts holes, the reread hunts leaks
— because one combined pass does whichever was primed last and skimps the other.
The shelf gets the level held both ways before it leaves the shop. The temptation,
arriving when you most want to be done: *"I applied the test as I wrote — a final
reread is redundant."* Refuse it. You applied it with a writer's attention, hours
apart; the audits apply an auditor's attention across the whole artifact at once,
and the thin section and the leaked gear are exactly what the writing mind cannot
see, because it produced them.

- BAD: finishing the last section, skimming once, shipping — "looks complete."
- GOOD: a sweep pass producing a findings list ("no crash-residue statement;
  flag-vs-env precedence unstated"), the fixes, then a reread pass that caught
  and rewrote two mechanism verbs.

Diagnostic: can you point at where each pass happened and what each changed?

## Recap — the tokens

Cite these as `[APPSPEC:<token>]` at the moment of use while writing spec
sentences — naming the rule as you apply it keeps it active.

- `[APPSPEC:boundary-decides]` — one test, two directions: outside-observable and
  missing is a defect; inside-only and present is a defect. Every port, no gears.
- `[APPSPEC:one-structure-many-channels]` — the target's kind changes only where
  you stand, never the spec's structure; use every evidence channel; per-kind
  templates are the named anti-pattern; absence is a recorded fact.
- `[APPSPEC:sweep-the-surfaces]` — completeness by enumeration: entry points,
  configuration/environment, inputs, outputs, persistent state, external
  interactions, lifecycle, errors, observable guarantees — every one, every time.
- `[APPSPEC:errors-are-api]` — exit codes, error output shapes, malformed input,
  unreachable dependencies, partial failure: the unhappy path is contract.
- `[APPSPEC:lifecycle-is-api]` — startup requirements and behavior when unmet,
  readiness, shutdown/signals/in-flight work, crash residue.
- `[APPSPEC:wire-level-contracts]` — record the traffic the peer sees and sends,
  never the library or ORM; enough to build a fake of the peer.
- `[APPSPEC:behavior-not-mechanism]` — no algorithms, architecture, internal
  names, or code; "good documentation explains how it works" is true everywhere
  but here, where depth past the boundary is the defect.
- `[APPSPEC:exact-where-machines-read]` — boundary-crossing names and
  machine-parsed strings exact (flags, paths, env vars, exit codes, formats,
  protocol constants, exported symbols); human-facing prose described by
  function, never transcribed.
- `[APPSPEC:observed-beats-inferred]` — probe wherever a channel allows; never
  assert unobserved behavior as fact; mark the undeterminable `UNVERIFIED` with
  what was tried.
- `[APPSPEC:condition-effect]` — every sentence is condition → observable effect,
  sharp enough to become an acceptance test with no follow-up questions.
- `[APPSPEC:spec-stands-alone]` — self-contained `appspec/` (overridable):
  overview, boundary definition, provenance (identity/version, channels, observed
  vs. derived), then surfaces; no references into the source tree, ever.
- `[APPSPEC:two-audit-passes]` — before shipping: a completeness sweep of the
  nine surfaces, then a purity reread of every sentence.

The whole document in one breath: stand outside the case with every instrument
you have; write down everything the ports do, exactly where machines read and
functionally where humans do; observe before you assert, mark what you couldn't;
make every sentence an experiment a stranger could run; hand over a bundle that
needs nothing else; then check it once for holes and once for leaks.
