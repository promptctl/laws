// bun-host.mjs — run the module graph recovered from the installed binary (bun-graph.js) under node.
// The installed binary stays a read-only input; nothing is written to disk.
//
// WHAT NODE CANNOT DO ON ITS OWN, AND WHY THIS FILE OWNS A MODULE RUNTIME. Bun's chunks call
// `import.meta.require("/$bunfs/root/chunk-….js")` — a SYNCHRONOUS, LAZY require between ES modules,
// which Bun answers with a live namespace even when the target is mid-evaluation. Node's loader has
// no such thing: `require(esm)` refuses to link a module whose graph touches one that is currently
// evaluating (ERR_REQUIRE_CYCLE_MODULE), and rewriting those call sites into static imports fails
// differently — it creates cycles the real graph never had, which then break on TDZ. Both were
// measured on 2.1.258 before this shape was chosen. `vm.SourceTextModule` gives the one thing that
// does work: we link the graph ourselves and hand out a namespace on demand, exactly as Bun does.
// It also lets `import.meta` be populated directly, so the recovered sources run VERBATIM — there is
// no rewriting step anywhere in this file.
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
// This file is the WIRING. The two pieces with logic worth testing — the embedded filesystem and the
// Bun surface — are their own modules with their own suites, because neither should need a vm, a
// terminal, or a 199MB binary to be checked. [LAW:decomposition]
//
// [LAW:no-silent-failure] every degrade leaves on the boot channel, named — including which Bun APIs
//   the graph asked for that this surface does not have.

import fs from 'node:fs';
import vm from 'node:vm';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import childProcess from 'node:child_process';
import { Readable } from 'node:stream';
import { createRequire, isBuiltin } from 'node:module';

const require_ = createRequire(import.meta.filename);
const { readGraphFromFile } = require_('./bun-graph.js');
const { createEmbeddedFs } = require_('./embedded-fs.js');
const { createBunSurface } = require_('./bun-surface.js');

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
  embedded, realFs: fs, childProcess, crypto, zlib,
  env: process.env, platform: process.platform, entryName: graph.entryName,
  onAbsentApi: (name) => { if (!absentApis.has(name)) { absentApis.add(name); send('absent-api ' + name); } },
});

// ---------------------------------------------------------------------------------------------
// The module runtime
// ---------------------------------------------------------------------------------------------

// The modules the graph resolves that are not in the graph: node builtins, plus the two Bun provides
// itself. `fs` must show the embedded filesystem; `ws` Bun ships built in, and it is the only
// non-builtin bare specifier this graph imports. Substituting only for HOSTED code means node's own
// fs is never patched.
const substitute = {
  fs: (real) => embedded.substituteForFs(real),
  'fs/promises': (real) => embedded.substituteForFsPromises(real),
};
const provided = {
  ws: () => { const W = globalThis.WebSocket; class Server { on() { return this; } close() {} handleUpgrade() {} } return { WebSocket: W, WebSocketServer: Server, Server, default: W }; },
};

const externals = new Map();
async function externalExports(specifier) {
  const id = specifier.replace(/^node:/, '');
  if (provided[id]) return provided[id]();
  // Anything neither embedded, provided, nor a node builtin would otherwise be resolved out of THIS
  // host's node_modules — a different package tree than the one the graph was built against, which
  // is a wrong answer wearing the shape of a right one.
  if (!isBuiltin(id)) throw new Error(`the graph imports ${specifier}, which is neither embedded nor a module this host provides`);
  const real = await import('node:' + id);
  return substitute[id] ? substitute[id](real) : real;
}
async function externalModule(specifier) {
  const id = specifier.replace(/^node:/, '');
  const cached = externals.get(id);
  if (cached) return cached;
  const exported = await externalExports(specifier);
  const names = [...new Set(['default', ...Object.keys(exported)])].filter((k) => /^[A-Za-z_$][\w$]*$/.test(k));
  const mod = new vm.SyntheticModule(names, function () {
    for (const n of names) this.setExport(n, n === 'default' ? (exported.default ?? exported) : exported[n]);
  }, { identifier: specifier });
  externals.set(id, mod);
  return mod;
}

