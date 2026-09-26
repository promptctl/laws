# The in-session craft switch, preserved on a branch

The code that let a running session retire one craft and take up another is no longer
on master. It lives, complete and unchanged, on the branch `keep/craft-switch`. This
note says what that code did, why it was removed, and how to get it back.

## What it was

The conflict gate in `plugins/laws/hooks/scripts/skill-router.sh` refuses to load a
craft that is incompatible with one already engaged, because the second craft's
guidance corrupts work done under the first. Until `promptctl-injector-wih` lands, the refusal also carries
an offer: run `laws-switch <choice>` and the session would move to the new craft
without a relaunch. The four choices are `reject` (stay put), `tombstone` (keep the
conversation, replace the loaded craft's text with a stub), `rewind_summarize` (rewind
to just after the craft loaded and carry the work forward as a summary the agent
writes), and `rewind_discard` (rewind to just before the craft loaded).

Enacting a choice against a live conversation needs a hand inside the running app.
That hand was the injector: a node host that loaded Claude Code's own module graph
under a reconstructed Bun surface, found the conversation controller by seam, and
edited the in-memory message array. The switch was the injector's reason to exist in
this repo.

## Why it was removed

The owner decided on 2026-09-24 that the injector was too much complexity for a
repository whose job is guidance. The hosting machinery moved to `~/code/cc-extra`, a
repo built for augmenting Claude Code, and this plugin no longer depends on it. With no
injector there is nothing to enact a switch, so the gate's offer goes too: the gate will
refuse and name a fresh session as the alternative. Removing the offer, the launcher, and
the dead half of `laws-excise.js` is tracked as `promptctl-injector-wih`.

The switch had one open defect when it was shelved, recorded in the closed ticket
`promptctl-injector-bpx`. A live switch edits only the in-memory conversation, so a
session resumed later comes back unswitched. Native `/rewind` survives a resume once
one more turn follows it, because the app repoints its `last-prompt` record; the live
switch was measured on 2.1.258 as not doing that. Whether it differs on 2.1.270 was
never confirmed. Anyone reviving the switch should start there.

## How to get it back

The branch is pinned at commit `eea4ecc`, the tip of the former `bun-surface` work, so
it holds the switch together with everything it ran on:

- `plugins/laws/hooks/injector/live-switch.js` turns a decision into edits on the live
  message array, as a pure planner plus one applier that touches the controller.
- `plugins/laws/hooks/injector/switch-request.js` composes a request into an applied
  switch: reads the pending offer, re-runs `decide()` against the transcript as it
  stands, and refuses by name when nothing is pending or the conflict has lapsed.
- `plugins/laws/bin/laws-switch` is the command the offer pointed at.
- `plugins/laws/hooks/scripts/laws-excise.js` still carries the on-disk half:
  `rewindTo`, `exciseAt`, `writeAtomic`, and the `SWITCH_ACTIONS` bodies.
- The rest of `plugins/laws/hooks/injector/`, and `SEAMS.md` there, which records every
  seam the switch relied on and how each was measured.

Each file has a test beside it. To read or revive the code:

```
git fetch origin keep/craft-switch
git worktree add .claude/worktrees/craft-switch keep/craft-switch
```

For the hosting layer alone, `~/code/cc-extra` is the maintained copy and is newer than
what the branch holds. The two switch files and `bin/laws-switch` exist only on the
branch; `cc-extra` does not carry them and does not need them.

Do not delete `keep/craft-switch`. The former `bun-surface` and
`injector-retire-bun-inspect` branches are superseded by it and can go.
