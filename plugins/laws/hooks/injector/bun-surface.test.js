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
function t(name, fn) {
  try { fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

const record = (name, contents, loader = 'text') => {
  const bytes = Buffer.from(contents, 'utf8');
  return { name, loader, encoding: 'utf8', length: bytes.length, bytes: () => bytes, text: () => bytes.toString('utf8') };
};
const written = [];
const realFs = {
  constants: { X_OK: 1 },
  readFileSync: () => 'real', existsSync: () => true, statSync: () => ({ size: 1 }),
  createReadStream: () => 'real-stream',
  writeFileSync: (p, data) => written.push([p, data]),
  // Normalising here is what makes the separator case real: without the guard in `which`,
  // path.join('/usr/bin', '../bin/ls') resolves to a file that exists.
  accessSync: (p) => { if (!['/usr/bin/git', '/bin/ls'].includes(require('path').normalize(p))) throw new Error('ENOENT'); },
};
function surface(overrides = {}) {
  const embedded = createEmbeddedFs([record('/$bunfs/root/a.md', 'hello')], { realFs, streamFrom: (b) => ({ stub: b.length }) });
  const absent = [];
  const bun = S.createBunSurface({
    embedded, realFs, crypto: require('crypto'), zlib: require('zlib'),
    childProcess: { spawn: (...a) => ({ spawned: a }), spawnSync: (...a) => ({ spawnedSync: a }) },
    env: { PATH: '/usr/bin:/bin' }, platform: 'darwin', entryName: '/$bunfs/root/cli',
    onAbsentApi: (n) => absent.push(n), ...overrides,
  });
  return { bun, absent };
}

// ---- the absent-API recording the boot self-check depends on ------------------------------------

t('a member the surface does not have is RECORDED, and answers undefined', () => {
  const { bun, absent } = surface();
  assert.strictEqual(bun.somethingBunAddedLastWeek(), undefined);
  assert.deepStrictEqual(absent, ['somethingBunAddedLastWeek']);
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
  assert.strictEqual(new bun.CryptoHasher('sha256').update('abc').digest('hex'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.throws(() => new bun.CryptoHasher('xxhash3'), /does not serve the algorithm xxhash3/);
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
  assert.deepStrictEqual(bun.spawnSync({ cmd: ['ls'] }).spawnedSync, ['ls', [], {}]);
});

// ---- file, and the byte-window bug ---------------------------------------------------------------

t('Bun.file reads the embedded graph and the real disk alike, streams included', async () => {
  const { bun } = surface();
  assert.strictEqual(await bun.file('/$bunfs/root/a.md').text(), 'hello');
  assert.strictEqual(bun.file('/$bunfs/root/a.md').size, 5);
  assert.strictEqual(await bun.file('/$bunfs/root/a.md').exists(), true);
  assert.deepStrictEqual(bun.file('/$bunfs/root/a.md').stream(), { stub: 5 }, 'stream must not skip the embedded routing');
  assert.strictEqual(bun.file('/tmp/real').stream(), 'real-stream');
});

t('write honours a typed-array VIEW window instead of its whole backing store', () => {
  const { bun } = surface();
  written.length = 0;
  const backing = Buffer.from('XXXhelloYYY');
  bun.write('/tmp/out', new Uint8Array(backing.buffer, backing.byteOffset + 3, 5));
  assert.strictEqual(written[0][1].toString(), 'hello', 'Buffer.from(view.buffer) alone would write the whole 11 bytes');
});

// ---- the render-path helpers ---------------------------------------------------------------------

t('stringWidth counts wide and combining characters the way a terminal does', () => {
  assert.strictEqual(S.stringWidth('abc'), 3);
  assert.strictEqual(S.stringWidth('日本'), 4);
  assert.strictEqual(S.stringWidth('é'), 1, 'a combining accent takes no column');
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
