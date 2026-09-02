#!/usr/bin/env node
// Tests for boot-guard.js — reporting a crash during boot, and only during boot.
//
// The lifetime is the whole point, so it is what gets asserted: a crash before boot ends is named
// and exits "never booted", and the identical crash after boot ends is not this guard's business.

'use strict';
const assert = require('assert');
const G = require('./boot-guard.js');

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

// A stand-in process: records what was listened for, and lets a test fire it.
function fakeProcess() {
  const listeners = new Map();
  const sent = [], exits = [];
  return {
    sent, exits,
    events: () => [...listeners.keys()].filter((k) => listeners.get(k).length),
    fire: (event, value) => listeners.get(event)?.forEach((fn) => fn(value)),
    hooks: {
      on: (event, fn) => listeners.set(event, [...(listeners.get(event) || []), fn]),
      off: (event, fn) => listeners.set(event, (listeners.get(event) || []).filter((f) => f !== fn)),
      exit: (code) => exits.push(code),
      send: (line) => sent.push(line),
    },
  };
}

t('a crash during boot is named on the channel and exits "never booted"', () => {
  const p = fakeProcess();
  G.installBootGuard(p.hooks);
  p.fire('uncaughtException', new Error('render blew up'));
  assert.deepStrictEqual(p.sent, ['boot-threw uncaught: render blew up']);
  assert.deepStrictEqual(p.exits, [G.EXIT_NOT_BOOTED]);
});

t('a rejection nobody owns is named too, and distinguished from a throw', () => {
  const p = fakeProcess();
  G.installBootGuard(p.hooks);
  p.fire('unhandledRejection', new Error('nobody awaited this'));
  assert.deepStrictEqual(p.sent, ['boot-threw unhandled-rejection: nobody awaited this']);
});

t('a thrown non-Error still produces a reason, never undefined', () => {
  const p = fakeProcess();
  G.installBootGuard(p.hooks);
  p.fire('uncaughtException', 'just a string');
  assert.deepStrictEqual(p.sent, ['boot-threw uncaught: just a string']);
});

t('once boot is over the guard stops watching — the same crash is not its business', () => {
  // Left in place, every later crash reports EXIT_NOT_BOOTED, telling whatever reads the wrapper's
  // exit code that a session which ran for hours never started.
  const p = fakeProcess();
  const guard = G.installBootGuard(p.hooks);
  assert.strictEqual(guard.watching, true);
  guard.bootIsOver();
  assert.strictEqual(guard.watching, false);
  assert.deepStrictEqual(p.events(), [], 'the handlers have to be removed, not merely ignored');
  p.fire('uncaughtException', new Error('hours later'));
  assert.deepStrictEqual(p.sent, []);
  assert.deepStrictEqual(p.exits, []);
});

t('boot ending twice removes nothing the second time', () => {
  const p = fakeProcess();
  const guard = G.installBootGuard(p.hooks);
  guard.bootIsOver();
  p.hooks.on('uncaughtException', () => p.sent.push('somebody else'));
  guard.bootIsOver();
  p.fire('uncaughtException', new Error('x'));
  assert.deepStrictEqual(p.sent, ['somebody else'], "a second release must not take another owner's handler");
});

runAll();
