// yaml.js — `Bun.YAML.parse` and `Bun.YAML.stringify`, implemented for real.
//
// WHY THIS FILE EXISTS. The shipped graph reads EVERY skill, command, agent and plugin manifest
// through `Bun.YAML.parse`, at boot, in module m00142:
//     function iL(e){return Bun.YAML.parse(e)}
//     function Sle(e){return Bun.YAML.stringify(e,null,2)+"\n"}
// With YAML absent the frontmatter parser throws on every file, the app catches it and warns, and a
// hosted session comes up with no skills and no commands at all — a session that looks fine and
// quietly cannot do half of what the user installed. There is no shortcut past this: a parser that
// handles `key: value` and gives up on the rest is exactly the plausible-and-wrong answer the
// surface refuses, because the frontmatter that would break it (nested `hooks:`, `allowed-tools`
// lists, folded descriptions) is the frontmatter that matters. [LAW:no-silent-failure]
//
// WHICH YAML. Bun's, not a spec's — and the difference is not academic. Every resolution below was
// MEASURED against `Bun.YAML.parse` rather than read off YAML 1.2, because the graph was written
// against Bun and a `user-invocable: yes` that came back as the string "yes" instead of `true`
// would change what the app does with a real skill. What Bun actually resolves is a hybrid: YAML
// 1.1's booleans (`yes`/`no`/`on`/`off`, in their all-lower, Capitalised and ALL-CAPS spellings
// only), 1.2's nulls (`null`/`Null`/`NULL`/`~`/empty — which is also the list m00142 itself hard
// codes), 1.2's numbers (`0o17` is octal, `017` is seventeen, `0b101` is a string), no implicit
// timestamps, and `null` wherever a float would come out non-finite. Anchors, aliases, merge keys,
// block scalars, flow collections and multi-document streams are all here.
//
// WHERE THIS DELIBERATELY DIVERGES, and why each one is a divergence toward the right answer.
// Bun accepts three documents that YAML calls errors, and returns a wrong value for each:
//     description: Use it when: X     -> {description: "Use it when", null: "X"}
//     title: {{TITLE}}                -> {title: {"[object Object]": null}}
//     argument-hint: [a] [b]          -> the `[b]` is dropped
// This refuses all three, and that is the point: m00142 CATCHES a parse error and retries with the
// offending values quoted (`Tnr` -> `M`), so refusing is what reaches the retry the app already
// ships for exactly these documents — and the retry's answer is the whole description, the literal
// `{{TITLE}}`, and both bracketed hints. Accepting them the way Bun does means the retry never runs
// and the app keeps the garbage. Measured over every YAML file and markdown frontmatter block on
// this machine: 1712 of 1732 documents resolve identically to Bun, and every one of the rest is one
// of those three shapes. An unknown tag is the opposite call — Bun ignores it and so does this,
// because refusing there would fail a document the shipped binary reads fine.
//
// Four smaller corners also differ, all of them block-scalar and explicit-key spellings that appear
// in none of those 1732 documents: Bun refuses `|2`, mis-reads `? key` as an `[object Object]` key,
// and counts the trailing newlines of `|+` and the breaks around a more-indented folded block one
// differently. Those follow the spec here, cross-checked against a reference implementation.
// [LAW:parse-dont-validate] the refusals are the boundary; nothing downstream re-checks.
//
// [LAW:effects-at-boundaries] pure text in, plain values out. No fs, no clock, no process — which
//   is why the suite next door needs none of them either.
// [LAW:decomposition] its own file: "turn YAML text into values and back" is one sentence with no
//   conjunction, and bun-surface.js stays the place where the Bun global is ASSEMBLED, not where
//   its members are written.

'use strict';

// ---------------------------------------------------------------------------------------------
// Scalar resolution — Bun's schema, which is the whole of a plain scalar's implicit typing
// ---------------------------------------------------------------------------------------------

