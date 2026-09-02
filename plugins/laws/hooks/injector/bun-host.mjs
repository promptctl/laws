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
// terminal, a named refusal when the graph cannot be read or the entry throws. Whether those add up
// to a working session is the launcher's call, because the launcher is the one that can act on it,
// and it is the only party that can see whether the process was still there afterwards.
// [LAW:no-ambient-temporal-coupling] one owner for the timing, and it is not this file.
//
// [LAW:no-silent-failure] every degrade leaves on the boot channel, named — including which Bun APIs
//   the graph asked for that this surface does not have.

import fs from 'node:fs';
import vm from 'node:vm';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import childProcess from 'node:child_process';
import { createRequire } from 'node:module';

const require_ = createRequire(import.meta.filename);
const { readGraphFromFile } = require_('./bun-graph.js');

// The boot channel is a file descriptor passed in as a value, so this host is runnable by hand
// (verdicts on stderr) and under the launcher (verdicts on a private pipe) with one write path.
// Writing verdicts to an inherited stderr would corrupt the TUI's own rendering.
const BOOT_FD = Number(process.env.CLAUDE_LAWS_BOOT_FD || 2);
const EXIT_NOT_BOOTED = 70;
const send = (line) => {
  try { fs.writeSync(BOOT_FD, line + '\n'); } catch { /* the launcher closed the channel; the exit code still carries the verdict */ }
};
let reported = false;
function report(observation) {
  if (reported) return;
  reported = true;
  send(observation);
}

const [binaryPath, ...userArgs] = process.argv.slice(2);
const graph = readGraphFromFile(binaryPath);
if (!graph.ok) {
  report(`absent ${graph.reason}${graph.detail ? ' — ' + graph.detail : ''}`);
  process.exit(EXIT_NOT_BOOTED);
}

const byName = new Map(graph.modules.map((m) => [m.name, m]));
const isEmbedded = (p) => typeof p === 'string' && byName.has(p);

// The graph is also a read-only FILESYSTEM — chunks read embedded assets by their virtual path — and
// the real disk is still there for everything else. Which one answers is decided by the path, so
// every reader below is one function over both. [LAW:dataflow-not-control-flow]
const embeddedStat = (p) => ({ size: byName.get(p).length, isFile: () => true, isDirectory: () => false, isSymbolicLink: () => false, mode: 0o444, mtimeMs: 0 });
const decode = (p, options) => {
  const enc = typeof options === 'string' ? options : options?.encoding;
  return enc ? byName.get(p).bytes().toString(enc) : byName.get(p).bytes();
};
const readAny = (p, options) => isEmbedded(p) ? decode(p, options) : fs.readFileSync(p, options);
const existsAny = (p) => isEmbedded(p) || fs.existsSync(p);
const statAny = (p) => isEmbedded(p) ? embeddedStat(p) : fs.statSync(p);

// ---------------------------------------------------------------------------------------------
// The Bun global
// ---------------------------------------------------------------------------------------------

// Names the graph asked Bun for that this surface does not carry. A miss is not by itself a failure
// — most of Bun's API is never reached during boot — but when the boot self-check does fail, this
// list is the difference between "it hung" and "Bun grew an API called X". Each new name goes out
// the moment it is seen rather than at the end, because the failure worth diagnosing is the one
// where this process never reaches an end to report from.
const absentApis = new Set();
const noteAbsentApi = (name) => {
  if (absentApis.has(name)) return;
  absentApis.add(name);
  send('absent-api ' + name);
};

