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

## Seam anchors carried forward (re-derive against the 2.1.226 bundle before use)

From the recovered `ONE-LAW-SEAMS.md` (pinned to 2.1.197 — offsets are stale, anchors are not):

- **SEAM 1 — skill-load funnel `efl(messages, toolUseId)`.** The single point every Skill-tool load
  passes through; stamps `sourceToolUseID` onto each user message. Anchors: strings
  `tengu_skill_tool_invocation`, `SkillTool returning `, and the body fingerprint
  `function \w+\(\w+,\w+\)\{if\(!\w+\)return \w+;return \w+\.map\(…sourceToolUseID:\w+\}`. Wrapping
  it lets `craftMediumOf` (from laws-excise.js) read the incoming craft in-process — the detection
  reuses Part A verbatim, one source of truth across the boundary.
- **SEAM 2a — resume-time trim `deserializeMessagesWithInterruptDetection(…, rewindAnchorUuid)`.**
  The rewind driver for options 3/4. Set `rewindAnchorUuid` to `decide().rewind.summarizeTo` (#3)
  or `.discardTo` (#4). Anchors: the export-map literal `deserializeMessagesWithInterruptDetection`
  and the `rewindAnchorUuid` property name.
- **DO NOT TOUCH — `fileHistoryRewind`.** That reverts FILE edits. The gate is conversation-only;
  on-disk deliverables must survive every option, including discard. Anchor: `Rewinding to snapshot for `.

## Status ledger

- DONE: compatibility policy has one home; `decide()`/`exciseAt()` fire only on an incompatible
  pair and tombstone only the conflicting craft (`../scripts/laws-excise.js` + tests).
- DONE: injection channel re-verified on 2.1.226; `inspect-eval.js` packages the primitives.
- OPEN: pick Path A or B for reload; wire detection→gate→reload; live-verify the four effects with
  the on-disk-files-survive invariant. Distribution of the launcher is sibling `promptctl-routing-rat.7`.