const CORE_NULL = /^(?:~|null|Null|NULL|)$/;
// Bun takes YAML 1.1's boolean words but only in three spellings each — `yes`, `Yes`, `YES` and not
// `yEs`. Measured; the 1.1 spec allows every casing and Bun does not.
const CORE_TRUE = /^(?:true|True|TRUE|yes|Yes|YES|on|On|ON)$/;
const CORE_FALSE = /^(?:false|False|FALSE|no|No|NO|off|Off|OFF)$/;
const CORE_INT = /^[-+]?[0-9]+$/;
const CORE_OCT = /^0o[0-7]+$/;
const CORE_HEX = /^0x[0-9a-fA-F]+$/;
const CORE_FLOAT = /^[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?$/;
const CORE_INF = /^[-+]?\.(?:inf|Inf|INF)$/;
const CORE_NAN = /^\.(?:nan|NaN|NAN)$/;

// A number, or `undefined` when the text is not one. Non-finite results come back as null because
// that is what Bun hands over for `.inf`, `.nan` and an overflowing exponent alike — the one place
// where matching the measurement means not matching the spec.
const resolveNumber = (s) => {
  if (CORE_INT.test(s)) return Number(s);
  if (CORE_OCT.test(s)) return parseInt(s.slice(2), 8);
  if (CORE_HEX.test(s)) return parseInt(s.slice(2), 16);
  if (CORE_INF.test(s) || CORE_NAN.test(s)) return null;
  if (!CORE_FLOAT.test(s)) return undefined;
  const value = Number(s);
  return Number.isFinite(value) ? value : null;
};

// A plain scalar's type is its spelling and nothing else. Note what is NOT here: `2026-09-22` and
// `10:30` fall through to string, because there is no implicit timestamp or sexagesimal — which is
// what a frontmatter `version:` wants, and what Bun does.
const resolvePlain = (s) => {
  if (CORE_NULL.test(s)) return null;
  if (CORE_TRUE.test(s)) return true;
  if (CORE_FALSE.test(s)) return false;
  const number = resolveNumber(s);
  return number === undefined ? s : number;
};

// The tags a document may carry. A tag OVERRIDES resolution — `!!str 1` is the string "1" — so each
// one is a function from the raw scalar text to a value, and the failure arm is a throw rather than
// a fallback to the plain resolution: `!!bool banana` has no right answer.
const NUMBER_TAG = (s) => {
  const v = resolveNumber(s);
  if (v === undefined) throw err(`a numeric tag cannot hold ${JSON.stringify(s)}`);
  return v;
};
const TAG_RESOLVERS = {
  'tag:yaml.org,2002:str': (s) => s,
  'tag:yaml.org,2002:null': (s) => { if (!CORE_NULL.test(s)) throw err(`!!null cannot hold ${JSON.stringify(s)}`); return null; },
  'tag:yaml.org,2002:bool': (s) => {
    if (CORE_TRUE.test(s)) return true;
    if (CORE_FALSE.test(s)) return false;
    throw err(`!!bool cannot hold ${JSON.stringify(s)}`);
  },
  // `!!int` and `!!float` both mean "read this as a number": Bun does not check that the number is
  // of the kind the tag names, and `!!int 1.5` coming back as 1.5 under one reader and refused by
  // the other is a difference nobody wants to discover in a manifest.
  'tag:yaml.org,2002:int': NUMBER_TAG,
  'tag:yaml.org,2002:float': NUMBER_TAG,
};
// The shorthands the `!!` prefix expands to, plus the two collection tags, which say nothing a
// reader does not already know from the node's shape and so resolve to identity.
const TAG_SHORTHANDS = {
  '!!str': 'tag:yaml.org,2002:str', '!!null': 'tag:yaml.org,2002:null', '!!bool': 'tag:yaml.org,2002:bool',
  '!!int': 'tag:yaml.org,2002:int', '!!float': 'tag:yaml.org,2002:float',
  '!!map': 'tag:yaml.org,2002:map', '!!seq': 'tag:yaml.org,2002:seq',
};
const COLLECTION_TAGS = new Set(['tag:yaml.org,2002:map', 'tag:yaml.org,2002:seq']);

// ---------------------------------------------------------------------------------------------
// Refusals
// ---------------------------------------------------------------------------------------------

// One constructor for every refusal, so a caller's `e.message` always reads the same way and the
// `e instanceof Error` the graph tests is never in doubt. [LAW:one-source-of-truth]
class YAMLParseError extends SyntaxError {
  constructor(message, line) {
    super(line === undefined ? message : `${message} (line ${line + 1})`);
    this.name = 'YAMLParseError';
  }
}
const err = (message, line) => new YAMLParseError(message, line);

// ---------------------------------------------------------------------------------------------
// Character-level scanning, shared by the block and flow readers
// ---------------------------------------------------------------------------------------------

const DOC_START = /^---(?:\s|$)/;
const DOC_END = /^\.\.\.(?:\s|$)/;
const isDocMarker = (line) => DOC_START.test(line) || DOC_END.test(line);
const isBlankLine = (line) => line.trim() === '' || line.trimStart().startsWith('#');
// A `-` is a sequence indicator only when a space or the end of the line follows it; `-foo` and
// `-1` are plain scalars.
const isSeqEntry = (content) => content[0] === '-' && (content.length === 1 || content[1] === ' ');
// `? key` on its own line, and the `: value` that answers it. The two indicators behave exactly like
// `-` — an indicator, then a node starting one column right — so they are recognised the same way.
const isIndicator = (content, mark) => content[0] === mark && (content.length === 1 || content[1] === ' ');

// The column of a line's first non-space character. A tab in the indentation is refused rather than
// counted: YAML forbids it, editors disagree about its width, and a silently-accepted tab produces a
// tree whose shape depends on nothing in the file. [LAW:no-silent-failure]
const indentOf = (line, lineNo) => {
  let i = 0;
  while (i < line.length && line[i] === ' ') i++;
  if (line[i] === '\t') throw err('a tab character cannot be used for indentation', lineNo);
  return i;
};

// The index of the closing quote of the run starting at `i`, or the end of the string if the run
// never closes. Both quote styles are scanned by one function because both are scanned in the same
// places, and two of them would drift.
const endOfQuoted = (s, i) => {
  const quote = s[i];
  for (let j = i + 1; j < s.length; j++) {
    if (quote === '"' && s[j] === '\\') { j++; continue; }
    if (s[j] !== quote) continue;
    if (quote === "'" && s[j + 1] === "'") { j++; continue; }
    return j;
  }
  return s.length;
};

// Where a block-context mapping key ends, or -1 when the line is not a mapping entry at all. The
// rule is YAML's own and it is load-bearing for plain scalars: a `:` separates a key only when it is
// outside quotes, outside any flow collection, and followed by a space or the end of the line — so
// `https://example.com` is one scalar and `foo: bar` is two.
const findKeyEnd = (s) => {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    // A quote delimits only where a node may BEGIN. `test.ts "dead-lease: reclaims" flakes` is one
    // plain scalar containing a colon, not a key — and a plain scalar containing `: ` is an error
    // the caller must see, so skipping the quoted run here would swallow it.
    if ((c === '"' || c === "'") && i === 0) { i = endOfQuoted(s, i); continue; }
    if (c === '[' || c === '{') { depth++; continue; }
    if (c === ']' || c === '}') { depth--; continue; }
    if (c === '#' && i > 0 && /\s/.test(s[i - 1])) return -1;
    if (c === ':' && depth === 0 && (i + 1 === s.length || /\s/.test(s[i + 1]))) return i;
  }
  return -1;
};

// A plain scalar ends at a ` #`. Quotes do not protect one: inside a plain scalar a quote is an
// ordinary character, so `foo "bar # baz"` really does end at the hash. Callers that hold a QUOTED
// scalar never come here — they were routed to the quote reader by the character that opened them.
const stripComment = (s) => {
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '#' && (i === 0 || /\s/.test(s[i - 1]))) return s.slice(0, i);
  }
  return s;
};

