// bun-surface.js — the `Bun` global the hosted graph expects, built over the embedded filesystem.
//
// A NOTE ON WHAT BELONGS HERE. Every member is either a real implementation or absent. There is no
// third category, and the temptation to add one is strong: a stub that returns a constant boots
// today and is a wrong answer forever, whereas an absent member is RECORDED and shows up in the
// launcher's failure reason by name. `Bun.hash.wyhash` returning 0n for every input would keep the
// process alive while quietly collapsing every cache key onto one bucket — a present-but-wrong stub
// is worse than the absence it is impersonating. [LAW:no-silent-failure]
//
// [LAW:effects-at-boundaries] every capability this surface needs — the filesystem, the process
//   table, hashing — arrives as a parameter, so the whole thing is testable with no disk, no
//   spawning, and no mocks.

'use strict';

const { Readable } = require('stream');

const ENOENT_SIZE = 0;

// Bun's own default hash is a fast 64-bit NON-cryptographic hash, not a digest. The exact algorithm
// is not reproducible here, and it does not need to be — callers use it for bucketing, so what has
// to hold is that it is deterministic, well distributed, and 64 bits wide. FNV-1a is all three.
// The bytes a caller handed us, as a Buffer that respects a view's window. `Buffer.from(view.buffer)`
// alone takes the whole backing store, byteOffset and byteLength ignored. One definition, because
// every place that turns a caller's value into bytes has to make the same mistake or none.
// [LAW:one-source-of-truth]
const asBuffer = (data) => (typeof data === 'string' ? Buffer.from(data, 'utf8')
  : ArrayBuffer.isView(data) ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
    : Buffer.from(data));

const MASK64 = (1n << 64n) - 1n;
const fnv1a64 = (input, seed = 0) => {
  const bytes = asBuffer(input);
  // Bun's hashes take an optional seed that changes the result; ignoring it would hand every seeded
  // caller the same value and quietly collapse whatever they were separating.
  let h = 0xcbf29ce484222325n ^ (BigInt(seed) & MASK64);
  for (const b of bytes) h = ((h ^ BigInt(b)) * 0x100000001b3n) & MASK64;
  return h;
};
const crc32 = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return (input, seed = 0) => {
    const bytes = asBuffer(input);
    let c = (0xffffffff ^ seed) >>> 0;
    for (const b of bytes) c = table[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
})();

// Structural equality, order-independent. JSON.stringify would call {a:1,b:2} and {b:2,a:1}
// different, which is wrong for a primitive whose whole job is answering that question.
function deepEquals(a, b, seen = new Map()) {
  if (Object.is(a, b)) return true;
  if (typeof a !== 'object' || typeof b !== 'object' || a === null || b === null) return false;
  if (Object.getPrototypeOf(a) !== Object.getPrototypeOf(b)) return false;
  // A pair already being compared higher up the stack is equal unless something else proves
  // otherwise; without this, circular data recurses until the stack gives out.
  if (seen.get(a) === b) return true;
  seen.set(a, b);
  if (Array.isArray(a)) return a.length === b.length && a.every((x, i) => deepEquals(x, b[i], seen));
  if (a instanceof Date) return a.getTime() === b.getTime();
  if (a instanceof RegExp) return a.source === b.source && a.flags === b.flags;
  if (a instanceof Error) return a.name === b.name && a.message === b.message;
  if (a instanceof Map) return a.size === b.size && [...a].every(([k, v]) => b.has(k) && deepEquals(v, b.get(k), seen));
  if (a instanceof Set) return a.size === b.size && [...a].every((v) => b.has(v));
  if (ArrayBuffer.isView(a)) return a.byteLength === b.byteLength && Buffer.from(a.buffer, a.byteOffset, a.byteLength).equals(Buffer.from(b.buffer, b.byteOffset, b.byteLength));
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((k) => Object.hasOwn(b, k) && deepEquals(a[k], b[k], seen));
}

const HTML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#x27;' };

// Bun's CryptoHasher accepts algorithms node's crypto does not. Only the ones node serves under the
// SAME name are listed: blake2b256 is deliberately absent, because node has only blake2b512 and a
// truncation of it is a different function, not the same digest at a shorter length. Refusing it by
// name beats answering with somebody else's bytes.
const HASH_ALGORITHMS = new Set(['sha1', 'sha224', 'sha256', 'sha384', 'sha512', 'sha512-224', 'sha512-256', 'md5', 'blake2b512']);

