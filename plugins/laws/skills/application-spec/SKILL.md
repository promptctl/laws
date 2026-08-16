---
name: application-spec
description: Produce a thorough, functional, clean-room specification of an existing application - every externally observable behavior (invocation, inputs, outputs, configuration, startup requirements, shutdown, error behavior, interactions with external systems) captured precisely enough for an independent team to reimplement the application without ever seeing it, and no implementation internals, so the spec stays legally clean. Use when the user says "write a cleanroom spec", "spec this application for reimplementation", "black-box spec", "behavioral spec of this app", or wants an existing system specified for a from-scratch rebuild. Works the same on a repo, a CLI, a UI, a SaaS, or CI - the target's kind changes where you observe, never what the spec looks like. Not for documenting internals; the spec deliberately excludes them.
---

# Producing this artifact

The craft for this medium lives in `references/craft.md`, relative to this skill's
base directory.

1. Read `references/craft.md` before touching the target.
2. Fix these before you write:
   - the complete requirements, in the requester's own words
   - the target: the repo path, or how to reach the application (command, URL,
     credentials) - every evidence channel available to you
   - the exact output path for the spec (default: an `appspec/` directory at the
     target root)
   - the acceptance criterion: an independent team holding only the spec could
     rebuild the application, and no sentence in the spec states a fact an
     outside observer of the running application could not confirm
3. Write the spec against the craft.
4. Read back the spec files you produced - the files themselves, not your memory
   of writing them - and spot-check both directions: sample surfaces for
   completeness, sample sentences for leaked internals. If it misses, revise until
   it holds.
