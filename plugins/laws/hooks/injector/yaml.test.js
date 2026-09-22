#!/usr/bin/env node
// Unit tests for yaml.js — `Bun.YAML.parse` and `Bun.YAML.stringify`.
//
// Two things are being pinned here, and the second is the one that is easy to lose.
//
// The first is that the constructs real frontmatter uses come back right: nested mappings, sequences
// written at either indentation, block scalars with all three chomping modes, flow collections,
// anchors and merge keys.
//
// The second is that the documents YAML calls ERRORS are refused. The graph's frontmatter reader
// (m00142) is built on that: it calls `Bun.YAML.parse`, catches, re-quotes the offending values and
// calls again. A parser that accepted `description: Use it when: X` would turn one sentence into a
// tree of nested mappings and skip the retry written for exactly that document — so every refusal
// below is a behaviour the app depends on, not a limitation being documented.
//
// Every expectation below was MEASURED — against `Bun.YAML.parse` itself where the question is what
// the graph will see, and against a reference YAML implementation where the question is what the
// document means. The two disagree in places (Bun takes 1.1's boolean words and 1.2's nulls), and
// where they do, the measurement is what is written down here rather than anything read off a spec.

'use strict';
const assert = require('assert');
const Y = require('./yaml.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
const run = () => {
  for (const { name, fn } of cases) {
    try { fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
};

const eq = (text, expected, why) => assert.deepStrictEqual(Y.parse(text), expected, why);
const refuses = (text, fragment) => {
  let threw = null;
  try { Y.parse(text); } catch (e) { threw = e; }
  assert.ok(threw, `expected a refusal, got a value for ${JSON.stringify(text)}`);
  assert.ok(threw instanceof Error, 'a refusal must be an Error — the graph reads e.message');
  assert.ok(threw.message.includes(fragment), `refusal said ${JSON.stringify(threw.message)}, wanted ${JSON.stringify(fragment)}`);
};

// ---- the shapes real frontmatter is made of -----------------------------------------------------

t('a flat mapping resolves its scalars', () => {
  eq('name: foo\ncount: 3\nenabled: true\nratio: 1.5\nnothing:\n', { name: 'foo', count: 3, enabled: true, ratio: 1.5, nothing: null });
});

t('null has exactly the four spellings m00142 itself lists', () => {
  eq('a:\nb: null\nc: Null\nd: NULL\ne: ~\n', { a: null, b: null, c: null, d: null, e: null });
  eq('f: nil\ng: none\n', { f: 'nil', g: 'none' }, 'anything else is a string');
});

t('the 1.1 boolean words resolve, in the three spellings Bun accepts and no others', () => {
  // Measured against Bun: a `user-invocable: yes` really does reach the app as `true`, and reading
  // the 1.2 spec instead of the implementation would have made it the string "yes".
  eq('a: yes\nb: Off\nc: ON\nd: No\n', { a: true, b: false, c: true, d: false });
  eq('a: yEs\nb: oFF\nc: y\nd: n\n', { a: 'yEs', b: 'oFF', c: 'y', d: 'n' }, 'mixed case and single letters stay strings');
});

t('there is no implicit timestamp or sexagesimal', () => {
  eq('c: 2026-09-22\nd: 10:30\ne: 12:34:56\n', { c: '2026-09-22', d: '10:30', e: '12:34:56' });
});

t('numbers follow 1.2, and a non-finite one comes back null the way Bun hands it over', () => {
  eq('a: 0o17\nb: 017\nc: 0x1f\nd: 0b101\ne: 1.5e3\n', { a: 15, b: 17, c: 31, d: '0b101', e: 1500 });
  eq('a: .inf\nb: .nan\nc: 1e400\n', { a: null, b: null, c: null });
});

t('a version-like scalar is a string, not a float', () => {
  eq('version: 2.1.278\nminor: 2.1\n', { version: '2.1.278', minor: 2.1 });
});

t('a sequence is read at the key\'s indentation or past it', () => {
  eq('tools:\n- Read\n- Write\n', { tools: ['Read', 'Write'] });
  eq('tools:\n  - Read\n  - Write\n', { tools: ['Read', 'Write'] });
});

t('a sequence of mappings keeps the keys that share the dash\'s line', () => {
  eq('hooks:\n  - matcher: Bash\n    hooks:\n      - type: command\n        command: foo.sh\n',
    { hooks: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'foo.sh' }] }] });
});

t('an empty sequence entry is null', () => {
  eq('- \n- a\n', [null, 'a']);
});

t('a plain scalar keeps a colon that no space follows', () => {
  eq('url: http://example.com/a\n', { url: 'http://example.com/a' });
});

t('a hash only opens a comment when whitespace precedes it', () => {
  eq('a: foo#bar\nb: 1 # gone\n# gone too\nc: 2\n', { a: 'foo#bar', b: 1, c: 2 });
});

