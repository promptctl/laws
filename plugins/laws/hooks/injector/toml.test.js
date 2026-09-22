#!/usr/bin/env node
// Unit tests for toml.js — `Bun.TOML.parse`, which is how the graph reads `.mcp.toml`.
//
// The suite is shaped by the one rule that file is written to: never refuse a document Bun accepts.
// There is no retry downstream of `Bun.TOML.parse` the way there is for YAML — m00861 reads the
// file, calls this, and a throw is simply an MCP server that is not there. So the cases below are
// mostly about ACCEPTING, and the handful of refusals are the ones Bun refuses too.
//
// Where an expectation differs from Bun it is marked and says why. Each of those was measured, not
// assumed: Bun's TOML leaves the newline after a `"""` in the value, turns `\t` into a form feed,
// hands back the string "inf" for `inf`, and refuses every date-time — all of them defects, and
// reproducing a defect would make this file wrong on purpose.

'use strict';
const assert = require('assert');
const T = require('./toml.js');

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
const eq = (text, expected, why) => assert.deepStrictEqual(T.parse(text), expected, why);
const refuses = (text, fragment) => {
  let threw = null;
  try { T.parse(text); } catch (e) { threw = e; }
  assert.ok(threw, `expected a refusal, got a value for ${JSON.stringify(text)}`);
  assert.ok(threw.message.includes(fragment), `refusal said ${JSON.stringify(threw.message)}, wanted ${JSON.stringify(fragment)}`);
};

// ---- the shape an .mcp.toml actually has ---------------------------------------------------------

