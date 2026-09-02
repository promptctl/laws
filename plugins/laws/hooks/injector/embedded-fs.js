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

// Embedded module paths are rooted at Bun's virtual filesystem. A path outside it belongs to the
// real disk and every reader below hands it straight back to node.
const VIRTUAL_ROOT = '/$bunfs/';

// The fs members this host answers for an embedded path. Everything else is refused by name.
const SERVED_SYNC = ['readFileSync', 'existsSync', 'statSync', 'lstatSync', 'realpathSync', 'createReadStream'];
const SERVED_PROMISES = ['readFile', 'stat', 'lstat', 'realpath'];

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

  const bytes = (p) => recordFor(p).bytes();
  // Text comes back in the encoding the CONTAINER declared, not the one the caller guessed. A
  // utf16le asset read as 'utf8' is mojibake, and the container is the only party that knows which
  // it is — which is the whole reason bun-graph carries the field. [LAW:one-source-of-truth]
  const text = (p) => recordFor(p).text();
  const stat = (p) => ({
    size: recordFor(p).length, isFile: () => true, isDirectory: () => false,
    isSymbolicLink: () => false, mode: 0o444, mtimeMs: 0, mtime: new Date(0),
  });
  // A read with any encoding is a text read; without one it is a byte read.
  const read = (p, options) => ((typeof options === 'string' ? options : options?.encoding) ? text(p) : bytes(p));

  const served = {
    readFileSync: read,
    existsSync: () => true,
    statSync: stat,
    lstatSync: stat,
    realpathSync: (p) => p,
    createReadStream: (p) => streamFrom(bytes(p)),
    readFile: async (p, options) => read(p, options),
    stat: async (p) => stat(p),
    lstat: async (p) => stat(p),
    realpath: async (p) => p,
  };

  // Wrap a real fs-shaped module so embedded paths are answered here and everything else is the
  // real thing, unchanged. The set of names wrapped comes from the real module, so nothing this
  // host does not know about can slip past as a silent pass-through.
  const substituteFor = (real, names) => {
    const out = { ...real };
    for (const [key, value] of Object.entries(real)) {
      if (typeof value !== 'function') continue;
      const answer = names.includes(key) ? served[key] : null;
      out[key] = (...args) => {
        if (!isEmbedded(args[0])) return value.apply(real, args);
        if (!answer) throw new UnservedEmbeddedCall(key, args[0]);
        return answer(...args);
      };
    }
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
    substituteForFs: (real) => substituteFor(real, SERVED_SYNC),
    substituteForFsPromises: (real) => substituteFor(real, SERVED_PROMISES),
  };
}

module.exports = { VIRTUAL_ROOT, UnservedEmbeddedCall, createEmbeddedFs };
