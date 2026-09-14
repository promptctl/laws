# Clean-Room Application Specification

Scope: writing a functional, clean-room specification of an existing application, from which a team that never sees the application builds a behaviorally equivalent system.

## Terms

- Target: the existing application being specified.
- Clean team: the team that receives only the spec and builds a behaviorally equivalent system without ever seeing the target.
- Boundary: the target's interfaces with everything outside it. A boundary fact is externally observable.
- Externally observable: confirmable by an observer with no access to the target's internals, using tools at its interfaces (shell, network tap, browser, filesystem watcher). Algorithms, internal structure, private names, code, and libraries the target consumes internally are not externally observable.
- Evidence channel: a way to observe the target: its source, a runnable binary, a live endpoint, a drivable UI.
- The nine surfaces, in order:
  1. Invocation and entry points: every way in (commands, endpoints, routes, screens, hooks, scheduled triggers, signals as input).
  2. Configuration and environment: env vars, config files and formats, flags, defaults, and precedence among them when they conflict.
  3. Inputs: accepted shapes, rejected shapes, and what rejection observably looks like.
  4. Outputs: formats, streams (stdout vs. stderr), files written and where, responses, rendered states, notifications.
  5. Persistent state: everything that makes run N+1 differ from run N.
  6. External-system interactions (see 19-20).
  7. Lifecycle (see 14-18).
  8. Error behavior (see 13).
  9. Observable guarantees: ordering, idempotency, atomicity, concurrency behavior, where exhibited.

## Requirements

### The boundary test

1. Apply this test to every sentence of the spec: could an outside observer, with no access to the internals, confirm this sentence? [APPSPEC:boundary-decides]
2. Include every true externally observable fact; a missing one is a defect. [APPSPEC:boundary-decides]
3. Exclude every sentence that fails the test in 1, however true or helpful it seems, including algorithms, internal architecture, internal names, code excerpts, and descriptions of how the target works. [APPSPEC:boundary-decides] [APPSPEC:behavior-not-mechanism]
4. Give 2 and 3 equal weight: do not include an uncertain detail to avoid losing it, or leave one out to avoid risk; decide it by the test in 1. Failure: writers treat one direction as safe ("better to include it than lose it", "better to leave it out than risk it"). [APPSPEC:boundary-decides]
5. State externally observable facts sharply; do not hedge. Failure: writers afraid of either defect hedge and produce a vague spec. [APPSPEC:boundary-decides]

### One structure for every target

6. Use the same spec structure, the nine surfaces, for every target; the target's kind changes only where you observe. Treat anything in the spec that exists because of the target's kind rather than its observable boundary behavior as a sign to revise. [APPSPEC:one-structure-many-channels]
7. Do not use a template specific to the target's kind. Failure: writers pick the template matching the target's kind as an efficiency ("this is a CLI - I'll use my CLI template"). [APPSPEC:one-structure-many-channels]
8. Use every available evidence channel, not only the one matching the target's kind. [APPSPEC:one-structure-many-channels]
9. Where a surface does not exist, record it as absent and state how absence was verified. [APPSPEC:one-structure-many-channels]

### Sweeping the surfaces

10. Sweep all nine surfaces explicitly, in order, for every target, rather than asking what the application does; you must be able to point at where each surface, including empty ones, is answered. [APPSPEC:sweep-the-surfaces]
11. Do not stop because you believe you have documented everything the application does; stop only when every surface is swept. Failure: late in the session, writers conclude "I've documented everything the app does - I'm done." [APPSPEC:sweep-the-surfaces]
12. Record timing and resource numbers only where contractual or observably depended on, and mark them as such. [APPSPEC:sweep-the-surfaces]

### Error behavior

13. For each entry point, specify exit codes and their meanings, the stream and format of error output, and what a caller observes on malformed input, on an unreachable dependency, and on failure partway through, including whether partial output remains; do not treat error behavior as less part of the interface than success behavior. Failure: writers treat error paths as obvious and leave them out. [APPSPEC:errors-are-api]

### Lifecycle

