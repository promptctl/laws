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
const { CellSegmenter } = require('./cell-segmenter.js');
const YAML = require('./yaml.js');
const TOML = require('./toml.js');
const { recording } = require('./recording.js');
const { createSockets } = require('./sockets.js');
const { createImage } = require('./image.js');

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
// XXH64, the real one. Unlike `Bun.hash`'s default — a bucketing function whose exact algorithm is
// not reproducible here and does not need to be — this one is a NAMED algorithm with one answer, and
// the graph turns its result into an identifier (`Bun.hash.xxHash64(e).toString(36)` in m00319). An
// identifier that differs from the one the shipped binary computes for the same input is a wrong
// answer with nothing to catch it, so this is XXH64 to the letter, seed and all.
const rotl64 = (x, r) => ((x << r) | (x >> (64n - r))) & MASK64;
const XXH_P1 = 0x9e3779b185ebca87n, XXH_P2 = 0xc2b2ae3d27d4eb4fn, XXH_P3 = 0x165667b19e3779f9n;
const XXH_P4 = 0x85ebca77c2b2ae63n, XXH_P5 = 0x27d4eb2f165667c5n;
const xxhRound = (acc, input) => (rotl64((acc + input * XXH_P2) & MASK64, 31n) * XXH_P1) & MASK64;
const xxhMerge = (acc, value) => ((((acc ^ xxhRound(0n, value)) & MASK64) * XXH_P1) + XXH_P4) & MASK64;
const xxHash64 = (input, seed = 0) => {
  const bytes = asBuffer(input);
  const s = BigInt(seed) & MASK64;
  const len = bytes.length;
  let i = 0;
  let h;
  if (len >= 32) {
    let v1 = (s + XXH_P1 + XXH_P2) & MASK64, v2 = (s + XXH_P2) & MASK64, v3 = s, v4 = (s - XXH_P1) & MASK64;
    for (; i <= len - 32; i += 32) {
      v1 = xxhRound(v1, bytes.readBigUInt64LE(i));
      v2 = xxhRound(v2, bytes.readBigUInt64LE(i + 8));
      v3 = xxhRound(v3, bytes.readBigUInt64LE(i + 16));
      v4 = xxhRound(v4, bytes.readBigUInt64LE(i + 24));
    }
    h = (rotl64(v1, 1n) + rotl64(v2, 7n) + rotl64(v3, 12n) + rotl64(v4, 18n)) & MASK64;
    h = xxhMerge(xxhMerge(xxhMerge(xxhMerge(h, v1), v2), v3), v4);
  } else {
    h = (s + XXH_P5) & MASK64;
  }
  h = (h + BigInt(len)) & MASK64;
  for (; i + 8 <= len; i += 8) {
    h = (h ^ xxhRound(0n, bytes.readBigUInt64LE(i))) & MASK64;
    h = ((rotl64(h, 27n) * XXH_P1) + XXH_P4) & MASK64;
  }
  if (i + 4 <= len) {
    h = (h ^ ((BigInt(bytes.readUInt32LE(i)) * XXH_P1) & MASK64)) & MASK64;
    h = ((rotl64(h, 23n) * XXH_P2) + XXH_P3) & MASK64;
    i += 4;
  }
  for (; i < len; i++) {
    h = (h ^ ((BigInt(bytes[i]) * XXH_P5) & MASK64)) & MASK64;
    h = (rotl64(h, 11n) * XXH_P1) & MASK64;
  }
  h = (h ^ (h >> 33n)) * XXH_P2 & MASK64;
  h = (h ^ (h >> 29n)) * XXH_P3 & MASK64;
  return (h ^ (h >> 32n)) & MASK64;
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
  // Boxed primitives carry their value where no enumerable key can see it, so the generic fallback
  // called any two of them equal.
  if (a instanceof Number || a instanceof String || a instanceof Boolean) return a.valueOf() === b.valueOf();
  // Keys and members compare STRUCTURALLY, like everything else here. `has` is reference equality,
  // so two Maps keyed by equal-but-distinct objects would have been called different while their
  // values were being compared deeply — one collection, two notions of equality.
  const matches = (needle, haystack, ok) => haystack.some((candidate) => deepEquals(needle, candidate, seen) && ok(candidate));
  if (a instanceof Map) {
    const entries = [...b];
    return a.size === b.size && [...a].every(([k, v]) => matches(k, entries.map(([bk]) => bk), (bk) => deepEquals(v, b.get(bk), seen)));
  }
  if (a instanceof Set) { const members = [...b]; return a.size === b.size && [...a].every((v) => matches(v, members, () => true)); }
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

// How many terminal columns ONE code point occupies. Every width question in this file resolves
// here — `stringWidth` sums it and `sliceAnsi` counts with it — because a slice that measures
// columns differently from the function that measured the line would cut in the wrong place.
// [LAW:one-source-of-truth]
const codePointWidth = (c) => {
  // Combining marks and zero-width characters take no column. U+0300–U+036F is only the first of
  // several such ranges, and stopping there overcounts every script that uses the others.
  const combining = (c >= 0x300 && c <= 0x36f) || (c >= 0x483 && c <= 0x489)
    || (c >= 0x591 && c <= 0x5bd) || (c >= 0x610 && c <= 0x61a) || (c >= 0x64b && c <= 0x65f)
    || (c >= 0x1ab0 && c <= 0x1aff) || (c >= 0x1dc0 && c <= 0x1dff) || (c >= 0x20d0 && c <= 0x20f0)
    || (c >= 0xfe00 && c <= 0xfe0f) || (c >= 0xfe20 && c <= 0xfe2f)
    || c === 0x200b || c === 0x200c || c === 0x200d || c === 0xfeff;
  if (combining) return 0;
  const wide = c >= 0x1100 && (c <= 0x115f || c === 0x2329 || c === 0x232a
    || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff)
    || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6)
    || (c >= 0x1f300 && c <= 0x1faff));
  return wide ? 2 : 1;
};

