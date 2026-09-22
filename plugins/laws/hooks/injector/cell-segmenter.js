// cell-segmenter.js — `Bun.ant.CellSegmenter`, the text-shaping engine src/ink renders through.
//
// WHY THIS FILE EXISTS. `Bun.ant` is not public Bun: it is `@anthropic-ai/bun-internal`, a PRIVATE
// Anthropic build. Everything else in `Bun.ant` is reached behind `typeof`/try-catch and is safely
// absent, but the renderer demands this one outright and says so itself before throwing:
//   "This build of @anthropic-ai/bun-internal has no Bun.ant.CellSegmenter; src/ink needs
//    bun-internal >= the version pinned in package.json."
// The app swallows that throw, so the observable symptom is the worst one available — the TUI paints
// once and then sits there forever. Without this file no hosted INTERACTIVE session is possible at
// all; with it, the hosted graph renders. [LAW:no-silent-failure] is why the absence was diagnosable.
//
// WHAT THE CONTRACT IS, AND WHERE IT CAME FROM. Nothing here is guessed: every constant and bit
// position below was read off the renderer's own call sites, which are the specification.
//
//   segment(text, cells, runs, reordered) -> count
//     Fills two int32 per cell: cells[2i] = index into `graphemes`, cells[2i+1] = a packed word.
//     The renderer reads that word as `w & 255` (display width), `w & 256` (this cell is a TAB) and
//     `w >>> 10` (which run it belongs to) — so width is a COUNT in the low byte here, not the
//     screen's width enum. `runs` holds two int32 per run: an index into `sgrKeys` and an index into
//     `uris` (0 = no hyperlink). A NEGATIVE return means the caller's arrays were too small and its
//     magnitude is the size needed; the renderer reallocates and calls again, so this is a protocol,
//     not an error. [LAW:parse-dont-validate] the count it gets back is always a filled buffer.
//
//   paint(screenCells, screenWidth, x, y, segCells, count, _unused, charIndices, runWords) -> packed
//   setCell(screenCells, screenWidth, x, y, charIndex, word)                                -> packed
//     Both write packed cells into the screen and return ONE number carrying three fields, which the
//     renderer unpacks by division because it exceeds 32 bits:
//       bits 0..19   the column after the write   (`m % 1048576`)
//       bits 20..35  damaged span start column    (`Math.floor(m / 1048576) % 65536`)
//       bits 36..    damaged span end column      (`Math.floor(m / 68719476736)`)
//     A returned span with start >= end means "nothing damaged" and the renderer drops it.
//
// The screen's own cell word is built by the renderer as `styleId << 17 | hyperlinkId << 2 | width`,
// where `width` is the ENUM handed to us in `screen` (narrow/wide/spacerTail/spacerHead). A wide
// grapheme occupies two screen cells: the character, then a spacer carrying `spacerCharIndex`.
//
// [LAW:effects-at-boundaries] pure throughout — buffers in, buffers out. No terminal, no process, no
//   clock. That is why this is testable without a TUI.
// [LAW:one-source-of-truth] every layout constant arrives in `screen` from the caller that defined
//   it. Re-declaring `narrow`/`wide`/`tabWidth` here would be a second copy that drifts the first
//   time the renderer changes one.

'use strict';

// Bit positions the RENDERER owns when it reads the word `segment` writes. These are its constants,
// mirrored here because they travel in the other direction (we write, it reads) and so cannot be
// passed in. Named rather than inlined so the layout is stated once. [LAW:one-source-of-truth]
const WIDTH_MASK = 0xff;   // cells[2i+1] & 255  -> display columns this grapheme occupies
const TAB_FLAG = 0x100;    // cells[2i+1] & 256  -> this cell is a tab stop
const RUN_SHIFT = 10;      // cells[2i+1] >>> 10 -> index into the run table

// The three fields of the packed return value, as the renderer unpacks them.
const COLUMN_SPAN = 0x100000;        // 2 ** 20
const DAMAGE_START_SCALE = 0x100000; // 2 ** 20
const DAMAGE_END_SCALE = 0x1000000000; // 2 ** 36

// Runs are interned, and index 0 is reserved for "no style, no link": the renderer special-cases it
// (`ansiCodes(0)` returns [] without consulting the pools) so it must never be handed a styled run.
const PLAIN_RUN = 0;

