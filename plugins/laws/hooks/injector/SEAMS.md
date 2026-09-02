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

## The container format: Bun's module table, read from the installed binary

Packaged as `bun-graph.js`. Reproduce: `node bun-graph.js "$(readlink -f "$(which claude)")"`.

**The NUL-delimited record scan is dead — it cannot read what ships today.** 2.1.226 embedded its
JavaScript as ONE CommonJS module, recoverable by scanning for `\0<path>\0<contents>` records.
2.1.258 embeds an ESM module graph instead: 1,639 code-split chunks
(`/$bunfs/root/chunk-<hash>.js`) around one entry — 1,640 js modules in all — plus native,
compressed and text assets: 1,818 modules, 41.9MB of
contents. A module's NAME and its CONTENTS are no longer adjacent in the file (names sit near offset
69.8M, contents near 156M–188M), so the delimiter scan has nothing to key on; run it against 2.1.258
and it returns `no-contents-record-for-path`. The entry point moved as well: not
`/$bunfs/root/src/entrypoints/cli.js` any more, but `/$bunfs/root/cli`.

Bun writes a MODULE TABLE at the end of the executable and points at it from a 32-byte struct
sitting immediately before a `\n---- Bun! ----\n` trailer. `bun-graph.js` parses that table. Layout,
measured: the struct holds byte_count (u64, at +0), the module table's blob-relative offset (u32,
+8) and length (u32, +12), and the entry point ID (u32, +16). Each table row is 52 bytes — name
pointer (offset u32, length u32) at +0, contents pointer at +8, an encoding byte at +48 (0 binary,
1 utf8, 2 utf16le) and a loader byte at +49 (1 js, 5 file, 10 napi, 13 text). Every pointer is
relative to the blob's start. On macOS the code signature is appended after the trailer, so the LAST
trailer is the real one.

Three things the table buys over the scan, worth stating plainly:

- The container names its own entry point by index, so nothing has to know or guess what the entry
  is called — which matters, because that name has already changed once.
- Each row declares its encoding and loader, so no code sniffs bytes to decide how to decode a
  module or what it is.
- It is coupled to BUN's container format, which changes when Bun changes rather than when Claude
  ships weekly. There is still no version→offset table anywhere in the tree, and no version literal
  in the parser.

**One code path, both binaries — and that is the evidence the parse is right, not merely
plausible.** The same parser reads 2.1.226 (14 modules, entry id 0 =
`/$bunfs/root/src/entrypoints/cli.js`, contents offset 245,797,944, length 23,985,682, sha256
`a96b5f06a9feba9ff8f7ce7f938a7bd1cbc74c7c03ea0c94f68c50dd05a14f7c`) and 2.1.258 (1,818 modules,
entry id 5 = `/$bunfs/root/cli`). Those 2.1.226 numbers are exactly what the old delimiter scan
measured and exactly what `Debugger.getScriptSource` returns from a live session — so the new reader
reproduces the old ground truth byte for byte while also working on the current version.

**The Beta-product banner is still NOT a usable entrypoint anchor.** It heads many embedded modules,
not just the entry, so anchoring on it selects whichever comes first.

Two details of the live-session comparison cost an hour to find and are worth keeping:

- `?wait=1` is wrong for this. It freezes the process at entry, so nothing has been parsed yet and
  `Debugger.enable` yields zero `scriptParsed`. Use a plain `BUN_INSPECT=ws://127.0.0.1:<port>/dbg`
  against a session that is actually running; `Debugger.enable` then replays the existing scripts.
- `--help` exits before you can ask, and JSC reports **`url: ""` for all 244 scripts**, so the entry
  cannot be matched by name. Run the real TUI under a PTY (`script -q /dev/null claude`) and
  identify the script by its source, not its URL.

## Hosting the graph under node: `vm.SourceTextModule`, after two designs that failed

Six modules run the graph under node: `bun-graph.js` reads the container's module table,
`embedded-fs.js` presents the embedded modules as a read-only filesystem, `bun-surface.js` is the
`Bun` global, `bun-runtime.mjs` links and evaluates the graph under `vm.SourceTextModule`,
`boot-channel.js` is the line protocol the host reports on and the launcher reads, and
`bun-host.mjs` is the wiring that connects them. `launch.js` decides whether it worked.

Node's own ES module loader CANNOT host this graph, and the reason is worth recording because two
plausible designs were tried and measured before the third worked. Bun's chunks call
`import.meta.require("/$bunfs/root/chunk-*.js")` — a synchronous, LAZY require between ES modules
that returns a live namespace even when the target is mid-evaluation.

1. Node's `require(esm)` refuses to link a module whose graph touches one currently evaluating:
   `ERR_REQUIRE_CYCLE_MODULE`.
2. Rewriting those call sites into static imports fails differently — it creates cycles the real
   graph never had, which then break on TDZ (`Cannot access 'g3' before initialization`).
3. What works: `vm.SourceTextModule` in `bun-runtime.mjs`, which links the graph itself and hands
   out a namespace on demand exactly as Bun does. It also lets `import.meta` be populated directly,
   so the recovered sources run VERBATIM — there is no source-rewriting step anywhere.

`embedded-fs.js` serves the graph as a read-only filesystem, because chunks read embedded assets by
their virtual path through plain `fs` calls and `Bun.file`. It substitutes `fs`/`fs/promises` for
hosted code only; node's own fs is never patched. `ws` is provided too — Bun ships it built in and it
is the only non-builtin bare specifier the graph imports.

