#!/usr/bin/env node
// Unit tests for bun-graph.js — reading Bun's embedded module graph out of a standalone executable.
// Plain Node asserts, no framework: same dependency stance as laws-excise.test.js.
//
// Fixtures are SYNTHETIC containers assembled to the exact layout measured on two shipped binaries.
// Because the parser is pure (Buffer in, result out), the whole contract is assertable against
// few-hundred-byte buffers instead of a 199MB executable, with no mocks. Every negative case asserts
// its SPECIFIC reason code, so a check that stops working fails the test that covers it rather than
// sliding into a neighbour's.
//
// The one thing these fixtures cannot prove is that the layout is Bun's — that is what the live
// check at the bottom of this file is for, and it is skipped when no claude is installed.

'use strict';
const assert = require('assert');
const fs = require('fs');
const M = require('./bun-graph.js');

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

const ENC = { binary: 0, utf8: 1, utf16le: 2 };
const LOAD = { js: 1, file: 5, napi: 10, text: 13 };

// Build a container in Bun's layout: a blob holding names and contents, then the module table, then
// the 32-byte offsets struct, then the trailer. Every pointer in the table is blob-relative.
// `over` lets a test corrupt one field without rebuilding the whole shape by hand.
function container(modules, entry = 0, over = {}) {
  const chunks = [];
  let at = 0;
  const put = (buf) => { const off = at; chunks.push(buf); at += buf.length; return off; };
  const rows = modules.map((m) => {
    const body = Buffer.from(m.contents, m.encoding === 'utf16le' ? 'utf16le' : (m.encoding === 'binary' ? 'latin1' : 'utf8'));
    return { nameOffset: put(Buffer.from(m.name, 'latin1')), nameLength: m.name.length,
      contentsOffset: put(body), contentsLength: body.length, m };
  });

  const tableOffset = at;
  const table = Buffer.alloc(modules.length * M.ROW_BYTES);
  rows.forEach((r, i) => {
    const p = i * M.ROW_BYTES;
    table.writeUInt32LE(r.nameOffset, p + 0);
    table.writeUInt32LE(r.nameLength, p + 4);
    table.writeUInt32LE(r.contentsOffset, p + 8);
    table.writeUInt32LE(r.contentsLength, p + 12);
    table[p + 48] = over.encodingByte ?? ENC[r.m.encoding ?? 'utf8'];
    table[p + 49] = over.loaderByte ?? LOAD[r.m.loader ?? 'js'];
  });
  put(table);

  const blob = Buffer.concat(chunks);
  const offsets = Buffer.alloc(32);
  offsets.writeBigUInt64LE(BigInt(over.byteCount ?? blob.length), 0);
  offsets.writeUInt32LE(over.modulesOffset ?? tableOffset, 8);
  offsets.writeUInt32LE(over.modulesLength ?? table.length, 12);
  offsets.writeUInt32LE(over.entryPointId ?? entry, 16);
  // A code signature follows the trailer on macOS, so the parser must take the LAST trailer.
  return Buffer.concat([Buffer.from('leading junk'), blob, offsets, Buffer.from('\n---- Bun! ----\n', 'latin1'), Buffer.from('code signature')]);
}

const CHUNK = { name: '/$bunfs/root/chunk-aaaa.js', contents: 'export const a=1;' };
const ENTRY = { name: '/$bunfs/root/cli', contents: 'import{a}from"/$bunfs/root/chunk-aaaa.js";' };

// ---- the happy path --------------------------------------------------------------------------

t('reads every module, and names the entry by the container\'s own index', () => {
  const r = M.readGraph(container([CHUNK, ENTRY], 1));
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.modules.length, 2);
  assert.strictEqual(r.entryIndex, 1);
  assert.strictEqual(r.entryName, ENTRY.name);
  assert.strictEqual(r.modules[1].text(), ENTRY.contents);
});