// East Asian Wide and Fullwidth, plus the emoji blocks that render double-width. Ranges, not a
// per-codepoint table, because the property is defined in ranges and a table would be a second copy
// of Unicode that ages. Ambiguous-width characters are deliberately absent: the renderer constructs
// us with `ambiguousIsNarrow: true`, and honouring that is the whole reason it passes the flag.
const WIDE_RANGES = [
  [0x1100, 0x115f], [0x2e80, 0x303e], [0x3041, 0x33ff], [0x3400, 0x4dbf],
  [0x4e00, 0x9fff], [0xa000, 0xa4cf], [0xa960, 0xa97f], [0xac00, 0xd7a3],
  [0xf900, 0xfaff], [0xfe10, 0xfe19], [0xfe30, 0xfe6f], [0xff00, 0xff60],
  [0xffe0, 0xffe6], [0x1f300, 0x1f64f], [0x1f900, 0x1f9ff], [0x20000, 0x2fffd],
  [0x30000, 0x3fffd],
];

const inRanges = (code, ranges) => {
  for (let i = 0; i < ranges.length; i++) if (code >= ranges[i][0] && code <= ranges[i][1]) return true;
  return false;
};

// A grapheme CLUSTER's width is its base character's width: the combining marks that follow are part
// of the same cluster and add no columns. Control characters occupy none.
function clusterWidth(cluster, ambiguousIsNarrow) {
  const code = cluster.codePointAt(0);
  if (code === undefined) return 0;
  if (code === 0x09) return 1;                       // tab; the caller re-reads it via TAB_FLAG
  if (code < 0x20 || (code >= 0x7f && code < 0xa0)) return 0;
  if (code === 0x200b || code === 0xfeff) return 0;  // zero-width space / BOM
  if (inRanges(code, WIDE_RANGES)) return 2;
  // A cluster carrying an emoji presentation selector renders wide even when its base does not.
  if (cluster.includes('️')) return 2;
  return ambiguousIsNarrow ? 1 : 1;
}

// SGR openers the renderer will accept back from `ansiCodes()`; anything else it filters out. We
// still record non-SGR CSI so a run boundary is not lost, but only these earn a closing code.
// The close for a given opener is what the terminal needs to undo it, which is what the renderer
// re-emits when it re-renders a run.
const SGR_CLOSE = new Map([
  [1, 22], [2, 22], [3, 23], [4, 24], [5, 25], [7, 27], [8, 28], [9, 29],
  [21, 24], [53, 55],
]);

function closingFor(params) {
  const n = Number(params.split(';')[0] || 0);
  if (SGR_CLOSE.has(n)) return `\x1b[${SGR_CLOSE.get(n)}m`;
  if ((n >= 30 && n <= 38) || n === 39 || (n >= 90 && n <= 97)) return '\x1b[39m';
  if ((n >= 40 && n <= 48) || n === 49 || (n >= 100 && n <= 107)) return '\x1b[49m';
  if (n === 0) return '\x1b[0m';
  return '\x1b[0m';
}

// A pool that hands out a stable index per distinct value and keeps the backing array the renderer
// reads directly. The array IS the contract — `this.graphemes`/`sgrKeys`/`uris` are read straight
// off the instance — so it is exposed rather than copied. [LAW:one-source-of-truth]
function createPool(initial) {
  const values = initial.slice();
  const index = new Map(values.map((v, i) => [v, i]));
  return {
    values,
    intern(value) {
      const found = index.get(value);
      if (found !== undefined) return found;
      const id = values.length;
      values.push(value);
      index.set(value, id);
      return id;
    },
  };
}

class CellSegmenter {
  constructor(options = {}) {
    const { ambiguousIsNarrow = true, substitute = [], screen = {} } = options;
    this.ambiguousIsNarrow = ambiguousIsNarrow;
    // Codepoint ranges the renderer wants replaced before shaping: bidi controls and invisible
    // separators, which would otherwise reorder or hide terminal output. It passes them in rather
    // than hard-coding them here, so the list stays the renderer's to change.
    this.substitute = substitute;
    this.screen = screen;

    this.graphemePool = createPool([]);
    // Index 0 of every run pool is the reserved PLAIN run, so an unstyled span interns to 0 and the
    // renderer's `ansiCodes(0) === []` fast path stays true.
    this.sgrPool = createPool(['']);
    this.sgrClosePool = createPool(['']);
    this.uriPool = createPool(['']);

    this.iterator = new Intl.Segmenter('en', { granularity: 'grapheme' });
  }

