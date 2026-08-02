# Design goals: the `application-spec` skill

This skill governs writing a thorough, functional, clean-room-style specification of
an existing application. The spec's purpose is legal clean-room reimplementation: an
independent team that has never seen the original - and must never see it - receives
the spec alone and builds a behaviorally equivalent system from it. Today the target
is usually a repo the agent is sitting in or pointed at; the design must extend,
without restructuring, to applications observed directly - a CLI, a UI, a SaaS, a CI
system, anything with a boundary.

## What it's built on

One fact does almost all the work: **the application's boundary decides every
sentence of the spec, in both directions.** A fact observable from outside the
boundary - an invocation form, an output shape, an exit code, a request the app
makes to another system - belongs in the spec, and leaving it out is a real defect
(the reimplementation silently diverges). A fact visible only from inside - an
algorithm, an internal structure, a private name, a line of code - must not appear,
and including it is a real defect (the clean-room guarantee is void). Completeness
and purity are not two rules; they are the two directions of the same boundary test,
and every statement in a spec can be checked against it: *could an outside observer,
with no access to the internals, confirm this sentence?*

The spec writer is on the contaminated side - they have read the source or probed
the system - and the spec is the only thing that crosses to the clean side. That is
the ordinary mechanics of clean-room work, and the skill states it as mechanics, not
as menace. Deliberately: the failure history of this plugin's ticket skill showed
that a fear-heavy frame produces ceremony and over-caution, and a spec writer
frightened into vagueness produces an unusable spec, which fails the mission as
surely as a contaminated one. Omission and contamination get equal weight.

## The goals, and the choices that serve them

**One spec structure for any kind of target; forks live only in evidence-gathering.**
The requirement is breadth - repo now; CLI, UI, SaaS, CI later - with the minimum
forks in the logic. The design answer: the target's kind never changes what the spec
looks like; it only changes *where the writer stands to observe*. Source code,
a runnable binary, a live endpoint, a drivable UI are **evidence channels**, and a
writer uses every channel available. The spec's structure - the surface taxonomy
below - is invariant across all of them. There are no per-kind templates and no
"if it's a CLI, then…" branches anywhere in the craft.

**Completeness comes from sweeping surfaces, not listing features.** A feature list
is finished when the writer runs out of ideas; a surface sweep is finished when the
enumeration is. The craft fixes a universal taxonomy of boundary surfaces and
requires each to be swept explicitly: invocation and entry points (commands,
endpoints, screens, hooks - however the app is entered); configuration and
environment (env vars, config files, defaults, precedence); inputs and their
accepted/rejected shapes; outputs (formats, streams, files written, responses,
rendered states); persistent state as observable across runs; interactions with
external systems; lifecycle; error behavior; and observable guarantees (ordering,
idempotency, atomicity, concurrency behavior) where the app exhibits them. The
user's enumeration - "all APIs, including application startup requirements, when it
shuts down, when it throws errors, and any interactions with external systems …
along with all functional requirements" - is this taxonomy; the taxonomy exists so
none of those get covered only when the writer happens to think of them.

**Error behavior and lifecycle are API, not appendix.** The two surfaces writers
habitually skip are named as first-class: what the app requires to start (and how it
behaves when a requirement is missing), when and how it shuts down (signals,
cleanup, in-flight work), and what it does when things go wrong (exit codes, error
output shapes, behavior on malformed input, on unreachable dependencies, on partial
failure). A spec with only the happy path specifies a different, simpler
application.

**External-system interactions are specified as wire-level contracts.** What the
app sends, what it expects back, what it does when the other side misbehaves -
never "it uses library X" or "it talks to the database via the ORM," which are
implementation facts. The other system sees traffic; the spec records the traffic.

**Behavior, never mechanism.** The purity direction of the boundary test, made
concrete: no algorithms, no internal architecture, no internal names, no code
excerpts, no references into the source tree. With one precision the legal line
requires: names and strings that *cross* the boundary are contract and must be
exact - flag names, endpoint paths, env var names, exit codes, machine-parsed
output formats, protocol constants, a library's exported symbols. Text the app
emits for humans to read (log prose, help text) is described by its function and
information content, not transcribed - function is specifiable; expression is the
thing clean-room exists to not copy.

**Observed beats inferred; unknown is marked, never guessed.** Reading source
yields hypotheses about behavior; running the application yields facts. Where a
channel to run or probe exists, verify by observation. Where behavior cannot be
determined, the spec says so explicitly (an UNVERIFIED marker with what was tried),
because a guessed behavior stated confidently is the worst artifact the spec can
contain - the clean team, with no way to check, builds on it.

**Every statement is checkable.** The unit of spec prose is condition → observable
effect, sharp enough that the clean team could turn it into an acceptance test
without asking anyone. "The tool validates its input" is not a spec sentence;
"given input missing required field F, the run produces no output file, writes a
diagnostic to stderr, and exits non-zero" is.

**The spec stands alone.** The deliverable is a self-contained set of documents
(default: an `appspec/` directory at the target root, overridable) that survives
being handed over with nothing else: an overview with the boundary definition and a
provenance section (target identity and version, which channels were available,
what was verified by observation vs. derived from source), then the surfaces. A
spec that says "see src/router.js" is broken twice - it leaks the source and it
fails the handoff.

**The craft ends with two audit passes, one per direction.** A completeness pass
(sweep the taxonomy again against the finished spec: any surface thin or missing?)
and a purity pass (reread every sentence against the boundary test: could an
outside observer confirm this?). The two passes are the boundary fact turned into
a shipping procedure.

## Structural choices

- Same shape as the other artifact skills: a thin dispatch `SKILL.md` that routes
  to a subagent, and the craft in `references/craft.md`, written in the far-end
  style under the `prompt` skill's authority - the spec-writing session is long and
  autonomous, and the contamination temptation ("the implementer needs to know how
  this works inside") arrives deep in it, exactly where guidance has to still fire.
- Canonical tokens in the house pattern (`[APPSPEC:<token>]`) with a closing recap,
  so rules are citable at the moment a sentence is being written into the spec.

## What it deliberately avoids, and why

- **Per-target-kind templates or branches.** A CLI template, a SaaS template, a UI
  template would triple the maintenance surface and still miss the next kind. The
  surface taxonomy plus evidence channels covers all kinds with zero forks; a
  surface that doesn't exist for a target (no persistent state, say) is recorded as
  absent, which is itself a boundary fact.

- **Fear framing of the legal constraint.** The measured lesson from the ticket
  skill's history: menace produces ceremony, and a writer scared of every sentence
  pads the spec with hedges or omits sharp facts it is entitled to state. The
  boundary test is stated as a working instrument the writer applies sentence by
  sentence, with contamination and omission as symmetric defects.

- **Describing internals "for context."** The most respectable-sounding
  contamination: architecture overviews, "how it works" sections, algorithm
  sketches to "help the implementer." Depth past the boundary is not thoroughness
  - it is the one thing the deliverable exists to exclude, and the craft must argue
  this inversion explicitly because every other documentation genre teaches the
  opposite.

- **Source references as pointers.** The plugin's other skills use "point, don't
  transcribe" (a filename beats a copied excerpt). Here that device is *inverted*
  by the medium: the clean reader must never follow a pointer into the source, so
  the spec transcribes the boundary fact exactly and points at nothing. Craft from
  the other media does not carry in.

- **Performance numbers as default content.** Observable timing is boundary-real
  but usually incidental; the spec records timing and resource behavior only where
  it is contractual or where consumers observably depend on it, and marks it as
  such - otherwise the clean team inherits accidental constants as requirements.