t('contents are exact — no leading or trailing byte of a neighbouring record', () => {
  const r = M.readGraph(container([CHUNK, ENTRY], 0));
  assert.strictEqual(r.modules[0].text(), CHUNK.contents);
  assert.strictEqual(r.modules[0].length, CHUNK.contents.length);
  assert.strictEqual(r.modules[0].bytes().length, CHUNK.contents.length);
});

t('decodes by the encoding the container declares, not by sniffing', () => {
  const utf16 = { name: '/$bunfs/root/SKILL.md', contents: '# hello', encoding: 'utf16le', loader: 'text' };
  const r = M.readGraph(container([utf16, ENTRY], 1));
  assert.strictEqual(r.modules[0].text(), '# hello');
  assert.strictEqual(r.modules[0].encoding, 'utf16le');
  assert.strictEqual(r.modules[0].loader, 'text');
  // ...and the bytes are the stored bytes, two per character.
  assert.strictEqual(r.modules[0].bytes().length, 14);
});

t('an entry the host could not evaluate is refused here, not left for the host to discover', () => {
  const asset = { name: '/$bunfs/root/SKILL.md', contents: '# hello', loader: 'text' };
  const r = M.readGraph(container([asset, ENTRY], 0));
  assert.strictEqual(r.reason, M.ABSENT.entryNotJs);
});

t('carries the loader through, so callers never guess what a module is', () => {
  const mods = [
    { name: '/$bunfs/root/cli', contents: 'x', loader: 'js' },
    { name: '/$bunfs/root/a.node', contents: 'bin', loader: 'napi', encoding: 'binary' },
    { name: '/$bunfs/root/a.md', contents: 'text', loader: 'text' },
    { name: '/$bunfs/root/a.zst', contents: 'zzz', loader: 'file', encoding: 'binary' },
  ];
  const r = M.readGraph(container(mods, 0));
  assert.strictEqual(r.ok, true, 'reason: ' + r.reason);
  assert.deepStrictEqual(r.modules.map((m) => m.loader), ['js', 'napi', 'text', 'file']);
});

t('takes the LAST trailer, so an appended code signature cannot shadow it', () => {
  const buf = container([ENTRY], 0);
  // A stray earlier trailer, as appears inside Bun's own machine code on the real binaries.
  const r = M.readGraph(Buffer.concat([Buffer.from('\n---- Bun! ----\n', 'latin1'), buf]));
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.entryName, ENTRY.name);
});

// ---- every named absence ---------------------------------------------------------------------

t('a file with no trailer is a typed absence, not an empty graph', () => {
  const r = M.readGraph(Buffer.from('not a bun executable'));
  assert.deepStrictEqual(r, { ok: false, reason: M.ABSENT.noTrailer });
});

t('a byte count that runs off the front of the file is refused', () => {
  const r = M.readGraph(container([ENTRY], 0, { byteCount: 0xfffffff }));
  assert.strictEqual(r.reason, M.ABSENT.blobTooLarge);
});

t('a module table outside the blob is refused', () => {
  const r = M.readGraph(container([ENTRY], 0, { modulesOffset: 0xffffff }));
  assert.strictEqual(r.reason, M.ABSENT.tableOutOfRange);
});

t('a table length that is not whole rows is refused rather than truncated', () => {
  // Two rows' worth of table, described as one and a bit — in bounds, so this is the shape check
  // firing and not the bounds check next to it.
  const r = M.readGraph(container([CHUNK, ENTRY], 0, { modulesLength: M.ROW_BYTES + 7 }));
  assert.strictEqual(r.reason, M.ABSENT.tableNotWholeRows);
});

t('an empty module table is refused', () => {
  const r = M.readGraph(container([ENTRY], 0, { modulesLength: 0 }));
  assert.strictEqual(r.reason, M.ABSENT.empty);
});

t('an entry point id past the end of the table is refused, never clamped', () => {
  const r = M.readGraph(container([CHUNK, ENTRY], 0, { entryPointId: 7 }));
  assert.strictEqual(r.reason, M.ABSENT.entryOutOfRange);
});

