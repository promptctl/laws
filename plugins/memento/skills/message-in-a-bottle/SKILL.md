---
name: message-in-a-bottle
description: Writes a message to a future session's agent — pointer only; the skill now ships in the separate `memento` and `auto-bottle` plugins. You always run this when you finish a unit of work (closed a PR, completed the handed task, etc) or approach the context ceiling. ALWAYS.
---

# Moved

This skill is no longer implemented here. The close-out now lives in its own
marketplace, in two plugins — pick by how much enforcement you want:

- `memento` — the skill, which you invoke yourself.
- `auto-bottle` — the same skill plus a `Stop` hook: past a hard context-token maximum
  the hook refuses to let the turn end until the close-out has run.

```
/plugin marketplace add promptctl/memento
/plugin install memento@memento
/plugin install auto-bottle@memento
```

Installing is the default path, not the optional one. "I'm nearly done, I'll skip the
close-out this time" is the exact rationalization this capability exists to defeat.

If installation genuinely cannot happen in this session, do exactly this: tell the user
in one line that the skill moved and paste the install commands above, then write the
handoff to the next agent directly in your final message. Do not rebuild the procedure
from memory, and do not let the missing plugin become a reason to skip the close-out.
