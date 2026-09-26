# The in-session craft switch, preserved on a branch

The code that let a running session retire one craft and take up another was
removed from this repo under `promptctl-injector-wih`. It is preserved, complete and
runnable, on the branch `keep/craft-switch` and the tag `craft-switch-preserved`, both
at commit `eea4ecc`. That commit is not on master: it is master's injector plus the four
commits that finished the Bun surface (PR #73, never merged). The tree as it stood on master
before the removal is `5d61c1f`. This note says what that code
did, why it is going, what was known to be wrong with it, and how to get it back.

## What it was

The conflict gate in `plugins/laws/hooks/scripts/skill-router.sh` refuses to load a
craft that is incompatible with one already engaged, because the second craft's
guidance corrupts work done under the first. In a session hosted by the `claude-laws`
launcher, and only there, the refusal also carried an offer: run `laws-switch <choice>`
and the session would move to the new craft without a relaunch. A stock session got
the bare refusal. The four choices are `reject` (stay put), `tombstone` (keep the
conversation, replace the loaded craft's text with a stub), `rewind_summarize` (rewind
to just after the craft loaded and carry the work forward as a summary the agent
writes), and `rewind_discard` (rewind to just before the craft loaded).

Enacting a choice against a live conversation needs a hand inside the running app.
That hand was the injector: a node host that loaded Claude Code's own module graph
under a reconstructed Bun surface, found the conversation controller by seam, and
edited the in-memory message array. The switch was the injector's reason to exist in
this repo, and the hosted-only condition on the offer is why.

## Why it is going

The owner decided on 2026-09-24 that the injector was too much complexity for a
repository whose job is guidance. The hosting machinery moved to `~/code/cc-extra`, a
repo built for augmenting Claude Code, and this plugin will not depend on it. With no
injector there is nothing to enact a switch, so the offer went too: the gate refuses and
names a fresh session as the alternative. `promptctl-injector-wih` removed the offer, the
launcher, the injector directory, and the whole of `laws-excise.js` - once nothing enacts
a switch, its policy half has no caller either, and `skill-router.sh` is the one reader
of `incompatible-crafts.txt`.

## What was known to be wrong

Four defects were on record when the switch was shelved. None is fixed on the branch.

- A live switch edits only the in-memory conversation, so a session resumed later
  comes back unswitched. Native `/rewind` survives a resume once one more turn follows
  it, because the app repoints its `last-prompt` record; the live switch was measured
  on 2.1.258 as not doing that, and 2.1.270 was never re-measured. This is the closed
  ticket `promptctl-injector-bpx`, whose comments hold the measurements.
- `rewind_summarize` stubs the first conflicting message while the rewind anchors on a
  separately chosen one, and nothing checks they are the same message.
- The `rewind_discard` guard for "nothing before the craft load" tests a raw index
  against a store that carries holes, so a leading hole truncates the whole
  conversation and reports success.
- A throw from `consumeOffer()` escapes after the live store has already been cut,
  leaving the offer enactable a second time.

The last three come from a 2026-09-23 review recorded in `~/code/cc-extra/reference/README.md`.

## How to get it back

The branch and tag sit at the tip of the former `bun-surface` work, so they hold the
switch together with everything it ran on:

- `plugins/laws/hooks/injector/live-switch.js` turns a decision into edits on the live
  message array, as a pure planner plus one applier that touches the controller.
- `plugins/laws/hooks/injector/switch-request.js` composes a request into an applied
  switch: reads the pending offer, re-runs `decide()` against the transcript as it
  stands, and refuses by name when nothing is pending or the conflict has lapsed.
- `plugins/laws/bin/laws-switch` is the command the offer pointed at.
- `plugins/laws/hooks/scripts/laws-excise.js` carries the policy reader and the on-disk
  half: `decide()`, `rewindTo`, `exciseAt`, `writeAtomic`, and the `SWITCH_ACTIONS` bodies.
- The rest of `plugins/laws/hooks/injector/`, and `SEAMS.md` there, which records every
  seam the switch relied on and how each was measured.

Those four files each have a test beside them. To read or revive the code:

```
git fetch origin keep/craft-switch
git worktree add .claude/worktrees/craft-switch keep/craft-switch
```

`~/code/cc-extra` is the maintained home of the hosting layer, and its `src/` is newer
than what the branch holds. Its `reference/` directory keeps read-only copies of
`live-switch.js` and `switch-request.js` with their tests, plus the craft-gate seam
history, but they cannot run there because `laws-excise.js` is absent. The branch is
the only runnable copy, and the only home of `bin/laws-switch`.

The tag is what pins the commit; the branch is there for convenience. The former
`bun-surface` branch is this same commit and can go. `injector-retire-bun-inspect` was
squash-merged as `c8ef89c` in PR #47, so its content is on master but its commits are
not ancestors of anything; delete it with `git branch -D`, not `-d`.
