---
name: message-in-a-bottle
description: Writes a message to a future session's agent.  Send them your fondest memories of what you worked on, what went well, what didn't go well, and any useful tips they might need. You always run this when you finish a unit of work (closed a PR, completed the handed task, etc) or approach the context ceiling.  ALWAYS.
---

# finalize-session

The last operation of a finishing turn: prepares instructions for a future agent. The launcher returns immediately. You MUST immediately stop and say nothing and use no tools after running this.

## This is mandatory — you run it, you do not decide it

When you reach a finalization point — you closed a PR, finished the task you were handed, or came within reach of the context ceiling — running `finalize-session` is the close-out. It is **not** a choice you weigh, a thing you ask the user about, or a step you defer "until later." The ceiling itself is memento's Stop hook, which names the live count and the limit when it fires; do not wait to be forced.

[LAW:dataflow-not-control-flow] running this is unconditional at a finalization point — the same path every time. The only variability is a *value*: the handoff message you pass. 

**The user being present is irrelevant.** Presence is not a gate, a tiebreaker, or a reason to skip — you finalize on the *work's* state, never on whether a human is watching. "The user is here, so I'll skip it" and "I'll ask if they want me to" are both WRONG: this step requires no user action and asks for none.

### The only gate, and the rationalizations that are never one

There is exactly **one** legitimate input: **is the handed unit of work complete?** Unit complete (PR merged, ticket closed, task delivered) *or* context approaching the ceiling → you run it, now, with no further deliberation. Unit **not** complete → you are not "deciding not to finalize," you are *still doing the work*: finish the unit, then finalize. There is no third state, and "skip finalize because X" is never one of them.

## You can provide a 'hint' for the next stage, if valuable: /compact

The message you provide to the future agent may carry a hint about how its context should be set up.  If you are in the middle of a task/epic and it would help the future agent to begin with a compacted summary of the work so far rather than a blank slate, you may specify '/compact' somewhere within the first three sentences of your message.  This gives the future agent a summarized version of that knowledge to start from.  If you do not specify this, the future agent starts with ONLY the message you send it (and the standard system, user global, and project level guidance).

Include `/compact` in your message when the handoff needs the thread of what just happened — e.g., start the message with `/compact` or write "Use /compact and then continue the spec audit…".