const DOUBLE_ESCAPES = {
  '0': '\0', a: '\x07', b: '\b', t: '\t', '\t': '\t', n: '\n', v: '\v', f: '\f', r: '\r',
  e: '\x1b', ' ': ' ', '"': '"', '/': '/', '\\': '\\', N: '\x85', _: '\xa0', L: ' ', P: ' ',
};
const HEX_ESCAPE_WIDTH = { x: 2, u: 4, U: 8 };

// A double-quoted scalar's body, already stripped of its quotes, with line folding applied. The
// escape table above is YAML's complete set; an unknown escape is refused, because `"\q"` meaning
// `q` in one reader and failing in another is exactly the divergence that makes two parsers of one
// document disagree.
const unescapeDouble = (body, lineNo) => {
  let out = '';
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c !== '\\') { out += c; continue; }
    const next = body[++i];
    // A backslash at end of line joins the two lines with no space at all, which is the only way a
    // double-quoted scalar can carry a line that does not end in whitespace.
    if (next === '\n') { while (/[ \t]/.test(body[i + 1] || '')) i++; continue; }
    const width = HEX_ESCAPE_WIDTH[next];
    if (width) {
      const digits = body.slice(i + 1, i + 1 + width);
      if (!new RegExp(`^[0-9a-fA-F]{${width}}$`).test(digits)) throw err(`\\${next} needs ${width} hex digits, found ${JSON.stringify(digits)}`, lineNo);
      out += String.fromCodePoint(parseInt(digits, 16));
      i += width;
      continue;
    }
    if (!(next in DOUBLE_ESCAPES)) throw err(`unknown escape \\${next} in a double-quoted scalar`, lineNo);
    out += DOUBLE_ESCAPES[next];
  }
  return out;
};

// YAML's folding, shared by quoted scalars and the `>` block style: a single line break between two
// non-empty lines becomes one space, and each break beyond the first becomes a newline. Written once
// because both callers must fold identically or a document means two things. [LAW:one-source-of-truth]
const foldLines = (lines) => {
  let out = '';
  for (let i = 0; i < lines.length; i++) {
    if (i === 0) { out += lines[i]; continue; }
    if (lines[i] === '') { out += '\n'; continue; }
    out += (lines[i - 1] === '' ? '' : ' ') + lines[i];
  }
  return out;
};

// A quoted scalar's inner lines are stripped of surrounding whitespace before folding — the
// indentation that positioned them in the document is not part of their value.
const foldQuoted = (raw) => {
  const lines = raw.split('\n');
  // A quoted scalar that never wrapped has no folding to do, and its whitespace is its own: the
  // trimming below belongs to the FOLD, not to the value, and applying it to a single line eats the
  // trailing space in `'trailing space '` that the author quoted it to keep.
  if (lines.length === 1) return raw;
  return foldLines(lines.map((l, i) => (i === 0 ? l.trimEnd() : i === lines.length - 1 ? l.trimStart() : l.trim())));
};

// ---------------------------------------------------------------------------------------------
// Flow collections
// ---------------------------------------------------------------------------------------------

const FLOW_PLAIN_END = /[,[\]{}]/;

// `[a, b]` / `{a: 1}`, already gathered into one string by the block reader. Newlines inside it are
// whitespace, which is why the gather can span lines without this parser knowing it did.
class FlowReader {
  constructor(text, lineNo, anchors) {
    this.s = text;
    this.i = 0;
    this.lineNo = lineNo;
    this.anchors = anchors;
  }

  ws() {
    for (;;) {
      while (this.i < this.s.length && /\s/.test(this.s[this.i])) this.i++;
      if (this.s[this.i] !== '#') return;
      while (this.i < this.s.length && this.s[this.i] !== '\n') this.i++;
    }
  }

  // The node's properties — `&anchor` and `!tag`, in either order — read off the front before the
  // node itself, exactly as the block reader does. One shape of node, one shape of preamble.
  properties() {
    const props = { anchor: null, tag: null };
    for (;;) {
      this.ws();
      const c = this.s[this.i];
      if (c !== '&' && c !== '!') return props;
      const start = this.i++;
      while (this.i < this.s.length && !/[\s,[\]{}]/.test(this.s[this.i])) this.i++;
      const token = this.s.slice(start, this.i);
      if (c === '&') props.anchor = token.slice(1);
      else props.tag = resolveTagToken(token, this.lineNo);
    }
  }

  node() {
    const { anchor, tag } = this.properties();
    const value = this.taggedNode(tag);
    if (anchor !== null) this.anchors.set(anchor, value);
    return value;
  }

  taggedNode(tag) {
    this.ws();
    const c = this.s[this.i];
    if (c === undefined) throw err('a flow collection ended while a value was expected', this.lineNo);
    if (c === '[') return applyTag(tag, this.sequence(), null, this.lineNo);
    if (c === '{') return applyTag(tag, this.mapping(), null, this.lineNo);
    if (c === '*') {
      const start = ++this.i;
      while (this.i < this.s.length && !/[\s,[\]{}]/.test(this.s[this.i])) this.i++;
      const name = this.s.slice(start, this.i);
      if (!this.anchors.has(name)) throw err(`alias *${name} refers to an anchor that has not been defined`, this.lineNo);
      return this.anchors.get(name);
    }
    if (c === '"' || c === "'") {
      const end = endOfQuoted(this.s, this.i);
      if (end >= this.s.length) throw err('a quoted scalar was never closed', this.lineNo);
      const body = this.s.slice(this.i + 1, end);
      this.i = end + 1;
      const text = c === '"' ? unescapeDouble(foldQuoted(body), this.lineNo) : foldQuoted(body).replace(/''/g, "'");
      return applyTag(tag, text, text, this.lineNo);
    }
    return this.plain(tag);
  }