t('a plain scalar folds across the lines indented past its key', () => {
  eq('description: hello\n  world again\nname: foo\n', { description: 'hello world again', name: 'foo' });
});

t('a blank line inside a plain scalar is a break, and the one before the next key is not', () => {
  eq('d: one\n\n  two\ne: 1\n', { d: 'one\ntwo', e: 1 });
  eq('a: 1\n\nb: 2\n', { a: 1, b: 2 });
});

// ---- quoted scalars ----------------------------------------------------------------------------

t('quoted scalars carry what plain ones cannot', () => {
  eq(`a: "x: y"\nb: 'it''s'\nc: "tab\\there"\nd: "\\u00e9"\n`, { a: 'x: y', b: "it's", c: 'tab\there', d: '\u00e9' });
});

t('a quoted scalar keeps the whitespace it was quoted to keep', () => {
  eq("a: 'trailing '\nb: ' leading'\n", { a: 'trailing ', b: ' leading' });
});

t('a quoted scalar folds when it wraps', () => {
  eq('a: "one\n  two"\n', { a: 'one two' });
});

t('an unknown escape is refused rather than silently dropped', () => {
  refuses('a: "\\q"\n', 'unknown escape');
});

// ---- block scalars -------------------------------------------------------------------------------

t('literal, folded, and the three chomping modes', () => {
  eq('d: |\n  one\n  two\n', { d: 'one\ntwo\n' }, 'clip keeps one trailing newline');
  eq('d: |-\n  one\n', { d: 'one' }, 'strip keeps none');
  eq('d: |+\n  one\n\n\n', { d: 'one\n\n\n' }, 'keep keeps every one of them');
  eq('d: >-\n  one\n  two\n', { d: 'one two' }, 'folded joins with a space');
});

t('a folded scalar keeps the breaks around a more-indented block', () => {
  // The line break beside an indented line is literal, and it is literal IN ADDITION to the one an
  // empty line contributes — which is why "code line" ends up with a blank line on each side.
  eq('d: >\n  para one\n  still one\n\n    code line\n\n  para two\n',
    { d: 'para one still one\n\n  code line\n\npara two\n' });
});

t('an explicit indentation indicator measures from the parent, not the first line', () => {
  eq('d: |2\n    x\n   y\n', { d: '  x\n y\n' });
});

t('a hash inside a block scalar is content', () => {
  eq('d: |\n  # not a comment\n  still\n', { d: '# not a comment\nstill\n' });
});

// ---- flow collections ----------------------------------------------------------------------------

t('flow collections nest and span lines', () => {
  eq('a: [1, 2, three]\nb: {x: 1, y: [2, {z: w}]}\n', { a: [1, 2, 'three'], b: { x: 1, y: [2, { z: 'w' }] } });
  eq('a: [1,\n  2,\n  3]\n', { a: [1, 2, 3] });
  eq('a: []\nb: {}\n', { a: [], b: {} });
});

t('a flow mapping key with no colon has a null value', () => {
  eq('a: {x, y: 1}\n', { a: { x: null, y: 1 } });
});

// ---- anchors, aliases, merge keys, tags ----------------------------------------------------------

t('an anchor on its own line names the node written below it', () => {
  eq('base: &b\n  a: 1\nuse: *b\n', { base: { a: 1 }, use: { a: 1 } });
  eq('base: &b\n- 1\n- 2\nuse: *b\n', { base: [1, 2], use: [1, 2] });
});

t('a merge key fills in only what the mapping did not say itself', () => {
  eq('base: &b\n  a: 1\n  b: 1\nchild:\n  <<: *b\n  b: 2\n', { base: { a: 1, b: 1 }, child: { a: 1, b: 2 } });
});

t('an alias with no anchor is refused', () => {
  refuses('a: *nope\n', 'has not been defined');
});

t('a known tag overrides resolution, and an unknown one falls back to the node\'s own kind', () => {
  eq('a: !!str 1\nb: !!int 0x10\nc: !!bool yes\n', { a: '1', b: 16, c: true });
  refuses('a: !!bool banana\n', '!!bool cannot hold');
  // Bun ignores a tag it cannot resolve, and so does this: refusing would fail `!relative` and
  // `!new:` documents that the shipped binary reads without complaint.
  eq('a: !relative 1\nb: !new:Thing [1, 2]\n', { a: '1', b: [1, 2] });
});

// ---- explicit keys and multiple documents --------------------------------------------------------

t('the explicit key form is read as the mapping it is', () => {
  eq('m:\n  ? explicit\n  : value\n', { m: { explicit: 'value' } });
});

t('one document comes back as its value and several as an array', () => {
  eq('a: 1\n', { a: 1 });
  eq('---\na: 1\n---\nb: 2\n', [{ a: 1 }, { b: 2 }]);
  eq('', null);
  eq('# only a comment\n', null);
});

// ---- the refusals the graph's retry is built on ---------------------------------------------------

