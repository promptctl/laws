#!/usr/bin/env node
// Unit tests for bun-surface.js — the `Bun` global the hosted graph runs against.
//
// This suite exists because of the one thing the surface must never do: answer plausibly and
// wrongly. A present-but-wrong stub keeps the process alive while corrupting whatever it touched,
// and it is invisible — which is why the absent-API recording, the hash functions and the deep
// equality all get cases here rather than being taken on faith from a boot that happened to work.
//
// Every capability the surface needs arrives as a parameter, so nothing below spawns a process,
// touches a disk, or needs a binary.

'use strict';
const assert = require('assert');
const S = require('./bun-surface.js');
const { createEmbeddedFs } = require('./embedded-fs.js');

let pass = 0, fail = 0;
// Every case is queued and awaited. A harness that calls fn() and moves on turns a FAILING async
// case into a rejected promise nobody reads: the assertion loses, and the suite prints ok.
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
async function runAll() {
  for (const { name, fn } of cases) {
    try { await fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

const record = (name, contents, loader = 'text') => {
  const bytes = Buffer.from(contents, 'utf8');
  return { name, loader, encoding: 'utf8', length: bytes.length, bytes: () => bytes, text: () => bytes.toString('utf8') };
};
const written = [];
const realFs = {
  constants: { X_OK: 1 },
  readFileSync: () => 'real', existsSync: () => true, statSync: () => ({ size: 1 }),
  createReadStream: () => require('stream').Readable.from(Buffer.from('real')),
  writeFileSync: (p, data) => written.push([p, data]),
  // Normalising here is what makes the separator case real: without the guard in `which`,
  // path.join('/usr/bin', '../bin/ls') resolves to a file that exists.
  accessSync: (p) => { if (!['/usr/bin/git', '/bin/ls'].includes(require('path').normalize(p))) throw new Error('ENOENT'); },
};
function surface(overrides = {}) {
  const embedded = createEmbeddedFs([record('/$bunfs/root/a.md', 'hello')], { realFs, streamFrom: (b) => require('stream').Readable.from(b) });
  const absent = [];
  const bun = S.createBunSurface({
    embedded, realFs, crypto: require('crypto'), zlib: require('zlib'), http: require('http'),
    // Shaped like a ChildProcess so the Bun-child affordances can be attached, while still
    // recording what node was actually asked for.
    childProcess: { spawn: (...a) => ({ spawned: a, on: () => {} }), spawnSync: (...a) => ({ spawnedSync: a }) },
    env: { PATH: '/usr/bin:/bin' }, platform: 'darwin', entryName: '/$bunfs/root/cli',
    onAbsentApi: (n) => absent.push(n), ...overrides,
  });
  return { bun, absent };
}

// ---- the absent-API recording the boot self-check depends on ------------------------------------

t('a member the surface does not have is RECORDED, and is undefined — not a truthy stub', () => {
  const { bun, absent } = surface();
  assert.strictEqual(bun.somethingBunAddedLastWeek, undefined);
  // The point of undefined over `() => undefined`: feature detection has to be able to answer no.
  assert.strictEqual(Boolean(bun.somethingBunAddedLastWeek), false);
  assert.strictEqual(bun.somethingBunAddedLastWeek ?? 'fallback', 'fallback');
  // Every access is reported; collapsing repeats is the host's job, not the surface's.
  assert.deepStrictEqual([...new Set(absent)], ['somethingBunAddedLastWeek']);
});

t('the members the graph never uses are absent rather than wrong', () => {
  // Surveyed against the shipped graph: nothing reads Bun.stdin/stdout/stderr or calls Bun.color.
  // Keeping a wrong-shaped member for them would answer plausibly; absence is recorded.
  const { bun, absent } = surface();
  for (const name of ['stdin', 'stdout', 'stderr', 'color', 'spawnSync', 'generateHeapSnapshot']) {
    assert.strictEqual(bun[name], undefined, name);
  }
  assert.deepStrictEqual([...new Set(absent)], ['stdin', 'stdout', 'stderr', 'color', 'spawnSync', 'generateHeapSnapshot']);
});

t('a member the surface does have is never recorded as absent', () => {
  const { bun, absent } = surface();
  assert.strictEqual(typeof bun.stringWidth, 'function');
  bun.stringWidth('x');
  assert.deepStrictEqual(absent, []);
});

// ---- hashes: deterministic and distinct, never constants ----------------------------------------

t('hashes are deterministic and actually distinguish inputs', () => {
  const { bun } = surface();
  for (const h of [bun.hash, bun.hash.wyhash, bun.hash.crc32, bun.hash.adler32]) {
    assert.strictEqual(h('alpha'), h('alpha'), 'the same input must hash the same way twice');
    assert.notStrictEqual(h('alpha'), h('beta'), 'a hash that maps every input to one value is a stub, not a hash');
  }
});

t('the default hash is a 64-bit value, which is what Bun returns', () => {
  const { bun } = surface();
  const h = bun.hash('alpha');
  assert.strictEqual(typeof h, 'bigint');
  assert.ok(h < (1n << 64n) && h > 0n);
});

t('CryptoHasher digests, and refuses an algorithm it cannot serve BY NAME', () => {
  const { bun } = surface();
  // The encoding argument real Bun accepts is forwarded, not dropped.
  assert.strictEqual(new bun.CryptoHasher('sha256').update('616263', 'hex').digest('hex'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.strictEqual(new bun.CryptoHasher('sha256').update('abc').digest('hex'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.throws(() => new bun.CryptoHasher('xxhash3'), /does not serve the algorithm xxhash3/);
  // node has only blake2b512, and a truncation of it is a different function — refused, not faked.
  assert.throws(() => new bun.CryptoHasher('blake2b256'), /does not serve the algorithm blake2b256/);
  // The hmac key real Bun accepts is honoured, not dropped on the floor.
  const keyed = new bun.CryptoHasher('sha256', 'secret').update('abc').digest('hex');
  assert.strictEqual(keyed, require('crypto').createHmac('sha256', 'secret').update('abc').digest('hex'));
  assert.notStrictEqual(keyed, new bun.CryptoHasher('sha256').update('abc').digest('hex'));
});

t('a seed changes the hash, rather than being ignored', () => {
  const { bun } = surface();
  assert.notStrictEqual(bun.hash('alpha', 1), bun.hash('alpha', 2));
  assert.strictEqual(bun.hash('alpha', 7), bun.hash('alpha', 7));
  assert.notStrictEqual(bun.hash.crc32('alpha', 1), bun.hash.crc32('alpha', 2));
});

t('a hash reads a typed-array VIEW window, not its whole backing store', () => {
  const { bun } = surface();
  const backing = Buffer.from('XXXhelloYYY');
  const view = new Uint8Array(backing.buffer, backing.byteOffset + 3, 5);
  assert.strictEqual(bun.hash(view), bun.hash('hello'));
});

// ---- the members that were identity functions ---------------------------------------------------

t('escapeHTML escapes, rather than returning its input', () => {
  const { bun } = surface();
  assert.strictEqual(bun.escapeHTML(`<a href="x">&'`), '&lt;a href=&quot;x&quot;&gt;&amp;&#x27;');
});

t('deepEquals does not depend on key order', () => {
  const { bun } = surface();
  assert.strictEqual(bun.deepEquals({ a: 1, b: 2 }, { b: 2, a: 1 }), true, 'JSON.stringify would call these different');
  assert.strictEqual(bun.deepEquals({ a: 1 }, { a: 2 }), false);
  assert.strictEqual(bun.deepEquals([1, [2, 3]], [1, [2, 3]]), true);
  assert.strictEqual(bun.deepEquals([{ a: 1, b: 2 }], [{ b: 2, a: 1 }]), true, 'the order-independence has to hold inside arrays too');
  assert.strictEqual(bun.deepEquals(new Map([['a', 1]]), new Map([['a', 1]])), true);
  assert.strictEqual(bun.deepEquals(new Set([1, 2]), new Set([2, 1])), true);
  assert.strictEqual(bun.deepEquals(new Date(5), new Date(5)), true);
  assert.strictEqual(bun.deepEquals({ a: undefined }, {}), false, 'a present undefined key is not an absent one');
  assert.strictEqual(bun.deepEquals(/a/g, /a/g), true);
  assert.strictEqual(bun.deepEquals(/a/g, /b/g), false, 'two RegExps have no enumerable keys to tell apart');
  const loopA = { name: 'a' }; loopA.self = loopA;
  const loopB = { name: 'a' }; loopB.self = loopB;
  assert.strictEqual(bun.deepEquals(loopA, loopB), true, 'circular data must terminate, not exhaust the stack');
  assert.strictEqual(bun.deepEquals(new Error('boom'), new Error('boom')), true);
  assert.strictEqual(bun.deepEquals(new Error('boom'), new Error('other')), false, 'an Error has no enumerable keys to tell apart');
});

// ---- which: no shell, ever ----------------------------------------------------------------------

t('which finds an executable on PATH', () => {
  const { bun } = surface();
  assert.strictEqual(bun.which('git'), '/usr/bin/git');
  assert.strictEqual(bun.which('ls'), '/bin/ls');
  assert.strictEqual(bun.which('definitely-not-here'), null);
});

t('which cannot be talked into running a command — there is no shell to inject into', () => {
  // With `spawnSync('command -v ' + cmd, {shell: true})` this name would execute `touch`. The PATH
  // scan has no interpreter in it at all, so the worst a hostile name can do is not be found.
  const { bun } = surface();
  assert.strictEqual(bun.which('git; touch /tmp/pwned'), null);
  assert.strictEqual(bun.which('../bin/ls'), null, 'a name containing a path separator is not a PATH lookup, even when it would resolve');
});

// ---- spawn accepts both of Bun's shapes ----------------------------------------------------------

t('spawn takes the array form and the object form alike', () => {
  const { bun } = surface();
  assert.deepStrictEqual(bun.spawn(['git', 'status'], { cwd: '/tmp' }).spawned, ['git', ['status'], { cwd: '/tmp' }]);
  assert.deepStrictEqual(bun.spawn({ cmd: ['git', 'status'], cwd: '/tmp' }).spawned, ['git', ['status'], { cwd: '/tmp' }]);
  // spawnSync has no call site in the graph, so it is absent rather than kept in a shape that
  // would only be guessed at — Bun's spawnSync result is not node's.
  assert.strictEqual(bun.spawnSync, undefined);
});

t("Bun's per-stream options become node's stdio, instead of being silently dropped", () => {
  // The shipped graph passes exactly this shape. Forwarding it unchanged leaves node at its own
  // defaults, so an `ignore` becomes an unread pipe that fills up and blocks the child.
  const { bun } = surface();
  const [, , options] = bun.spawn({ cmd: ['git', '--version'], stdout: 'pipe', stderr: 'ignore' }).spawned;
  assert.deepStrictEqual(options.stdio, ['inherit', 'pipe', 'ignore']);
  assert.strictEqual(options.stdout, undefined, "node would not know what to do with Bun's spelling");
  // A BunFile stands for the descriptor it names, and an explicit stdio still wins.
  assert.deepStrictEqual(bun.spawn({ cmd: ['x'], stderr: { fd: 7 } }).spawned[2].stdio, ['inherit', 'pipe', 7]);
  assert.deepStrictEqual(bun.spawn({ cmd: ['x'], stdio: ['ignore', 'ignore', 'ignore'], stdout: 'pipe' }).spawned[2].stdio, ['ignore', 'ignore', 'ignore']);
});

t('a spawned child answers the two things the graph asks of it', async () => {
  const { bun } = surface({ childProcess: require('child_process') });
  const child = bun.spawn({ cmd: [process.execPath, '-e', 'process.stdout.write("hi")'], stdout: 'pipe' });
  assert.strictEqual(await child.stdout.text(), 'hi');
  assert.strictEqual(await child.exited, 0);
});

t('a BunFile in an explicit stdio array is resolved to a descriptor', () => {
  // The graph passes `stdio:["ignore","ignore",Bun.file(path)]`. Handing that array to node
  // unchanged means handing node an object it cannot use.
  const opened = [];
  const { bun } = surface({ realFs: { ...realFs, openSync: (p) => { opened.push(p); return 42; } } });
  const [, , options] = bun.spawn({ cmd: ['x'], stdio: ['ignore', 'ignore', bun.file('/tmp/log')] }).spawned;
  assert.deepStrictEqual(options.stdio, ['ignore', 'ignore', 42]);
  assert.deepStrictEqual(opened, ['/tmp/log']);
});

t('a child killed by a signal is not reported as a clean exit', async () => {
  const { bun } = surface({ childProcess: require('child_process') });
  const child = bun.spawn({ cmd: [process.execPath, '-e', 'setTimeout(()=>{},9999)'], stdout: 'ignore' });
  child.kill('SIGKILL');
  await assert.rejects(() => child.exited, /killed by SIGKILL/);
});

t('an unrecognised stdio value is refused by name, not quietly turned into a pipe', () => {
  const { bun } = surface();
  assert.throws(() => bun.spawn({ cmd: ['x'], stdout: 'somethingelse' }), /does not know the stdio value "somethingelse"/);
});

t('a child\'s output can be read once — and reading it twice does not come back empty', async () => {
  const { bun } = surface({ childProcess: require('child_process') });
  const child = bun.spawn({ cmd: [process.execPath, '-e', 'process.stdout.write("hi")'], stdout: 'pipe' });
  assert.strictEqual(await child.stdout.text(), 'hi');
  assert.strictEqual(await child.stdout.text(), 'hi', 'a stream is consumed by reading it; the drain has to be shared');
});

t('the exited promise is built only when something asks for it', async () => {
  // Created eagerly it rejects on 'error' with nobody awaiting, and an unhandled rejection ends the
  // process over a child nobody was watching.
  const { bun } = surface({ childProcess: require('child_process') });
  const child = bun.spawn({ cmd: ['definitely-not-a-real-binary-xyz'], stdout: 'ignore', stderr: 'ignore' });
  await new Promise((r) => setTimeout(r, 60));
  await assert.rejects(() => child.exited);
});

t('a handler that throws still answers, rather than hanging the request', async () => {
  const { bun } = surface();
  const server = bun.serve({ port: 0, fetch: () => { throw new Error('handler blew up'); } });
  await new Promise((r) => setTimeout(r, 40));
  try {
    // Bounded on purpose. Without the 500 the request never answers, and an unbounded fetch would
    // turn this case into a hang — which reports nothing and is no better than a case that passes.
    const res = await fetch(`http://127.0.0.1:${server.port}/`, { signal: AbortSignal.timeout(2000) });
    assert.strictEqual(res.status, 500);
  } finally {
    server.stop(true);
  }
});

t('serve actually serves — the handler runs and its response comes back', async () => {
  const { bun } = surface();
  const server = bun.serve({ hostname: '127.0.0.1', port: 0, fetch: (req) => new Response('pong ' + new URL(req.url).pathname, { status: 201 }) });
  await new Promise((r) => setTimeout(r, 40));
  const res = await fetch(`http://127.0.0.1:${server.port}/ping`);
  assert.strictEqual(res.status, 201);
  assert.strictEqual(await res.text(), 'pong /ping');
  server.stop(true);
});

// ---- file, and the byte-window bug ---------------------------------------------------------------

t('Bun.file reads the embedded graph and the real disk alike, streams included', async () => {
  const { bun } = surface();
  assert.strictEqual(await bun.file('/$bunfs/root/a.md').text(), 'hello');
  assert.strictEqual(bun.file('/$bunfs/root/a.md').size, 5);
  assert.strictEqual(await bun.file('/$bunfs/root/a.md').exists(), true);
  // Bun hands back a web ReadableStream, and the embedded routing must not be skipped on the way.
  const stream = bun.file('/$bunfs/root/a.md').stream();
  assert.strictEqual(typeof stream.getReader, 'function', 'a node Readable is not what Bun promises here');
  const { value } = await stream.getReader().read();
  assert.strictEqual(Buffer.from(value).toString(), 'hello');
});

t('write honours a typed-array VIEW window, and reports what it wrote', async () => {
  const { bun } = surface();
  written.length = 0;
  const backing = Buffer.from('XXXhelloYYY');
  const n = await bun.write('/tmp/out', new Uint8Array(backing.buffer, backing.byteOffset + 3, 5));
  assert.strictEqual(written[0][1].toString(), 'hello', 'Buffer.from(view.buffer) alone would write the whole 11 bytes');
  assert.strictEqual(n, 5, 'a constant 0 tells the caller nothing about what happened');
});

t('sleepSync actually blocks', () => {
  const { bun } = surface();
  const started = Date.now();
  bun.sleepSync(30);
  assert.ok(Date.now() - started >= 25, 'a no-op returns instantly from a call whose point is not to');
});

// ---- the render-path helpers ---------------------------------------------------------------------

t('stringWidth counts wide and combining characters the way a terminal does', () => {
  assert.strictEqual(S.stringWidth('abc'), 3);
  assert.strictEqual(S.stringWidth('日本'), 4);
  assert.strictEqual(S.stringWidth('é'), 1, 'a combining accent takes no column');
  assert.strictEqual(S.stringWidth('a\u200bb'), 2, 'a zero-width space takes no column either');
  // A base character plus a mark from one of the later combining ranges is still one column.
  assert.strictEqual(S.stringWidth('\u0e01\u0483'), 1, 'nor do the other combining ranges');
  assert.strictEqual(S.stringWidth('\ufe0f'), 0, 'nor a variation selector');
});

t('stripANSI removes escapes and leaves the text', () => {
  assert.strictEqual(S.stripANSI('[38;5;220mhi[39m'), 'hi');
});

t('wrapAnsi wraps on width, not on byte count', () => {
  assert.strictEqual(S.wrapAnsi('aaa bbb ccc', 7), 'aaa bbb\nccc');
  assert.strictEqual(S.wrapAnsi('[31maaa[39m bbb', 3), '[31maaa[39m\nbbb', 'escapes take no columns');
});

t('semver orders and matches ranges', () => {
  assert.strictEqual(S.semver.order('2.1.258', '2.1.226'), 1);
  assert.strictEqual(S.semver.order('2.1.226', '2.1.226'), 0);
  assert.strictEqual(S.semver.satisfies('2.1.258', '^2.1.0'), true);
  assert.strictEqual(S.semver.satisfies('3.0.0', '^2.1.0'), false);
  assert.strictEqual(S.semver.satisfies('2.1.258', '>=2.0.0'), true);
});

runAll();