  // A flow plain scalar runs to the next structural character. `:` ends it only when a space or a
  // flow indicator follows, so `{url: http://x}` keeps its colon and `{a: 1}` does not.
  plain(tag) {
    const start = this.i;
    while (this.i < this.s.length) {
      const c = this.s[this.i];
      if (FLOW_PLAIN_END.test(c)) break;
      if (c === ':' && (this.i + 1 === this.s.length || /[\s,[\]{}]/.test(this.s[this.i + 1]))) break;
      if (c === '#' && this.i > start && /\s/.test(this.s[this.i - 1])) break;
      this.i++;
    }
    const raw = this.s.slice(start, this.i).trim().replace(/\s*\n\s*/g, ' ');
    return applyTag(tag, resolvePlain(raw), raw, this.lineNo);
  }

  sequence() {
    const out = [];
    this.i++;
    for (;;) {
      this.ws();
      if (this.s[this.i] === undefined) throw err('a flow sequence was never closed', this.lineNo);
      if (this.s[this.i] === ']') { this.i++; return out; }
      out.push(this.node());
      this.ws();
      if (this.s[this.i] === ',') { this.i++; continue; }
      if (this.s[this.i] !== ']') throw err(`expected , or ] in a flow sequence, found ${JSON.stringify(this.s[this.i] ?? '')}`, this.lineNo);
    }
  }

