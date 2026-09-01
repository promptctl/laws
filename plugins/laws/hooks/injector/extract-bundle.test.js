#!/usr/bin/env node
// Unit tests for extract-bundle.js — recovering an embedded module's source from a Bun standalone
// container. Plain Node asserts, no framework: same dependency stance as laws-excise.test.js.
//
// Fixtures are SYNTHETIC containers built to the exact record shape measured on the shipped binary
// (`\0<path>\0<contents>`), which is what makes this suite possible at all: because the slicing core
// is pure (Buffer in, result out), the contract can be asserted against 200-byte buffers instead of
// a 279MB binary, with no mocks. Each negative case asserts its SPECIFIC reason code, so a guard
// that stops working fails the test that covers it rather than sliding into a neighbour's.

'use strict';
const assert = require('assert');
const fs = require('fs');
const M = require('./extract-bundle.js');

let pass = 0, fail = 0;
function t(name, fn) {
  try { fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

const P = '/$bunfs/root/src/entrypoints/cli.js';
const OTHER = '/$bunfs/root/image-processor.js';

// A module body in the shape Bun actually emits: marker line, then the CommonJS wrapper.
// The Beta-product banner is included on purpose — it heads SIX embedded modules on the real
// binary, so every fixture carrying it is a chance for the wrong module to be selected.
const body = (tag) =>
  '// @bun @bytecode @bun-cjs\n(function(exports, require, module, __filename, __dirname) {' +
  "// Claude Code is a Beta product per Anthropic's Commercial Terms of Service.\n" +
  'var tag=' + JSON.stringify(tag) + ';})\n';

// Join records into a container. A string element is a bare path (a name-table entry, no contents);
// a [path, contents] pair is a real record.
const container = (...parts) =>
  Buffer.from(parts.map((p) => (Array.isArray(p) ? '\0' + p[0] + '\0' + p[1] : '\0' + p)).join('') + '\0/$bunfs/root/trailer', 'latin1');

t('extracts exactly the contents of the named record', () => {
  const buf = container([P, body('entry')], [OTHER, body('other')]);
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, body('entry'));
  assert.strictEqual(r.length, Buffer.byteLength(body('entry')));
  assert.strictEqual(buf.toString('latin1', r.offset, r.offset + r.length), body('entry'));
});

t('selects the right module when several carry the same banner', () => {
  // The failure this guards: anchoring on the Beta-product banner instead of the record delimiter
  // matches whichever bannered module comes first, which on the real binary is not the entrypoint.
  const buf = container([OTHER, body('other')], [P, body('entry')]);
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, body('entry'));
});

t('a repeated path before the contents yields one record, not two', () => {
  // The real entrypoint stores its path twice in a row before the contents begin.
  const buf = Buffer.from('\0' + P + '\0' + P + '\0' + body('entry') + '\0/$bunfs/root/next', 'latin1');
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, body('entry'));
});

t('a name-table entry is not mistaken for contents', () => {
  const buf = container(P, OTHER, [OTHER, body('other')]);
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.noRecord);
});

t('an absent path is a typed absence, never an empty string', () => {
  const r = M.extractModuleSource(container([OTHER, body('other')]), P);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.noRecord);
  assert.strictEqual(r.source, undefined);
});

t('two contents records for one path refuse rather than pick', () => {
  const buf = container([P, body('first')], [P, body('second')]);
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.ambiguous);
});

t('a record with no following record refuses rather than running to EOF', () => {
  // Slicing to EOF here would swallow the module graph and the code signature while looking
  // exactly like a good answer.
  const buf = Buffer.from('\0' + P + '\0' + body('entry'), 'latin1');
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.unterminated);
});

t('a NUL inside the contents refuses', () => {
  const buf = Buffer.from('\0' + P + '\0' + body('entry') + '\0junk\0/$bunfs/root/next', 'latin1');
  const r = M.extractModuleSource(buf, P);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.embeddedNul);
});

t('the default path is the entrypoint', () => {
  assert.strictEqual(M.EMBEDDED_ENTRYPOINT, P);
  const r = M.extractModuleSource(container([P, body('entry')], [OTHER, body('other')]));
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, body('entry'));
});

t('an unreadable binary is a typed absence, not a throw', () => {
  const r = M.readModuleSource('/nonexistent/claude-binary-for-tests');
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, M.ABSENT.unreadable);
});

// Live check against whatever claude is actually installed. It asserts only format-invariant
// properties — no version, offset, or digest literal, which is the whole point of the design — so
// it keeps holding across weekly releases. It reports loudly when there is no binary to read.
(function live() {
  const link = process.env.HOME + '/.local/bin/claude';
  const bin = fs.existsSync(link) ? fs.realpathSync(link) : null;
  if (!bin) return console.log('SKIP - live extraction: no installed claude at ' + link);
  t('live: the installed binary yields a complete CommonJS module', () => {
    const r = M.readModuleSource(bin);
    assert.strictEqual(r.ok, true, 'extraction failed: ' + r.reason);
    assert.ok(/^\/\/ @bun[^\n]*\n\(function\(exports, require, module, __filename, __dirname\) \{/.test(r.source),
      'source does not begin with the CJS wrapper');
    assert.ok(r.source.endsWith('})\n'), 'source does not end with the wrapper close');
    assert.strictEqual(r.source.indexOf('\0'), -1, 'source contains a NUL byte');
    assert.strictEqual(Buffer.byteLength(r.source), r.length, 'reported length is not the source length');
  });
})();

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
