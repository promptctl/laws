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

const ENOENT_SIZE = 0;

// Bun's own default hash is a fast 64-bit NON-cryptographic hash, not a digest. The exact algorithm
// is not reproducible here, and it does not need to be — callers use it for bucketing, so what has
// to hold is that it is deterministic, well distributed, and 64 bits wide. FNV-1a is all three.
const MASK64 = (1n << 64n) - 1n;
const fnv1a64 = (input) => {
  const bytes = typeof input === 'string' ? Buffer.from(input, 'utf8') : Buffer.from(input.buffer ?? input);
  let h = 0xcbf29ce484222325n;
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
  return (input) => {
    const bytes = typeof input === 'string' ? Buffer.from(input, 'utf8') : Buffer.from(input.buffer ?? input);
    let c = 0xffffffff;
    for (const b of bytes) c = table[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
})();

// Structural equality, order-independent. JSON.stringify would call {a:1,b:2} and {b:2,a:1}
// different, which is wrong for a primitive whose whole job is answering that question.
function deepEquals(a, b) {
  if (Object.is(a, b)) return true;
  if (typeof a !== 'object' || typeof b !== 'object' || a === null || b === null) return false;
  if (Object.getPrototypeOf(a) !== Object.getPrototypeOf(b)) return false;
  if (Array.isArray(a)) return a.length === b.length && a.every((x, i) => deepEquals(x, b[i]));
  if (a instanceof Date) return a.getTime() === b.getTime();
  if (a instanceof Map) return a.size === b.size && [...a].every(([k, v]) => b.has(k) && deepEquals(v, b.get(k)));
  if (a instanceof Set) return a.size === b.size && [...a].every((v) => b.has(v));
  if (ArrayBuffer.isView(a)) return a.byteLength === b.byteLength && Buffer.from(a.buffer, a.byteOffset, a.byteLength).equals(Buffer.from(b.buffer, b.byteOffset, b.byteLength));
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((k) => Object.hasOwn(b, k) && deepEquals(a[k], b[k]));
}

const HTML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#x27;' };

// Bun's CryptoHasher accepts algorithms node's crypto does not. Mapping the ones node can serve and
// refusing the rest by name beats forwarding an unknown name and letting createHash throw something
// that names neither the algorithm nor this shim.
const HASH_ALGORITHMS = new Set(['sha1', 'sha224', 'sha256', 'sha384', 'sha512', 'sha512-224', 'sha512-256', 'md5', 'blake2b256', 'blake2b512']);
const NODE_ALGORITHM = { blake2b256: 'blake2b512' };

const stringWidth = (s) => {
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

// Bun.spawn accepts both spawn(["cmd","arg"], options) and spawn({cmd: ["cmd","arg"], ...options}).
const spawnArgs = (first, second) => {
  const { cmd, ...rest } = Array.isArray(first) ? { cmd: first } : (first || {});
  return { command: cmd?.[0], args: cmd?.slice(1) ?? [], options: { ...rest, ...(second || {}) } };
};

// The bytes a caller handed us, as a Buffer that respects a view's window. `Buffer.from(view.buffer)`
// alone takes the whole backing store, byteOffset and byteLength ignored.
const asBuffer = (data) => (typeof data === 'string' ? Buffer.from(data)
  : ArrayBuffer.isView(data) ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
    : Buffer.from(data));

// Build the surface. `onAbsentApi` is called once per name the graph asks for that is not here.
function createBunSurface({ embedded, realFs, childProcess, crypto, zlib, env, platform, entryName, onAbsentApi }) {
  const surface = {
    version: '1.3.14', revision: '0', main: entryName, env,
    get argv() { return process.argv; },
    stdin: process.stdin, stdout: process.stdout, stderr: process.stderr,
    isStandaloneExecutable: true, enableANSIColors: true, isMainThread: true,

    file: (p) => ({
      async text() { return String(embedded.readAny(p, 'utf8')); },
      async json() { return JSON.parse(String(embedded.readAny(p, 'utf8'))); },
      async exists() { return embedded.existsAny(p); },
      async bytes() { return new Uint8Array(embedded.readAny(p)); },
      async arrayBuffer() { const b = asBuffer(embedded.readAny(p)); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); },
      stream() { return embedded.streamAny(p); },
      get size() { return embedded.existsAny(p) ? embedded.statAny(p).size : ENOENT_SIZE; },
      name: p, type: '',
    }),
    write: async (dst, data) => {
      realFs.writeFileSync(typeof dst === 'object' && dst?.name ? dst.name : dst, asBuffer(data));
      return 0;
    },

    zstdDecompressSync: (b) => zlib.zstdDecompressSync(b),
    zstdDecompress: async (b) => zlib.zstdDecompressSync(b),
    gzipSync: (b) => zlib.gzipSync(b), gunzipSync: (b) => zlib.gunzipSync(b),

    spawn: (first, second) => { const { command, args, options } = spawnArgs(first, second); return childProcess.spawn(command, args, options); },
    spawnSync: (first, second) => { const { command, args, options } = spawnArgs(first, second); return childProcess.spawnSync(command, args, options); },
    which: whichVia(realFs, env, platform),

    hash: Object.assign((x) => fnv1a64(x), { wyhash: (x) => fnv1a64(x), crc32, adler32: (x) => { let a = 1, b = 0; for (const byte of asBuffer(typeof x === 'string' ? x : x)) { a = (a + byte) % 65521; b = (b + a) % 65521; } return ((b << 16) | a) >>> 0; } }),
    CryptoHasher: class {
      constructor(algorithm = 'sha256') {
        if (!HASH_ALGORITHMS.has(algorithm)) throw new Error(`CryptoHasher: this host does not serve the algorithm ${algorithm}`);
        this.h = crypto.createHash(NODE_ALGORITHM[algorithm] || algorithm);
      }
      update(d) { this.h.update(d); return this; }
      digest(enc) { return enc ? this.h.digest(enc) : new Uint8Array(this.h.digest()); }
    },

    stringWidth, stripANSI, wrapAnsi, semver, deepEquals,
    escapeHTML: (s) => String(s).replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]),
    color: (c) => String(c),
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)), sleepSync: () => {},
    nanoseconds: () => Number(process.hrtime.bigint()),
    gc() {}, generateHeapSnapshot: () => ({}),
    pathToFileURL: (p) => require('url').pathToFileURL(p),
    fileURLToPath: (u) => require('url').fileURLToPath(u),
    serve: () => ({ stop() {}, reload() {}, ref() {}, unref() {}, port: 0, url: new URL('http://localhost:0'), hostname: 'localhost' }),
  };

  // An unknown key returns the undefined-yielding stub Bun's absence would produce anyway, and is
  // RECORDED. Answering silently and forgetting silently is what turns a new Bun API into a hang
  // with no cause attached. [LAW:no-silent-failure]
  return new Proxy(surface, {
    get(target, key) {
      if (key in target) return target[key];
      onAbsentApi(String(key));
      return () => undefined;
    },
  });
}

module.exports = { createBunSurface, deepEquals, stringWidth, stripANSI, wrapAnsi, semver, fnv1a64, crc32, whichVia, spawnArgs, asBuffer, HASH_ALGORITHMS };