  mapping() {
    const out = {};
    const seen = new Set();
    this.i++;
    for (;;) {
      this.ws();
      if (this.s[this.i] === undefined) throw err('a flow mapping was never closed', this.lineNo);
      if (this.s[this.i] === '}') { this.i++; return out; }
      // `? key` is the explicit-key form; the key that follows is read exactly like any other node.
      if (this.s[this.i] === '?' && /[\s]/.test(this.s[this.i + 1] ?? ' ')) this.i++;
      const key = this.node();
      this.ws();
      // `{a, b}` is a mapping of two null-valued keys — the colon is optional in flow context.
      let value = null;
      if (this.s[this.i] === ':') { this.i++; value = this.node(); }
      setKey(out, seen, key, value, this.lineNo);
      this.ws();
      if (this.s[this.i] === ',') { this.i++; continue; }
      if (this.s[this.i] !== '}') throw err(`expected , or } in a flow mapping, found ${JSON.stringify(this.s[this.i] ?? '')}`, this.lineNo);
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Keys, tags, and the one place a mapping is written to
// ---------------------------------------------------------------------------------------------

// Every mapping assignment in this file goes through here, so the two rules that protect a caller
// from a hostile document hold everywhere or nowhere. [LAW:single-enforcer]
//   - A duplicate key is a refusal, not a last-writer-wins silent overwrite: YAML forbids it, and
//     the graph's frontmatter reader turns the throw into a warning naming the file.
//   - A collection used as a key is a refusal too. JavaScript would turn it into the string
//     "[object Object]", which is a key nobody wrote and every later lookup misses.
//   - `__proto__` is written as an own property rather than through the setter, so a skill file
//     cannot reach the object prototype of the process that reads it.
const setKey = (target, seen, key, value, lineNo) => {
  if (key !== null && typeof key === 'object') throw err('a collection used as a mapping key is not supported by this host', lineNo);
  const name = typeof key === 'string' ? key : key === null ? 'null' : String(key);
  if (seen.has(name)) throw err(`duplicate mapping key ${JSON.stringify(name)}`, lineNo);
  seen.add(name);
  Object.defineProperty(target, name, { value, writable: true, enumerable: true, configurable: true });
};

// A tag this host has no resolver for becomes YAML's NON-SPECIFIC tag: the node keeps whatever its
// own kind gives it, except that a scalar stays the text it was written as. That is measurably what
// Bun does (`!weird 1` is the string "1", `!weird [1,2]` is still a list), and refusing instead
// would make a hosted session fail on `!relative` or `!new:` documents the shipped binary reads.
const NON_SPECIFIC = 'tag:yaml.org,2002:str';
const resolveTagToken = (token) => {
  if (token in TAG_SHORTHANDS) return TAG_SHORTHANDS[token];
  const verbatim = token.startsWith('!<') && token.endsWith('>') ? token.slice(2, -1) : null;
  if (verbatim !== null && (verbatim in TAG_RESOLVERS || COLLECTION_TAGS.has(verbatim))) return verbatim;
  return NON_SPECIFIC;
};

// `raw` is the scalar's source text, or null for a collection. A tag on a collection is checked and
// then does nothing, because `!!map` and `!!seq` say only what the node's shape already said.
const applyTag = (tag, value, raw, lineNo) => {
  if (tag === null) return value;
  if (COLLECTION_TAGS.has(tag)) {
    const wanted = tag.endsWith('seq');
    if (Array.isArray(value) !== wanted) throw err(`${wanted ? '!!seq' : '!!map'} applied to a node that is not one`, lineNo);
    return value;
  }
  // A scalar tag on a collection is the non-specific tag arriving on a node whose kind already
  // decided everything — the collection passes through unchanged rather than being refused.
  if (raw === null) return value;
  return TAG_RESOLVERS[tag](raw);
};

// ---------------------------------------------------------------------------------------------
// The block reader
// ---------------------------------------------------------------------------------------------

// The indicators that cannot open a plain scalar anywhere. The rest of YAML's indicator set is
// absent because each one has a reader of its own: `-?:` are tested with the space that follows
// them, `[{` open flow, `#` opens a comment, `&*!` are node properties, `|>` are block scalars and
// `'\"` are quotes. [LAW:one-source-of-truth]
const RESERVED_PLAIN_START = '@`,]}%';

const BLOCK_SCALAR_HEADER = /^([|>])([-+]?)([0-9]*)([-+]?)\s*(?:#.*)?$/;

class BlockReader {
  constructor(text) {
    // The line array is the ONLY representation of the document this reader has, and two of the
    // constructs below rewrite a line in place — `-` and `---` are overwritten with spaces so the
    // content after them keeps its original column and can then be read as an ordinary node at that
    // column. That is YAML's own model of those indicators, and it is why a sequence of mappings
    // needs no special case anywhere below. [LAW:dataflow-not-control-flow]
    this.lines = text.replace(/^\uFEFF/, '').split(/\r\n|\r|\n/);
    // The empty element a final newline leaves behind is not a line of the document. Keeping it
    // would add one to every count of the blank lines at the end of a `|+` block scalar, which is
    // the one construct whose value depends on exactly how many there were.
    if (this.lines.length > 1 && this.lines[this.lines.length - 1] === '') this.lines.pop();
    this.i = 0;
    this.anchors = new Map();
  }

  atEnd() { return this.i >= this.lines.length; }

  // Blank lines, comment lines and `%YAML`/`%TAG` directives carry nothing a value can be built
  // from. Document markers are left in place: they are the caller's business, not this one's.
  skipIgnorable() {
    while (!this.atEnd()) {
      const line = this.lines[this.i];
      if (isBlankLine(line) || /^%\S/.test(line)) { this.i++; continue; }
      return;
    }
  }

  // Every document in the stream, in order. A stream with no `---` is one document; `Bun.YAML.parse`
  // hands back the single value in that case and the array of values otherwise, which is what the
  // frontmatter caller (one document, always) depends on.
  documents() {
    const docs = [];
    for (;;) {
      this.skipIgnorable();
      if (this.atEnd()) return docs;
      const line = this.lines[this.i];
      if (DOC_END.test(line)) { this.i++; continue; }
      if (DOC_START.test(line)) {
        this.lines[this.i] = '   ' + line.slice(3);
        this.anchors = new Map();
        this.skipIgnorable();
        if (this.atEnd()) { docs.push(null); return docs; }
        if (isDocMarker(this.lines[this.i])) { docs.push(null); continue; }
      }
      docs.push(this.node(indentOf(this.lines[this.i], this.i), -1));
    }
  }

  // `column` is where this node's text begins on the current line; `parentIndent` is the indentation
  // of the construct that owns it, which is what block scalars and multi-line plain scalars measure
  // their continuation lines against. Both are needed and neither is derivable from the other: a
  // sequence entry's text starts two columns right of the dash that owns it.
  node(column, parentIndent) {
    this.skipIgnorable();
    if (this.atEnd() || isDocMarker(this.lines[this.i])) return null;
    const line = this.lines[this.i];
    const ind = indentOf(line, this.i);
    if (ind < column) return null;

    const { anchor, tag, rest, restColumn } = this.properties(line, ind);
    if (rest === '') {
      // The properties stood alone on their line, so the node they describe is whatever the lines
      // below hold — at THEIR indentation, which is the only thing that positions it.
      this.i++;
      return this.anchored(anchor, applyTag(tag, this.nodeBelow(parentIndent), null, this.i));
    }
    return this.anchored(anchor, this.taggedNode(tag, restColumn, parentIndent, rest));
  }

  anchored(anchor, value) {
    if (anchor !== null) this.anchors.set(anchor, value);
    return value;
  }

  // `&anchor`, `!tag`, or both, in either order, off the front of a line.
  properties(line, ind) {
    let at = ind;
    let anchor = null, tag = null;
    for (;;) {
      const c = line[at];
      if (c !== '&' && c !== '!') break;
      let end = at;
      while (end < line.length && !/\s/.test(line[end])) end++;
      const token = line.slice(at, end);
      if (c === '&') anchor = token.slice(1);
      else tag = resolveTagToken(token);
      at = end;
      while (line[at] === ' ') at++;
    }
    const rest = line.slice(at);
    return { anchor, tag, rest: rest.trimStart().startsWith('#') ? '' : rest, restColumn: at };
  }

  taggedNode(tag, column, parentIndent, content) {
    if (isSeqEntry(content)) return applyTag(tag, this.sequence(column), null, this.i);
    if (isIndicator(content, '?')) return applyTag(tag, this.mapping(column), null, this.i);
    const keyEnd = findKeyEnd(content);
    if (keyEnd >= 0) return applyTag(tag, this.mapping(column), null, this.i);
    if (content[0] === '*') {
      const name = content.slice(1).trim();
      this.i++;
      if (!this.anchors.has(name)) throw err(`alias *${name} refers to an anchor that has not been defined`, this.i - 1);
      return this.anchors.get(name);
    }
    if (content[0] === '|' || content[0] === '>') return applyTag(tag, this.blockScalar(content, parentIndent), null, this.i);
    if (content[0] === '[' || content[0] === '{') return applyTag(tag, this.flow(column), null, this.i);
    return this.scalar(tag, column, parentIndent);
  }

  // A block sequence: every entry is the node that starts where its `-` stood, once the `-` has
  // been overwritten with a space. `- name: x` and a `name:` on the next line at the same column are
  // then literally the same construct, which is what YAML says they are.
  sequence(ind) {
    const out = [];
    for (;;) {
      this.skipIgnorable();
      if (this.atEnd() || isDocMarker(this.lines[this.i])) return out;
      const line = this.lines[this.i];
      if (indentOf(line, this.i) !== ind) return out;
      const content = line.slice(ind);
      if (!isSeqEntry(content)) return out;
      out.push(this.afterIndicator(ind));
    }
  }

  mapping(ind) {
    const out = {};
    const seen = new Set();
    const merges = [];
    for (;;) {
      this.skipIgnorable();
      if (this.atEnd() || isDocMarker(this.lines[this.i])) break;
      const line = this.lines[this.i];
      const lineIndent = indentOf(line, this.i);
      if (lineIndent < ind) break;
      if (lineIndent > ind) throw err('a mapping key is indented further than the one above it', this.i);
      const content = line.slice(ind);
      if (isSeqEntry(content)) break;
      if (isIndicator(content, '?')) { this.explicitEntry(ind, out, seen); continue; }
      const keyEnd = findKeyEnd(content);
      if (keyEnd < 0) throw err(`expected a mapping key, found ${JSON.stringify(content.slice(0, 40))}`, this.i);
      const key = this.key(content.slice(0, keyEnd));
      const valueColumn = ind + keyEnd + 1;
      // The key and its colon are overwritten the same way a `-` is, so the value keeps its column
      // and is read by the same `node` every other value goes through.
      this.lines[this.i] = ' '.repeat(valueColumn) + line.slice(valueColumn);
      const value = this.value(ind, valueColumn);
      if (key === '<<') merges.push(...(Array.isArray(value) ? value : [value]));
      else setKey(out, seen, key, value, this.i);
    }
    // A merge key contributes only the keys the mapping did not state for itself, and an earlier
    // source wins over a later one — both are YAML's rules, and both are why this happens at the end
    // rather than as each `<<` is read.
    const merged = {};
    for (const source of merges) {
      if (source === null || typeof source !== 'object' || Array.isArray(source)) throw err('a merge key (<<) must name a mapping', this.i);
      for (const [k, v] of Object.entries(source)) if (!(k in merged)) Object.defineProperty(merged, k, { value: v, writable: true, enumerable: true, configurable: true });
    }
    for (const k of Object.keys(out)) Object.defineProperty(merged, k, { value: out[k], writable: true, enumerable: true, configurable: true });
    return merges.length === 0 ? out : merged;
  }

  // `? key` / `: value` — the explicit form, where the key is a node in its own right rather than
  // something that has to fit before a colon. Both halves are read by overwriting their indicator
  // with a space and then reading an ordinary node, which is the same move `-` makes.
  explicitEntry(ind, out, seen) {
    const key = this.afterIndicator(ind);
    this.skipIgnorable();
    // A `?` with no answering `:` is a key whose value is empty, which YAML allows.
    const line = this.atEnd() ? null : this.lines[this.i];
    const hasValue = line !== null && !isDocMarker(line) && indentOf(line, this.i) === ind && isIndicator(line.slice(ind), ':');
    setKey(out, seen, key, hasValue ? this.afterIndicator(ind) : null, this.i);
  }

  // The node that begins where an indicator stands, once the indicator is a space. A construct whose
  // node occupies no line at all leaves the cursor where it was, so the indicator's own line is
  // stepped over here rather than by every caller.
  afterIndicator(ind) {
    const line = this.lines[this.i];
    this.lines[this.i] = line.slice(0, ind) + ' ' + line.slice(ind + 1);
    const at = this.i;
    const value = this.node(ind + 1, ind);
    if (this.i === at) this.i++;
    return value;
  }

  key(raw) {
    const text = raw.trim();
    // `? key` is the explicit-key indicator; on one line it adds nothing the plain form does not say.
    const body = text.startsWith('? ') ? text.slice(2).trim() : text;
    if (body[0] === '"' || body[0] === "'") {
      const end = endOfQuoted(body, 0);
      const inner = body.slice(1, end);
      return body[0] === '"' ? unescapeDouble(inner, this.i) : inner.replace(/''/g, "'");
    }
    if (body[0] === '[' || body[0] === '{') throw err('a flow collection used as a mapping key is not supported by this host', this.i);
    const value = resolvePlain(stripComment(body).trim());
    return typeof value === 'string' ? value : value === null ? 'null' : String(value);
  }

  // The value of a mapping entry: on the rest of the key's line if there is anything there, on the
  // more-indented lines below it if there is not, and — the one case that is neither — a block
  // sequence sitting at the key's own indentation.
  value(keyIndent, valueColumn) {
    const line = this.lines[this.i];
    const inline = line.slice(valueColumn);
    if (inline.trim() !== '' && !inline.trimStart().startsWith('#')) {
      // `description: Use it when: X` is not a nested mapping — in block context a mapping cannot
      // begin on its own key's line, and YAML calls it an error. Refusing matters more here than
      // almost anywhere else in this file: the graph's frontmatter reader CATCHES this throw and
      // retries with the value quoted (m00142's `Tnr`), so a parse that accepted it would hand the
      // app a tree of nested mappings built out of one sentence's punctuation and skip the retry
      // that was written for exactly this. [LAW:no-silent-failure]
      if (findKeyEnd(inline.trimStart()) >= 0) throw err('a mapping value cannot begin on the same line as its key', this.i);
      return this.node(valueColumn, keyIndent);
    }
    this.i++;
    return this.nodeBelow(keyIndent);
  }

  // The node owned by a construct at `parentIndent` but written on the lines below it. Two shapes
  // reach here — a mapping value whose key's line ended, and a node whose `&anchor`/`!tag` stood
  // alone — and both admit the one asymmetry in YAML's indentation: a block sequence may sit at its
  // owner's own column, while everything else must sit past it.
  nodeBelow(parentIndent) {
    this.skipIgnorable();
    if (this.atEnd() || isDocMarker(this.lines[this.i])) return null;
    const ind = indentOf(this.lines[this.i], this.i);
    if (ind > parentIndent) return this.node(ind, parentIndent);
    if (ind === parentIndent && isSeqEntry(this.lines[this.i].slice(ind))) return this.sequence(parentIndent);
    return null;
  }

  // `|` and `>`, with their optional explicit indentation and chomping indicators. The content's
  // indentation is the first non-empty line's unless the header stated one, and every line is
  // measured against it — which is what lets a folded description hold an indented code block.
  blockScalar(content, parentIndent) {
    const header = BLOCK_SCALAR_HEADER.exec(content.trimEnd());
    if (!header) throw err(`a block scalar header this host cannot read: ${JSON.stringify(content.trim())}`, this.i);
    const style = header[1];
    const chomp = header[2] || header[4] || '';
    const explicit = header[3] === '' ? null : Number(header[3]);
    if (explicit === 0) throw err('a block scalar indentation indicator must be at least 1', this.i);
    this.i++;

    const floor = Math.max(parentIndent + 1, 1);
    let contentIndent = explicit === null ? null : floor - 1 + explicit;
    const raw = [];
    while (!this.atEnd()) {
      const line = this.lines[this.i];
      if (line.trim() === '') { raw.push(''); this.i++; continue; }
      const ind = indentOf(line, this.i);
      if (contentIndent === null) {
        if (ind < floor) break;
        contentIndent = ind;
      }
      if (ind < contentIndent) break;
      raw.push(line.slice(contentIndent));
      this.i++;
    }
    while (raw.length > 0 && raw[raw.length - 1] === '') raw.pop();
    if (contentIndent === null) return chomp === '+' ? '\n' : '';

    const body = style === '|' ? raw.join('\n') : foldBlock(raw);
    if (chomp === '-') return body;
    if (chomp === '+') return body + '\n'.repeat(1 + this.trailingBlankCount());
    return body === '' ? '' : body + '\n';
  }

  // How many blank lines followed the scalar's last content line. Only `+` (keep) asks, and only it
  // needs them — clip keeps one newline and strip keeps none regardless.
  trailingBlankCount() {
    let n = 0;
    for (let j = this.i - 1; j >= 0 && this.lines[j].trim() === ''; j--) n++;
    return n;
  }

  // A flow collection, gathered across as many lines as its brackets take and then read by
  // FlowReader. Gathering first is what lets that reader be a plain string scanner with no idea
  // that documents have lines at all. [LAW:decomposition]
  flow(column) {
    const startLine = this.i;
    let depth = 0;
    let text = '';
    for (;;) {
      if (this.atEnd()) throw err('a flow collection was never closed', startLine);
      const line = this.lines[this.i];
      const from = this.i === startLine ? column : 0;
      let j = from;
      for (; j < line.length; j++) {
        const c = line[j];
        if (c === '"' || c === "'") { j = endOfQuoted(line, j); continue; }
        if (c === '#' && j > from && /\s/.test(line[j - 1]) && depth > 0) { j = line.length; break; }
        if (c === '[' || c === '{') depth++;
        else if (c === ']' || c === '}') { depth--; if (depth === 0) { j++; break; } }
      }
      text += (this.i === startLine ? '' : '\n') + line.slice(from, j);
      this.i++;
      if (depth === 0) {
        // Only a comment may follow a closed flow collection. `argument-hint: [a] [b]` is not a
        // sequence with something after it — it is an error, and one the graph recovers from by
        // quoting the whole value. Consuming the `[a]` and dropping the rest would hand the app a
        // list nobody wrote. [LAW:no-silent-failure]
        const tail = line.slice(j);
        if (tail.trim() !== '' && !tail.trimStart().startsWith('#')) {
          throw err(`a flow collection is followed by ${JSON.stringify(tail.trim().slice(0, 20))} on the same line`, this.i - 1);
        }
        break;
      }
    }
    const reader = new FlowReader(text, startLine, this.anchors);
    const value = reader.node();
    reader.ws();
    if (reader.i < reader.s.length) throw err(`trailing content after a flow collection: ${JSON.stringify(reader.s.slice(reader.i, reader.i + 20))}`, startLine);
    return value;
  }

  // A quoted or plain scalar, either of which may run past the end of its line.
  scalar(tag, column, parentIndent) {
    const line = this.lines[this.i];
    const first = line[column];
    if (first === '"' || first === "'") return applyTag(tag, this.quoted(column), null, this.i);

    // `@` and a backtick are reserved by YAML and can never open a plain scalar; `,`, `]` and `}`
    // close a flow collection that was never opened. Each one is a document the graph's frontmatter
    // reader retries with the value quoted, which it can only do if this refuses first.
    if (RESERVED_PLAIN_START.includes(first)) throw err(`a plain scalar cannot begin with ${JSON.stringify(first)} — YAML reserves it`, this.i);

    const startLine = this.i;
    const parts = [stripComment(line.slice(column)).trimEnd()];
    this.i++;
    // A plain scalar continues onto every following line indented past its owner. Blank lines are
    // taken provisionally and dropped again if nothing more indented follows them, which is how a
    // paragraph break inside a value is told apart from the gap before the next key.
    while (!this.atEnd()) {
      const next = this.lines[this.i];
      if (next.trim() === '') { parts.push(''); this.i++; continue; }
      if (isDocMarker(next)) break;
      if (indentOf(next, this.i) <= parentIndent) break;
      parts.push(stripComment(next.trim()).trimEnd());
      this.i++;
    }
    while (parts.length > 0 && parts[parts.length - 1] === '') { parts.pop(); this.i--; }
    const raw = foldLines(parts);
    return applyTag(tag, parts.length > 1 ? raw : resolvePlain(raw), raw, startLine);
  }

  quoted(column) {
    const quote = this.lines[this.i][column];
    const startLine = this.i;
    let body = this.lines[this.i].slice(column);
    for (;;) {
      const end = endOfQuoted(body, 0);
      if (end < body.length) {
        // Whatever follows the closing quote on that line can only be a comment; a value cannot.
        const consumed = body.slice(0, end + 1);
        const lineOffset = consumed.split('\n').length - 1;
        const lastLine = this.lines[startLine + lineOffset];
        const tail = lastLine.slice(lineOffset === 0 ? column + consumed.length : consumed.length - consumed.lastIndexOf('\n') - 1);
        if (tail.trim() !== '' && !tail.trimStart().startsWith('#')) {
          throw err(`a quoted scalar is followed by ${JSON.stringify(tail.trim().slice(0, 20))} on the same line`, startLine);
        }
        this.i = startLine + lineOffset + 1;
        const inner = consumed.slice(1, -1);
        const folded = foldQuoted(inner);
        return quote === '"' ? unescapeDouble(folded, startLine) : folded.replace(/''/g, "'");
      }
      this.i++;
      if (this.atEnd()) throw err('a quoted scalar was never closed', startLine);
      body += '\n' + this.lines[this.i];
    }
  }
}

// `>` folding, with YAML's more-indented exception: a line indented past the block's own content
// indentation keeps its line breaks, because that is how a folded scalar carries a code sample.
const foldBlock = (lines) => {
  let out = '';
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (i === 0) { out += line; continue; }
    const moreIndented = /^\s/.test(line) || /^\s/.test(lines[i - 1]);
    // An empty line contributes its own break, and a more-indented NEIGHBOUR contributes another on
    // top of it — the two are independent, which is why an empty line beside an indented block ends
    // up separated from it by two newlines rather than one. Measured against a reference parser;
    // reading it off the spec's production rules alone gets this wrong in exactly that spot.
    if (line === '') out += /^\s/.test(lines[i - 1]) ? '\n\n' : '\n';
    else if (moreIndented) out += '\n' + line;
    else if (lines[i - 1] === '') out += line;
    else out += ' ' + line;
  }
  return out;
};

// ---------------------------------------------------------------------------------------------
// parse
// ---------------------------------------------------------------------------------------------

const parse = (text) => {
  if (typeof text !== 'string') throw err(`YAML.parse expects a string, got ${text === null ? 'null' : typeof text}`);
  const docs = new BlockReader(text).documents();
  if (docs.length === 0) return null;
  return docs.length === 1 ? docs[0] : docs;
};

// ---------------------------------------------------------------------------------------------
// stringify
// ---------------------------------------------------------------------------------------------

// A plain scalar is safe only when nothing about its spelling would make a reader see something
// else: an implicit type, an indicator at the front, a comment or a key inside it, or whitespace at
// either end that a reader would trim. Everything else gets quoted. The check is deliberately
// conservative — a needless quote costs a byte, a missing one costs the value.
const PLAIN_UNSAFE_START = /^[-?:,[\]{}#&*!|>'"%@`]/;
const needsQuoting = (s) => s === '' || PLAIN_UNSAFE_START.test(s) || /: |\s#|^\s|\s$|[\n\r\t\0-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(s)
  || resolvePlain(s) !== s || /^[-?]$/.test(s);

const quoteDouble = (s) => '"' + s.replace(/[\\"\u0000-\u001f\u007f]/g, (c) => {
  if (c === '\\' || c === '"') return '\\' + c;
  const named = { '\n': '\\n', '\t': '\\t', '\r': '\\r', '\b': '\\b', '\f': '\\f', '\v': '\\v', '\0': '\\0', '\x1b': '\\e' }[c];
  return named ?? '\\x' + c.charCodeAt(0).toString(16).padStart(2, '0');
}) + '"';

// Single quotes when the string has nothing a single-quoted scalar must escape; double otherwise.
// Single-quoted output is the more readable of the two and cannot misinterpret a backslash.
const renderScalar = (s) => {
  if (!needsQuoting(s)) return s;
  if (!/[\n\r\t\0-\x1f\x7f]/.test(s)) return "'" + s.replace(/'/g, "''") + "'";
  return quoteDouble(s);
};

const renderKey = (key) => renderScalar(typeof key === 'string' ? key : String(key));

const renderNumber = (n) => {
  if (Number.isNaN(n)) return '.nan';
  if (n === Infinity) return '.inf';
  if (n === -Infinity) return '-.inf';
  return String(n);
};

const isCollection = (v) => v !== null && typeof v === 'object' && !(v instanceof Date);

// The one-line form of a value, or null when the value needs lines of its own. Returning null rather
// than a flag is what keeps the caller's two cases — `key: value` and `key:` plus a block — from
// needing a third. [LAW:dataflow-not-control-flow]
const inlineOf = (value) => {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean') return String(value);
  if (typeof value === 'number') return renderNumber(value);
  if (typeof value === 'bigint') return String(value);
  if (typeof value === 'string') return renderScalar(value);
  if (value instanceof Date) return renderScalar(value.toISOString());
  if (Array.isArray(value)) return value.length === 0 ? '[]' : null;
  return Object.keys(value).length === 0 ? '{}' : null;
};

const stringify = (value, replacer, space) => {
  const width = typeof space === 'number' ? Math.min(10, Math.max(1, Math.floor(space)))
    : typeof space === 'string' ? Math.max(1, space.length) : 2;
  const allowed = Array.isArray(replacer) ? new Set(replacer.map(String)) : null;
  const transform = typeof replacer === 'function' ? replacer : null;
  // The cycle check is the stack of containers currently being written, not every container seen:
  // the same object appearing twice in a tree is a DAG and writes fine, only a container inside
  // itself cannot terminate.
  const open = new Set();

  // JSON's own pre-processing, in JSON's own order: toJSON first, then the replacer sees what it
  // produced. A caller that hands this a value JSON can serialize gets a document that round-trips.
  const prepare = (holder, key, raw) => {
    const viaToJSON = raw !== null && typeof raw === 'object' && typeof raw.toJSON === 'function' ? raw.toJSON(key) : raw;
    return transform ? transform.call(holder, key, viaToJSON) : viaToJSON;
  };

  const lines = (value_, indent) => {
    if (open.has(value_)) throw new TypeError('YAML.stringify cannot serialize a value that contains itself');
    open.add(value_);
    const pad = ' '.repeat(indent);
    const out = [];
    if (Array.isArray(value_)) {
      for (let i = 0; i < value_.length; i++) {
        const item = prepare(value_, String(i), value_[i]);
        // An array hole and an undefined element are both `null` in JSON and both are here.
        const inline = inlineOf(item);
        if (inline !== null) { out.push(pad + '- ' + inline); continue; }
        const nested = lines(item, indent + 2);
        out.push(pad + '- ' + nested[0].slice(indent + 2), ...nested.slice(1));
      }
    } else {
      for (const key of Object.keys(value_)) {
        if (allowed && !allowed.has(key)) continue;
        const item = prepare(value_, key, value_[key]);
        // An undefined property is dropped, exactly as JSON.stringify drops it. A YAML `null` here
        // would be a value the caller never wrote.
        if (item === undefined || typeof item === 'function' || typeof item === 'symbol') continue;
        const inline = inlineOf(item);
        if (inline !== null) { out.push(pad + renderKey(key) + ': ' + inline); continue; }
        out.push(pad + renderKey(key) + ':', ...lines(item, indent + width));
      }
    }
    open.delete(value_);
    return out;
  };

  const root = prepare({ '': value }, '', value);
  const inline = inlineOf(root);
  if (inline !== null) return inline + '\n';
  return lines(root, 0).join('\n') + '\n';
};

module.exports = { parse, stringify, YAMLParseError, resolvePlain, foldBlock, findKeyEnd, needsQuoting };
