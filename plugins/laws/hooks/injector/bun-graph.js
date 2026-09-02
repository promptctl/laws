#!/usr/bin/env node
// bun-graph.js — read the module graph Bun embeds in a compiled standalone executable, in memory,
// from the INSTALLED binary. The host (bun-host.mjs) runs those modules under node; this file's only
// job is producing the graph, or proving it cannot.
//
// WHY THIS EXISTS AT ALL. Claude Code ships as a Bun-compiled standalone Mach-O with its JavaScript
// embedded. Keeping a copy of that JavaScript in the repo would be [LAW:one-source-of-truth] violated
// on a weekly release cadence: the copy is a second map of the installed binary, and it starts lying
// the next time the user updates. The installed binary is the single source; this file is a visibly
// derived read of it, and nothing is written to disk.
//
// WHY THE CONTAINER'S OWN TABLE AND NOT A SCAN. Bun writes a module table at the end of the file and
// points at it from a fixed struct just before the `\n---- Bun! ----\n` trailer. That table names
// every embedded module, gives its exact bounds, and names the ENTRY POINT BY INDEX — so nothing here
// has to know what the entry point is called, scan for delimiters, or disambiguate look-alike records.
// It also means the only thing this file is coupled to is BUN'S container format, which changes when
// Bun changes rather than when Claude ships. There is deliberately no version literal in this file and
// no {version: offset} table anywhere in the tree.
//
// MEASURED, on two shipped binaries a month apart, with one code path and no special cases:
//   2.1.226 (279,661,952 bytes) — 14 modules, entry id 0 = /$bunfs/root/src/entrypoints/cli.js,
//     contents at 245,797,944, length 23,985,682. Those are exactly the bounds the previous
//     delimiter-scanning extractor measured, and the slice `node --check` accepts; they are also
//     byte-identical to what `Debugger.getScriptSource` returns from a LIVE session.
//   2.1.258 (199,027,600 bytes) — 1,818 modules, entry id 5 = /$bunfs/root/cli, an ESM graph of
//     1,642 chunks plus native, compressed and text assets.
// Those numbers are dated observations, not inputs: nothing below reads them.
//
// [LAW:effects-at-boundaries] the whole parser is pure (Buffer in, result out); reading the binary is
//   a separate one-line edge. That is why the tests need no 199MB fixture and no mocks.
// [LAW:parse-dont-validate] the output is a PROVEN graph or a typed absence — never a half-parsed
//   table that callers must re-check, and never a record wearing the shape of a good one.

'use strict';

const fs = require('fs');

// Bun writes this immediately after the offsets struct, at the end of the graph it appended to the
// executable. On macOS the code signature follows it, so the LAST occurrence is the real one.
const TRAILER = Buffer.from('\n---- Bun! ----\n', 'latin1');

// The struct between the module blob and the trailer. Only the four fields below are read; the
// remaining bytes are not named here, because naming a field whose meaning has not been established
// would be a map claiming to show territory nobody has walked.
const OFFSETS_BYTES = 32;
const OFFSETS = { byteCount: 0, modulesOffset: 8, modulesLength: 12, entryPointId: 16 };

// One module's row in that table. Every offset in a row is relative to the START of the blob.
const ROW_BYTES = 52;
const ROW = { nameOffset: 0, nameLength: 4, contentsOffset: 8, contentsLength: 12, encoding: 48, loader: 49 };

// How the contents are stored, and what they are. Both come from the container itself, so nothing
// downstream has to sniff bytes to decide how to decode a module or what to do with it.
const ENCODINGS = { 0: 'binary', 1: 'utf8', 2: 'utf16le' };
const LOADERS = { 1: 'js', 5: 'file', 10: 'napi', 13: 'text' };

// Embedded module paths are rooted at Bun's virtual filesystem. Used only to check that a decoded
// name IS a name — a row whose name is arbitrary bytes means the table was not where we thought.
const VIRTUAL_ROOT = '/$bunfs/';

// Every way this can fail to produce a graph, named. Callers switch on the reason to log WHY they
// fell back to stock claude, so these are part of the contract, not debug strings.
// [LAW:no-silent-failure] an unreadable container is reported, never guessed past.
const ABSENT = {
  unreadable: 'binary-unreadable',
  noTrailer: 'no-bun-module-graph-trailer',
  blobOutOfRange: 'module-blob-outside-file',
  tableOutOfRange: 'module-table-outside-blob',
  tableNotWholeRows: 'module-table-is-not-whole-rows',
  empty: 'module-table-empty',
  rowOutOfRange: 'module-contents-outside-blob',
  badName: 'module-name-is-not-a-virtual-path',
  unknownEncoding: 'module-has-unknown-encoding',
  unknownLoader: 'module-has-unknown-loader',
  entryOutOfRange: 'entry-point-id-outside-module-table',
};

const absent = (reason, detail) => (detail === undefined ? { ok: false, reason } : { ok: false, reason, detail });