Cost: linking all 1,640 js modules takes ~800ms, first frame ~700ms after that.

### What the code review changed

`bun-runtime.mjs`'s up-front linking loop only worked because Bun happens to emit its module table
dependencies-first: node refuses a second explicit `link()` on a module something else already
pulled in, so an entry-first table would have broken boot with a confusing error. The loop now
checks each module's status instead of relying on that order — found by writing the runtime's first
test against a synthetic graph, which the real graph could never have shown. The second finding is
the doctrine this shim runs on, stated plainly: every member of the `Bun` surface is either a real
implementation or absent. A present-but-wrong stub keeps the process alive while corrupting what it
touched and is invisible; an absent member is recorded and reaches the launcher by name. Members the
graph never uses — `Bun.stdin`, `Bun.stdout`, `Bun.stderr`, `Bun.color` — were deleted rather than
kept as plausible-looking placeholders.

## The boot self-check: observations in the host, the verdict in the launcher

The host reports observations and forms no verdict: `painted` once, the first time the hosted graph
writes to the terminal; a named refusal if the graph cannot be read; and `absent-api <name>` lines as
they occur. A `boot-threw` message is sent even after painting, because a graph that painted and then
died still has the useful message. `launch.js` forms the verdict and owns the deadline. A plan became
the session if it painted AND was still there a settle window later (5s); a clean early exit, or any
exit outside an interactive terminal, also counts, because a one-shot command that already did real
work must never be re-run. A named refusal with nothing painted falls back REGARDLESS of whether the
terminal is interactive: the never-re-run rule protects work a run already did, and a host that
refused before painting did none. The launcher runs a LIST of plans and keeps the first that boots;
the last is stock `claude`, which is the floor.

The settle window exists because of a specific finding: the first byte on stdout is NOT sufficient
evidence of a session. Deleting `Bun.stripANSI` — simulating a Bun API the shim does not have — let
the app print a pre-flight renderer notice, THEN die on `Cannot read properties of undefined
(reading 'replace')`. Byte-watching alone called that booted.

Verified live on 2.1.258, in a real PTY under tmux, not a pipe:

- The launcher boots the extracted graph to an idle, authenticated TUI — input box, statusline,
  model and context meters.
- With `Bun.stripANSI` deliberately removed, the hosted session is detected as not-booted and the
  launcher falls back to stock claude, logging: `claude-laws: hosted session did not start —
  painted, then exited 1 after 1008ms — never became a session (Bun APIs the shim does not have:
  YAML, ant); falling back`. No hang. The parenthetical is on every failure reason: it names the Bun
  APIs the shim was asked for and does not have, streamed as they are seen rather than collected at
  the end, because on a hang the killed host never reaches an end to report from. `Bun.YAML` and
  `Bun.ant` are genuinely absent from the surface and are recorded rather than stubbed; boot does
  not need them. Note that `stripANSI` does NOT appear in that list, and should not: the break
  removes a member's VALUE, not its key, so the Proxy never sees a missing name. The two lists are
  independent — the reason names what died, and the parenthetical names what was missing while it
  ran.
- One caution for whoever runs that break test again: the app persists a `fullscreenAutoDisabled`
  flag in `~/.claude.json` when its renderer fails to start, so a live break test mutates the user's
  config and must be cleaned up afterwards. This is why the automated suite (`launch.test.js`) uses
  stub plans and never the real bundle.

Tests: `bun-graph.test.js` (21 — synthetic containers for every named absence, plus a live read of
the installed binary), `embedded-fs.test.js` (19), `bun-surface.test.js` (29),
`bun-runtime.test.mjs` (14), `boot-channel.test.js` (7) and `launch.test.js` (29, stub plans) — 119
in all. 92 deliberate source mutations across the six modules were each killed by a test.

Run the mutation sweep against a COPY of this directory, never the working tree. A sweep that edits
the sources in place leaves a defect on disk that reads as source if it crashes or if two runs
overlap — which happened here, and cost an audit of every guard in every file to be sure nothing
else had been left behind. Count a mutation that makes a test HANG as a survivor, too: a case that
never returns reports nothing, which is no better than one that passes.

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
- DONE (2026-08-31): the bundle is recoverable in memory from the installed binary —
  `bun-graph.js`, which parses Bun's own module table rather than scanning for NUL-delimited
  records, so it reads both the one-CJS-module 2.1.226 and the 1,818-module ESM graph of 2.1.258
  from one code path, with no disk copy and no version→offset table
  (`promptctl-injector-xy0.1`).
- DONE (2026-09-02): the recovered graph runs under node — `bun-runtime.mjs` links it with
  `vm.SourceTextModule` (node's own ESM loader cannot: `ERR_REQUIRE_CYCLE_MODULE`), `embedded-fs.js`
  serves the embedded assets as a read-only filesystem, `bun-surface.js` is the `Bun` global,
  `bun-host.mjs` wires the four together, and `launch.js` decides whether a plan became a
  session before keeping it. Verified live on 2.1.258 in a PTY: boots to an idle authenticated
  TUI, and with `Bun.stripANSI` removed it is detected as not-booted and falls back to stock
  claude without hanging (`promptctl-injector-xy0.2`).
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
