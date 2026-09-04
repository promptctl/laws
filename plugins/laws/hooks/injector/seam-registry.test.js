#!/usr/bin/env node
// Tests for seam-registry.js — holding what the seams announced, and proving which one owns a
// conversation.
//
// The property under test is that ownership is PROVEN, never picked. "The last controller to
// announce itself" would be a guess that reads as a fact, and would be wrong on the day a second one
// exists — with nothing reporting that it happened.

'use strict';
const assert = require('assert');
const R = require('./seam-registry.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
// A suite that stops early must not look green. Every handle this file opens is unref'd or closed,
// so a case that never resolves lets node drain the event loop and exit 0 with the summary never
// printed — a passing exit code for a suite that ran half its cases. The exit hook is what makes
// that visible, because it is the only thing that still runs when nothing else does.
let finished = false;
process.on('exit', () => {
  if (finished) return;
  console.log(`\nINCOMPLETE - exited after ${pass + fail} of ${cases.length} cases`);
  process.exitCode = 1;
});
async function runAll() {
  for (const { name, fn } of cases) {
    try { await fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
  }
  finished = true;
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

// A controller, as the app shapes one: a transcript store read through getSnapshot.
const controller = (uuids) => ({ transcript: { getSnapshot: () => uuids.map((uuid) => ({ uuid })) } });

t('nothing announced is its own reason, not "not found"', () => {
  // A seam that spliced but never fired and a seam that fired on a different conversation are two
  // different failures, and collapsing them would send whoever reads the log to the wrong place.
  const reg = R.createSeamRegistry();
  assert.deepStrictEqual(reg.ownerOf('u1'), { ok: false, reason: R.UNOWNED.neverAnnounced });
});

t('the controller whose live store holds the uuid is the owner', () => {
  const reg = R.createSeamRegistry();
  const mine = controller(['u1', 'u2']);
  reg.registrar.controller(controller(['other']));
  reg.registrar.controller(mine);
  assert.deepStrictEqual(reg.ownerOf('u2'), { ok: true, controller: mine });
});

t('a uuid no live conversation holds refuses, and says which uuid', () => {
  const reg = R.createSeamRegistry();
  reg.registrar.controller(controller(['u1']));
  const owner = reg.ownerOf('missing');
  assert.strictEqual(owner.ok, false);
  assert.strictEqual(owner.reason, R.UNOWNED.none);
  assert.strictEqual(owner.detail, 'missing');
});

t('two conversations holding one uuid refuses rather than picking', () => {
  // Picking either would enact the switch on a coin flip, against a conversation the caller may not
  // have meant.
  const reg = R.createSeamRegistry();
  reg.registrar.controller(controller(['shared']));
  reg.registrar.controller(controller(['shared']));
  const owner = reg.ownerOf('shared');
  assert.strictEqual(owner.ok, false);
  assert.strictEqual(owner.reason, R.UNOWNED.several);
});

t('the LAST announcement does not win — ownership is by contents', () => {
  // The specific guess this file exists to refuse.
  const reg = R.createSeamRegistry();
  const first = controller(['u1']);
  reg.registrar.controller(first);
  reg.registrar.controller(controller(['u9']));
  assert.strictEqual(reg.ownerOf('u1').controller, first);
});

t('count reports how many announced, so a seam that never fired is visible', () => {
  const reg = R.createSeamRegistry();
  assert.strictEqual(reg.count, 0);
  reg.registrar.controller(controller([]));
  reg.registrar.controller(controller([]));
  assert.strictEqual(reg.count, 2);
});

t('the registrar returns undefined — announcing is a side effect, not a value', () => {
  // Its return value lands in a class field on the app's own instance; anything else would put an
  // object of ours where the app might find it.
  const reg = R.createSeamRegistry();
  assert.strictEqual(reg.registrar.controller(controller([])), undefined);
});

t('a hole in the live array does not throw', () => {
  // The store is the app's, and a null entry is its business, not a reason to crash the switch.
  const reg = R.createSeamRegistry();
  reg.registrar.controller({ transcript: { getSnapshot: () => [null, { uuid: 'u1' }] } });
  assert.strictEqual(reg.ownerOf('u1').ok, true);
});

t('snapshotOf reads the store the one way, so callers cannot spell it differently', () => {
  const c = controller(['u1']);
  assert.deepStrictEqual(R.snapshotOf(c), [{ uuid: 'u1' }]);
});

runAll();