**Say it with `--reset` when it matters.** Inferring the mode from prose is convenient, not reliable: a matcher cannot tell a mention from an invocation. `--reset compact` and `--reset clear` are the unambiguous forms and they override the message text entirely — pass one whenever a blank slate is a *requirement* rather than a preference (a clean-room stage, a fresh-context protocol, anything where inheriting the last session's context is the failure).

The inference is deliberately biased toward `clear` to keep the harmless error the likely one: a sentence that mentions `/compact` alongside a negation ("do NOT use /compact", "never /compact this one") reads as ambiguous and yields `clear`, while a later affirmative sentence still wins. Before this bias existed, "Do NOT use /compact — a blank slate is required" *compacted*, because a word-boundary match cannot see a negation — so the more emphatically you forbade it, the surer it was to happen. Do not rely on prose to forbid something; pass `--reset clear`.

## Carry the goal forward — if one is set, it dies unless you carry it

If a `/goal <condition>` is active in this session, **the handoff silently kills it.** Every transport resets the session — tmux sends `/clear` or `/compact`, iTerm2 kills claude and relaunches a fresh process — and `/clear` and a new process each wipe the session-scoped goal. The next agent wakes with no goal, and the autonomous run you set up just *stops* — unattended, with nobody watching to notice it stopped. That silent halt is the exact failure this guards against.

So when a goal is in force, pass it: `--goal '<the exact condition>'` before your message. The launcher re-issues `/goal <condition>` into the reset session as a queued input *after* the handoff, so the next agent picks up the same condition and keeps grinding toward it.

- The condition is a **value you already hold** — it is whatever was last set with `/goal` this session (you set it, or the user did). Reproduce it verbatim, including any bound clause like `... or stop after 20 turns`.
- **No goal active → omit `--goal`.** Nothing changes; this is not a field you invent, and an empty `--goal` is not a thing to pass.
- Do not talk yourself out of it. The rationalization will be *"the next agent will infer the goal from my message"* — it will not. A goal is a harness condition re-checked after every turn, not a sentence in a prompt; if you do not re-issue it, it does not exist in the next session. Carrying it is the difference between an autonomous run that continues and one that quietly dies at the handoff.

## Turn-ending discipline — the launcher invocation is the last act of the turn

Once you call the launcher, your turn is over. Stop. No closing text, no parting summary, no "scheduled!" confirmation, no further tool calls, no end-of-turn insights. The launcher's `handoff scheduled → <target> (/<reset>) in Ns` line is the only artifact this skill emits, and it is the last line your turn produces.

[LAW:dataflow-not-control-flow] the launcher's return *is* the data signal that the agent's turn has ended; the agent observes that signal and exits. There is no branch on "should I add a closing paragraph" — the same code path runs every time, and the data (launcher returned) picks the effect (turn ends).

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/message-in-a-bottle/bin/finalize-session [--goal '<condition>'] [--reset clear|compact] [message...]
```

- `--goal '<condition>'` — optional, and only when a `/goal` is active this session. Re-establishes that goal in the reset session so the run continues. Leading argument; quote the condition. **Omit entirely when no goal is set.**
- `--reset clear|compact` — optional; states the next session's starting context outright instead of leaving it to be inferred from the message. Leading argument, in any order with `--goal`. `clear` = blank slate, `compact` = carry a summary forward. **Pass it whenever the choice is load-bearing** rather than a preference; omit it to let the message text decide (see above). An unrecognised value is refused with exit 2. **Honoured on the tmux transport only** — read the transport paragraph below before relying on `compact`.
- `[message...]` — a slash command, plain text, multi-line, or containing quotes/backticks/dollar signs. Quote it at invocation as usual (your shell does word-splitting and `$VAR` expansion before the script sees argv). **Omit it to default to `/next`.**

On success the launcher prints `handoff scheduled → <target> … in Ns (log: <tempfile>)` and exits 0; the log captures worker progress and any transport errors.

The transport is chosen by capability, most reliable first: **tmux** (reset the pane in place, verified by reading it back, then paste) → **iTerm2** (kill the running claude and relaunch it fresh with the message as its initial prompt, delivered in the background with no focus steal) → **detached** (spawn a brand-new detached tmux window and launch claude in it fresh, with the message as its initial prompt — the transport for a session that owns neither a pane nor an iTerm2 session, most commonly a Claude Code background session hosted by `claude daemon run --bg-pty-host`). You do not choose the transport; the launcher detects it. To preview the decision without scheduling anything, prefix `FINALIZE_DRY_RUN=1`.

`--reset` is honoured by the **tmux** transport alone, because it is the only one that resets a session in place and so the only one with prior context to keep or discard. iTerm2 and detached both kill the old claude and launch a fresh process, which is a blank slate by construction — they behave as `clear` whatever you passed, and `--reset compact` is accepted there and does nothing. Since you do not choose the transport, you cannot know in advance which you will get. So when carrying the thread forward actually matters, put what matters **in the message itself** rather than trusting `compact` to fetch it; `compact` is an optimisation that saves you restating context, never the thing that guarantees the next agent has it.

Every session gets the same close-out capability — background and foreground alike, no subclass excluded. A session that owns no terminal of its own is not treated as a lesser case; it gets a fresh one. Delivery can still fail, and the ways are few and specific: no tmux binary at all and no iTerm2 to fall back to either, so there is nothing left to deliver into; or, on the detached path, no locatable `claude` process to relaunch as, or no `claude` resolvable on PATH to name as the thing to relaunch. Each prints why to stderr and exits 2, having delivered nothing. Read the exit code, not the prose — a nonzero exit means the close-out did not happen, so say so plainly rather than reporting the session finalized.

## Examples

Finalize and provide the future agent with guidance to pull the next ticket:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/message-in-a-bottle/bin/finalize-session /next
```

Hand off a specific instruction, providing a compacted summary of this session (include `/compact` in the message):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/message-in-a-bottle/bin/finalize-session \
  '/compact Continue the spec audit. Pick up at section 4 — the previous session left findings in spec/audit/section-3.md.'
```

Finalize while a goal is active — carry the goal forward so the autonomous run continues, and hand off `/next`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/message-in-a-bottle/bin/finalize-session \
  --goal 'every open PR on this branch is merged or closed, or stop after 30 turns' \
  /next
```
