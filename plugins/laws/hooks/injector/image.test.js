#!/usr/bin/env node
// Unit tests for image.js — the header reader behind `Bun.Image.metadata`.
//
// The fixtures are built here rather than committed, so the suite needs no binary files and no
// disk. They are not invented, though: the same reader was run against real PNG, JPEG and GIF files
// produced by macOS `screencapture` and `sips` and agreed with them on every dimension, and the
// three WebP chunk forms were checked the same way. What is pinned below is the byte layout those
// files turned out to have.
//
// The point of the suite is the boundary as much as the reading. `metadata()` answers for the four
// formats the app itself calls sendable and REFUSES anything else, rather than returning an empty
// object that reads downstream like a decoded image with no pixels.

'use strict';
const assert = require('assert');
const { createImage, readHeader } = require('./image.js');

let pass = 0, fail = 0;
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

const png = (width, height) => {
  const bytes = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes, 0);
  bytes.writeUInt32BE(13, 8);
  bytes.write('IHDR', 12, 'latin1');
  bytes.writeUInt32BE(width, 16);
  bytes.writeUInt32BE(height, 20);
  return bytes;
};

// A JPEG with segments before the frame, which is what a real one always has: JFIF, then a comment,
// then the frame itself. A reader that assumes the frame comes first passes on nothing real.
const jpeg = (width, height, { marker = 0xc0, lead = [] } = {}) => {
  const parts = [Buffer.from([0xff, 0xd8])];
  for (const [segMarker, size] of lead) {
    const seg = Buffer.alloc(2 + size);
    seg[0] = 0xff; seg[1] = segMarker;
    seg.writeUInt16BE(size, 2);
    parts.push(seg);
  }
  const frame = Buffer.alloc(2 + 8);
  frame[0] = 0xff; frame[1] = marker;
  frame.writeUInt16BE(8, 2);
  frame[4] = 8;
  frame.writeUInt16BE(height, 5);
  frame.writeUInt16BE(width, 7);
  parts.push(frame, Buffer.alloc(16));
  return Buffer.concat(parts);
};

const gif = (width, height) => {
  const bytes = Buffer.alloc(16);
  bytes.write('GIF89a', 0, 'latin1');
  bytes.writeUInt16LE(width, 6);
  bytes.writeUInt16LE(height, 8);
  return bytes;
};

const webp = (chunk, payload) => {
  const bytes = Buffer.alloc(20 + payload.length);
  bytes.write('RIFF', 0, 'latin1');
  bytes.writeUInt32LE(4 + 8 + payload.length, 4);
  bytes.write('WEBP', 8, 'latin1');
  bytes.write(chunk, 12, 'latin1');
  bytes.writeUInt32LE(payload.length, 16);
  payload.copy(bytes, 20);
  return bytes;
};

t('a PNG carries its size in IHDR', () => {
  assert.deepStrictEqual(readHeader(png(3024, 1964)), { format: 'png', width: 3024, height: 1964 });
});

t('a JPEG\'s size is in the frame, which is not the first segment', () => {
  assert.deepStrictEqual(readHeader(jpeg(1920, 1080, { lead: [[0xe0, 16], [0xfe, 40]] })),
    { format: 'jpeg', width: 1920, height: 1080 });
});

t('a progressive JPEG is read too, and a Huffman table is not mistaken for a frame', () => {
  assert.deepStrictEqual(readHeader(jpeg(640, 480, { marker: 0xc2 })), { format: 'jpeg', width: 640, height: 480 });
  // 0xC4 sits inside the C0..CF range and is a table, not a frame. Taking the range whole reads its
  // length bytes as a picture's dimensions — a wrong size that looks exactly like a right one.
  assert.deepStrictEqual(readHeader(jpeg(640, 480, { lead: [[0xc4, 30]] })), { format: 'jpeg', width: 640, height: 480 });
});

t('a GIF stores its size little-endian right after the signature', () => {
  assert.deepStrictEqual(readHeader(gif(800, 600)), { format: 'gif', width: 800, height: 600 });
});

t('all three WebP chunk forms', () => {
  const lossy = Buffer.alloc(20);
  lossy.writeUInt16LE(640, 6); lossy.writeUInt16LE(480, 8);
  assert.deepStrictEqual(readHeader(webp('VP8 ', lossy)), { format: 'webp', width: 640, height: 480 });

  const lossless = Buffer.alloc(16);
  lossless[0] = 0x2f;
  lossless.writeUInt32LE(((480 - 1) << 14) | (640 - 1), 1);
  assert.deepStrictEqual(readHeader(webp('VP8L', lossless)), { format: 'webp', width: 640, height: 480 });

  const extended = Buffer.alloc(16);
  const put24 = (at, value) => { extended[at] = value & 255; extended[at + 1] = (value >> 8) & 255; extended[at + 2] = (value >> 16) & 255; };
  put24(4, 640 - 1); put24(7, 480 - 1);
  assert.deepStrictEqual(readHeader(webp('VP8X', extended)), { format: 'webp', width: 640, height: 480 });
});

t('anything else is not a header this host can read', () => {
  assert.strictEqual(readHeader(Buffer.from('not an image at all')), null);
  assert.strictEqual(readHeader(Buffer.alloc(0)), null);
  assert.strictEqual(readHeader(Buffer.from('BM')), null, 'a BMP is not one of the four the app sends');
  assert.strictEqual(readHeader(png(1, 1).subarray(0, 12)), null, 'a truncated PNG has no dimensions to read');
});

// ---- the member as the graph reaches it ------------------------------------------------------------

const build = () => {
  const absent = [];
  const files = { '/tmp/x.png': png(40, 26) };
  const Image = createImage({ realFs: { readFileSync: (p) => files[p] }, onAbsentApi: (n) => absent.push(n) });
  return { Image, absent };
};

t('Bun.Image takes bytes or a path, exactly as its one call site does', async () => {
  const { Image } = build();
  assert.deepStrictEqual(await new Image(png(40, 26)).metadata(), { format: 'png', width: 40, height: 26 });
  assert.deepStrictEqual(await new Image('/tmp/x.png').metadata(), { format: 'png', width: 40, height: 26 });
  const view = new Uint8Array(png(7, 9));
  assert.deepStrictEqual(await new Image(view).metadata(), { format: 'png', width: 7, height: 9 });
});

t('metadata refuses what it cannot read instead of answering with an empty shape', async () => {
  const { Image } = build();
  await assert.rejects(new Image(Buffer.from('nope')).metadata(), /not a PNG, JPEG, GIF or WebP/);
});

t('every pixel operation is absent and records itself by name', async () => {
  const { Image, absent } = build();
  const image = new Image(png(10, 10));
  assert.strictEqual(image.resize, undefined);
  assert.strictEqual(image.png, undefined);
  assert.strictEqual(image.jpeg, undefined);
  assert.strictEqual(image.toBuffer, undefined);
  assert.deepStrictEqual(absent, ['Image.resize', 'Image.png', 'Image.jpeg', 'Image.toBuffer']);
});

t('the clipboard statics are absent, because fromClipboard is useless without an encoder', () => {
  const { Image, absent } = build();
  assert.strictEqual(Image.hasClipboardImage, undefined);
  assert.strictEqual(Image.fromClipboard, undefined);
  assert.deepStrictEqual(absent, ['Image.hasClipboardImage', 'Image.fromClipboard']);
});

runAll();
