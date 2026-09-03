---
name: prompt
description: Craft reference for any text another LLM will read - a one-turn instruction to a subagent, a message that opens a long run, a prompt written into a file or code, a system prompt, a CLAUDE.md, a skill body, a hook. Use BEFORE writing any of them. Every text enters the reader's context at distance zero; what differs is the hold - how many turns after entry it must still be steering the reader. The hold picks the craft, not the kind of file and not the text's length. A one-turn hold wants terse, complete, said-once. A long hold keeps the body terse and hardens only the lines nothing will re-ask - boundaries, the stop condition, constraints that bite late. A whole-session hold against situations the writer cannot see buys redundancy, imagery, and rehearsed temptations. Reading the hold off the text's length or its filename is the known failure.
---

# Producing this artifact

The craft for this medium lives in `references/craft.md`, relative to this skill's
base directory.

1. Read `references/craft.md` before writing anything.
2. Fix the deliverable before you write it: the exact output path and format, and
   the complete requirements in the requester's own words.
3. Write it against the craft.
4. Read back the file you produced - the file itself, not your memory of writing
   it - and check it against the requirements and the craft. If it misses, revise
   until it holds.