14. Specify lifecycle per 15-18, detailed enough that an operator with only the spec could tell when the application is up, stop it safely, and know what a crash costs; do not treat lifecycle as boilerplate. Failure: writers treat startup and shutdown as boilerplate beside the features. [APPSPEC:lifecycle-is-api]
15. Specify what must be true for the application to start (env vars, files, ports, reachable services) and, for each unmet requirement, what it observably does: refuses (with which message and exit code), starts degraded, or blocks and retries. [APPSPEC:lifecycle-is-api]
16. Specify when the application is ready and how an observer tells readiness from merely running. [APPSPEC:lifecycle-is-api]
17. Specify shutdown: which signals are honored, what cleanup is detectable, and what happens to in-flight work. [APPSPEC:lifecycle-is-api]
18. Specify what a crash leaves behind and what the next startup observably does about it. [APPSPEC:lifecycle-is-api]

### External interactions

19. Specify everything the application sends to other systems: requests made (methods, paths, payload shapes, auth scheme), responses expected, retry and timeout behavior, and the observable consequence of the peer being down, slow, or wrong, detailed enough that the clean team could build a faithful fake of the peer from it alone. Failure: writers forget outbound traffic. [APPSPEC:wire-level-contracts]
20. Describe each interaction by its wire protocol and the shape and semantics of its traffic; never name the library, ORM, or other internal means that produces it. Failure: writers describe the library as the interaction ("it talks to Postgres through the ORM"). [APPSPEC:wire-level-contracts]

### Behavior, never mechanism

21. Do not include an architecture overview, design-rationale paragraph, algorithm sketch, or module map, including for context, intent, or orientation. Failure: writers apply the documentation norm "good documentation explains how it works" and believe the implementer needs to know how the target works inside. [APPSPEC:behavior-not-mechanism]
22. Transcribe exactly every name and string that crosses the boundary: flag names, endpoint paths, file paths, env var names, exit codes, machine-parsed output formats, protocol constants, and, when the target is a library, its exported symbols and signatures. [APPSPEC:exact-where-machines-read]
23. Describe text emitted for humans (log prose, help text, error wording) by its function and information content; never transcribe it. [APPSPEC:exact-where-machines-read]

### Observation

24. Where an evidence channel lets you run, call, click, or probe the target, verify a behavior by observation before writing it into the spec; treat what source reading yields as a hypothesis that tells you what to probe. Failure: writers conclude "I read the code, so I know what it does." [APPSPEC:observed-beats-inferred]
25. Do not assert unobserved behavior as fact; where behavior cannot be determined, mark it `UNVERIFIED`, state what was tried, and state the hypothesis as a hypothesis. [APPSPEC:observed-beats-inferred]

### Sentence form

26. Write each spec sentence as a condition and its observable effect, sharp enough that a stranger could write an acceptance test from it alone (setup, action, assertion) without asking anyone. Failure: writers state a virtue ("the tool validates its input") instead of a behavior. [APPSPEC:condition-effect]

### Self-contained delivery

27. Deliver the spec as a self-contained set of documents in an `appspec/` directory at the target root, unless the user directs another location; every sentence must still resolve with the target entirely unavailable. [APPSPEC:spec-stands-alone]
28. Open with an overview stating what the application is at boundary level and where its boundary lies, then a provenance section per 29, then the surfaces. [APPSPEC:spec-stands-alone]
29. In the provenance section, state the target's identity and version, which evidence channels were available, and which facts were verified by observation versus derived from source. [APPSPEC:spec-stands-alone] [APPSPEC:observed-beats-inferred]
30. Never reference the source tree; transcribe the boundary fact instead. Failure: writers point the clean team at an intricate source file rather than re-derive its behavior. [APPSPEC:spec-stands-alone]
31. Do not carry in practices from other kinds of writing, including pointing at a file instead of transcribing. [APPSPEC:spec-stands-alone]

### Audits before shipping

32. Before shipping, run two separate passes on the finished spec, 33 then 34; do not combine them or skip them, and be able to point at where each pass happened and what it changed. Failure: writers judge the audits redundant because they applied the test while writing. [APPSPEC:two-audit-passes]
33. Completeness sweep: walk the nine surfaces in the written documents, not from memory; confirm each is addressed, fix any thin one (entries without error behavior, outputs without formats, lifecycle without unmet-requirement cases), and confirm every absent surface records how absence was verified. [APPSPEC:two-audit-passes]
34. Purity reread: apply the test in 1 to every sentence, including "for context" phrases, internal names used as vocabulary, and verbs that assert an internal mechanism where only an external effect was observed; rewrite each failing sentence as its observable effect, or cut it. [APPSPEC:two-audit-passes]

### Rule tokens

35. While writing spec sentences, cite the token of the rule you are applying as `[APPSPEC:<token>]` at the moment you apply it; each requirement above ends with its token.
