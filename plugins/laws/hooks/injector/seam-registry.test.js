#!/usr/bin/env node
// Tests for seam-registry.js — holding what the seams announced, and proving which one owns a
// conversation.
//
// The property under test is that ownership is PROVEN, never picked. "The last controller to
// announce itself" would be a guess that reads as a fact, and would be wrong on the day a second one
// exists — with nothing reporting that it happened.

'use strict';
const assert = require('assert');

// Collection is the behaviour under test, and it cannot be observed without a way to force it — so
// this suite re-runs itself with --expose-gc rather than skipping the case when gc is absent. A
// conditionally-skipped test is one that reports nothing on the machine where it matters.
if (!global.gc) {
  const { spawnSync } = require('child_process');
  const r = spawnSync(process.execPath, ['--expose-gc', __filename], { stdio: 'inherit' });
  process.exit(r.status === null ? 1 : r.status);
}

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

t('an absent uuid refuses on its own reason, never matching messages that have none', () => {
  // The trap: `m.uuid === undefined` is true of every record without a uuid, so without this guard
  // the first conversation holding one would come back as the PROVEN owner of nothing.
  const reg = R.createSeamRegistry();
  reg.registrar.controller({ transcript: { getSnapshot: () => [{ type: 'progress' }, { uuid: 'u1' }] } });
  for (const absent of [undefined, null, '']) {
    const owner = reg.ownerOf(absent);
    assert.strictEqual(owner.ok, false, 'accepted ' + JSON.stringify(absent));
    assert.strictEqual(owner.reason, R.UNOWNED.noUuid);
  }
});

t('an absent uuid is NOT reported as "no conversation holds it"', () => {
  // Two different facts: one sends you looking for a conversation, the other for a caller bug.
  const reg = R.createSeamRegistry();
  reg.registrar.controller({ transcript: { getSnapshot: () => [{ uuid: 'u1' }] } });
  assert.notStrictEqual(reg.ownerOf(undefined).reason, R.UNOWNED.none);
});

t('a controller the app has dropped stops being held', async () => {
  // The registry must never be the reason a conversation stays alive: the seam fires for every
  // controller the app builds and nothing tells us when one ends.
  const reg = R.createSeamRegistry();
  let doomed = { transcript: { getSnapshot: () => [{ uuid: 'gone' }] } };
  const kept = { transcript: { getSnapshot: () => [{ uuid: 'stays' }] } };
  reg.registrar.controller(doomed);
  reg.registrar.controller(kept);
  assert.strictEqual(reg.count, 2);

  doomed = null;
  global.gc();
  await new Promise((r) => setImmediate(r));
  global.gc();

  assert.strictEqual(reg.count, 1, 'a dropped controller is still held');
  assert.strictEqual(reg.ownerOf('gone').reason, R.UNOWNED.none);
  assert.strictEqual(reg.ownerOf('stays').controller, kept);
});

t('every controller collected leaves the registry reporting never-announced', async () => {
  const reg = R.createSeamRegistry();
  reg.registrar.controller({ transcript: { getSnapshot: () => [{ uuid: 'x' }] } });
  global.gc();
  await new Promise((r) => setImmediate(r));
  global.gc();
  assert.strictEqual(reg.count, 0);
  assert.strictEqual(reg.ownerOf('x').reason, R.UNOWNED.neverAnnounced);
});

t('snapshotOf reads the store the one way, so callers cannot spell it differently', () => {
  const c = controller(['u1']);
  assert.deepStrictEqual(R.snapshotOf(c), [{ uuid: 'u1' }]);
});

runAll();
