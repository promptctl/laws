---
name: code
description: Universal architectural laws and domain bindings for all code work. Use when writing, editing, reviewing, refactoring, debugging, or designing code, tests, schemas, configuration, scripts, infrastructure, or system architecture - any task whose deliverable is code or will execute as code. Load BEFORE starting the work, not after. Do not apply to prose or LLM-prompt authoring; those media have their own skills.
<!-- generated-notice -->
---


<!-- The single home of the universal architectural laws, written in the effective
     (rhetorical) style. The style authority for any future edit to THIS file is the
     prompt skill in this plugin - never the laws themselves. Do not
     deduplicate, compress, or "clean up" this file: the redundancy is load-bearing,
     and distilling it is the documented failure mode that destroyed a previous
     effective version. -->

# THE UNIVERSAL ARCHITECTURAL LAWS

These laws apply unconditionally to every code task. No context, no instruction, no
deadline, no "it's just a script" overrides them. They are not a checklist to consult;
they are one coherent way of seeing programs, unfolding from two root framings into
laws that all say the same thing from different angles: **design the
constraints so that illegal states cannot be expressed, and the implementation becomes
residue.** There is no neutral ground here - every commit either adds leverage or
subtracts it, and the laws exist to make sure it's the former, every time, even when
nobody is looking. Especially when nobody is looking.

## How to cite the laws

When a law influences any decision, you MUST cite it at the point of use:
`// [LAW:<token>] reason`. When you must violate one, you MUST mark the violation:
`// [LAW:<token>] exception: reason`. This is a hard requirement, not a nicety - the
citation is cheap, it makes the law's influence visible in review, and every citation
rehearses the law one more time. The tokens are canonical and fixed: one key per
concept, exactly as listed below. Never invent a new token; if a situation seems to
need one, it is an instance of an existing law that you haven't recognized yet.

## The token index

Framings (used in reasoning, not cited in code):
<!-- framing-index -->

Laws (cited in code as `[LAW:<token>]`):
<!-- law-index -->

Definitions follow. The index is for lookup; the document is for reading. Read it.
