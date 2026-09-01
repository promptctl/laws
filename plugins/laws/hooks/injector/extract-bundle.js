#!/usr/bin/env node
// extract-bundle.js — recover the Claude Code JS bundle as a source string by reading the
// INSTALLED binary, in memory. The injector host (promptctl-injector-xy0.2) runs that string
// under the Bun->node shim; this module's only job is producing it, or proving it cannot.
//
// WHY THIS EXISTS AT ALL. Claude Code ships as a Bun-compiled standalone Mach-O with the JS
// embedded as contiguous plaintext. The alternative — keeping a copy of cli.js in the repo — is
// [LAW:one-source-of-truth] violated on a weekly release cadence: the copy is a second map of the
// installed binary and it starts lying the next time the user updates. The installed binary is the
// single source; this file is a visibly-derived read of it, and nothing is written to disk.
//
// WHY ANCHORS AND NOT OFFSETS. A {version: offset} table would be that same drifting second map,
// maintained by hand, wrong exactly when someone upgrades and right only until then. Every
// boundary below is instead found by scanning for a property of BUN'S CONTAINER FORMAT, which
// changes on Bun format changes rather than on Claude's weekly bundle. There is deliberately no
// version literal anywhere in this file.
//
// THE FORMAT, AS MEASURED (2.1.226, 279,661,952 bytes — see the record in SEAMS.md). Embedded
// modules are stored as NUL-delimited records, `\0<path>\0<contents>`, where <path> is a
// /$bunfs/ virtual path. Enumerating them on the shipped binary yields the entrypoint at
// contents offset 245,797,944, length 23,985,682 — the slice `node --check` accepts and which
// every off-by-one mutation of (start-1, end-3, end-2000, end+31) makes it reject. Confirmed
// against ground truth: `Debugger.getScriptSource` from a LIVE session returns a byte-identical
// string (same length, same sha256), so what this returns is exactly what the process runs.
//
// ONE CORRECTION TO THE ORIGINAL SURVEY, worth stating because it would have silently produced the
// WRONG module: the plan was to disambiguate the entrypoint by the Beta-product banner that follows
// its CJS wrapper. That banner is not entrypoint-only — it heads six embedded modules
// (cli.js plus image-processor, audio-capture, url-handler, computer-use-swift, computer-use-input).
// The record's own `\0<path>\0` delimiter is the honest discriminator and is what is used here.
//
// [LAW:effects-at-boundaries] the byte-slicing core is pure (Buffer in, result out); reading the
//   binary is a separate one-line edge. That is why the tests need no 279MB fixture and no mocks.
// [LAW:parse-dont-validate] the output is a PROVEN source string or a typed absence — never a
//   maybe-empty string that callers must re-check, and never a truncated slice wearing the shape
//   of a good one.

'use strict';

const fs = require('fs');

// The entrypoint's virtual path inside the Bun container. A default, not a hardcoding: every
// function below takes the path as a value, so the same code reads any embedded module.
// [LAW:composability] variability crosses the boundary as data instead of forking the code.
const EMBEDDED_ENTRYPOINT = '/$bunfs/root/src/entrypoints/cli.js';

// A record's path is introduced by a NUL and the /$bunfs/ prefix; the next such introduction is
// where the current record's contents stop.
const PATH_PREFIX = '\0/$bunfs/';

