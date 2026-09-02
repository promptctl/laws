#!/usr/bin/env node
// Tests for boot-channel.js — the line protocol between the host and the launcher.
//
// Both halves are asserted here against each other, which is the point of the protocol having one
// home: a writer and a reader that each carry their own idea of the format have two ideas of it, and
// the day they differ the launcher misreads a failure as something else entirely.

'use strict';
const assert = require('assert');
const C = require('./boot-channel.js');

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

const open = () => { const written = []; return { written, channel: C.createBootChannel({ write: (b) => written.push(b) }) }; };
const linesOf = (written) => written.join('').split('\n').filter(Boolean);

// ---- writing ------------------------------------------------------------------------------------

t('each observation goes out as its own record', () => {
  const { written, channel } = open();
  channel.started();
  channel.absentApi('YAML');
  channel.report('painted');
  assert.deepStrictEqual(linesOf(written), ['started', 'absent-api YAML', 'painted']);
});

t('the verdict fires once; every later observation still goes out', () => {
  // A graph that painted and then threw has spent its verdict, and the message it died with is the
  // useful part — so `send` must not be gated by the same latch.
  const { written, channel } = open();
  channel.report('painted');
  channel.report('absent no-bun-module-graph-trailer');
  channel.send('boot-threw something later');
  assert.deepStrictEqual(linesOf(written), ['painted', 'boot-threw something later']);
});

t('an absent API is reported once, however often it is asked for', () => {
  const { written, channel } = open();
  for (let i = 0; i < 5; i++) channel.absentApi('newThing');
  channel.absentApi('other');
  assert.deepStrictEqual(linesOf(written), ['absent-api newThing', 'absent-api other']);
});

t('a message carrying a newline stays ONE record', () => {
  // Otherwise a multi-line error message arrives as a refusal followed by garbage, and the reader
  // treats the garbage as further reports.
  const { written, channel } = open();
  channel.send('boot-threw Error: one\ntwo\r\nthree');
  assert.deepStrictEqual(linesOf(written), ['boot-threw Error: one two three']);
  assert.strictEqual(written.join('').split('\n').length, 2, 'exactly one record and its terminator');
});

// ---- reading, against what writing produces --------------------------------------------------------

t('the reader recognises every observation the writer can emit', () => {
  const { written, channel } = open();
  channel.started();
  channel.report('painted');
  channel.absentApi('YAML');
  channel.send('absent module-has-unknown-loader');
  assert.deepStrictEqual(linesOf(written).map(C.readReport), [
    { kind: 'started' },
    { kind: 'painted' },
    { kind: 'absent-api', name: 'YAML' },
    { kind: 'refusal', reason: 'absent module-has-unknown-loader' },
  ]);
});

t('a blank line is nothing, not a refusal with an empty reason', () => {
  assert.deepStrictEqual(C.readReport(''), { kind: 'blank' });
});

t('a refusal that merely mentions an observation is still a refusal', () => {
  assert.deepStrictEqual(C.readReport('boot-threw painted is not a word here'),
    { kind: 'refusal', reason: 'boot-threw painted is not a word here' });
});

runAll();
