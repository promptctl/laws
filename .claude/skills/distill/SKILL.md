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
  directly, or carried by a story, metaphor, example, warning, or self-check question.
- Strength: hard (Do / Do not), soft (Prefer / Avoid), or permission (May). A
  declarative sentence about what the reader does or what the output is ("A ticket
  carries its why") is hard unless the source softens it ("usually", "ideally",
  "encouraged"). A symptom the source names without an imperative is written as the
  check it implies: "Treat X as a sign to revise."
- Condition: when a rule applies. Exception: when it does not.
- Failure clause: one sentence on a requirement naming a mistake the source says is
  made, by the reader of the guidance or by the readers of what they produce, e.g.
  "Failure: writers skip this when they think they know the reader." Written only
  where the source says the mistake happens.

## Setup

1. Do not read laws:prompt or `plugins/laws/skills/prompt/references/craft.md` in this
   session, unless that craft is itself the source; then read it only as material to
   extract, never as guidance for your output. If either is in context for any other
   reason, stop and run this skill in a fresh session or a fresh subagent seeded with
   only this skill.
2. Fix the source path and the output path. Default output: the source's directory,
   same basename with `.spec.md`. An output path the requester names wins. Never
   overwrite the source.
3. Read the whole source before extracting anything.

## Extract

Build a working list, not part of the output. One entry per rule: source location,
statement, strength, condition, exceptions, failure clause.

4. A direct statement is one entry.
5. A story or anecdote yields the rule it demonstrates and the condition that
   triggered it. The characters, setting, and outcome are dropped. If the story shows a
   mistake being made, that mistake becomes the entry's failure clause.
6. A metaphor yields the literal claim it stands for.
7. An example yields the rule it demonstrates. Keep the example itself only if the
   rule cannot be stated without it, cut to the shortest form that still shows it. A bad
   example yields a failure clause only if the source says its mistake is actually made.
8. A warning about a temptation ("you will want to X; refuse it") is a Do-not entry with
   its trigger as the condition and the temptation as its failure clause.
9. A self-check or diagnostic question becomes the check inside the requirement it
   tests.
10. Passages that say the same rule in different words merge into one entry, with the
    strongest strength any of them used; if they disagree, record the disagreement for
    the report. A soft passage and a hard passage that state separable rules are split
    instead of merged. Two rules that conflict with no order in the source both stay,
    and the conflict is recorded for the report.
11. A term the source coined or uses in a non-plain sense is replaced by the plain
    term. If no plain term exists, or the plain term loses part of the meaning, and the
    term appears in two or more entries, define it once under Terms. Identifiers the
    source attaches to rules, such as `[LAW:token]`, stay on their requirements.
12. Rationale is dropped. Keep one clause of it only where the rule's boundary cannot
    be found without it.
13. Pure motivation, praise, framing, audience address, and passages addressed to the
    source's editors rather than its reader yield no entry.
14. Record every passage that yielded no entry, whichever rule dropped it, including
    passages used only for the Scope sentence. On a long source, group them by kind with
    line ranges.

## Write

15. Format: title; one Scope sentence, which may name what is out of scope; Terms (only
    defined terms, omit the heading if none); Requirements, numbered continuously,
    grouped under headings in the source's topic order. A topic whose entries all merged
    into other topics gets no heading.
16. Each requirement is one rule in one or two imperative sentences, checkable by a
    reader who has not seen the source, with its condition and exceptions inside those
    sentences, followed by its failure clause if it has one. A rule that governs a group
    of other rules names them by number.
17. State each rule once. No story, metaphor, anecdote, repetition, or example beyond
    what rule 7 allows.
18. Preserve strength. Do not promote a soft rule to hard or demote a hard one, except
    as rule 10 decides for merged passages.
19. Preserve ordering the source gives between rules that conflict.
20. Add nothing the source did not say. A gap in the source is reported, not filled.

## Verify

21. Every working-list entry maps to one requirement; every requirement maps to at
    least one source location. Fix any miss before reporting.
22. Re-read the output file, not the draft in memory. For each requirement, confirm a
    reader could tell whether they had followed it. Where the source gives only an
    inward test ("sounds right"), keep it as stated; do not invent an outward one.
23. Report: source and output paths; the word count of each, frontmatter included; the
    passages from rule 14; any disagreement or conflict from rule 10; any gap from rule
    20. Keep the working list and include it when the requester asks for the mapping.
