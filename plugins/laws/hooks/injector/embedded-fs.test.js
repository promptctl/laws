#!/usr/bin/env node
// Unit tests for embedded-fs.js — the modules Bun embedded in the executable, seen as a filesystem.
//
// The whole point of the module is that it needs neither a disk nor a 199MB binary to be checked:
// its inputs are records shaped exactly like bun-graph's output, and its one effectful dependency
// (the real fs) is a parameter. So the fixtures below are four fake modules and a stub fs.

'use strict';
const assert = require('assert');
const { createEmbeddedFs, UnservedEmbeddedCall } = require('./embedded-fs.js');

let pass = 0, fail = 0;
function t(name, fn) {
  try { fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

// Records in bun-graph's shape. Note the utf16le one: its text() decodes by the encoding the
// CONTAINER declared, which is the fact the read path must not override with a caller's guess.
const record = (name, contents, loader = 'js', encoding = 'utf8') => {
  const bytes = Buffer.from(contents, encoding === 'utf16le' ? 'utf16le' : 'utf8');
  return { name, loader, encoding, length: bytes.length, bytes: () => bytes, text: () => bytes.toString(encoding) };
};
const MODULES = [
  record('/$bunfs/root/cli', 'export const x=1;'),
  record('/$bunfs/root/SKILL.md', '# wide chars: ✓', 'text', 'utf16le'),
  record('/$bunfs/root/plain.md', '# plain', 'text'),
  record('/$bunfs/root/blob.node', 'RAW', 'napi', 'binary'),
];

const realCalls = [];
const realFs = {
  constants: { X_OK: 1 },
  readFileSync: (p, o) => { realCalls.push(['readFileSync', p]); return 'real:' + p; },
  existsSync: (p) => { realCalls.push(['existsSync', p]); return true; },
  statSync: (p) => { realCalls.push(['statSync', p]); return { size: 99 }; },
  createReadStream: (p) => { realCalls.push(['createReadStream', p]); return 'real-stream'; },
  readdirSync: (p) => { realCalls.push(['readdirSync', p]); return ['real-entry']; },
  writeFileSync: (p) => { realCalls.push(['writeFileSync', p]); },
};
const make = () => createEmbeddedFs(MODULES, { realFs, streamFrom: (bytes) => ({ stubStreamOf: bytes.length }) });

// ---- reading the embedded graph ---------------------------------------------------------------

t('an embedded path is recognised, a real one is not', () => {
  const e = make();
  assert.strictEqual(e.has('/$bunfs/root/cli'), true);
  assert.strictEqual(e.has('/$bunfs/root/nope'), false, 'a virtual path the graph does not carry is not embedded');
  assert.strictEqual(e.has('/etc/passwd'), false);
  assert.strictEqual(e.has(undefined), false);
});

t('text decodes by the encoding the CONTAINER declared, not the one the caller guessed', () => {
  const e = make();
  // The stored bytes are utf16le. Reading with 'utf8' — which is what the app asks for — must not
  // decode them as utf8, or every wide character comes back as mojibake.
  assert.strictEqual(e.read('/$bunfs/root/SKILL.md', 'utf8'), '# wide chars: ✓');
  assert.strictEqual(e.read('/$bunfs/root/SKILL.md', { encoding: 'utf8' }), '# wide chars: ✓');
});

t('a read with no encoding returns the stored bytes untouched', () => {
  const e = make();
  const bytes = e.read('/$bunfs/root/SKILL.md');
  assert.ok(Buffer.isBuffer(bytes));
  assert.strictEqual(bytes.length, '# wide chars: ✓'.length * 2, 'utf16le, two bytes per character');
});

t('a missing embedded path raises ENOENT, not undefined', () => {
  const e = make();
  assert.throws(() => e.bytes('/$bunfs/root/gone'), (err) => err.code === 'ENOENT' && /gone/.test(err.message));
});

t('stat reports the stored length', () => {
  const e = make();
  assert.strictEqual(e.stat('/$bunfs/root/plain.md').size, Buffer.from('# plain').length);
  assert.strictEqual(e.stat('/$bunfs/root/plain.md').isFile(), true);
});

t('the loader is carried through so callers never guess what a module is', () => {
  const e = make();
  assert.strictEqual(e.loaderOf('/$bunfs/root/cli'), 'js');
  assert.strictEqual(e.loaderOf('/$bunfs/root/plain.md'), 'text');
  assert.strictEqual(e.loaderOf('/$bunfs/root/blob.node'), 'napi');
  assert.strictEqual(e.loaderOf('/etc/passwd'), undefined);
});

// ---- the readers that span both the graph and the disk ------------------------------------------

t('readAny, existsAny, statAny and streamAny each answer from whichever side the path names', () => {
  const e = make();
  realCalls.length = 0;
  assert.strictEqual(e.readAny('/$bunfs/root/plain.md', 'utf8'), '# plain');
  assert.strictEqual(e.readAny('/tmp/x', 'utf8'), 'real:/tmp/x');
  assert.strictEqual(e.existsAny('/$bunfs/root/cli'), true);
  assert.strictEqual(e.statAny('/$bunfs/root/plain.md').size, 7);
  assert.deepStrictEqual(e.streamAny('/$bunfs/root/plain.md'), { stubStreamOf: 7 });
  assert.strictEqual(e.streamAny('/tmp/x'), 'real-stream');
  assert.deepStrictEqual(realCalls.map((c) => c[0]), ['readFileSync', 'createReadStream'], 'only the real paths reached the real fs');
});

// ---- the fs substitutes -------------------------------------------------------------------------

t('the fs substitute serves embedded paths and passes everything else straight through', () => {
  const e = make();
  const sub = e.substituteForFs(realFs);
  realCalls.length = 0;
  assert.strictEqual(sub.readFileSync('/$bunfs/root/plain.md', 'utf8'), '# plain');
  assert.strictEqual(sub.existsSync('/$bunfs/root/cli'), true);
  assert.strictEqual(sub.statSync('/$bunfs/root/plain.md').size, 7);
  assert.strictEqual(sub.readFileSync('/tmp/real', 'utf8'), 'real:/tmp/real');
  assert.deepStrictEqual(realCalls, [['readFileSync', '/tmp/real']]);
});

t('an fs member this host does not serve REFUSES an embedded path by name', () => {
  // The alternative is what the real fs would do — throw ENOENT for a path that plainly exists in
  // the graph — which the calling app catches and turns into a wrong answer with nothing pointing
  // back here. A named refusal says which member to add.
  const e = make();
  const sub = e.substituteForFs(realFs);
  assert.throws(() => sub.readdirSync('/$bunfs/root/cli'), (err) =>
    err instanceof UnservedEmbeddedCall && /readdirSync/.test(err.message) && /\/\$bunfs\/root\/cli/.test(err.message));
});

t('...while that same member still works normally on a real path', () => {
  const e = make();
  const sub = e.substituteForFs(realFs);
  realCalls.length = 0;
  assert.deepStrictEqual(sub.readdirSync('/tmp'), ['real-entry']);
  assert.deepStrictEqual(realCalls, [['readdirSync', '/tmp']]);
});

t('the promises substitute serves its own members and refuses the rest', async () => {
  const e = make();
  const sub = e.substituteForFsPromises({ readFile: async () => 'real', stat: async () => ({ size: 1 }), readdir: async () => ['real'] });
  assert.strictEqual(await sub.readFile('/$bunfs/root/plain.md', 'utf8'), '# plain');
  assert.strictEqual((await sub.stat('/$bunfs/root/plain.md')).size, 7);
  await sub.readdir('/$bunfs/root/plain.md').then(
    () => { throw new Error('readdir on an embedded path should have been refused'); },
    (err) => assert.ok(err instanceof UnservedEmbeddedCall));
});

t('non-function properties of the real module survive the substitution', () => {
  const e = make();
  const sub = e.substituteForFs(realFs);
  assert.deepStrictEqual(sub.constants, { X_OK: 1 });
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
