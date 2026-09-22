// toml.js — `Bun.TOML.parse`, the reader the graph's MCP configuration goes through.
//
// WHY THIS FILE EXISTS. `claude import` reads another agent's configuration with it and with
// nothing else — m00861's `function Wt(n){return Bun.TOML.parse(n)}`, pointed at `~/.codex/config.toml`
// and at `commands/*.toml`, handing the result straight to the schema that describes an MCP server
// (command, args, env, url, http_headers, bearer_token_env_var).
//
// WHEN THAT PATH IS REACHABLE, said plainly because it is not today. In 2.1.278 the subcommand
// answers "`claude import` is not yet available in this build": it is behind the server gate
// `P("tengu_import", false)`, the same mechanism that holds `tengu_propose_goal` shut. So an absent
// `Bun.TOML` costs a 2.1.278 session nothing right now. It is written anyway for the reason the
// rest of this surface is: the graph names the member, the gate is a flag rather than a deletion,
// and a shim whose coverage tracks which flags happen to be on this week is a shim that breaks on
// somebody else's deploy. Earlier builds (2.1.259 through 2.1.270) reached it, and the next one may.
//
// ONE MEMBER, BECAUSE BUN HAS ONE. `Bun.TOML` carries `parse` and nothing else; there is no
// `stringify` to be absent, and adding one would be inventing an API the graph cannot call.
//
// WHAT IT ACCEPTS. TOML v1.0.0: bare/quoted/dotted keys, tables, arrays of tables, inline tables,
// arrays (including across lines), all four string forms, integers in four bases, floats, and the
// date-time forms. The rule this file is written to is narrower than "follow the spec", and it is
// the rule that matters for a shim: NEVER REFUSE A DOCUMENT BUN ACCEPTS. Unlike the YAML reader
// next door, the caller here has no retry to fall into — a refusal is a lost MCP server, full stop.
// So the places where Bun is loose are loose here too (a leading zero, a table header repeated), and
// the places where Bun is simply broken are fixed rather than reproduced. Measured against
// `Bun.TOML.parse` over every .toml file on this machine — 389 of 400 identical — the whole of the
// difference is Bun defects:
//   - a multi-line string keeps the newline that follows its opening `"""` (11 of the 400 files);
//   - a line-ending backslash does not swallow the indentation after it (1 file);
//   - `inf` comes back as the STRING "inf", `-inf` as `0`, `nan` as "nan";
//   - `\t` in a basic string comes back as a form feed, and `\f` refuses the whole document;
//   - every date-time form is refused, as is an array written across lines with a trailing comma.
// Each of those is a value no caller can want, and accepting more than Bun cannot cost a document
// that used to parse. [LAW:no-silent-failure] is the reason none of them is reproduced for fidelity:
// a form feed where a tab was written is wrong quietly, forever.
//
// [LAW:effects-at-boundaries] text in, values out; no fs, no clock.
// [LAW:decomposition] one file, one sentence: turn TOML text into a plain object.

'use strict';

class TOMLParseError extends SyntaxError {
  constructor(message, line) {
    super(`${message} (line ${line})`);
    this.name = 'TOMLParseError';
  }
}

const BARE_KEY = /^[A-Za-z0-9_-]+/;
// A date-time is tried before a number because it starts like one; without that, `1979-05-27` reads
// as the integer 1979 and the rest of the line becomes a syntax error pointing at the wrong place.
const OFFSET_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(\.\d+)?([Zz]|[+-]\d{2}:\d{2})/;
const LOCAL_DATE_TIME = /^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?/;
const LOCAL_DATE = /^\d{4}-\d{2}-\d{2}/;
const LOCAL_TIME = /^\d{2}:\d{2}:\d{2}(\.\d+)?/;
const SPECIAL_FLOAT = /^([+-]?)(inf|nan)/;
const RADIX_INT = /^0(x[0-9a-fA-F_]+|o[0-7_]+|b[01_]+)/;
const DECIMAL = /^[+-]?[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9][0-9_]*)?/;
const RADIX = { x: 16, o: 8, b: 2 };

