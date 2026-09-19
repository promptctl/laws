---
name: spec
description: Write and maintain the three requirements documents (PRD, FSD, Spec) for a feature. Use when asked to write a PRD, functional spec, technical spec, or requirements document, or to trace a component back to a user request.
---

# Spec writing

Most requirements processes spend weeks proving a need before anything gets built. This one treats a real user's request as sufficient proof and spends the time on building and trying instead. Every requirement names the person who asked for it. The team designs the solution, builds the smallest working version, puts it in front of a user or an agent on a real task, and records what happened.

The process uses three documents, each with a single job, plus a matrix that ties them together:

- **PRD:** what is needed, who asked for it, and what has been validated so far.
- **FSD:** what the product does, written as testable functional requirements.
- **Spec:** how it is built, with rigor scaled to how much each part has been validated and how costly it would be to reverse.

A standard traceability matrix connects all three, so every component traces back to a user request and anything that doesn't trace back gets cut. Its coverage checks run after every iteration. The terms and section names are industry standard, so a new team member can follow the documents without learning a new vocabulary.

The result is less documentation written before the first build and a recorded reason for each decision.

## Templates

Copy the template for the document being written and fill every section. The rules at the bottom of each template apply to the finished document.

- PRD: `references/prd-template.md`
- FSD: `references/fsd-template.md`
- Spec: `references/spec-template.md`
- Traceability matrix, spanning all three: `references/traceability-matrix-template.md`
- Iteration cycle across the four documents: `references/iteration-cycle.md`