// Proof that a matched path is followed by MODULE CONTENTS rather than being one more entry in the
// container's name table — Bun heads every embedded CJS module with its `// @bun ...` marker line
// and then the CommonJS wrapper. The name table has no such bytes after a path, so this single
// test separates the two populations without knowing anything about either one's layout.
const CJS_CONTENTS = /^\/\/ @bun[^\n]*\n\(function\(exports, require, module, __filename, __dirname\) \{/;

// How far past a candidate path we look to apply CJS_CONTENTS. Only the marker line and the wrapper
// need to fit; decoding more of a 24MB module to test its first 100 bytes would be waste.
const PROBE_BYTES = 256;

// Every way this can fail to produce a source, named. Callers switch on the reason to log WHY they
// fell back to stock claude, so these are part of the contract, not debug strings.
// [LAW:no-silent-failure] an unresolved anchor is reported, never guessed past.
const ABSENT = {
  noRecord: 'no-contents-record-for-path',
  ambiguous: 'multiple-contents-records-for-path',
  unterminated: 'contents-record-has-no-following-record',
  embeddedNul: 'contents-contain-a-nul-byte',
  unreadable: 'binary-unreadable',
};

// Offsets of every `\0<modulePath>\0` in the container that is followed by module contents.
// Pure, and the whole of the format knowledge lives here.
function contentsRecordsOf(buf, modulePath) {
  const needle = Buffer.from('\0' + modulePath + '\0', 'latin1');
  const found = [];
  // Unconditional scan to exhaustion — the set of operations never depends on the input, only the
  // values do. [LAW:dataflow-not-control-flow]
  for (let at = buf.indexOf(needle, 0); at !== -1; at = buf.indexOf(needle, at + 1)) {
    const start = at + needle.length;
    // latin1 keeps this a byte-for-byte view: the marker and wrapper are ASCII, and decoding a
    // probe as utf8 could split a multi-byte sequence at the window edge.
    if (CJS_CONTENTS.test(buf.toString('latin1', start, start + PROBE_BYTES))) found.push(start);
  }
  return found;
}

// Extract one embedded module's source from the container bytes.
// Returns { ok: true, source, offset, length } or { ok: false, reason } — the caller cannot
// receive a string that has not passed every check below. [LAW:parse-dont-validate]
function extractModuleSource(buf, modulePath = EMBEDDED_ENTRYPOINT) {
  const starts = contentsRecordsOf(buf, modulePath);
  // Two records for one path means the format assumption no longer holds, and picking either one
  // would be a guess. Refusing is the whole point of a typed absence.
  if (starts.length !== 1) {
    return { ok: false, reason: starts.length === 0 ? ABSENT.noRecord : ABSENT.ambiguous };
  }
  const offset = starts[0];

  // The record ends where the next one is introduced. Deliberately NOT falling back to end-of-file:
  // a module with no successor is a container shape this code has not been shown to read, and a
  // slice running to EOF would swallow the module graph and the code signature while looking
  // exactly like a good answer.
  const end = buf.indexOf(Buffer.from(PATH_PREFIX, 'latin1'), offset);
  if (end === -1) return { ok: false, reason: ABSENT.unterminated };

  // JavaScript source contains no NUL bytes, so a NUL inside the slice means the boundaries are
  // wrong and the slice has run into an adjacent record — the failure that must never be returned
  // as a source string.
  if (buf.indexOf(0, offset) !== end) return { ok: false, reason: ABSENT.embeddedNul };

  return { ok: true, source: buf.toString('utf8', offset, end), offset, length: end - offset };
}

// The edge: the only line in this module that touches the world. [LAW:effects-at-boundaries]
function readModuleSource(binaryPath, modulePath = EMBEDDED_ENTRYPOINT) {
  let buf;
  try {
    buf = fs.readFileSync(binaryPath);
  } catch (e) {
    return { ok: false, reason: ABSENT.unreadable, detail: e && e.message };
  }
  return extractModuleSource(buf, modulePath);
}

module.exports = { EMBEDDED_ENTRYPOINT, ABSENT, extractModuleSource, readModuleSource };

if (require.main === module) (function main() {
  const [binaryPath, modulePath] = process.argv.slice(2);
  if (!binaryPath) {
    process.stderr.write('usage: extract-bundle.js <installed-claude-binary> [embedded-module-path]\n');
    process.exit(2);
  }
  const r = readModuleSource(binaryPath, modulePath || EMBEDDED_ENTRYPOINT);
  // A summary, never the source: this CLI is the launcher's self-check and a human's diagnostic,
  // and 24MB on stdout serves neither. The digest is what makes two runs comparable.
  const out = r.ok
    ? { ok: true, offset: r.offset, length: r.length, sha256: require('crypto').createHash('sha256').update(r.source).digest('hex') }
    : r;
  process.stdout.write(JSON.stringify(out) + '\n');
  process.exit(r.ok ? 0 : 1);
})();