const ESCAPES = { b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\', e: '\x1b' };

class Reader {
  constructor(text) {
    // Only the line endings are normalised. Everything else is read where it stands, because a
    // multi-line literal string is defined to carry whatever bytes lie between its delimiters.
    this.s = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
    this.i = 0;
  }

  get line() { return this.s.slice(0, this.i).split('\n').length; }
  fail(message) { throw new TOMLParseError(message, this.line); }
  at(re) { return re.exec(this.s.slice(this.i)); }
  take(match) { this.i += match[0].length; return match[0]; }

  // Horizontal whitespace and a trailing comment; a newline is structure and is never skipped here.
  inlineSpace() {
    while (' \t'.includes(this.s[this.i])) this.i++;
    if (this.s[this.i] !== '#') return;
    while (this.i < this.s.length && this.s[this.i] !== '\n') this.i++;
  }

  // Whitespace of every kind, including newlines and the comments between them. Used inside arrays,
  // which are the one construct TOML lets breathe across lines.
  anySpace() {
    for (;;) {
      while (' \t\n'.includes(this.s[this.i])) this.i++;
      if (this.s[this.i] !== '#') return;
      while (this.i < this.s.length && this.s[this.i] !== '\n') this.i++;
    }
  }

  endOfLine() {
    this.inlineSpace();
    if (this.i >= this.s.length) return;
    if (this.s[this.i] !== '\n') this.fail(`expected the end of the line, found ${JSON.stringify(this.s[this.i])}`);
    this.i++;
  }

  // ---- keys ------------------------------------------------------------------------------------

  key() {
    const c = this.s[this.i];
    if (c === '"') return this.basicString();
    if (c === "'") return this.literalString();
    const bare = this.at(BARE_KEY);
    if (!bare) this.fail(`expected a key, found ${JSON.stringify(this.s[this.i] ?? '<end of file>')}`);
    return this.take(bare);
  }

  keyPath() {
    const path = [this.key()];
    for (;;) {
      this.inlineSpace();
      if (this.s[this.i] !== '.') return path;
      this.i++;
      this.inlineSpace();
      path.push(this.key());
    }
  }

  // ---- strings ---------------------------------------------------------------------------------

  basicString() {
    if (this.s.startsWith('"""', this.i)) return this.multiline('"""', true);
    this.i++;
    let out = '';
    for (;;) {
      const c = this.s[this.i];
      if (c === undefined || c === '\n') this.fail('a basic string was never closed');
      this.i++;
      if (c === '"') return out;
      out += c === '\\' ? this.escape() : c;
    }
  }

  literalString() {
    if (this.s.startsWith("'''", this.i)) return this.multiline("'''", false);
    this.i++;
    const end = this.s.indexOf("'", this.i);
    const newline = this.s.indexOf('\n', this.i);
    if (end < 0 || (newline >= 0 && newline < end)) this.fail('a literal string was never closed');
    const out = this.s.slice(this.i, end);
    this.i = end + 1;
    return out;
  }

  // Both triple-quoted forms, which differ only in whether backslashes mean anything. A newline
  // immediately after the opening delimiter is not part of the value — that is what lets the first
  // line of a block start at the left margin.
  multiline(delimiter, escaped) {
    this.i += 3;
    if (this.s[this.i] === '\n') this.i++;
    let out = '';
    for (;;) {
      if (this.i >= this.s.length) this.fail(`a multi-line string was never closed`);
      if (this.s.startsWith(delimiter, this.i)) {
        // Up to two extra delimiter characters belong to the VALUE: `"""a""""` ends in a quote.
        let extra = 0;
        while (extra < 2 && this.s[this.i + 3 + extra] === delimiter[0]) extra++;
        out += delimiter[0].repeat(extra);
        this.i += 3 + extra;
        return out;
      }
      const c = this.s[this.i++];
      if (!escaped || c !== '\\') { out += c; continue; }
      // A backslash at the end of a line swallows the break and the indentation after it, which is
      // how a long value is written across several lines without gaining whitespace.
      if (/^[ \t]*\n/.test(this.s.slice(this.i))) {
        while (' \t\n'.includes(this.s[this.i])) this.i++;
        continue;
      }
      out += this.escape();
    }
  }

  escape() {
    const c = this.s[this.i++];
    if (c in ESCAPES) return ESCAPES[c];
    const width = c === 'u' ? 4 : c === 'U' ? 8 : 0;
    if (width === 0) this.fail(`unknown escape \\${c}`);
    const digits = this.s.slice(this.i, this.i + width);
    if (!new RegExp(`^[0-9a-fA-F]{${width}}$`).test(digits)) this.fail(`\\${c} needs ${width} hex digits`);
    this.i += width;
    return String.fromCodePoint(parseInt(digits, 16));
  }

  // ---- values ----------------------------------------------------------------------------------

  value() {
    const c = this.s[this.i];
    if (c === '"') return this.basicString();
    if (c === "'") return this.literalString();
    if (c === '[') return this.array();
    if (c === '{') return this.inlineTable();
    if (this.s.startsWith('true', this.i)) { this.i += 4; return true; }
    if (this.s.startsWith('false', this.i)) { this.i += 5; return false; }
    return this.numberOrDate();
  }

  numberOrDate() {
    const offset = this.at(OFFSET_DATE_TIME);
    // An offset date-time names an instant, so it becomes the one JavaScript type that means one:
    // a Date. The three LOCAL forms name a wall-clock reading with no zone, and there is no JS type
    // for that — handing back a Date would attach this machine's zone to a value that has none, so
    // they stay the text they were written as. [LAW:no-silent-failure]
    if (offset) return new Date(this.take(offset).replace(' ', 'T'));
    for (const form of [LOCAL_DATE_TIME, LOCAL_DATE, LOCAL_TIME]) {
      const match = this.at(form);
      if (match) return this.take(match);
    }
    const special = this.at(SPECIAL_FLOAT);
    if (special) {
      this.take(special);
      return special[2] === 'nan' ? NaN : special[1] === '-' ? -Infinity : Infinity;
    }
    const radix = this.at(RADIX_INT);
    if (radix) return parseInt(this.take(radix).slice(2).replace(/_/g, ''), RADIX[radix[1][0]]);
    const decimal = this.at(DECIMAL);
    if (!decimal) this.fail(`expected a value, found ${JSON.stringify(this.s.slice(this.i, this.i + 12))}`);
    return Number(this.take(decimal).replace(/_/g, ''));
  }

  array() {
    this.i++;
    const out = [];
    for (;;) {
      this.anySpace();
      if (this.s[this.i] === undefined) this.fail('an array was never closed');
      if (this.s[this.i] === ']') { this.i++; return out; }
      out.push(this.value());
      this.anySpace();
      if (this.s[this.i] === ',') { this.i++; continue; }
      if (this.s[this.i] !== ']') this.fail(`expected , or ] in an array, found ${JSON.stringify(this.s[this.i] ?? '')}`);
    }
  }

  inlineTable() {
    this.i++;
    const table = {};
    const seen = new Set();
    for (;;) {
      this.anySpace();
      if (this.s[this.i] === undefined) this.fail('an inline table was never closed');
      if (this.s[this.i] === '}') { this.i++; return table; }
      const path = this.keyPath();
      this.inlineSpace();
      if (this.s[this.i] !== '=') this.fail(`expected = after a key, found ${JSON.stringify(this.s[this.i] ?? '')}`);
      this.i++;
      this.anySpace();
      assign(table, seen, path, this.value(), (m) => this.fail(m));
      this.anySpace();
      if (this.s[this.i] === ',') { this.i++; continue; }
      if (this.s[this.i] !== '}') this.fail(`expected , or } in an inline table, found ${JSON.stringify(this.s[this.i] ?? '')}`);
    }
  }
}

// Every write into a table goes through here. `__proto__` is written as an own property rather than
// through the setter — a config file must not be able to reach the prototype of the process reading
// it — and a key that already holds a value is refused, which is the one duplicate Bun refuses too.
// [LAW:single-enforcer]
const define = (target, name, value) => Object.defineProperty(target, name, { value, writable: true, enumerable: true, configurable: true });

// Walk a dotted path, creating the tables it names, and write the leaf. `seen` holds the full dotted
// paths this document has already written a value to, which is what makes `a.b = 1` twice an error
// while `a.b = 1` and `a.c = 2` are not.
const assign = (root, seen, path, value, fail) => {
  let table = root;
  for (let i = 0; i < path.length - 1; i++) {
    const name = path[i];
    const next = Object.hasOwn(table, name) ? table[name] : undefined;
    // A path passing through an array of tables continues in its LAST element, which is what makes
    // `[[a]]` followed by `a.b.c = 1` land inside the entry just opened.
    const step = Array.isArray(next) ? next[next.length - 1] : next;
    if (step === undefined) { define(table, name, {}); table = table[name]; continue; }
    if (step === null || typeof step !== 'object') fail(`${path.slice(0, i + 1).join('.')} is a value, so it cannot also be a table`);
    table = step;
  }
  const leaf = path[path.length - 1];
  const dotted = path.join('.');
  if (seen.has(dotted)) fail(`cannot redefine key '${dotted}'`);
  seen.add(dotted);
  define(table, leaf, value);
};

// A table header, `[a.b]` or `[[a.b]]`. The returned object is where the key/value lines that follow
// are written. A header repeated is allowed to reopen its table rather than refused, because Bun
// allows it and a refusal here has nowhere to go but a missing MCP server.
const openTable = (root, path, isArray, fail) => {
  let table = root;
  for (let i = 0; i < path.length - 1; i++) {
    const name = path[i];
    const next = Object.hasOwn(table, name) ? table[name] : undefined;
    const step = Array.isArray(next) ? next[next.length - 1] : next;
    if (step === undefined) { define(table, name, {}); table = table[name]; continue; }
    if (step === null || typeof step !== 'object') fail(`${path.slice(0, i + 1).join('.')} is a value, so it cannot also be a table`);
    table = step;
  }
  const leaf = path[path.length - 1];
  const existing = Object.hasOwn(table, leaf) ? table[leaf] : undefined;
  if (!isArray) {
    if (existing === undefined) define(table, leaf, {});
    else if (existing === null || typeof existing !== 'object' || Array.isArray(existing)) fail(`${path.join('.')} is already a value, so it cannot also be a table`);
    return table[leaf];
  }
  if (existing === undefined) define(table, leaf, []);
  else if (!Array.isArray(existing)) fail(`${path.join('.')} is already a table, so it cannot also be an array of tables`);
  const entry = {};
  table[leaf].push(entry);
  return entry;
};

const parse = (text) => {
  if (typeof text !== 'string') throw new TOMLParseError(`TOML.parse expects a string, got ${text === null ? 'null' : typeof text}`, 1);
  const reader = new Reader(text);
  const root = {};
  // Scoped per table, so `[a] x=1` and `[b] x=1` are two different keys and `[a] x=1 x=2` is not.
  let current = root;
  let seen = new Set();
  for (;;) {
    reader.anySpace();
    if (reader.i >= reader.s.length) return root;
    if (reader.s[reader.i] === '[') {
      const isArray = reader.s.startsWith('[[', reader.i);
      reader.i += isArray ? 2 : 1;
      reader.inlineSpace();
      const path = reader.keyPath();
      reader.inlineSpace();
      const close = isArray ? ']]' : ']';
      if (!reader.s.startsWith(close, reader.i)) reader.fail(`expected ${close} to close a table header`);
      reader.i += close.length;
      current = openTable(root, path, isArray, (m) => reader.fail(m));
      seen = new Set();
      reader.endOfLine();
      continue;
    }
    const path = reader.keyPath();
    reader.inlineSpace();
    if (reader.s[reader.i] !== '=') reader.fail(`expected = after a key, found ${JSON.stringify(reader.s[reader.i] ?? '<end of file>')}`);
    reader.i++;
    reader.inlineSpace();
    assign(current, seen, path, reader.value(), (m) => reader.fail(m));
    reader.endOfLine();
  }
};

module.exports = { parse, TOMLParseError };