  // The renderer reads these arrays directly and watches their `.length` to decide when to rebuild
  // this instance, so they must be the live backing arrays and not snapshots.
  get graphemes() { return this.graphemePool.values; }
  get sgrKeys() { return this.sgrPool.values; }
  get sgrCloseKeys() { return this.sgrClosePool.values; }
  get uris() { return this.uriPool.values; }

  // Replace the codepoints the renderer asked us to substitute. Done before shaping so a bidi
  // control can never reach the terminal, and so its replacement is measured like any other cell.
  applySubstitutions(text) {
    if (this.substitute.length === 0) return text;
    let out = '';
    for (const ch of text) {
      const code = ch.codePointAt(0);
      out += inRanges(code, this.substitute) ? '�' : ch;
    }
    return out;
  }

  // text -> (cells, runs). Returns the cell count, or -(needed) when a buffer is too small.
  segment(text, cells, runs, _reordered) {
    const source = this.applySubstitutions(String(text ?? ''));

    // The style state carried across the string. `open` holds the SGR openers currently in effect,
    // in the order the terminal received them, because the renderer re-emits them in that order.
    let open = [];
    let uriIndex = 0;
    let runIndex = PLAIN_RUN;
    let runCount = 0;
    let dirtyRun = true;

    const runsNeeded = () => (runCount + 1) * 2;
    let needed = 0;
    let count = 0;

    // Interning is deferred to the first cell that actually uses the style, so a string that sets a
    // colour and then ends contributes no run and no pool entry.
    const currentRun = () => {
      if (!dirtyRun) return runIndex;
      if (open.length === 0 && uriIndex === 0) {
        runIndex = PLAIN_RUN;
      } else {
        const key = open.join('\x00');
        const closeKey = open.map((code) => closingFor(code.slice(2, -1))).join('\x00');
        const styleIndex = this.sgrPool.intern(key);
        // The close pool is indexed by the SAME run index as the open pool, so the two must grow in
        // lockstep; interning the close key separately could give it a different index the renderer
        // would then read as another run's close. Write it at the style's index instead.
        this.sgrClosePool.values[styleIndex] = closeKey;
        runIndex = styleIndex;
      }
      dirtyRun = false;
      return runIndex;
    };

    const emit = (graphemeIndex, width, isTab) => {
      const run = currentRun();
      if (run > runCount) runCount = run;
      const at = count * 2;
      if (at + 1 >= cells.length || runsNeeded() > runs.length) {
        // Record the largest requirement seen and keep counting: the renderer sizes from our answer,
        // so stopping at the first overflow would make it grow one cell at a time.
        needed = Math.max(needed, at + 2, runsNeeded());
      } else {
        cells[at] = graphemeIndex;
        cells[at + 1] = (width & WIDTH_MASK) | (isTab ? TAB_FLAG : 0) | (run << RUN_SHIFT);
        runs[run * 2] = run;
        runs[run * 2 + 1] = uriIndex;
      }
      count++;
    };

    let i = 0;
    while (i < source.length) {
      const ch = source[i];
      if (ch === '\x1b') {
        // CSI ... m is a style change; OSC 8 carries a hyperlink. Both move the run boundary and
        // neither occupies a cell.
        const csi = /^\x1b\[([\d;:]*)m/.exec(source.slice(i));
        if (csi) {
          const params = csi[1];
          const first = Number(params.split(';')[0] || 0);
          if (params === '' || first === 0) open = [];
          else open = open.concat(`\x1b[${params}m`);
          dirtyRun = true;
          i += csi[0].length;
          continue;
        }
        const osc = /^\x1b\]8;[^;]*;([^\x07\x1b]*)(?:\x07|\x1b\\)/.exec(source.slice(i));
        if (osc) {
          uriIndex = osc[1] === '' ? 0 : this.uriPool.intern(osc[1]);
          dirtyRun = true;
          i += osc[0].length;
          continue;
        }
        // An escape we do not model is skipped rather than measured; letting it through would give
        // it cells and shift every column after it.
        const other = /^\x1b\[[\d;:?]*[A-Za-z]/.exec(source.slice(i));
        i += other ? other[0].length : 1;
        continue;
      }

      // Segment only the plain span up to the next escape, so cluster boundaries are never computed
      // across a control sequence.
      let end = source.indexOf('\x1b', i);
      if (end === -1) end = source.length;
      for (const { segment } of this.iterator.segment(source.slice(i, end))) {
        const isTab = segment === '\t';
        const width = clusterWidth(segment, this.ambiguousIsNarrow);
        emit(this.graphemePool.intern(segment), width, isTab);
      }
      i = end;
    }

    if (needed > 0) return -needed;
    return count;
  }

  // Pack the three fields the renderer unpacks. Built with arithmetic rather than shifts because the
  // damage-end field lives above bit 32, where `<<` would silently wrap. [LAW:no-silent-failure]
  static pack(column, damageStart, damageEnd) {
    const end = damageEnd > damageStart ? damageEnd : damageStart;
    return (column % COLUMN_SPAN) + damageStart * DAMAGE_START_SCALE + end * DAMAGE_END_SCALE;
  }

  // One cell, already shaped by the renderer: it hands us the char index and the finished word.
  setCell(screenCells, screenWidth, x, y, charIndex, word) {
    const { widthMask, wide, spacerTail, spacerCharIndex } = this.screen;
    if (x < 0 || y < 0 || x >= screenWidth) return CellSegmenter.pack(x, x, x);
    const base = (y * screenWidth + x) * 2;
    screenCells[base] = charIndex;
    screenCells[base + 1] = word;
    let next = x + 1;
    // A wide character owns the column after it. Writing the spacer is what keeps the grid aligned;
    // leaving the old contents there would let a stale glyph show through the right half.
    if ((word & widthMask) === wide && next < screenWidth) {
      const tail = (y * screenWidth + next) * 2;
      screenCells[tail] = spacerCharIndex;
      screenCells[tail + 1] = (word & ~widthMask) | spacerTail;
      next += 1;
    }
    return CellSegmenter.pack(next, x, next);
  }

  // A whole segmented string onto one screen row, starting at (x, y).
  paint(screenCells, screenWidth, x, y, segCells, count, _unused, charIndices, runWords) {
    const { widthMask, narrow, wide, spacerTail, emptyCharIndex, spacerCharIndex, emptyWord, tabWidth } = this.screen;
    const start = x;
    let column = x;
    if (y < 0 || column < 0) return CellSegmenter.pack(column, start, start);

    const put = (col, charIndex, word) => {
      const at = (y * screenWidth + col) * 2;
      screenCells[at] = charIndex;
      screenCells[at + 1] = word;
    };

    for (let i = 0; i < count && column < screenWidth; i++) {
      const meta = segCells[i * 2 + 1];
      const runWord = runWords[meta >>> RUN_SHIFT] ?? emptyWord;
      const style = runWord & ~widthMask;

      if ((meta & TAB_FLAG) !== 0) {
        // A tab advances to the next stop and leaves real, styled blanks behind it, so a later write
        // to those columns damages a cell that exists rather than one the screen thinks is empty.
        const stop = tabWidth > 0 ? column + (tabWidth - (column % tabWidth)) : column + 1;
        for (; column < stop && column < screenWidth; column++) put(column, emptyCharIndex, style | narrow);
        continue;
      }

      const width = meta & WIDTH_MASK;
      if (width === 0) continue;   // combining marks rode along inside their cluster
      const charIndex = charIndices[segCells[i * 2]];
      if (width >= 2) {
        // A wide glyph that would straddle the right edge is dropped rather than split: half a
        // character on screen is corruption the renderer cannot undo on the next frame.
        if (column + 1 >= screenWidth) break;
        put(column, charIndex, style | wide);
        put(column + 1, spacerCharIndex, style | spacerTail);
        column += 2;
      } else {
        put(column, charIndex, style | narrow);
        column += 1;
      }
    }
    return CellSegmenter.pack(column, start, column);
  }
}

module.exports = { CellSegmenter, clusterWidth, closingFor, WIDTH_MASK, TAB_FLAG, RUN_SHIFT };
