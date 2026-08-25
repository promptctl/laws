# The injected craft-compatibility gate — status, primitives, and frontier

Part B of `promptctl-routing-rat.5`: the runtime mechanism that turns the PreToolUse guard's
plain DENY of an incompatible craft load into a four-choice SWITCH
(reject / tombstone / rewind+summarize / rewind+discard), enacted against the live session.

Companion to Part A (`../scripts/laws-excise.js`, the pure transcript surgery + `decide()` gate)
and to the compatibility policy (`../scripts/incompatible-crafts.txt`, the one home both the
bash guard and the JS gate read).

> Bundle symbol names are minified and **drift every Claude Code release**. Resolve seams by the
> invariant anchors below (strings, body fingerprints, stable env/CLI surfaces), never by a
> minified name. Everything in "Verified primitives" was re-confirmed on the shipped **2.1.226**
> binary; re-run `inspect-eval.js --probe` after any update to catch drift in seconds.

## The channel: Bun's inspector, opened by an env var

Claude Code ships as a Bun-compiled standalone Mach-O (`~/.local/share/claude/versions/<v>`, a
symlink target of `claude`). It honors `BUN_INSPECT`: set it to a ws URL and the process opens a
WebKit/JSC inspector on that socket. **No code patch — just an env var** — which is why the
channel is stable across weekly minified releases and satisfies the ticket's "lightweight,
shippable in the plugin" bar. For the compiled binary the ws URL you set IS the endpoint; there
is no `http://host:port/json/list` discovery (that exists only for `bun --inspect-brk bundle.js`).

## Verified primitives (shipped 2.1.226) — the foundation is real and current

Reproduce: `BUN_INSPECT="ws://127.0.0.1:9933/dbg?wait=1" claude --help &` then
`node inspect-eval.js ws://127.0.0.1:9933/dbg --probe`.

1. **Inspector opens.** `BUN_INSPECT="ws://127.0.0.1:<port>/dbg?wait=1"` opens a LISTEN socket on
   `<port>` and blocks the process at entry until a debugger sends `Runtime.runIfWaitingForDebugger`.
   (`BUN_INSPECT_WAIT`/`BUN_INSPECT_BRK` alone did not block in probes; the `ws://…?wait=1` form does.)
