---
name: distill
description: Rewrite an LLM-guidance document (a skill body, craft reference, CLAUDE.md, system prompt, or similar) that carries its rules in stories, metaphors, anecdotes, jargon, repetition, and long examples into a short specification - every rule stated once, plainly, with its condition, strength, and exceptions, and nothing else. Use when the user says "distill this", "turn this guidance into a spec", "strip the stories out", "make this minimal", "spec-ify this prompt", or wants a long-form prompt reduced to its rules. Do not load laws:prompt in the same session - its standard is the inverse of this one and reading it corrupts this work.
---

# Distill

Scope: one source document written for an LLM reader, rewritten as a specification
for the same reader. The output carries the same rules as the source and nothing
the source did not say.

## Terms

- Rule: a statement the source expects the reader to obey. Rules are stated
  directly, or carried by a story, metaphor, example, or warning.
- Strength: hard (Do / Do not), soft (Prefer / Avoid), or permission (May). A
  symptom the source names without an imperative ("headers in a short document") is
  written as the check it implies: "Treat X as a sign to revise."
- Condition: when a rule applies. Exception: when it does not.

## Setup

1. Do not read laws:prompt or `plugins/laws/skills/prompt/references/craft.md` in this
   session. If either is already in context, stop and run this skill in a fresh session
   or a fresh subagent seeded with only this skill.
2. Fix the source path and the output path. Default output: the source's directory,
   same basename with `.spec.md`. Never overwrite the source.
3. Read the whole source before extracting anything.

## Extract

Build a working list, not part of the output. One entry per rule: source location,
statement, strength, condition, exceptions.

4. A direct statement is one entry.
5. A story or anecdote yields the rule it demonstrates and the condition that
   triggered it. The characters, setting, and outcome are dropped.
6. A metaphor yields the literal claim it stands for.
7. An example yields the rule it demonstrates. Keep the example itself only if the
   rule cannot be stated without it, cut to the shortest form that still shows it.
8. A warning about a temptation ("you will want to X; refuse it") is a Do-not entry with
   its trigger as the condition.
9. Passages that say the same rule in different words merge into one entry. Record the
   strongest strength any of them used. If they disagree, write the strongest and
   record the disagreement for the report.
10. A term the source coined or uses in a non-plain sense is replaced by the plain
    term. If no plain term exists and the term appears in two or more entries, define it
    once under Terms.
11. Rationale is dropped. Keep one clause of it only where the rule's boundary cannot
    be found without it.
12. Pure motivation, praise, framing, and audience address yield no entry.
13. Record every passage that yielded no entry, whichever rule dropped it, for the
    report.

## Write

14. Format: title; one Scope sentence; Terms (only defined terms, omit the heading if
    none); Requirements, numbered continuously, grouped under headings in the source's
    topic order. A topic whose entries all merged into other topics gets no heading.
15. Each requirement is one rule: one or two sentences, imperative, checkable by a
    reader who has not seen the source. Condition and exceptions sit in the same item.
16. State each rule once. No story, metaphor, anecdote, repetition, or example beyond
    what rule 7 allows.
17. Preserve strength. Do not promote a soft rule to hard or demote a hard one.
18. Preserve ordering the source gives between rules that conflict.
19. Add nothing the source did not say. A gap in the source is reported, not filled.

## Verify

20. Every working-list entry maps to one requirement; every requirement maps to at
    least one source location. Fix any miss before reporting.
21. Re-read the output file, not the draft in memory. For each requirement, confirm a
    reader could tell whether they had followed it.
22. Report: source and output paths; word count of each; the dropped passages from
    rule 13; any disagreement from rule 9; any gap from rule 19. Keep the working
    list and include it when the requester asks for the mapping.
