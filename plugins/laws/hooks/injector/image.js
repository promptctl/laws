// image.js — `Bun.Image`, as far as it can honestly go under node.
//
// WHAT THE GRAPH ASKS FOR. m00311 runs every image the user reads or pastes through a sharp-shaped
// pipeline: `new Bun.Image(bytes).metadata()`, then `.resize(w, h, {fit, withoutEnlargement})`,
// `.png()`, `.jpeg({quality})` and `.toBuffer()` when the image is over the API's byte or pixel
// limits. m00382 additionally reaches for the two statics `Bun.Image.hasClipboardImage()` and
// `Bun.Image.fromClipboard()`.
//
// WHERE THE LINE IS, AND WHY IT IS THERE. `metadata()` is a HEADER read — the dimensions and the
// format of a PNG, JPEG, GIF or WebP are in the first few dozen bytes, and reading them is a real
// implementation with one right answer. Everything past it is a codec: resizing means decoding
// pixels, and `.png()`/`.jpeg()` mean encoding them. Bun gets those from a native library; node has
// none, and writing a JPEG decoder into an injector is not a smaller lie than shipping a stub. So
// those members are ABSENT and recorded by name, and the same goes for the clipboard pair —
// `fromClipboard` is followed by an unconditional `.png().toBuffer()` at its only call site, so a
// clipboard image that could not be encoded would be an image that could not be sent.
//
// WHAT THAT BUYS, WHICH IS MORE THAN IT SOUNDS. m00311 returns early for any image already inside
// the limits: `if (bytes <= targetRawSize && width <= maxWidth && height <= maxHeight) return ...`.
// That path needs nothing but `metadata()`, so ordinary screenshots and diagrams go through
// complete and correctly sized. An image OVER the limits reaches for `.resize`, gets a TypeError
// naming the absent member, and lands in the app's own documented fallback — which reads the
// dimensions out of the file header itself and sends the original when it fits. Both outcomes are
// ones the app already has code for; neither is silent. [LAW:no-silent-failure]
//
// [LAW:effects-at-boundaries] the filesystem arrives as a parameter, so this is testable on bytes
//   alone.

'use strict';

const { recording } = require('./recording.js');

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

// The JPEG frame markers that carry the image's size. `C4`, `C8` and `CC` sit inside the range and
// are NOT frames — they are the Huffman, extension and arithmetic-coding tables — so a scanner that
// takes the whole `C0..CF` range reads a table's length as a picture's height.
const isFrameMarker = (marker) => marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;

const jpegSize = (bytes) => {
  let at = 2;
  while (at + 9 < bytes.length) {
    // Segments are `FF <marker> <length:2>`; padding `FF`s between them are legal and skipped.
    if (bytes[at] !== 0xff) { at++; continue; }
    const marker = bytes[at + 1];
    if (marker === 0xff) { at++; continue; }
    if (isFrameMarker(marker)) return { width: bytes.readUInt16BE(at + 7), height: bytes.readUInt16BE(at + 5) };
    // A standalone marker carries no length field, so stepping over a length here would step over
    // whatever follows it instead.
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd9)) { at += 2; continue; }
    at += 2 + bytes.readUInt16BE(at + 2);
  }
  return null;
};

// WebP's three chunk kinds each store the canvas size somewhere else. Lossy hides it in the VP8
// bitstream's frame header; lossless packs two 14-bit fields across three bytes; the extended form
// stores width-1 and height-1 as 24-bit little-endian. There is no shortcut that covers all three.
const webpSize = (bytes) => {
  const chunk = bytes.toString('latin1', 12, 16);
  if (chunk === 'VP8 ') return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
  if (chunk === 'VP8L') {
    const bits = bytes.readUInt32LE(21);
    return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X') {
    const read24 = (at) => bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16);
    return { width: read24(24) + 1, height: read24(27) + 1 };
  }
  return null;
};

// The image's format and pixel dimensions, read from its container header. Returns null when the
// bytes are not one of the four formats the app itself lists as sendable.
const readHeader = (bytes) => {
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    return { format: 'png', width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    const size = jpegSize(bytes);
    return size === null ? null : { format: 'jpeg', ...size };
  }
  if (bytes.length >= 10 && (bytes.toString('latin1', 0, 6) === 'GIF87a' || bytes.toString('latin1', 0, 6) === 'GIF89a')) {
    return { format: 'gif', width: bytes.readUInt16LE(6), height: bytes.readUInt16LE(8) };
  }
  if (bytes.length >= 30 && bytes.toString('latin1', 0, 4) === 'RIFF' && bytes.toString('latin1', 8, 12) === 'WEBP') {
    const size = webpSize(bytes);
    return size === null ? null : { format: 'webp', ...size };
  }
  return null;
};

const createImage = ({ realFs, onAbsentApi }) => {
  class Image {
    // Bun takes a path or the bytes themselves, and both reach this constructor at the one call
    // site (`new Bun.Image(resolvedPath ?? buffer)`).
    constructor(source) {
      const bytes = typeof source === 'string' ? realFs.readFileSync(source)
        : ArrayBuffer.isView(source) ? Buffer.from(source.buffer, source.byteOffset, source.byteLength)
          : Buffer.from(source);
      // Read once, at construction, so `metadata()` is a pure read of an already-decided answer and
      // two calls cannot disagree. [LAW:one-source-of-truth]
      this.header = readHeader(bytes);
      this.byteLength = bytes.length;
      // `resize`, `png`, `jpeg`, `toBuffer`, `rotate`, `composite` — every pixel operation — is
      // absent, and reaching for one says so by name rather than returning undefined in silence.
      return recording('Image', this, onAbsentApi);
    }

    // Bun's is async and the graph awaits it. A refusal here is what the caller's own catch is
    // written for, and it says which of the two questions could not be answered rather than
    // handing back an empty object that reads like a decoded image with no pixels.
    // [LAW:parse-dont-validate]
    async metadata() {
      if (this.header === null) throw new Error('Image: these bytes are not a PNG, JPEG, GIF or WebP that this host can read a header from');
      return { format: this.header.format, width: this.header.width, height: this.header.height };
    }
  }

  // Wrapped so the two clipboard STATICS record themselves too. `Bun.Image.hasClipboardImage` on a
  // bare class is a silent undefined, which is the one thing this surface does not do.
  return recording('Image', Image, onAbsentApi);
};

module.exports = { createImage, readHeader };