const stringWidth = (s) => {
  let width = 0;
  for (const ch of String(s ?? '')) {
    const c = ch.codePointAt(0);
    const wide = c >= 0x1100 && (c <= 0x115f || c === 0x2329 || c === 0x232a
      || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff)
      || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6)
      || (c >= 0x1f300 && c <= 0x1faff));
      // Combining marks and zero-width characters take no column. U+0300–U+036F is only the first
      // of several such ranges, and stopping there overcounts every script that uses the others.
      const combining = (c >= 0x300 && c <= 0x36f) || (c >= 0x483 && c <= 0x489)
        || (c >= 0x591 && c <= 0x5bd) || (c >= 0x610 && c <= 0x61a) || (c >= 0x64b && c <= 0x65f)
        || (c >= 0x1ab0 && c <= 0x1aff) || (c >= 0x1dc0 && c <= 0x1dff) || (c >= 0x20d0 && c <= 0x20f0)
        || (c >= 0xfe00 && c <= 0xfe0f) || (c >= 0xfe20 && c <= 0xfe2f)
        || c === 0x200b || c === 0x200c || c === 0x200d || c === 0xfeff;
    width += combining ? 0 : (wide ? 2 : 1);
  }
  return width;
};

const ANSI = new RegExp('[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\\u0007)|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))', 'g');
const stripANSI = (s) => String(s ?? '').replace(ANSI, '');

const wrapAnsi = (str, columns, options) => {
  const cols = columns > 0 ? columns : 80;
  const width = (x) => stringWidth(stripANSI(x));
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
};

const semver = (() => {
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
})();

// Bun.which, without a shell. `spawnSync('command -v ' + cmd, {shell:true})` runs whatever a command
// name containing `;` says to run, and this surface is handed names that came from the graph.
const whichVia = (realFs, env, platform) => (cmd) => {
  if (typeof cmd !== 'string' || cmd.includes('/')) return null;
  const path = require('path');
  const exts = platform === 'win32' ? (env.PATHEXT || '.EXE;.CMD;.BAT').split(';') : [''];
  for (const dir of (env.PATH || '').split(path.delimiter)) {
    for (const ext of exts) {
      const candidate = path.join(dir, cmd + ext);
      try { realFs.accessSync(candidate, realFs.constants.X_OK); return candidate; } catch { /* next candidate */ }
    }
  }
  return null;
};

// Bun.spawn accepts both spawn(["cmd","arg"], options) and spawn({cmd: ["cmd","arg"], ...options}),
// and it names the three streams at the TOP level — `stdout: "pipe"`, `stderr: "ignore"` — where
// node wants one `stdio` array. Node ignores keys it does not know, so forwarding Bun's shape
// unchanged silently gives every stream node's default: an `ignore` becomes an unread pipe that
// fills and blocks the child, which is a hang with no reported cause. Measured on the shipped graph,
// which passes exactly these options and then awaits `child.stdout.text()`.
const STREAM_SLOTS = ['stdin', 'stdout', 'stderr'];
const spawnArgs = (first, second, openFd) => {
  const { cmd, ...rest } = Array.isArray(first) ? { cmd: first } : (first || {});
  const options = { ...rest, ...(second || {}) };
  const named = STREAM_SLOTS.map((slot) => options[slot]);
  for (const slot of STREAM_SLOTS) delete options[slot];
  // An explicit array is node's own spelling but not node's own VALUES: the graph passes
  // `stdio:["ignore","ignore",Bun.file(path)]`, and node cannot take a BunFile. Every element is
  // translated, whichever spelling it arrived in.
  if (Array.isArray(options.stdio)) options.stdio = options.stdio.map((v) => toNodeStdio(v, openFd));
  // An explicit `stdio` wins; it is node's own spelling and the graph uses it too. A caller that
  // names none of the three gets NODE's defaults, not Bun's: Bun's per-slot defaults are not
  // documented anywhere this host can read, and inventing them would be a guess wearing the shape of
  // a fix. This is a known limit, stated rather than papered over.
  if (options.stdio === undefined && named.some((v) => v !== undefined)) {
    options.stdio = named.map((v, i) => (v === undefined ? (i === 0 ? 'inherit' : 'pipe') : toNodeStdio(v, openFd)));
  }
  return { command: cmd?.[0], args: cmd?.slice(1) ?? [], options };
};
// Bun's per-stream values, in node's vocabulary. A BunFile stands for the descriptor it names. An
// unrecognised value is refused rather than quietly becoming 'pipe' — a wrong stream is a hang or a
// lost output with nothing pointing at the cause. [LAW:no-silent-failure]
const toNodeStdio = (v, openFd) => {
  if (v === 'ignore' || v === 'inherit' || v === 'pipe' || v === null || v === undefined) return v ?? 'pipe';
  if (typeof v === 'number') return v;
  if (v && typeof v === 'object' && typeof v.fd === 'number') return v.fd;
  // A BunFile names a path rather than carrying a descriptor, so one is opened for it.
  if (v && typeof v === 'object' && typeof v.name === 'string') return openFd(v.name);
  throw new Error(`spawn: this host does not know the stdio value ${JSON.stringify(v)}`);
};

