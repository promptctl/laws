// embedded-fs.js — the modules Bun embedded in the executable, presented as a read-only filesystem.
//
// Hosted chunks reach their embedded assets three different ways: `import`, `import.meta.require`,
// and plain `fs` calls on the virtual path. All three read the SAME map, so the map is built once
// here and the adapters below are thin. [LAW:one-source-of-truth]
//
// WHAT THE SUBSTITUTES REFUSE, AND WHY THAT IS THE POINT. `substituteFor` wraps EVERY function of
// node's real fs and serves the handful this host knows how to answer for an embedded path. Any
// other entry point reached with an embedded path — `readdir`, `open`, `createWriteStream`, one
// that does not exist yet — is refused BY NAME rather than passed through to the real fs, where it
// would raise a bare ENOENT that the calling app catches and turns into a wrong answer with no
// trace back to here. Synthesising a plausible reply instead (a fabricated directory listing, say)
// would be worse still: a guess wearing the shape of an answer. So the gap is closed as a class,
// not member by member, and the refusal names the member to add next.
// [LAW:no-silent-failure] [LAW:parse-dont-validate]

'use strict';

// The container format owns this literal; this module reads it rather than restating it.
// [LAW:one-source-of-truth]
const { VIRTUAL_ROOT } = require('./bun-graph.js');

// The fs members this host answers for an embedded path. Everything else is refused by name.
const SERVED_SYNC = ['readFileSync', 'existsSync', 'statSync', 'lstatSync', 'realpathSync', 'createReadStream'];
const SERVED_PROMISES = ['readFile', 'stat', 'lstat', 'realpath'];

// How a refusal has to LOOK depends on what the member promised to return, and only on that. A
// promise-returning member rejects — same loudness, since an unhandled rejection ends the process,
// but the shape its callers await. Everything else throws where it was called. What a refusal must
// never become is a callback error: that is a value the app already knows how to catch and turn
// into "the asset is missing", which is the laundering that made the real fs's bare ENOENT
// unacceptable to begin with. [LAW:no-silent-failure]
class UnservedEmbeddedCall extends Error {
  constructor(member, path) {
    super(`fs.${member} was called on the embedded path ${path}, which this host does not serve`);
    this.code = 'ENOSYS';
    this.member = member;
    this.path = path;
  }
}

function noSuchFile(path) {
  const e = new Error(`ENOENT: no such file or directory, open '${path}'`);
  return Object.assign(e, { code: 'ENOENT', errno: -2, syscall: 'open', path });
}

// Build the view over a graph's modules. `realFs` and `streamFrom` are parameters rather than
// imports so the whole thing is testable with no disk and no mocks. [LAW:effects-at-boundaries]
function createEmbeddedFs(modules, { realFs, streamFrom } = {}) {
  const byName = new Map(modules.map((m) => [m.name, m]));

  const isEmbedded = (p) => typeof p === 'string' && p.startsWith(VIRTUAL_ROOT) && byName.has(p);
  const recordFor = (p) => { const m = byName.get(p); if (!m) throw noSuchFile(p); return m; };

  // A COPY, not the view bun-graph hands back. That view aliases the one buffer holding the whole
  // executable, and real `readFileSync` gives its caller memory the caller owns — hosted code that
  // writes into what it read would otherwise be editing the graph itself.
  const bytes = (p) => Buffer.from(recordFor(p).bytes());
  // Text comes back in the encoding the CONTAINER declared, not the one the caller guessed. A
  // utf16le asset read as 'utf8' is mojibake, and the container is the only party that knows which
  // it is — which is the whole reason bun-graph carries the field. [LAW:one-source-of-truth]
  const text = (p) => recordFor(p).text();
  // A whole Stats shape, not the three predicates this host happens to care about: a caller is
  // entitled to ask any of them, and a missing one is a TypeError rather than a `false`.
  const stat = (p) => ({
    size: recordFor(p).length, mode: 0o444, mtimeMs: 0, mtime: new Date(0), atimeMs: 0, ctimeMs: 0, birthtimeMs: 0,
    isFile: () => true, isDirectory: () => false, isSymbolicLink: () => false,
    isSocket: () => false, isFIFO: () => false, isBlockDevice: () => false, isCharacterDevice: () => false,
  });
  // A read with any encoding is a text read; without one it is a byte read.
  const read = (p, options) => ((typeof options === 'string' ? options : options?.encoding) ? text(p) : bytes(p));

  const served = {
    readFileSync: read,
    existsSync: () => true,
    statSync: stat,
    lstatSync: stat,
    realpathSync: (p) => p,
    createReadStream: (p, options) => streamFrom(bytes(p), options),
    readFile: async (p, options) => read(p, options),
    stat: async (p) => stat(p),
    lstat: async (p) => stat(p),
    realpath: async (p) => p,
  };

  // Wrap a real fs-shaped module so embedded paths are answered here and everything else is the
  // real thing, unchanged. The set of names wrapped comes from the real module, so nothing this
  // host does not know about can slip past as a silent pass-through.
  const substituteFor = (real, names, rejects) => {
    const out = { ...real };
    for (const [key, value] of Object.entries(real)) {
      if (typeof value !== 'function') continue;
      const answer = names.includes(key) ? served[key] : null;
      const wrapper = (...args) => {
        if (!isEmbedded(args[0])) return value.apply(real, args);
        if (answer) return answer(...args);
        const refusal = new UnservedEmbeddedCall(key, args[0]);
        if (rejects) return Promise.reject(refusal);
        throw refusal;
      };
      // Node hangs things off its fs functions — `realpathSync.native` is the well-known one — and a
      // bare arrow would drop every one of them.
      Object.defineProperties(wrapper, Object.getOwnPropertyDescriptors(value));
      out[key] = wrapper;
    }
    return out;
  };

  // `require('fs').promises` is an OBJECT on the real module, so the loop above skips it and hosted
  // code reaching through it would get the real, unwrapped promises API and a bare ENOENT.
  const substituteForFs = (real) => {
    const out = substituteFor(real, SERVED_SYNC, false);
    if (real.promises) out.promises = substituteFor(real.promises, SERVED_PROMISES, true);
    return out;
  };

  return {
    VIRTUAL_ROOT, UnservedEmbeddedCall,
    has: isEmbedded,
    names: () => [...byName.keys()],
    loaderOf: (p) => byName.get(p)?.loader,
    bytes, text, stat, read,
    // Readers that answer for the embedded graph AND the real disk, decided by the path.
    // [LAW:dataflow-not-control-flow] one function over both, no caller-side branching.
    readAny: (p, options) => isEmbedded(p) ? read(p, options) : realFs.readFileSync(p, options),
    existsAny: (p) => isEmbedded(p) || realFs.existsSync(p),
    statAny: (p) => isEmbedded(p) ? stat(p) : realFs.statSync(p),
    streamAny: (p) => isEmbedded(p) ? streamFrom(bytes(p)) : realFs.createReadStream(p),
    substituteForFs,
    substituteForFsPromises: (real) => substituteFor(real, SERVED_PROMISES, true),
  };
}

module.exports = { VIRTUAL_ROOT, UnservedEmbeddedCall, createEmbeddedFs };
