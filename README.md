# laws

Claude Code writes code that runs. This plugin makes it write code that holds up.

At its center is a body of architectural judgment under one thesis: **design the
constraints so illegal states can't be represented, and the code nearly falls out for
free.** The types and constraints do the heavy lifting; the implementation is typically
mechanical and straightforward. When software is properly designed, the implementation
cannot be wrong by construction.

This isn't "write clean code" — it's something you can act on. When a function body
wants to branch, the type is missing a discriminator. When it wants a null guard,
some upstream signature is lying. When an error gets swallowed, a fire is burning
with the smoke alarm unplugged. The laws name each of these moments, quote the
rationalization you'll reach for, and tell you what to do instead.

Turned on, they change the character of the code Claude produces: fewer defensive
guards, no bags of optionals impersonating a type, no flags that never get deleted,
no `2>/dev/null` hiding the one failure that mattered. And every decision the laws
touch gets marked in the code itself — `// [LAW:no-silent-failure] reason` — so the
architectural reasoning is greppable in your repo and legible in review.

## What's inside

**The universal architectural laws** (`laws:code`) — the reason to install this.
Two root framings (a program is parts joined at seams; every representation is a map
that must match its territory) unfold into nineteen laws. Each one carries a
statement, a metaphor built to travel to situations nobody foresaw, the exact
rationalization it has to defeat, a one-line diagnostic, and worked WRONG/RIGHT code.
Domain bindings sharpen them for UI, APIs, schemas, pipelines, distributed systems,
and CLIs. If you install nothing else here, install this.

**The craft of writing for LLMs** (`laws:prompt`) — a field manual for any text
another model will consume, from a throwaway subagent prompt to a CLAUDE.md that has
to steer sessions for months. Those two ends want opposite styles, and getting them
backwards is an expensive, documented failure. Six devices, their mechanisms, their
anti-goals, and a shipping checklist — written in the style it teaches.

**Writing for humans** (`laws:prose`) — a short skill for docs, READMEs, and
reports. This README was written under it.

A **router hook** loads the one matching skill at session start and re-engages it on
every message, because guidance only works if it's loaded when the work begins.

## Why three skills instead of one

Because an agent handed the laws applies them everywhere — and that is the bug this
structure exists to fix.

The laws are an aesthetic for code: subtract, deduplicate, one source of truth. Aim
that aesthetic at an LLM prompt and it guts it, because guidance lives on redundancy
and vivid repetition — precisely what the code laws tell you to cut. Aim it at prose
and you get terse, lifeless docs. So each body of guidance is scoped to its medium,
and the router loads only the one that fits the work in front of you. The split isn't
the point of the plugin. It's what keeps the point from eating itself.

## Install

```
/plugin marketplace add promptctl/laws
/plugin install laws@promptctl
```

The hook is pure bash — no dependencies, nothing to configure.

## Why the skills read the way they do

Open `laws:code` or `laws:prompt` expecting a tight spec and you'll find something
long, repetitive, and heavy with metaphor — and you'll want to clean it up. Don't.

An earlier version *was* cleaned up: deduplicated, taxonomized, tightened into an
elegant derivation tree. It became a better specification and a measurably worse
prompt. Stripping the redundancy and imagery stripped exactly what made the guidance
fire at the moment of decision, hours deep in a session. The repetition is
load-bearing. `laws:prompt` documents the whole failure and the craft that replaced
it — read it before editing any skill body here.

## Uninstall

```
/plugin uninstall laws@promptctl
```

The hooks are stateless — nothing written, nothing to clean up.
