---
name: ticket
description: Craft reference for breaking work into epics and issues another agent will build — backlog planning, decomposing a feature or fix, writing or splitting tickets, defining acceptance criteria. Use BEFORE you create or groom tickets. A ticket is read later, against a moved codebase, by an agent with none of the planning conversation — the craft covers what a ticket must carry, how work is sized and ordered, and what makes done checkable.
---

# Producing this artifact

The craft for this medium lives in `references/craft.md`, relative to this skill's
base directory. Do not read it in this conversation — it is the writing agent's
material, and loading it here stacks guidance this session does not need.

Produce the deliverable with a subagent:

1. Dispatch a fresh subagent (one that inherits no conversation context). Its
   prompt must contain:
   - the complete requirements, in the requester's own words — anything omitted
     does not exist for the subagent
   - the exact output path and format of the artifact
   - a verifiable acceptance criterion
   - as its first instruction: read `references/craft.md` (give the absolute path,
     resolved from this skill's base directory) before writing anything

   Keep the prompt clean. It carries the problem, the requester's own words, the
   genuine requester-imposed constraints, the output spec, and the acceptance
   criterion — and none of the solutions or mechanisms you have been forming this
   session. The temptation is strong precisely here: you have spent the whole
   conversation designing an approach, and it feels helpful to hand the subagent
   your ideas so it "isn't starting cold." Do not. Whatever *how* you pour into the
   prompt comes back out as prescription in the artifact — the subagent faithfully
   turns your context into wording, and your half-formed answer becomes a pinned
   requirement the eventual implementer builds instead of the right thing. The
   approach is the implementer's to discover; the prompt gives the problem and the
   constraints, not the answer. Give the subagent what must become true, and let it
   write the ticket that leaves the *how* open.
2. When it returns, read the artifact it produced — the file, not its report —
   and check it against the requirements. If it misses, re-dispatch with the
   corrections stated explicitly.

If this harness cannot dispatch subagents, read `references/craft.md` now and
apply it directly yourself.
