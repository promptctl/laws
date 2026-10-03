---
name: spec
description: Write and maintain the three requirements documents (PRD, FSD, Spec) for a feature being built. Use when asked to write a PRD, functional spec, technical spec, or requirements document, or to trace a component back to a user request. For specifying an application that already exists, so another team can rebuild it, use laws:application-spec instead.
---

# Spec writing

This process treats a real user's request as sufficient proof of a need and spends the time on building and trying instead. The team designs the solution, builds the smallest working version, puts it in front of a user or an agent on a real task, and records what happened.

The process uses three documents, each with a single job, plus a matrix that ties them together:

- **PRD:** what is needed, who asked for it, and what has been validated so far.
- **FSD:** what the product does, written as testable functional requirements.
- **Spec:** how it is built, with rigor scaled to how much each part has been validated and how costly it would be to reverse.

A standard traceability matrix connects all three, so every component traces back to a user request and anything that doesn't trace back gets cut. The documents' own terms and section names are industry standard, so a new team member can follow them without learning a new vocabulary. What the documents say about the product is written in the vocabulary of the subject it serves (an invoicing product's documents say invoice, sent, and overdue), so someone who knows that subject reads them as written in their own language. The project's names for its parts sit alongside that vocabulary, spelled as the project spells them, and a narrower part of the product can add more specific terms of its own; each layer adds to the ones above it and replaces none, so the subject's vocabulary holds even in the narrowest section. Where the subject already has a word, use it before coining one.

## Templates

Copy the template for the document being written and fill every section — a dash where the answer isn't known yet, so the gap stays visible. The rules at the bottom of each template apply to the finished document.

- PRD: `references/prd-template.md`
- FSD: `references/fsd-template.md`
- Spec: `references/spec-template.md`
- Traceability matrix, spanning all three: `references/traceability-matrix-template.md`
- Iteration cycle across the four documents: `references/iteration-cycle.md`

## Stop at the build

Stop at the smallest set of sections that lets the next iteration be built and put in front of a person or an agent on a real task — then go build it. What is still unknown stays a dash and an open issue; the build is what answers it.

When a section looks thin, hand it off thin: the next build answers it more cheaply than an untested guess.

- WRONG: four complete documents, nothing built, nobody has used anything.
- RIGHT: two sourced requirements, the three functional requirements they need, a Spec covering only those, and a working version in someone's hands.