t('a name that is not a virtual path means the table is not where we thought', () => {
  const r = M.readGraph(container([{ name: 'not/a/bunfs/path', contents: 'x' }], 0));
  assert.strictEqual(r.reason, M.ABSENT.badName);
});

t('an unknown encoding code is refused, not decoded as a neighbouring value', () => {
  const r = M.readGraph(container([ENTRY], 0, { encodingByte: 99 }));
  assert.strictEqual(r.reason, M.ABSENT.unknownEncoding);
});

t('an unknown loader code is refused, not treated as js', () => {
  const r = M.readGraph(container([ENTRY], 0, { loaderByte: 99 }));
  assert.strictEqual(r.reason, M.ABSENT.unknownLoader);
});

t('contents pointing outside the blob are refused', () => {
  const buf = container([CHUNK, ENTRY], 0);
  // Reach into row 0 and push its contents length past the end of the blob.
  const trailerAt = buf.lastIndexOf(Buffer.from('\n---- Bun! ----\n', 'latin1'));
  const offsets = trailerAt - 32;
  const blob = offsets - buf.readUInt32LE(offsets);
  const row = blob + buf.readUInt32LE(offsets + 8);
  buf.writeUInt32LE(0xffff, row + 12);
  assert.strictEqual(M.readGraph(buf).reason, M.ABSENT.rowOutOfRange);
});

t('a byte count that does not fit in 32 bits is refused, not silently truncated', () => {
  // Reading only the low half of the u64 would make this look like a small, plausible blob and
  // produce a valid-looking graph built from the wrong bytes — the one outcome worth refusing.
  const r = M.readGraph(container([ENTRY], 0, { byteCount: 0x1_0000_0040 }));
  assert.strictEqual(r.reason, M.ABSENT.blobTooLarge);
});

t('a trailer with no room for its own struct is named for what it is, not called missing', () => {
  const r = M.readGraph(Buffer.from('\n---- Bun! ----\n', 'latin1'));
  assert.strictEqual(r.reason, M.ABSENT.trailerTooEarly);
});

t('two modules sharing one name are refused — callers key by name, so one would vanish', () => {
  const r = M.readGraph(container([CHUNK, CHUNK], 0));
  assert.strictEqual(r.reason, M.ABSENT.duplicateName);
  assert.strictEqual(r.detail, CHUNK.name);
});

t('an unreadable binary is a typed absence carrying the OS reason', () => {
  const r = M.readGraphFromFile('/no/such/claude/binary');
  assert.strictEqual(r.reason, M.ABSENT.unreadable);
  assert.match(r.detail, /ENOENT/);
});

// ---- against the real thing --------------------------------------------------------------------

// The fixtures above prove the parser reads THIS layout. Only an installed binary proves the layout
// is Bun's, so when one is present the suite reads it: the entry must be a js module whose source
// carries Bun's own marker line, and every module must land inside the file.
const installed = (() => { try { return fs.realpathSync(require('child_process').execSync('command -v claude', { encoding: 'utf8' }).trim()); } catch { return null; } })();

t(installed ? `reads the installed binary (${installed.split('/').pop()})` : 'SKIPPED: no installed claude to read', () => {
  if (!installed) return;
  const r = M.readGraphFromFile(installed);
  assert.strictEqual(r.ok, true, 'reason: ' + r.reason + ' ' + (r.detail || ''));
  const entry = r.modules[r.entryIndex];
  assert.strictEqual(entry.loader, 'js');
  assert.match(entry.text().slice(0, 40), /^\/\/ @bun/);
  const size = fs.statSync(installed).size;
  for (const m of r.modules) assert.ok(m.offset + m.length <= size, m.name + ' runs past the end of the file');
  assert.ok(r.modules.filter((m) => m.loader === 'js').length >= 1);
});

runAll();
