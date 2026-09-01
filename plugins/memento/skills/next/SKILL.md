---
name: next
description: Pull the next ticket — pointer only; the skill now ships in the separate `memento` plugin.
---

# Moved

This skill is no longer implemented here. Picking up the next ticket now lives in the
`memento` plugin, in its own marketplace. Nothing in this file tells you how to do it,
and reconstructing it from memory produces a second, drifting copy — don't.

Install it:

```
/plugin marketplace add promptctl/memento
/plugin install memento@memento
```

Installing is the default path, not the optional one. "I'll just pick a ticket myself
this once" is the rationalization to refuse: run the two lines above first.

If installation genuinely cannot happen in this session, do exactly this: tell the user
in one line that `next` moved to the `memento` plugin, paste the two install commands
above, then pick up the work with your own judgment. Do not improvise a replacement
procedure and do not present it as this skill.
