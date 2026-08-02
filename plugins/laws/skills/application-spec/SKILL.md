---
name: application-spec
description: Produce a thorough, functional, clean-room specification of an existing application - every externally observable behavior (invocation, inputs, outputs, configuration, startup requirements, shutdown, error behavior, interactions with external systems) captured precisely enough for an independent team to reimplement the application without ever seeing it, and no implementation internals, so the spec stays legally clean. Use when the user says "write a cleanroom spec", "spec this application for reimplementation", "black-box spec", "behavioral spec of this app", or wants an existing system specified for a from-scratch rebuild. Works the same on a repo, a CLI, a UI, a SaaS, or CI - the target's kind changes where you observe, never what the spec looks like. Not for documenting internals; the spec deliberately excludes them.
---

# Producing this artifact

The craft for this medium lives in `references/craft.md`, relative to this skill's
base directory. Do not read it in this conversation - it is the writing agent's
material, and loading it here stacks guidance this session does not need.

Produce the deliverable with a subagent:

1. Dispatch a fresh subagent (one that inherits no conversation context). Its
   prompt must contain:
   - the complete requirements, in the requester's own words - anything omitted
     does not exist for the subagent
   - the target: the repo path, or how to reach the application (command, URL,
     credentials) - every evidence channel the subagent may use
   - the exact output path for the spec (default: an `appspec/` directory at the
     target root)
   - the acceptance criterion: an independent team holding only the spec could
     rebuild the application, and no sentence in the spec states a fact an
     outside observer of the running application could not confirm
   - as its first instruction: read `references/craft.md` (give the absolute path,
     resolved from this skill's base directory) before touching the target
2. When it returns, read the artifact it produced - the spec files, not its
   report - and spot-check both directions: sample surfaces for completeness,
   sample sentences for leaked internals. If it misses, re-dispatch with the
   corrections stated explicitly.

If this harness cannot dispatch subagents, read `references/craft.md` now and
apply it directly yourself.
