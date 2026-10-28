# Design goals: the `intent` skill

The `intent` skill governs how an agent reads what the requester said - a correction, a constraint, an instruction - and what it records from it. It is not a medium: it has no output of its own. It is the input side that every medium skill shares, and it has one home so the rule is not restated in five places with five drifts. The one thing it is for: a correction is read for the general rule it is an instance of, and the rule - with its reason - is what gets recorded, in plain technical language.

## The premise everything follows from

Feedback arrives as an instance. "Don't do that" points at one case of something general the requester has not stated and expects the agent to find. The lossy step is the write-down: when the case is recorded - in a ticket, a handoff, a CLAUDE.md line, a memory - without the situation that produced it, the next agent inherits a ban on an action that was wrong once, for a reason nobody wrote down. Quoting the requester makes this failure mandatory: a quote keeps the wording and drops the situation. The owner's requirement (2026-10-26): the skills carry the requester's intent, found from what they said, never their words.

## What good output looks like, and the choice that gets there

- **The rule, not the instance.** Name the specific action in the specific situation; find what about the situation made it wrong; state the rule about that feature with the harm it prevents. The case becomes the example under the rule.
- **Two checks before anything is written.** Can the same action be right somewhere? If not, it is a ban. Can a different action be wrong for the same reason? If not, it is the surface, not the rule.
- **Intensity read as weight, not scope.** Tone and emphasis say how much the case mattered; they do not widen the rule, and they do not enter anything written from it.
- **Every kept rule carries its reason**, so a later reader can tell when it has lapsed. A rule whose reason does not fit the current situation is surfaced and asked about, not obeyed silently and not dropped silently.
- **The current request outranks an extracted rule.** The rule is a reading of past intent; the request is present intent.

## What it deliberately avoids, and why

- **Quoting the requester** - keeps the wording, drops the situation; the next reader cannot tell what it was an instance of.
- **Bans** ("never do X") - wrong the next time X is the job, and silent about the next situation where the real rule applies.
- **Register carried into content** - the requester's tone is not part of the requirement.
- **Rules used against the requester** - an old correction cited to resist what they are asking for now.

## Where it is reached from

The session-start text names it beside the rung-S pointer; the per-turn engage text points at it in one clause, since a correction arrives as a user message and that hook fires on every one; each medium skill's step 2 points at it where it fixes the requester's intent before writing. The skill is a Skill-tool load, not a path, because the medium skills cannot know where the plugin is installed.
