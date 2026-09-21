# `[LAW:nothing-unseen]` - specification for the law entry

Scope: what the observability law must say inside `plugins/laws/skills/code/SKILL.md`,
where it applies unconditionally to every code task. How to instrument a given domain
and how to retrofit an existing codebase belong to the `laws:code-observability` skill
and are specified in `design-docs/observability-skill.spec.md`. Observability of an
agent's own work, of verification instruments, and of claim status in documents is
outside the law.

This specifies content, not wording. Bracketed line numbers cite
`design-docs/observability-law.md` unless another file is named.

## Terms

- Unit of work: one request, job run, command invocation, or migration.
- Event: the one structured record a unit of work emits, carrying everything known about
  it under one correlation ID.
- Shared layer: the one layer every unit of work already passes through, such as request
  middleware, a base outbound client, a job runner, or a command dispatcher.

## Requirements

### What the law says

1. State that a running system must expose enough of itself that its state can be
   reconstructed from its outputs alone, including for questions nobody thought to ask
   in advance, and name the three conditions directly: when it is working, when it is
   not, and when nobody yet knows which. [15-20, 44-45; `observability.md`:277-283]
2. State that the law covers the whole run - including runs that succeed and runs whose
   outcome nobody can name - and is therefore not a clause of `[LAW:no-silent-failure]`,
   which covers the moment of failure. [36-38]
3. State that pre-aggregated monitoring does not satisfy requirement 1: the bar is raw,
   high-cardinality records that can be sliced by a dimension nobody named until the
   incident named it. Failure: "we have dashboards" is offered as proof a system is
   observable. [90-95]
4. State that instrumentation is built into the shared layer from the first commit: the
   shared layer is built first, and the event goes into it before the first unit of work
   passes through. Failure: on new code, writers plan to get it working first and add
   logging after. [17-18, 69-71, 145-151]
5. State that zero and absent are different facts and both must be visible: a unit of
   work that ran and did nothing emits its counts as zero, and one that never ran emits
   nothing. Failure: readers of telemetry that cannot separate the two read silence as
   "all quiet" when the reporter is dead. [46-50]
6. State that the absence of an expected signal is itself a signal, and that the
   instrument reporting an absence exists before the absence can occur. [50-51]
7. `[LAW:one-source-of-truth]` State that one event per unit of work is the source of
   truth, and that metrics are aggregates over those events, traces are those events
   with parent IDs, and log lines are fields on them - never independently maintained
   copies of the same facts. [53-60]
8. `[LAW:single-enforcer]` State that telemetry is emitted from the shared layer only,
   not from log lines hand-placed inside functions, and that telemetry per call site
   where a shared layer exists is the tell of a violation. [62-68, 241]
9. State that the system reports its decisions, not only its outcomes, and can show what
   it will do before it does it. [73-76]
10. State that telemetry is code - typed, tested, versioned, named by one convention -
    and gets no exemption from any other law. [17-18, 78-79]
11. `[LAW:no-silent-failure]` State that a telemetry failure is itself telemetry: when
    the exporter is unreachable the unit of work does not fail, the dropped events are
    counted and surfaced, and the hot path never depends on the telemetry pipeline being
    up. [82-86]

### Forbidden shapes

12. List these shapes as bugs on sight: (a) a script exits 0 having processed zero items
    and nothing distinguishes "all done" from "did nothing"; (b) a catch-all swallows an
    exception and continues, so a failure count reads zero because nothing counted; (c) a
    retry loop succeeds on a later attempt and nobody learns the earlier ones failed;
    (d) a cache with no hit-rate surface; (e) a background job whose only visible states
    are running and not running; (f) a config value read from one of several places with
    no way to ask which one won. [108-118]

### Placement inside laws:code

13. Add `nothing-unseen` to the token index. [`code/SKILL.md`:35-52]
14. Add it to the recap under **Observable correctness**, alongside
    `[LAW:verifiable-goals]`, `[LAW:behavior-not-structure]`, and
    `[LAW:no-silent-failure]`. [278-284]
15. Close the entry with its relations: dynamic twin of `[LAW:types-are-the-program]`,
    an instance of `[FRAMING:representation]`, sibling of `[LAW:no-silent-failure]` and
    `[LAW:verifiable-goals]`. [162-167]
16. Do not add observability bullets to the DOMAIN BINDINGS section of laws:code; the
    skill owns the bindings, and a copy here would be a second source for them.
    [owner instruction, 2026-09-18; supersedes `observability.md`:263-265]
17. Keep out of the entry everything the skill owns: no per-domain list of shared layers,
    no retrofit procedure, no tool or vendor names, no cardinality, sampling, redaction,
    or overhead operations. Requirement 12 is the only domain-recognizable content the
    entry carries.

### Writing the entry

18. Give the entry the shape every other law entry has: a `## [LAW:nothing-unseen] -
    <short title>` heading, a bold statement carrying requirements 1, 4, and 10, the
    FORBIDDEN list of requirement 12, one rehearsed temptation with its redirect
    (requirement 4's), the diagnostic of requirement 19, and the relations of
    requirement 15. [`code/SKILL.md`:914-1027]
19. End with the diagnostic, which tests requirements 5 and 9: *if this ran at 3 a.m. and
    did nothing, could anyone tell that from it not having run - and could they say, from
    the outputs alone, why it did what it did?* [159-160]
20. Write the entry in the effective, rhetorical style of the file it joins, not in this
    spec's words; that file's redundancy is load-bearing and distilling it is a
    documented failure. The style authority is laws:prompt, which cannot be loaded beside
    laws:code, so a subagent seeded with only laws:prompt writes the entry from this
    spec. [`code/SKILL.md`:5-11; `.claude/skills/laws/SKILL.md` rules 1 and 2]
21. Draw the entry's imagery from `design-docs/observability-law.md`, which is the
    approved candidate expression, rather than inventing new imagery. [decision, not from
    the source]