const bunSurface = {
  version: '1.3.14', revision: '0', main: graph.entryName, env: process.env,
  get argv() { return process.argv; },
  stdin: process.stdin, stdout: process.stdout, stderr: process.stderr,
  isStandaloneExecutable: true, enableANSIColors: true, isMainThread: true,

  file: (p) => ({
    async text() { return String(readAny(p, 'utf8')); },
    async json() { return JSON.parse(String(readAny(p, 'utf8'))); },
    async exists() { return existsAny(p); },
    async bytes() { return new Uint8Array(readAny(p)); },
    async arrayBuffer() { return new Uint8Array(readAny(p)).buffer; },
    stream() { return fs.createReadStream(p); },
    get size() { return existsAny(p) ? statAny(p).size : 0; },
    name: p, type: '',
  }),
  write: async (dst, data) => {
    const path = typeof dst === 'object' && dst?.name ? dst.name : dst;
    fs.writeFileSync(path, typeof data === 'string' ? data : Buffer.from(data.buffer ?? data));
    return 0;
  },

  zstdDecompressSync: (b) => zlib.zstdDecompressSync(b),
  zstdDecompress: async (b) => zlib.zstdDecompressSync(b),
  gzipSync: (b) => zlib.gzipSync(b), gunzipSync: (b) => zlib.gunzipSync(b),

  spawn: (cmd, options) => childProcess.spawn(cmd[0], cmd.slice(1), options || {}),
  spawnSync: (cmd, options) => childProcess.spawnSync(cmd[0], cmd.slice(1), options || {}),
  which: (cmd) => {
    const r = childProcess.spawnSync('command', ['-v', cmd], { shell: true, encoding: 'utf8' });
    return r.status === 0 ? r.stdout.trim() || null : null;
  },

  hash: Object.assign((x) => crypto.createHash('sha256').update(typeof x === 'string' ? x : Buffer.from(x)).digest(),
    { wyhash: () => 0n, crc32: () => 0, adler32: () => 0 }),
  CryptoHasher: class { constructor(a) { this.h = crypto.createHash(a || 'sha256'); } update(d) { this.h.update(d); return this; } digest(enc) { return enc ? this.h.digest(enc) : new Uint8Array(this.h.digest()); } },

  // Measured boot-critical: the render path strips and wraps ANSI on every frame, and the version
  // gates run hundreds of times before the first paint. A stub that returns the input unchanged is
  // enough to render, but a stub that returns undefined is the exact failure the self-check exists
  // to catch — so these are real implementations, not placeholders.
  stringWidth: (s) => {
    let width = 0;
    for (const ch of String(s ?? '')) {
      const c = ch.codePointAt(0);
      const wide = c >= 0x1100 && (c <= 0x115f || c === 0x2329 || c === 0x232a
        || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff)
        || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6)
        || (c >= 0x1f300 && c <= 0x1faff));
      const combining = c >= 0x300 && c <= 0x36f;
      width += combining ? 0 : (wide ? 2 : 1);
    }
    return width;
  },
  stripANSI: (s) => String(s ?? '').replace(new RegExp('[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\\u0007)|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))', 'g'), ''),
  wrapAnsi: (str, columns, options) => {
    const cols = columns > 0 ? columns : 80;
    const width = (x) => bunSurface.stringWidth(bunSurface.stripANSI(x));
    return String(str ?? '').split('\n').map((line) => {
      const out = [];
      let current = '', currentWidth = 0;
      for (const word of line.split(' ')) {
        const w = width(word);
        if (currentWidth === 0) { current = word; currentWidth = w; }
        else if (currentWidth + 1 + w <= cols) { current += ' ' + word; currentWidth += 1 + w; }
        else { out.push(current); current = word; currentWidth = w; }
      }
      out.push(current);
      if (!options?.hard) return out.join('\n');
      return out.flatMap((seg) => {
        if (width(seg) <= cols) return [seg];
        const parts = []; let acc = '';
        for (const ch of seg) { if (width(acc + ch) > cols) { parts.push(acc); acc = ch; } else acc += ch; }
        if (acc) parts.push(acc);
        return parts;
      }).join('\n');
    }).join('\n');
  },
  semver: (() => {
    const parse = (v) => { const m = String(v).trim().replace(/^[v=\s]+/, '').match(/^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?/); return m ? { M: +m[1], m: +m[2], p: +m[3], pre: m[4] || '' } : null; };
    const cmp = (a, b) => {
      const x = parse(a), y = parse(b);
      if (!x || !y) return 0;
      if (x.M !== y.M) return x.M < y.M ? -1 : 1;
      if (x.m !== y.m) return x.m < y.m ? -1 : 1;
      if (x.p !== y.p) return x.p < y.p ? -1 : 1;
      if (x.pre && !y.pre) return -1;
      if (!x.pre && y.pre) return 1;
      return x.pre < y.pre ? -1 : x.pre > y.pre ? 1 : 0;
    };
    const one = (v, range) => {
      const r = String(range).trim();
      if (r === '' || r === '*' || r === 'x') return true;
      let m;
      if ((m = r.match(/^\^(\d+)\.(\d+)\.(\d+)/))) {
        const p = parse(v); if (!p) return false;
        if (cmp(v, `${m[1]}.${m[2]}.${m[3]}`) < 0) return false;
        return +m[1] > 0 ? p.M === +m[1] : (+m[2] > 0 ? (p.M === 0 && p.m === +m[2]) : (p.M === 0 && p.m === 0 && p.p === +m[3]));
      }
      if ((m = r.match(/^~(\d+)\.(\d+)(?:\.(\d+))?/))) {
        const p = parse(v); if (!p) return false;
        return p.M === +m[1] && p.m === +m[2] && cmp(v, `${m[1]}.${m[2]}.${m[3] || 0}`) >= 0;
      }
      if ((m = r.match(/^(>=|<=|>|<|=)?\s*(\d+)\.(\d+)\.(\d+)/))) {
        const op = m[1] || '=', c = cmp(v, `${m[2]}.${m[3]}.${m[4]}`);
        return op === '>=' ? c >= 0 : op === '<=' ? c <= 0 : op === '>' ? c > 0 : op === '<' ? c < 0 : c === 0;
      }
      return false;
    };
    return { order: cmp, satisfies: (v, range) => String(range).split('||').some((part) => part.trim().split(/\s+/).every((c) => one(v, c))) };
  })(),

  deepEquals: (a, b) => { try { return JSON.stringify(a) === JSON.stringify(b); } catch { return a === b; } },
  escapeHTML: (s) => String(s), color: (c) => String(c),
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)), sleepSync: () => {},
  nanoseconds: () => Number(process.hrtime.bigint()),
  gc() {}, generateHeapSnapshot: () => ({}),
  pathToFileURL: (p) => require_('node:url').pathToFileURL(p),
  fileURLToPath: (u) => require_('node:url').fileURLToPath(u),
  resolveSync: (id, base) => { try { return require_.resolve(id, { paths: [base] }); } catch { return id; } },
  serve: () => ({ stop() {}, reload() {}, ref() {}, unref() {}, port: 0, url: new URL('http://localhost:0'), hostname: 'localhost' }),
};