t('a server definition reads as the schema downstream expects', () => {
  eq([
    '[mcp_servers.files]',
    'command = "npx"',
    'args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]',
    '',
    '[mcp_servers.files.env]',
    'LOG_LEVEL = "debug"',
    '',
    '[mcp_servers.remote]',
    'url = "https://example.com/mcp"',
    'bearer_token_env_var = "TOKEN"',
    '',
    '[mcp_servers.remote.http_headers]',
    '"X-Trace" = "on"',
    '',
  ].join('\n'), {
    mcp_servers: {
      files: { command: 'npx', args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'], env: { LOG_LEVEL: 'debug' } },
      remote: { url: 'https://example.com/mcp', bearer_token_env_var: 'TOKEN', http_headers: { 'X-Trace': 'on' } },
    },
  });
});

t('an empty document is an empty table, and so is one made only of comments', () => {
  eq('', {});
  eq('# nothing here\n\n# nor here\n', {});
});

// ---- keys --------------------------------------------------------------------------------------

t('bare, quoted and dotted keys all name the same kind of thing', () => {
  eq('a = 1\n"quoted key" = 2\n\'lit key\' = 3\nx.y.z = 4\nx.y.w = 5\n',
    { a: 1, 'quoted key': 2, 'lit key': 3, x: { y: { z: 4, w: 5 } } });
});

t('a key written twice is refused, the one duplicate Bun refuses too', () => {
  refuses('a = 1\na = 2\n', "cannot redefine key 'a'");
  eq('[a]\nb = 1\n[a]\nc = 2\n', { a: { b: 1, c: 2 } }, 'a table header repeated reopens it, as it does under Bun');
});

t('a key cannot pass through a value', () => {
  refuses('a = 1\na.b = 2\n', 'cannot also be a table');
});

// ---- values -------------------------------------------------------------------------------------

t('integers come in four bases and may carry underscores', () => {
  eq('a = 1_000\nb = 0x1F\nc = 0o17\nd = 0b1011\ne = -7\nf = +7\ng = 01\n',
    { a: 1000, b: 31, c: 15, d: 11, e: -7, f: 7, g: 1 });
});

t('floats, including the ones Bun gets wrong', () => {
  eq('a = 1.5\nb = 1e3\nc = 6.626e-34\nd = 1_0.5\n', { a: 1.5, b: 1000, c: 6.626e-34, d: 10.5 });
  // Bun answers "inf", 0 and "nan" here. Those are not values a caller can do anything with.
  const special = T.parse('a = inf\nb = -inf\nc = nan\n');
  assert.strictEqual(special.a, Infinity);
  assert.strictEqual(special.b, -Infinity);
  assert.ok(Number.isNaN(special.c));
});

t('booleans are only the two lowercase words', () => {
  eq('a = true\nb = false\n', { a: true, b: false });
  refuses('a = True\n', 'expected a value');
});

t('date-times: an instant becomes a Date, a local reading stays text', () => {
  // Bun refuses all five. A local date-time has no zone, so turning it into a Date would attach
  // this machine's — the text is the only honest answer for those three.
  const v = T.parse('a = 1979-05-27T07:32:00Z\nb = 1979-05-27T00:32:00-07:00\nc = 1979-05-27T07:32:00\nd = 1979-05-27\ne = 07:32:00\n');
  assert.ok(v.a instanceof Date);
  assert.strictEqual(v.a.toISOString(), '1979-05-27T07:32:00.000Z');
  assert.strictEqual(v.b.toISOString(), '1979-05-27T07:32:00.000Z');
  assert.strictEqual(v.c, '1979-05-27T07:32:00');
  assert.strictEqual(v.d, '1979-05-27');
  assert.strictEqual(v.e, '07:32:00');
});

// ---- strings ---------------------------------------------------------------------------------------

t('the four string forms', () => {
  eq('a = "basic"\nb = \'literal \\n not an escape\'\n', { a: 'basic', b: 'literal \\n not an escape' });
  eq('a = """\nline one\nline two"""\n', { a: 'line one\nline two' }, 'the newline after the opener is not part of the value');
  eq("a = '''\nraw \\n stays'''\n", { a: 'raw \\n stays' });
});

t('escapes, including the tab Bun turns into a form feed', () => {
  eq('a = "x\\ty"\nb = "x\\ny"\nc = "x\\u00e9y"\nd = "x\\\\y"\ne = "x\\"y"\n',
    { a: 'x\ty', b: 'x\ny', c: 'xéy', d: 'x\\y', e: 'x"y' });
  refuses('a = "x\\qy"\n', 'unknown escape');
});

t('a line-ending backslash swallows the break and the indentation after it', () => {
  eq('a = """one \\\n    two"""\n', { a: 'one two' });
});

t('a closing delimiter may be preceded by up to two of its own quotes', () => {
  eq('a = """he said ""hi"""\n', { a: 'he said ""hi' });
});

t('an unterminated string is refused', () => {
  refuses('a = "open\n', 'never closed');
  refuses('a = """open\n', 'never closed');
});

// ---- collections ------------------------------------------------------------------------------------

t('arrays nest, mix types, span lines and may end in a comma', () => {
  eq('a = [1, 2, 3]\nb = [[1, 2], [3]]\nc = [1, "two", true]\nd = []\n',
    { a: [1, 2, 3], b: [[1, 2], [3]], c: [1, 'two', true], d: [] });
  // Bun refuses this one outright — a trailing comma across lines takes the whole document with it.
  eq('a = [\n  1,\n  # a comment in the middle\n  2,\n]\n', { a: [1, 2] });
});

t('inline tables', () => {
  eq('a = {x = 1, y = "two"}\nb = {}\nc = {n = {deep = true}}\n',
    { a: { x: 1, y: 'two' }, b: {}, c: { n: { deep: true } } });
});

t('arrays of tables collect their entries in order, and dotted keys land in the last one', () => {
  eq('[[s]]\nn = 1\n[[s]]\nn = 2\n[[s.inner]]\nk = "v"\n',
    { s: [{ n: 1 }, { n: 2, inner: [{ k: 'v' }] }] });
});

t('an array of tables cannot reuse a plain table\'s name', () => {
  refuses('[a]\nx = 1\n[[a]]\ny = 2\n', 'cannot also be an array of tables');
});

// ---- refusals and safety -------------------------------------------------------------------------------

t('a line with no value, or content after one, is refused', () => {
  refuses('a = \n', 'expected a value');
  refuses('a = 1 b = 2\n', 'expected the end of the line');
  refuses('a\n', 'expected = after a key');
});

t('parse refuses a non-string outright', () => {
  refuses(undefined, 'expects a string');
});

t('a __proto__ key lands as an own property and reaches no prototype', () => {
  const parsed = T.parse('[__proto__]\npolluted = true\n');
  assert.strictEqual(({}).polluted, undefined, 'a config file must not be able to touch Object.prototype');
  assert.ok(Object.hasOwn(parsed, '__proto__'));
});

run();