2. **In-process global eval.** After `Runtime.enable`, `Runtime.evaluate` returns live values from
   the running process — verified reading `process.pid`, `globalThis`, `globalThis.fetch` (a
   function), and `argv = ["bun","/$bunfs/root/src/entrypoints/cli.js", …]` (the bundle runs from
   Bun's virtual FS). Zero-dep client: Node's global `WebSocket` (Node ≥ 22).
3. **Live interactive TUI, not just `--help`.** All of the above works against a real interactive
   session (launched in a tmux PTY under `BUN_INSPECT`), and the session keeps running after the
   eval — the channel does not disturb the TUI.
4. **stdin-injection drives built-in commands.** `process.stdin.push(Buffer.from("/context\r"))`
   evaluated in-process made the `/context` panel render in the live session. The TUI reads stdin
   in pull mode (paused ReadStream, one `readable` listener, zero `data` listeners), so `.push()`
   is the right primitive and a trailing `\r` submits. This runs commands through the session's
   OWN dispatch path — the gate's reload can therefore ride Claude's own mechanisms (`/compact`,
   `/clear`) rather than reaching into minified internals.

`inspect-eval.js` packages primitives 1–4 (`connect`, `evaluate`, `injectStdin`, `probe`).

## The frontier: reloading an edited transcript into a running session

The gate's reload options (tombstone / rewind) edit the ON-DISK transcript, then need the running
session to REFLECT that edit. The blocker, empirically pinned on 2.1.226:

- **The live message store is closure-local, not global.** In the `Runtime.evaluate` context
  `require`/`module` are `undefined` and no `session`/`conversation`/`message` global exists. So
  the in-place reload (`loadConversationForResume` → `setMessagesParams`) cannot be driven from a
  global eval; it needs an in-CLOSURE frame.

Two ways across, an open owner decision (see "Decision pending"):

- **Path A — in-closure injection (owner's stated preference: in-process, no relaunch).** Set a
  `Debugger` breakpoint at a module-scope callsite to get a paused frame with closure access, then
  `Debugger.evaluateOnCallFrame` to call the store's own reload. The skill-load funnel (SEAM 1) is
  the natural pause point: it fires exactly on the 2nd craft load — the trigger AND an in-closure
  entry at once. Cost: needs the 2.1.226 bundle dumped (`Debugger.getScriptSource`) and the seams
  re-derived by anchor; fragile against weekly minification. This is the multi-day part.
- **Path B — restart-in-place (`claude --resume <sid>`).** A launcher wrapper re-execs the public
  resume flag after Part A edits the transcript. Robust (public CLI, no minified anchors) and
  lightweight, but it is the "external relaunch" the owner deprioritized in `promptctl-routing-rat.2`.

### RESOLVED 2026-08-16 on 2.1.226: the rewind is disk surgery — `rewindTo()` in `../scripts/laws-excise.js`

**The frontier above is closed for options 3 and 4.** They need no in-closure frame, no
`rewindAnchorUuid`, and no bundle anchor: a rewind is two edits to the on-disk transcript, and a
plain `claude --resume` then comes up rewound. Measured on a disposable 3-fact session (one fact per
turn, `-p --resume`, project memory deleted first so the conversation was the only source of the
facts). All four combinations were run, and the result is a conjunction:

| surgery | rewound? |
|---|---|
| repoint the trailing `last-prompt` record at the anchor | **no** |
| sever the anchor's children (unroot the tail), pointer untouched | **no** |
| graft a new record onto the anchor | **no** |
| **sever the anchor's children AND repoint `last-prompt`** | **yes** |

The model that fits: the resume takes its leaf from the trailing `last-prompt` record but will not
stop at a node that still has reachable descendants — it follows the branch down to the tip. So the
pointer alone is overridden by the surviving tail, and severing alone leaves the leaf where it was.
Both halves, or nothing. That is also why **no purely additive surgery can ever rewind** — a graft
onto an early anchor is a shallow branch that never displaces the real tail.

`rewindTo(rawLines, anchorUuid, severUuid)` is the one operation, deliberately not shipped as a
separate `sever` step: a half-primitive here is a unit that looks like it works and silently does
not. It is non-destructive — every record stays in the file, only the link of each severed branch
changes, and the discarded conversation remains on disk as an orphan branch. **Verified live**: the
shipped function applied to a real 82-record transcript, then `--resume`, and the session reported
only the pre-anchor fact.

Corrects `promptctl-routing-rat.2`'s "excision = reparent, VERIFIED" (recorded against 2.1.197):
reparenting the FIRST POST-RANGE record is the additive form, and it does not rewind on 2.1.226.
The tombstone half of `.2` is unaffected — that is in-place content replacement, not a tree edit.

Still open for option 2 (tombstone in place, full conversation kept): it edits an early message
without moving the leaf, so a resumed session picks it up, but making the ALREADY-RUNNING session
re-read the file is the reload question below.

## Seam anchors carried forward (re-derive against the 2.1.226 bundle before use)

From the recovered `ONE-LAW-SEAMS.md` (pinned to 2.1.197 — offsets are stale, anchors are not):

- **SEAM 1 — NOT NEEDED, confirmed 2026-08-16. Do not wrap `efl`.** It was to be the in-process
  detection point for a 2nd craft load. The shipped PreToolUse guard already has strictly more than
  it would give: the hook payload carries `tool_input.skill` (the INCOMING craft), `session_id`, and
  — measured with a probe hook on 2.1.226 — **`transcript_path`, the absolute path of the live
  transcript**. So `decide(readFileSync(transcript_path), {incomingMedium})` runs entirely in the
  hook, off public surfaces, before the load is allowed. Full payload keys observed: `session_id`,
  `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `hook_event_name`, `tool_name`,
  `tool_input`, `tool_use_id`. (Was: funnel `efl(messages, toolUseId)`, anchored by the strings
  `tengu_skill_tool_invocation` / `SkillTool returning ` and a `sourceToolUseID` body fingerprint.)
- **SEAM 2a — SUPERSEDED 2026-08-16, do not build against it.** Was the intended rewind driver for
  options 3/4 (`deserializeMessagesWithInterruptDetection(…, rewindAnchorUuid)`, set from
  `decide().rewind.summarizeTo`/`.discardTo`). `rewindTo()` achieves the same effect through the
  transcript alone, so this minified anchor buys nothing and costs a re-derivation every release.
  Kept only as a record of what was mapped.
- **DO NOT TOUCH — `fileHistoryRewind`.** That reverts FILE edits. The gate is conversation-only;
  on-disk deliverables must survive every option, including discard. Anchor: `Rewinding to snapshot for `.

## Status ledger

- DONE: compatibility policy has one home; `decide()`/`exciseAt()` fire only on an incompatible
  pair and tombstone only the conflicting craft (`../scripts/laws-excise.js` + tests).
- DONE: injection channel re-verified on 2.1.226; `inspect-eval.js` packages the primitives.
- DONE (2026-08-16): the rewind for options 3/4 is disk surgery — `rewindTo()`, sever + repoint,
  verified live against a real transcript. **SEAM 2a is not needed**, and neither is native
  `/rewind` with its modal arrow-key driving. See the resolved section above.
- DONE (2026-08-23): the reload — Path B, via `../../bin/claude-laws`. All four options edit the
  transcript, and a RESUMED session reads it while the already-running one does not; the launcher
  closes that gap by relaunching, applying the surgery after exit, and `--resume`ing so the
  corrected transcript is reread. `claude-laws.test.sh` exercises the four options end to end,
  including the multi-craft, one-shot and session-selector cases. The on-disk-files-survive
  invariant still holds by construction (`rewindTo`/`exciseAt` write nothing but the transcript)
  and is now exercised rather than only argued. Distribution of the launcher is sibling
  `promptctl-routing-rat.7`.
- DONE (2026-08-16): SEAM 1 is unnecessary, confirmed by probe — the PreToolUse payload carries
  `transcript_path` alongside `tool_input.skill`, so detection + `decide()` run in the hook off
  public surfaces. **With SEAM 1 and SEAM 2a both retired, the gate carries NO minified anchor at
  all**: detection is a hook, enactment is two pure functions over the transcript, and the reload
  is a launcher driving the public CLI. Nothing here needs re-deriving when Claude Code updates.
