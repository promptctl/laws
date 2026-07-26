---
name: prompt
description: Craft reference for any text another LLM will consume — task prompts, subagent instructions, prompts written into files or code, and persistent agent guidance (CLAUDE.md files, system prompts, skill bodies, hook text). Use BEFORE writing either kind. The regime determines the craft — task prompts want terse, complete, say-it-once instructions; persistent guidance wants redundancy, imagery, and rehearsed temptations — and applying either regime's style to the other is a known failure mode.
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
2. When it returns, read the artifact it produced — the file, not its report —
   and check it against the requirements. If it misses, re-dispatch with the
   corrections stated explicitly.

If this harness cannot dispatch subagents, read `references/craft.md` now and
apply it directly yourself.
