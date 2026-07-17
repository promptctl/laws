# laws

A Claude Code plugin that scopes quality guidance by the medium of the deliverable —
and ships the guidance itself.

The premise: the standards that make code excellent (deduplicate, subtract, one source
of truth) actively destroy behavioral guidance, and the instincts that make prose
pleasant hide bugs in code. So this plugin carries one skill per medium, plus a hook
that reminds Claude to load the right one before starting work.

## What's inside

| Component | What it does |
|---|---|
| `laws:code` skill | The universal architectural laws: 19 laws under 2 root framings, each with a statement, a metaphor, the rationalization it must defeat (quoted, with the refusal), a one-line diagnostic, and its place in the derivation tree. Includes worked WRONG/RIGHT examples and domain bindings for UI, APIs, schemas, pipelines, distributed systems, and CLIs. |
| `laws:prose` skill | Writing guidance for human-audience text: docs, READMEs, reports, messages. |
| `laws:guidance` skill | The craft of writing persistent agent guidance (CLAUDE.md files, system prompts, skill bodies): six devices with their mechanisms, explicit anti-goals, and a shipping checklist. Ships the original style exemplar the devices were observed in. |
| Skill-router hook | Injects a short routing instruction at prompt submit, before subagent spawns, and (throttled to every 5 minutes) after file reads: identify the medium, load the matching skill, hold its bar. |

## Install

```
/plugin marketplace add promptctl/laws
/plugin install laws@promptctl
```

Or from a local clone:

```
/plugin marketplace add ~/code/promptctl_laws
/plugin install laws@promptctl
```

The hook requires `jq` on your PATH.

## Why the laws read the way they do

The laws skill is long, repetitive, and vivid on purpose. An earlier version was
rewritten to be terse and deduplicated — a better specification that turned out to be
a worse prompt, because the redundancy and imagery were what made the guidance fire at
the moment of decision. That failure and the craft that replaced it are documented in
the `laws:guidance` skill; read it before editing any of the skill bodies
here, and do not "clean them up."

## Uninstall

```
/plugin uninstall laws@promptctl
```

The hook writes one state file (`~/.claude/.last_laws_router_reminder`) for its
cooldown; remove it if you want no trace left.