// The graph reads a finished child's output as `await child.stdout.text()` and waits on
// `child.exited`. Node's ChildProcess has neither, so the streams it does have are given those two
// affordances; nothing else about the child is touched.
const withBunChildShape = (child) => {
  for (const slot of ['stdout', 'stderr']) {
    const stream = child[slot];
    if (!stream || typeof stream.text === 'function') continue;
    // Drained ONCE and shared. A stream is consumed by reading it, so three readers that each drain
    // it independently means the second and third get nothing back.
    let drained;
    const drain = () => (drained ??= (async () => { const parts = []; for await (const c of stream) parts.push(c); return Buffer.concat(parts); })());
    stream.text = async () => (await drain()).toString('utf8');
    stream.json = async () => JSON.parse((await drain()).toString('utf8'));
    stream.bytes = async () => new Uint8Array(await drain());
  }
  if (child.exited === undefined) {
    // Listen at once, promise on demand. Both halves are needed: an 'error' event with no listener
    // is thrown by node, and a promise created eagerly rejects with nobody awaiting it — an
    // unhandled rejection that ends the process over a child nobody was watching. So the outcome is
    // captured the moment it happens, and only turned into a promise if something asks.
    let outcome, settle;
    const record = (o) => { outcome = o; settle?.(o); };
    // A process killed by a signal exits with code null. Reporting 0 for it would call a kill a
    // clean finish.
    child.on('exit', (code, signal) => record(code === null ? { error: new Error(`killed by ${signal}`) } : { code }));
    child.on('error', (error) => record({ error }));
    let exited;
    const promise = () => new Promise((resolve, reject) => {
      const deliver = (o) => (o.error ? reject(o.error) : resolve(o.code));
      if (outcome) return deliver(outcome);
      settle = deliver;
    });
    Object.defineProperty(child, 'exited', { configurable: true, get: () => (exited ??= promise()) });
  }
  return child;
};

// A real server, because the graph really uses one — with a `fetch` handler, `.unref()` and
// `.stop(true)`. The stub this replaces answered every one of those and served nothing, so a caller
// that started a listener and waited for a callback on it waited forever.
function serveOver(http, options = {}) {
  const handler = options.fetch;
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
      const body = ['GET', 'HEAD'].includes(req.method) ? undefined : req;
      const request = new Request(url, { method: req.method, headers: req.headers, body, duplex: 'half' });
      const response = await handler(request, server);
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      // A handler that throws must still answer. Without this the request hangs and the rejection
      // is unhandled, which takes the whole session down for one bad response.
      if (!res.headersSent) res.writeHead(500);
      res.end();
    }
  });
  server.listen(options.port ?? 0, options.hostname ?? '127.0.0.1');
  return {
    stop: (closeActive) => { server.close(); if (closeActive) server.closeAllConnections?.(); },
    reload: () => {}, ref: () => server.ref(), unref: () => server.unref(),
    get port() { return server.address()?.port ?? 0; },
    get hostname() { return options.hostname ?? '127.0.0.1'; },
    get url() { return new URL(`http://${options.hostname ?? '127.0.0.1'}:${server.address()?.port ?? 0}`); },
  };
}

