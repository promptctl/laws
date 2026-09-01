---
name: address-pr-reviews
description: Address open PR review findings — pointer only; the skill now ships in the separate `memento` plugin. Use when the user says "address the PR review", "handle the review threads", "go through the review comments", or asks to respond to PR feedback on a specific PR or the current branch's PR.
---

# Moved

This skill is no longer implemented here. The PR-review loop now lives in the `memento`
plugin, in its own marketplace. Nothing in this file tells you how to run it, and
rebuilding the loop from memory produces a second, drifting copy — don't.

Install it:

```
/plugin marketplace add promptctl/memento
/plugin install memento@memento
```

Installing is the default path, not the optional one. "The PR only has three comments,
I'll just handle them" is the rationalization to refuse: run the two lines above first.

If installation genuinely cannot happen in this session, do exactly this: tell the user
in one line that `address-pr-reviews` moved to the `memento` plugin, paste the two
install commands above, then work the review threads with your own judgment. Do not
improvise a replacement loop and do not present it as this skill.