const stringWidth = (s) => {
  let width = 0;
  for (const ch of String(s ?? '')) width += codePointWidth(ch.codePointAt(0));
  return width;
};

const ANSI = new RegExp('[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\\u0007)|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))', 'g');
const stripANSI = (s) => String(s ?? '').replace(ANSI, '');

// Is this escape sequence one that turns styling OFF? Only an SGR sequence whose parameters are all
// zero (or absent) does; a cursor move or a hyperlink says nothing about style.
const SGR = /^[\u001B\u009B]\[([0-9;]*)m$/;
const isStyleReset = (sequence) => {
  const sgr = SGR.exec(sequence);
  return sgr !== null && sgr[1].split(';').every((code) => code === '' || Number(code) === 0);
};

// `Bun.sliceAnsi(line, start, end)` — a slice measured in DISPLAY COLUMNS rather than in code units,
// with the escape sequences carried through. This is what the renderer cuts every line with
// (m00398), so getting it wrong does not throw: it draws the frame one column off and keeps going.
//
// Two rules decide everything here. Escapes encountered before the window are EMITTED, because the
// colour a slice starts in was set somewhere to its left and dropping it would repaint half the
// screen. And a character is emitted only when it fits ENTIRELY inside the window, because half of a
// two-column glyph is not a thing a terminal can draw — the caller's own loop (`vo` in m00398)
// shrinks its end column until the widths agree, and it can only do that if a wide character at the
// edge is dropped rather than smuggled through.
const sliceAnsi = (input, start = 0, end = Infinity) => {
  const str = String(input ?? '');
  const from = Number.isFinite(start) ? Math.max(0, Math.trunc(start)) : 0;
  const to = Number.isFinite(end) ? Math.trunc(end) : Infinity;
  if (to <= from) return '';
  const escapes = new RegExp(ANSI.source, 'g');
  let out = '', column = 0, styled = false, at = 0;
  const text = (chunk) => {
    for (const ch of chunk) {
      if (column >= to) return;
      const width = codePointWidth(ch.codePointAt(0));
      if (column >= from && column + width <= to) out += ch;
      column += width;
    }
  };
  for (let match = escapes.exec(str); match !== null; match = escapes.exec(str)) {
    text(str.slice(at, match.index));
    // An escape past the end of the window belongs to the text after the slice, not to the slice.
    if (column < to) { out += match[0]; styled = !isStyleReset(match[0]); }
    at = match.index + match[0].length;
  }
  text(str.slice(at));
  // The reset the slice cut off. Without it the style the last kept escape opened runs on into
  // whatever the caller writes next, which on a composited screen is somebody else's cell.
  return styled ? out + '\u001B[0m' : out;
};

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

// Prerelease identifiers compare per dot-separated field: numeric ones numerically, and a numeric
// identifier always ranks below an alphanumeric one. Plain string comparison gets `1.0.0-2` and
// `1.0.0-10` backwards, and every ordering built on it with them.
const comparePrerelease = (a, b) => {
  if (a === b) return 0;
  const left = a.split('.'), right = b.split('.');
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const l = left[i], r = right[i];
    if (l === undefined) return -1;
    if (r === undefined) return 1;
    const ln = /^\d+$/.test(l), rn = /^\d+$/.test(r);
    if (ln && rn) { if (+l !== +r) return +l < +r ? -1 : 1; continue; }
    if (ln !== rn) return ln ? -1 : 1;
    if (l !== r) return l < r ? -1 : 1;
  }
  return 0;
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
    return comparePrerelease(x.pre, y.pre);
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
  if (Array.isArray(options.stdio)) options.stdio = options.stdio.map((v, i) => toNodeStdio(v, openFd, i));
  // An explicit `stdio` wins; it is node's own spelling and the graph uses it too. A caller that
  // names none of the three gets NODE's defaults, not Bun's: Bun's per-slot defaults are not
  // documented anywhere this host can read, and inventing them would be a guess wearing the shape of
  // a fix. This is a known limit, stated rather than papered over.
  if (options.stdio === undefined && named.some((v) => v !== undefined)) {
    options.stdio = named.map((v, i) => (v === undefined ? (i === 0 ? 'inherit' : 'pipe') : toNodeStdio(v, openFd, i)));
  }
  return { command: cmd?.[0], args: cmd?.slice(1) ?? [], options };
};
// Bun's per-stream values, in node's vocabulary. A BunFile stands for the descriptor it names. An
// unrecognised value is refused rather than quietly becoming 'pipe' — a wrong stream is a hang or a
// lost output with nothing pointing at the cause. [LAW:no-silent-failure]
const toNodeStdio = (v, openFd, slot) => {
  if (v === 'ignore' || v === 'inherit' || v === 'pipe' || v === null || v === undefined) return v ?? 'pipe';
  if (typeof v === 'number') return v;
  if (v && typeof v === 'object' && typeof v.fd === 'number') return v.fd;
  // A BunFile names a path rather than carrying a descriptor, so one is opened for it.
  // The slot decides the mode: a descriptor opened append-only cannot be read from, so a BunFile
  // standing in for stdin has to be opened for reading.
  if (v && typeof v === 'object' && typeof v.name === 'string') return openFd(v.name, slot === 0 ? 'r' : 'a');
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
      // The raw pairs, not an object: a header the Fetch iterator yields more than once (Set-Cookie)
      // collapses to whichever came last when it becomes a key.
      const headers = [];
      response.headers.forEach((value, name) => headers.push(name, value));
      res.writeHead(response.status, headers);
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
// `Bun.Transpiler`, over node's own TypeScript type stripper.
//
// WHAT THE GRAPH ASKS FOR. m00079 compiles a plugin's `hooks/register.ts` with exactly one call:
//     new Bun.Transpiler({loader, macro:false}).transformSync(`${pragma}${source}`)
// where the loader comes off the file extension — `js`/`mjs`/`cjs` never reach here (the caller
// returns them untouched), leaving `ts`, `tsx` and `jsx`.
//
// WHERE THIS STOPS, AND WHY IT STOPS LOUDLY. node strips types; it does not COMPILE them, and it
// carries no JSX at all. So `.ts` hooks modules — which is what the extension resolver reaches for
// first and what essentially every one of them is — work, and the constructs node's stripper
// refuses (an `enum`, a `namespace`, a constructor parameter property) and the two JSX loaders are
// refused BY NAME. That refusal is not a degrade smuggled in: m00079 wraps this call in a try/catch
// that turns the message into "the hooks module of <plugin> cannot ship: <reason>", so the reason
// reaches the user with the plugin's name attached. A transformSync that returned the source
// unchanged would ship a `.tsx` file to the runtime as JavaScript and fail somewhere else entirely.
// [LAW:no-silent-failure]
const TRANSPILER_LOADERS = new Set(['js', 'ts', 'tsx', 'jsx']);
const transpilerOver = (stripTypeScriptTypes, onAbsentApi) => class Transpiler {
  constructor(options = {}) {
    // A Bun macro runs arbitrary code at transpile time through Bun's own bundler. There is nothing
    // to approximate, so a caller asking for one is told, rather than quietly getting no macros.
    if (options.macro) throw new Error('Transpiler: this host does not run Bun macros');
    this.loader = options.loader ?? 'js';
    if (!TRANSPILER_LOADERS.has(this.loader)) throw new Error(`Transpiler: this host does not know the loader ${JSON.stringify(this.loader)}`);
    // `scan` and `scanImports` are Bun's other two methods and they need a real parser; absent, and
    // recorded by name if anything ever reaches for them.
    return recording('Transpiler', this, onAbsentApi);
  }

  transformSync(source, loader = this.loader) {
    const text = String(source);
    if (loader === 'js') return text;
    if (loader !== 'ts') {
      throw new Error(`Transpiler: the ${loader} loader needs a JSX compiler, which this host does not carry — write the module as .ts, or ship it already compiled`);
    }
    try {
      return stripTypeScriptTypes(text);
    } catch (e) {
      // node's own message already names the construct ("TypeScript enum is not supported in
      // strip-only mode"); the prefix says whose limitation it is so the plugin author is not left
      // thinking their TypeScript is invalid.
      throw new Error(`Transpiler: this host strips TypeScript types rather than compiling them — ${e && e.message}`);
    }
  }

  async transform(source, loader) { return this.transformSync(source, loader); }
};

function createBunSurface({ embedded, realFs, childProcess, crypto, zlib, http, net, stripTypeScriptTypes, env, platform, entryName, stdin, onAbsentApi }) {
  const sockets = createSockets({ net, onAbsentApi });
  // A member the graph reads THROUGH — `Bun.unsafe.setJITPolicy?.(1)` — needs its namespace present,
  // because `?.` guards the last step and not the one before it. The namespace records its own absent
  // members by dotted name, exactly as the surface records top-level ones, so an empty namespace is
  // still absence and never a stub. [LAW:no-silent-failure]
  // Each namespace's name is its key here, so the dotted name it records cannot drift from the path
  // the graph read. [LAW:one-source-of-truth]
  const namespaces = Object.fromEntries(Object.entries({
    // Read through from 2.1.270, which calls setJITPolicy in the message loop: undefined here threw
    // on the first turn. node has no JIT tier-up knob, so the member stays absent.
    unsafe: {},
    // `claude edit-hook` reads its edit as `new Response(Bun.stdin.stream()).text()`.
    stdin: { stream: () => Readable.toWeb(stdin) },
    // `Bun.ant` is @anthropic-ai/bun-internal, a PRIVATE Anthropic Bun build — not public Bun. Its
    // other members (getPeerPid, getPeerUid, memoryPressureLevel, waitForUrlEvent) are each reached
    // behind a typeof check or a try/catch and degrade cleanly, so they stay absent and record
    // themselves. CellSegmenter is the exception: src/ink demands it outright, and its absence is
    // the difference between a rendering TUI and one that paints once and hangs forever.
    ant: { CellSegmenter },
  }).map(([name, members]) => [name, recording(name, members, onAbsentApi)]));
  const surface = {
    version: '1.3.14', revision: '0', main: entryName, env,
    get argv() { return process.argv; },
    isStandaloneExecutable: true, enableANSIColors: true, isMainThread: true,
    ...namespaces,

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
      const { command, args, options } = spawnArgs(first, second, (path, mode) => realFs.openSync(path, mode));
      return withBunChildShape(childProcess.spawn(command, args, options));
    },
    which: whichVia(realFs, env, platform),

    hash: Object.assign((x, seed) => fnv1a64(x, seed), {
      wyhash: (x, seed) => fnv1a64(x, seed),
      crc32, xxHash64,
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

    stringWidth, stripANSI, sliceAnsi, wrapAnsi, semver, deepEquals,
    // Boot-critical: m00142 reads every skill, command and plugin manifest's frontmatter through
    // this, so an absent YAML is a session with none of them. Only `parse` and `stringify` are
    // exposed because those are the two the graph names.
    YAML: recording('YAML', { parse: YAML.parse, stringify: YAML.stringify }, onAbsentApi),
    // `.mcp.toml` and nothing else (m00861). Bun's own TOML has `parse` alone, so there is no
    // `stringify` to be missing here.
    TOML: recording('TOML', { parse: TOML.parse }, onAbsentApi),
    Transpiler: transpilerOver(stripTypeScriptTypes, onAbsentApi),
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
    // The agent proxy's listener, its direct dials and its startup self-check (m01352). See
    // sockets.js for the two semantics a naive wrapper gets wrong: the synchronous bind and the
    // short write.
    listen: sockets.listen, connect: sockets.connect,
    // Header metadata is real; every pixel operation is absent and says so. See image.js for why
    // the line falls there and what the app does on each side of it.
    Image: createImage({ realFs, onAbsentApi }),
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

module.exports = { createBunSurface, serveOver, transpilerOver, withBunChildShape, deepEquals, stringWidth, stripANSI, sliceAnsi, wrapAnsi, semver, fnv1a64, crc32, xxHash64, whichVia, spawnArgs, asBuffer, HASH_ALGORITHMS };
