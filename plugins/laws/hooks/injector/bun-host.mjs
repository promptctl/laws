// bun-host.mjs — run the module graph recovered from the installed binary (bun-graph.js) under node.
// The installed binary stays a read-only input; nothing is written to disk.
//
// WHAT THIS FILE IS. Wiring. The three pieces with logic worth testing are their own modules with
// their own suites — bun-graph.js reads the container, embedded-fs.js presents it as a filesystem,
// bun-surface.js is the Bun global, and bun-runtime.mjs links and evaluates the graph (and explains
// why node's own loader cannot). None of them needs a vm, a terminal, or a 199MB binary to check.
// [LAW:decomposition]
//
// THE BOOT SELF-CHECK, AND WHAT THIS FILE'S HALF OF IT IS. The documented failure mode when Bun adds
// a boot-critical API is not a crash: the shim returns undefined, the first render throws a TypeError
// the app swallows, and the process sits there looking like a hang. This host reports OBSERVATIONS on
// the boot channel and forms no verdict — `painted` the first time the hosted graph writes to the
// terminal, a named refusal when the graph cannot be read or something throws. Whether those add up
// to a working session is the launcher's call, because the launcher is the one that can act on it,
// and it is the only party that can see whether the process was still there afterwards.
// [LAW:no-ambient-temporal-coupling] one owner for the timing, and it is not this file.
//
// [LAW:no-silent-failure] every degrade leaves on the boot channel, named — including which Bun APIs
//   the graph asked for that this surface does not have.

import fs from 'node:fs';
import { createRequire } from 'node:module';

// The boot channel is a file descriptor passed in as a value, so this host is runnable by hand
// (verdicts on stderr) and under the launcher (verdicts on a private pipe) with one write path.
// Writing verdicts to an inherited stderr would corrupt the TUI's own rendering.
const BOOT_FD = Number(process.env.CLAUDE_LAWS_BOOT_FD || 2);
// Nothing is swallowed here that could be reported anywhere else: this IS the reporting channel, so
// a failure to write to it has no second place to go, and the exit code still carries the verdict.
// The usual cause is the launcher having closed its end.
const { createBootChannel, PAINTED } = createRequire(import.meta.url)('./boot-channel.js');
const channel = createBootChannel({
  write: (bytes) => { try { fs.writeSync(BOOT_FD, bytes); } catch { /* see above */ } },
});
const send = channel.send;
// Installed FIRST, above every import that could throw. The window these handlers do not cover is
// the loading of the modules that make reporting possible, so it has to be as small as this file can
// make it. [LAW:no-silent-failure]
const { installBootGuard, EXIT_NOT_BOOTED, because } = createRequire(import.meta.url)('./boot-guard.js');
const { bootIsOver } = installBootGuard({
  on: (event, fn) => process.on(event, fn),
  off: (event, fn) => process.off(event, fn),
  exit: (code) => process.exit(code),
  send: (line) => send(line),
});

import zlib from 'node:zlib';
import crypto from 'node:crypto';
import childProcess from 'node:child_process';
import http from 'node:http';
import { Readable } from 'node:stream';
const require_ = createRequire(import.meta.filename);
const { readGraphFromFile } = require_('./bun-graph.js');
const { createEmbeddedFs } = require_('./embedded-fs.js');
const { createBunSurface } = require_('./bun-surface.js');
const { createModuleRuntime } = await import('./bun-runtime.mjs');

const report = channel.report;

const [binaryPath, ...userArgs] = process.argv.slice(2);
const graph = readGraphFromFile(binaryPath);
if (!graph.ok) {
  report(`absent ${graph.reason}${graph.detail ? ' — ' + graph.detail : ''}`);
  process.exit(EXIT_NOT_BOOTED);
}

const embedded = createEmbeddedFs(graph.modules, {
  realFs: fs,
  // The range arithmetic lives in embedded-fs.js, where its tests are; this closure only wraps.
  streamFrom: (bytes) => Readable.from(bytes),
});

