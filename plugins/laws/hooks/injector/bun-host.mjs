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
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import childProcess from 'node:child_process';
import http from 'node:http';
import { Readable } from 'node:stream';
import { createRequire } from 'node:module';

const require_ = createRequire(import.meta.filename);
const { readGraphFromFile } = require_('./bun-graph.js');
const { createEmbeddedFs } = require_('./embedded-fs.js');
const { createBunSurface } = require_('./bun-surface.js');
const { createModuleRuntime } = await import('./bun-runtime.mjs');

// The boot channel is a file descriptor passed in as a value, so this host is runnable by hand
// (verdicts on stderr) and under the launcher (verdicts on a private pipe) with one write path.
// Writing verdicts to an inherited stderr would corrupt the TUI's own rendering.
const BOOT_FD = Number(process.env.CLAUDE_LAWS_BOOT_FD || 2);
const EXIT_NOT_BOOTED = 70;
const send = (line) => {
  try { fs.writeSync(BOOT_FD, line + '\n'); } catch { /* the launcher closed the channel; the exit code still carries the verdict */ }
};
// The one-per-process VERDICT: whether this host ever got the graph as far as the terminal. Later
// observations still go out through `send` — a graph that painted and then threw has spent its
// verdict, and the message it died with is the useful part.
let reported = false;
const report = (verdict) => { if (!reported) { reported = true; send(verdict); } };
// A thrown value is not always an Error; `e.message` on a thrown string is undefined, and an
// undefined reason is the silence this whole channel exists to prevent.
const because = (e) => (e && e.message) || String(e);

const [binaryPath, ...userArgs] = process.argv.slice(2);
const graph = readGraphFromFile(binaryPath);
if (!graph.ok) {
  report(`absent ${graph.reason}${graph.detail ? ' — ' + graph.detail : ''}`);
  process.exit(EXIT_NOT_BOOTED);
}

const embedded = createEmbeddedFs(graph.modules, { realFs: fs, streamFrom: (bytes) => Readable.from(bytes) });

// ---------------------------------------------------------------------------------------------
// The Bun global
// ---------------------------------------------------------------------------------------------

// Names the graph asked Bun for that this surface does not carry. A miss is not by itself a failure
// — most of Bun's API is never reached during boot — but when the boot self-check does fail, this
// list is the difference between "it hung" and "Bun grew an API called X". Each new name goes out
// the moment it is seen rather than at the end, because the failure worth diagnosing is the one
// where this process never reaches an end to report from.
const absentApis = new Set();
globalThis.Bun = createBunSurface({
  embedded, realFs: fs, childProcess, crypto, zlib, http,
  env: process.env, platform: process.platform, entryName: graph.entryName,
  onAbsentApi: (name) => { if (!absentApis.has(name)) { absentApis.add(name); send('absent-api ' + name); } },
});

// ---------------------------------------------------------------------------------------------
// The module runtime
// ---------------------------------------------------------------------------------------------

// The modules the graph resolves that are not in the graph: node builtins, plus the one Bun provides
// itself. `fs` must show the embedded filesystem; `ws` Bun ships built in, and it is the only
// non-builtin bare specifier this graph imports. Substituting only for HOSTED code means node's own
// fs is never patched. `ws` is built ONCE — a factory per resolution path would give the sync and
// async resolvers each their own `Server` class, and an identity check across them would fail.
const WS = (() => {
  const W = globalThis.WebSocket;
  class Server { on() { return this; } close() {} handleUpgrade() {} }
  return { WebSocket: W, WebSocketServer: Server, Server, default: W };
})();

const runtime = createModuleRuntime({
  embedded,
  sources: new Map(graph.modules.map((m) => [m.name, m])),
  provided: { ws: WS },
  substitute: {
    fs: (real) => embedded.substituteForFs(real),
    'fs/promises': (real) => embedded.substituteForFsPromises(real),
  },
  importBuiltin: (id) => import('node:' + id),
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
process.stdout.write = (...args) => { report('painted'); return stdoutWrite(...args); };

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
  await runtime.evaluateEntry(graph.entryName);
} catch (e) {
  send(`boot-threw ${because(e)}`);
  process.exit(EXIT_NOT_BOOTED);
}