// The synchronous form the same specifiers reach through `import.meta.require`. It must answer from
// the SAME maps as the import paths above, or the embedded filesystem would be visible to a chunk
// that imports `fs` and invisible to one that requires it. [LAW:one-source-of-truth]
const syncExternals = new Map();
function externalExportsSync(specifier) {
  const id = specifier.replace(/^node:/, '');
  if (syncExternals.has(id)) return syncExternals.get(id);
  if (provided[id]) { const e = provided[id](); syncExternals.set(id, e); return e; }
  if (!isBuiltin(id)) throw new Error(`the graph requires ${specifier}, which is neither embedded nor a module this host provides`);
  const real = require_('node:' + id);
  const exported = substitute[id] ? substitute[id](real) : real;
  syncExternals.set(id, exported);
  return exported;
}

const sources = new Map(graph.modules.map((m) => [m.name, m]));
const compiled = new Map();
function moduleFor(name) {
  const cached = compiled.get(name);
  if (cached) return cached;
  const record = sources.get(name);
  // A specifier the graph resolves to nothing is version drift, and the message has to say which
  // one — "cannot read properties of undefined" would name only the symptom.
  if (!record) throw new Error(`the graph names no module ${name}`);
  if (record.loader !== 'js') throw new Error(`${name} is a ${record.loader} module and cannot be evaluated as JavaScript`);
  const mod = new vm.SourceTextModule(record.text(), {
    identifier: name,
    // Bun's import.meta, reproduced rather than rewritten into the source.
    initializeImportMeta(meta) {
      meta.url = 'file://' + name;
      meta.filename = name;
      meta.dirname = name.replace(/\/[^/]*$/, '');
      meta.require = requireSync;
    },
    importModuleDynamically: (specifier) => evaluatedModule(specifier),
  });
  compiled.set(name, mod);
  return mod;
}

// Bun's synchronous require. What comes back is decided by the container's own loader field, which
// is exactly why bun-graph carries it: a `napi` or `file` module fed to the JavaScript parser would
// either fail cryptically or, decoded as latin1, parse into nonsense.
function requireSync(specifier) {
  const loader = embedded.loaderOf(specifier);
  if (loader === undefined) return externalExportsSync(specifier);
  if (loader === 'js') return namespaceOf(specifier);
  if (loader === 'text') return embedded.text(specifier);
  throw new Error(`${specifier} is a ${loader} module; this host does not serve it to require()`);
}

const link = (specifier) => embedded.loaderOf(specifier) === 'js' ? moduleFor(specifier) : externalModule(specifier);

// The dynamic-import callback must hand back an EVALUATED module: node takes its namespace as it
// finds it and will not run the body on our behalf.
async function evaluatedModule(specifier) {
  const mod = embedded.loaderOf(specifier) === 'js' ? moduleFor(specifier) : await externalModule(specifier);
  if (mod.status === 'unlinked') await mod.link(link);
  if (mod.status === 'linked') await mod.evaluate();
  return mod;
}

function namespaceOf(name) {
  const mod = moduleFor(name);
  // evaluate() settles asynchronously, but V8 runs the body synchronously up to its first await and
  // the namespace object is live from link time — so this is the same object, filled in the same
  // order, that Bun's require hands back from inside a cycle. The catch is not a swallow: a body
  // that throws after its first await lands outside every try/catch in this file, and without this
  // it would take the process down with no name attached to the cause.
  if (mod.status === 'linked') mod.evaluate().catch((e) => send(`boot-threw ${name}: ${because(e)}`));
  return mod.namespace;
}

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
  const chunks = graph.modules.filter((m) => m.loader === 'js');
  for (const record of chunks) moduleFor(record.name);
  for (const record of chunks) await moduleFor(record.name).link(link);
  await moduleFor(graph.entryName).evaluate();
} catch (e) {
  send(`boot-threw ${because(e)}`);
  process.exit(EXIT_NOT_BOOTED);
}
