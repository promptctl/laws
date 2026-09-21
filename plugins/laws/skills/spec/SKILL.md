---
name: spec
description: Write and maintain the three requirements documents (PRD, FSD, Spec) for a feature being built. Use when asked to write a PRD, functional spec, technical spec, or requirements document, or to trace a component back to a user request. For specifying an application that already exists, so another team can rebuild it, use laws:application-spec instead.
---

# Spec writing

Most requirements processes spend weeks proving a need before anything gets built. This one treats a real user's request as sufficient proof and spends the time on building and trying instead. Every requirement names the person who asked for it. The team designs the solution, builds the smallest working version, puts it in front of a user or an agent on a real task, and records what happened.

The process uses three documents, each with a single job, plus a matrix that ties them together:

- **PRD:** what is needed, who asked for it, and what has been validated so far.
- **FSD:** what the product does, written as testable functional requirements.
- **Spec:** how it is built, with rigor scaled to how much each part has been validated and how costly it would be to reverse.

A standard traceability matrix connects all three, so every component traces back to a user request and anything that doesn't trace back gets cut. Its coverage checks run once the three documents are updated and before the build starts, so a gap lands in the implementation plan instead of surfacing an iteration late. The terms and section names are industry standard, so a new team member can follow the documents without learning a new vocabulary.

The result is less documentation written before the first build and a recorded reason for each decision.

## Templates

Copy the template for the document being written and fill every section — a dash where the answer isn't known yet, so the gap stays visible instead of being quietly dropped. The rules at the bottom of each template apply to the finished document.

- PRD: `references/prd-template.md`
- FSD: `references/fsd-template.md`
- Spec: `references/spec-template.md`
- Traceability matrix, spanning all three: `references/traceability-matrix-template.md`
- Iteration cycle across the four documents: `references/iteration-cycle.md`

## Stop at the build

These documents are written to reach a build, not to be finished. Stop at the smallest set of sections that lets the next iteration be built and put in front of a person or an agent on a real task — then go build it. What is still unknown stays a dash and an open issue; the build is what answers it.

The temptation arrives late, once the shape is clear and the writing is going well: a section looks thin, and the thought is *"let me firm this up before handing it off."* That is the weeks-of-proving this process refuses, wearing the clothes of diligence. Hand it off thin and let the iteration correct it — a section the next build would answer is cheaper left empty than filled in with a guess nobody has tested.

- WRONG: four complete documents, nothing built, nobody has used anything.
- RIGHT: two sourced requirements, the three functional requirements they need, a Spec covering only those, and a working version in someone's hands.