// An unknown key returns the undefined-yielding stub Bun's absence would produce anyway, and is
// RECORDED. Silently answering and silently forgetting is what turns a new Bun API into a hang with
// no cause attached. [LAW:no-silent-failure]
globalThis.Bun = new Proxy(bunSurface, {
  get(target, key) {
    if (key in target) return target[key];
    noteAbsentApi(String(key));
    return () => undefined;
  },
});

// ---------------------------------------------------------------------------------------------
// The module runtime
// ---------------------------------------------------------------------------------------------

// Node builtins the graph imports, plus the two it expects Bun to provide: `ws`, which Bun ships
// built in, and `fs`, which must show the embedded filesystem. Substituting only for hosted code
// means node's own `fs` is never patched.
const substitute = {
  fs: (real) => ({ ...real,
    readFileSync: (p, o) => isEmbedded(p) ? decode(p, o) : real.readFileSync(p, o),
    existsSync: (p) => isEmbedded(p) || real.existsSync(p),
    statSync: (p, o) => isEmbedded(p) ? embeddedStat(p) : real.statSync(p, o),
  }),
  'fs/promises': (real) => ({ ...real,
    readFile: async (p, o) => isEmbedded(p) ? decode(p, o) : real.readFile(p, o),
    stat: async (p, o) => isEmbedded(p) ? embeddedStat(p) : real.stat(p, o),
  }),
};
const provided = {
  ws: () => { const W = globalThis.WebSocket; class Server { on() { return this; } close() {} handleUpgrade() {} } return { WebSocket: W, WebSocketServer: Server, Server, default: W }; },
};

const externals = new Map();
async function externalModule(specifier) {
  const id = specifier.replace(/^node:/, '');
  const cached = externals.get(id);
  if (cached) return cached;
  const exported = provided[id] ? provided[id]() : (substitute[id] ? substitute[id](await import('node:' + id)) : await import('node:' + id));
  const names = [...new Set(['default', ...Object.keys(exported)])].filter((k) => /^[A-Za-z_$][\w$]*$/.test(k));
  const mod = new vm.SyntheticModule(names, function () {
    for (const n of names) this.setExport(n, n === 'default' ? (exported.default ?? exported) : exported[n]);
  }, { identifier: specifier });
  externals.set(id, mod);
  return mod;
}

const compiled = new Map();
function moduleFor(name) {
  const cached = compiled.get(name);
  if (cached) return cached;
  const record = byName.get(name);
  const mod = new vm.SourceTextModule(record.text(), {
    identifier: name,
    // Bun's import.meta, reproduced rather than rewritten into the source.
    initializeImportMeta(meta) {
      meta.url = 'file://' + name;
      meta.filename = name;
      meta.dirname = name.replace(/\/[^/]*$/, '');
      meta.require = (p) => {
        const embedded = byName.get(p);
        if (!embedded) return require_(p);
        // Requiring an embedded TEXT asset yields its decoded contents, which is what Bun does; a
        // chunk yields its namespace, live even mid-cycle.
        return embedded.loader === 'text' ? embedded.text() : namespaceOf(p);
      };
    },
    importModuleDynamically: (specifier) => evaluatedModule(specifier),
  });
  compiled.set(name, mod);
  return mod;
}

const link = (specifier) => byName.has(specifier) ? moduleFor(specifier) : externalModule(specifier);

// The dynamic-import callback must hand back an EVALUATED module: node takes its namespace as it
// finds it and will not run the body on our behalf.
async function evaluatedModule(specifier) {
  const mod = byName.has(specifier) ? moduleFor(specifier) : await externalModule(specifier);
  if (mod.status === 'unlinked') await mod.link(link);
  if (mod.status === 'linked') await mod.evaluate();
  return mod;
}

function namespaceOf(name) {
  const mod = moduleFor(name);
  // evaluate() settles asynchronously, but V8 runs the body synchronously up to its first await and
  // the namespace object is live from link time — so this is the same object, filled in the same
  // order, that Bun's require hands back from inside a cycle.
  if (mod.status === 'linked') mod.evaluate();
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
const chunks = graph.modules.filter((m) => m.loader === 'js');
for (const record of chunks) moduleFor(record.name);
for (const record of chunks) await moduleFor(record.name).link(link);

try {
  await moduleFor(graph.entryName).evaluate();
} catch (e) {
  report(`boot-threw ${e && e.message}`);
  process.exit(EXIT_NOT_BOOTED);
}