// Parse the graph out of a whole standalone executable.
// Returns { ok: true, modules, entryIndex, entryName } or { ok: false, reason }. Callers cannot
// receive a module list that has not passed every check below. [LAW:parse-dont-validate]
function readGraph(buf) {
  const trailerAt = buf.lastIndexOf(TRAILER);
  if (trailerAt === -1) return absent(ABSENT.noTrailer);

  const offsets = trailerAt - OFFSETS_BYTES;
  if (offsets < 0) return absent(ABSENT.noTrailer);
  const at = (field) => buf.readUInt32LE(offsets + field);

  // The blob is byteCount bytes ending where the offsets struct begins; every pointer below is
  // relative to its start.
  const blob = offsets - at(OFFSETS.byteCount);
  if (blob < 0) return absent(ABSENT.blobOutOfRange, `blob would start at ${blob}`);

  const tableAt = blob + at(OFFSETS.modulesOffset);
  const tableLength = at(OFFSETS.modulesLength);
  if (tableAt < blob || tableAt + tableLength > offsets) return absent(ABSENT.tableOutOfRange);
  if (tableLength % ROW_BYTES !== 0) return absent(ABSENT.tableNotWholeRows, `${tableLength} is not a multiple of ${ROW_BYTES}`);

  const count = tableLength / ROW_BYTES;
  if (count === 0) return absent(ABSENT.empty);

  const modules = [];
  for (let i = 0; i < count; i++) {
    const row = tableAt + i * ROW_BYTES;
    const field = (f) => buf.readUInt32LE(row + f);
    const nameAt = blob + field(ROW.nameOffset), nameLength = field(ROW.nameLength);
    const contentsAt = blob + field(ROW.contentsOffset), contentsLength = field(ROW.contentsLength);
    if (nameAt < blob || nameAt + nameLength > offsets) return absent(ABSENT.rowOutOfRange, `row ${i} name`);
    if (contentsAt < blob || contentsAt + contentsLength > offsets) return absent(ABSENT.rowOutOfRange, `row ${i} contents`);

    const name = buf.toString('latin1', nameAt, nameAt + nameLength);
    if (!name.startsWith(VIRTUAL_ROOT)) return absent(ABSENT.badName, `row ${i}: ${JSON.stringify(name.slice(0, 40))}`);

    // An unrecognised code means Bun's format moved under us. Decoding it as a neighbouring value
    // would produce a module that looks fine and is wrong, which is the one outcome worth refusing.
    const encoding = ENCODINGS[buf[row + ROW.encoding]];
    const loader = LOADERS[buf[row + ROW.loader]];
    if (encoding === undefined) return absent(ABSENT.unknownEncoding, `row ${i}: ${buf[row + ROW.encoding]}`);
    if (loader === undefined) return absent(ABSENT.unknownLoader, `row ${i}: ${buf[row + ROW.loader]}`);

    modules.push({
      name, loader, encoding, offset: contentsAt, length: contentsLength,
      bytes: () => buf.subarray(contentsAt, contentsAt + contentsLength),
      // 'binary' contents have no text form; latin1 is the byte-preserving decode, so a caller that
      // asks anyway gets its bytes back rather than replacement characters.
      text: () => buf.toString(encoding === 'binary' ? 'latin1' : encoding, contentsAt, contentsAt + contentsLength),
    });
  }

  const entryIndex = at(OFFSETS.entryPointId);
  if (entryIndex >= modules.length) return absent(ABSENT.entryOutOfRange, `${entryIndex} of ${modules.length}`);

  return { ok: true, modules, entryIndex, entryName: modules[entryIndex].name };
}

// The edge: the only line in this module that touches the world. [LAW:effects-at-boundaries]
function readGraphFromFile(binaryPath) {
  let buf;
  try {
    buf = fs.readFileSync(binaryPath);
  } catch (e) {
    return absent(ABSENT.unreadable, e && e.message);
  }
  return readGraph(buf);
}

module.exports = { ABSENT, ENCODINGS, LOADERS, ROW_BYTES, readGraph, readGraphFromFile };

if (require.main === module) (function main() {
  const [binaryPath] = process.argv.slice(2);
  if (!binaryPath) {
    process.stderr.write('usage: bun-graph.js <installed-claude-binary>\n');
    process.exit(2);
  }
  const g = readGraphFromFile(binaryPath);
  // A summary, never the sources: this CLI is the launcher's self-check and a human's diagnostic,
  // and 32MB on stdout serves neither. The digest is what makes two runs comparable.
  const out = g.ok
    ? {
      ok: true, modules: g.modules.length, entryIndex: g.entryIndex, entryName: g.entryName,
      byLoader: g.modules.reduce((acc, m) => ({ ...acc, [m.loader]: (acc[m.loader] || 0) + 1 }), {}),
      entrySha256: require('crypto').createHash('sha256').update(g.modules[g.entryIndex].bytes()).digest('hex'),
    }
    : g;
  process.stdout.write(JSON.stringify(out) + '\n');
  process.exit(g.ok ? 0 : 1);
})();