t('a mapping cannot begin on its own key\'s line', () => {
  // The single most common malformed frontmatter there is: a description with a colon in it.
  refuses('description: Use this agent when: X\n', 'cannot begin on the same line');
});

t('a plain scalar containing a quoted colon is still a plain scalar containing a colon', () => {
  refuses('description: the test "dead-lease: reclaims" flakes\n', 'cannot begin on the same line');
});

t('a plain scalar cannot open with a reserved indicator', () => {
  refuses('description: @promptctl/rich-js fails\n', 'YAML reserves it');
  refuses('description: `lit next` routes by claims\n', 'YAML reserves it');
});

t('a flow collection cannot be followed by more content on its line', () => {
  // `argument-hint: [command-name] [description]` — accepting it would hand the app a one-element
  // list and drop the rest of the line on the floor.
  refuses('argument-hint: [command-name] [description]\n', 'is followed by');
});

t('a duplicate key is refused rather than silently overwritten', () => {
  refuses('a: 1\na: 2\n', 'duplicate mapping key');
});

t('a tab in indentation is refused', () => {
  refuses('a:\n\tb: 1\n', 'tab character');
});

t('an unterminated collection or quote is refused', () => {
  refuses('a: [1, 2\n', 'never closed');
  refuses('a: "unterminated\n', 'never closed');
});

t('a collection used as a mapping key is refused instead of becoming [object Object]', () => {
  refuses('a: {{x: 1}: 2}\n', 'collection used as a mapping key');
});

t('parse refuses a non-string outright', () => {
  refuses(undefined, 'expects a string');
});

// ---- prototype safety -----------------------------------------------------------------------------

t('a __proto__ key lands as an own property and reaches no prototype', () => {
  const parsed = Y.parse('__proto__:\n  polluted: true\nok: 1\n');
  assert.strictEqual(parsed.ok, 1);
  assert.strictEqual(({}).polluted, undefined, 'a skill file must not be able to touch Object.prototype');
  assert.ok(Object.hasOwn(parsed, '__proto__'));
});

// ---- stringify ------------------------------------------------------------------------------------

t('stringify emits block collections that parse back to the same value', () => {
  const value = { name: 'foo', tools: ['Read', 'Write'], hooks: [{ matcher: 'Bash', run: { cmd: 'x.sh' } }], off: null };
  const text = Y.stringify(value, null, 2);
  assert.deepStrictEqual(Y.parse(text), value);
  assert.ok(text.endsWith('\n'), 'the graph appends its own newline to this and expects one already there');
});

t('stringify quotes exactly what would otherwise read as something else', () => {
  const value = { plain: 'hello', looksNull: 'null', looksNum: '3', hasColon: 'a: b', hasHash: 'a # b', spaced: ' x ', empty: '', dash: '- x' };
  assert.deepStrictEqual(Y.parse(Y.stringify(value, null, 2)), value);
});

t('stringify writes multi-line strings so they come back identical', () => {
  const value = { body: 'one\ntwo\n\nfour', tabbed: 'a\tb' };
  assert.deepStrictEqual(Y.parse(Y.stringify(value, null, 2)), value);
});

t('empty collections keep their kind', () => {
  assert.deepStrictEqual(Y.parse(Y.stringify({ a: [], b: {} }, null, 2)), { a: [], b: {} });
});

t('stringify follows JSON on undefined, toJSON and the replacer', () => {
  assert.strictEqual(Y.stringify({ a: 1, b: undefined }, null, 2), 'a: 1\n');
  assert.strictEqual(Y.stringify({ d: { toJSON: () => 'x' } }, null, 2), 'd: x\n');
  assert.strictEqual(Y.stringify({ a: 1, b: 2 }, ['a'], 2), 'a: 1\n');
  assert.strictEqual(Y.stringify({ a: 1 }, (k, v) => (k === 'a' ? v * 2 : v), 2), 'a: 2\n');
});

t('a non-finite number keeps its YAML spelling', () => {
  assert.strictEqual(Y.stringify({ a: NaN, b: Infinity, c: -Infinity }, null, 2), 'a: .nan\nb: .inf\nc: -.inf\n');
});

t('a value containing itself is refused, and one merely repeated is not', () => {
  const loop = {}; loop.self = loop;
  assert.throws(() => Y.stringify(loop, null, 2), /contains itself/);
  const shared = { x: 1 };
  assert.deepStrictEqual(Y.parse(Y.stringify({ a: shared, b: shared }, null, 2)), { a: { x: 1 }, b: { x: 1 } });
});

t('a scalar at the root is a document too', () => {
  assert.strictEqual(Y.stringify('hi', null, 2), 'hi\n');
  assert.strictEqual(Y.stringify(null, null, 2), 'null\n');
  assert.deepStrictEqual(Y.parse(Y.stringify([1, [2, 3]], null, 2)), [1, [2, 3]]);
});

run();