// Build the surface. `onAbsentApi` is called for every name the graph asks for that is not here.
function createBunSurface({ embedded, realFs, childProcess, crypto, zlib, http, env, platform, entryName, onAbsentApi }) {
  const surface = {
    version: '1.3.14', revision: '0', main: entryName, env,
    get argv() { return process.argv; },
    isStandaloneExecutable: true, enableANSIColors: true, isMainThread: true,

    file: (p) => ({
      async text() { return String(embedded.readAny(p, 'utf8')); },
      async json() { return JSON.parse(String(embedded.readAny(p, 'utf8'))); },
      async exists() { return embedded.existsAny(p); },
      async bytes() { return new Uint8Array(embedded.readAny(p)); },
      async arrayBuffer() { const b = asBuffer(embedded.readAny(p)); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); },
      // Bun hands back a web ReadableStream, and callers use its API rather than node's.
      stream() { return Readable.toWeb(embedded.streamAny(p)); },
      get size() { return embedded.existsAny(p) ? embedded.statAny(p).size : ENOENT_SIZE; },
      name: p, type: '',
    }),
    write: async (dst, data) => {
      const bytes = asBuffer(data);
      realFs.writeFileSync(typeof dst === 'object' && dst?.name ? dst.name : dst, bytes);
      return bytes.length;
    },

    zstdDecompressSync: (b) => zlib.zstdDecompressSync(b),
    zstdDecompress: (b) => new Promise((resolve, reject) => zlib.zstdDecompress(b, (e, out) => (e ? reject(e) : resolve(out)))),
    gzipSync: (b) => zlib.gzipSync(b), gunzipSync: (b) => zlib.gunzipSync(b),

    spawn: (first, second) => {
      const { command, args, options } = spawnArgs(first, second, (path) => realFs.openSync(path, 'a'));
      return withBunChildShape(childProcess.spawn(command, args, options));
    },
    which: whichVia(realFs, env, platform),

    hash: Object.assign((x, seed) => fnv1a64(x, seed), {
      wyhash: (x, seed) => fnv1a64(x, seed),
      crc32,
      adler32: (x, seed = 1) => { let a = seed & 0xffff, b = (seed >>> 16) & 0xffff; for (const byte of asBuffer(x)) { a = (a + byte) % 65521; b = (b + a) % 65521; } return ((b << 16) | a) >>> 0; },
    }),
    CryptoHasher: class {
      constructor(algorithm = 'sha256', hmacKey) {
        if (!HASH_ALGORITHMS.has(algorithm)) throw new Error(`CryptoHasher: this host does not serve the algorithm ${algorithm}`);
        this.h = hmacKey === undefined ? crypto.createHash(algorithm) : crypto.createHmac(algorithm, hmacKey);
      }
      update(d, encoding) { this.h.update(d, encoding); return this; }
      // Bun's encodingless digest is a Uint8Array, and a node Buffer already is one.
      digest(enc) { return enc ? this.h.digest(enc) : this.h.digest(); }
    },

    stringWidth, stripANSI, wrapAnsi, semver, deepEquals,
    escapeHTML: (s) => String(s).replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]),
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    // Actually blocks. A no-op would return instantly from a call whose entire purpose is not to.
    sleepSync: (ms) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Number(ms) || 0); },
    nanoseconds: () => Number(process.hrtime.bigint()),
    // A garbage-collection hint that does nothing is what an advisory hint IS, and it returns
    // nothing either way. `generateHeapSnapshot` is not in that position — an empty object is a
    // wrong answer rather than a declined one — so it is absent and recorded.
    gc() {},
    pathToFileURL: (p) => require('url').pathToFileURL(p),
    fileURLToPath: (u) => require('url').fileURLToPath(u),
    serve: (options) => serveOver(http, options),
  };

  // An unknown key returns the undefined-yielding stub Bun's absence would produce anyway, and is
  // RECORDED. Answering silently and forgetting silently is what turns a new Bun API into a hang
  // with no cause attached. [LAW:no-silent-failure]
  return new Proxy(surface, {
    get(target, key) {
      if (key in target) return target[key];
      onAbsentApi(String(key));
      // undefined, not a stub function: `if (Bun.newApi)` has to be able to answer no. A truthy
      // stub makes feature detection take the branch that then gets nothing back, which is the same
      // "plausible and wrong" this file exists to refuse — one level up, at the member itself.
      return undefined;
    },
  });
}

module.exports = { createBunSurface, serveOver, withBunChildShape, deepEquals, stringWidth, stripANSI, wrapAnsi, semver, fnv1a64, crc32, whichVia, spawnArgs, asBuffer, HASH_ALGORITHMS };