// ---------------------------------------------------------------------------------------------
// The Bun global
// ---------------------------------------------------------------------------------------------

// Names the graph asked Bun for that this surface does not carry. A miss is not by itself a failure
// — most of Bun's API is never reached during boot — but when the boot self-check does fail, this
// list is the difference between "it hung" and "Bun grew an API called X". Each new name goes out
// the moment it is seen rather than at the end, because the failure worth diagnosing is the one
// where this process never reaches an end to report from.
globalThis.Bun = createBunSurface({
  embedded, realFs: fs, childProcess, crypto, zlib, http,
  env: process.env, platform: process.platform, entryName: graph.entryName,
  onAbsentApi: (name) => channel.absentApi(name),
});

// ---------------------------------------------------------------------------------------------
// The module runtime
// ---------------------------------------------------------------------------------------------

// The modules the graph resolves that are not in the graph: node builtins, plus the one Bun provides
// itself. `fs` must show the embedded filesystem; `ws` Bun ships built in, and it is the only
// non-builtin bare specifier this graph imports. Substituting only for HOSTED code means node's own
// fs is never patched. `ws` is built ONCE — a factory per resolution path would give the sync and
// async resolvers each their own `Server` class, and an identity check across them would fail.
// Only what the graph imports. Every `from "ws"` in it takes the default export and nothing else,
// so a WebSocketServer here would be an accept-nothing stub standing in for a capability no caller
// asks for — and the absence, if one ever does, is recorded.
const WS = { WebSocket: globalThis.WebSocket, default: globalThis.WebSocket };

const runtime = createModuleRuntime({
  embedded,
  sources: new Map(graph.modules.map((m) => [m.name, m])),
  provided: { ws: WS },
  substitute: {
    fs: (real) => embedded.substituteForFs(real),
    'fs/promises': (real) => embedded.substituteForFsPromises(real),
  },
  requireBuiltin: (id) => require_('node:' + id),
  onEvaluationError: (name, e) => send(`boot-threw ${name}: ${because(e)}`),
});

// ---------------------------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------------------------

// The hosted graph reads process.argv exactly as the shipped binary would: argv[1] is the entry's
// virtual path and everything the user typed follows. Leaving this host's own arguments in place
// would feed the binary path to the CLI as a positional argument.
process.argv = [process.argv[0], graph.entryName, ...userArgs];

// The first byte the hosted graph puts on the terminal. Not proof of a working session — a pre-flight
// notice counts too, which is exactly why the verdict is not formed here — but a session that never
// paints at all is the hang this whole check exists to catch.
const stdoutWrite = process.stdout.write.bind(process.stdout);
process.stdout.write = (...args) => { report(PAINTED); return stdoutWrite(...args); };

// import.meta.require is synchronous, so a module can only be evaluated on demand if it is already
// linked. Linking every module up front is one unconditional pass over the graph — the alternative,
// deciding per module whether it might be required later, is a guess this file cannot make.
// [LAW:dataflow-not-control-flow]
// Linking and evaluating share one arm because they fail the same way and for the same reasons: a
// specifier this graph resolves and node does not, a module the graph names and does not carry, a
// Bun API the surface is missing. Every one of them is version drift, and every one has to arrive at
// the launcher as a named reason rather than as a bare nonzero exit. [LAW:no-silent-failure]
try {
  await runtime.linkAll();
  // The instant control passes to the hosted app. Before this, nothing the user asked for has run,
  // so a failure is always safe to replace; after it, the app owns whatever it did. The launcher
  // needs that as a FACT rather than an inference from whether stdout happened to see a byte.
  channel.started();
  await runtime.evaluateEntry(graph.entryName);
  // From here the session is the app's; its crashes are its own, and node's default handling is
  // what it expects.
  bootIsOver();
} catch (e) {
  send(`boot-threw ${because(e)}`);
  process.exit(EXIT_NOT_BOOTED);
}
