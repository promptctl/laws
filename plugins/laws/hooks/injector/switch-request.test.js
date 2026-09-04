#!/usr/bin/env node
// Tests for switch-request.js — composing decision, ownership and enactment into one applied switch.
//
// The properties under test are that this file DECIDES nothing (the verdict comes from laws-excise,
// unchanged), that every refusal its parts produce travels back by name rather than being flattened
// into a generic failure, and that a request which no longer applies refuses instead of enacting a
// stale one.

'use strict';
const assert = require('assert');
const S = require('./switch-request.js');
const { createSeamRegistry } = require('./seam-registry.js');
const { UNPLANNABLE } = require('./live-switch.js');

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

const load = (uuid, medium) => ({
  type: 'user', uuid, isMeta: true, timestamp: 't0',
  message: { role: 'user', content: [{ type: 'text', text: `Base directory for this skill: /laws/skills/${medium}/` }] },
});
const said = (uuid, text) => ({ type: 'user', uuid, timestamp: 't1', message: { role: 'user', content: text } });

const DECISION = {
  trigger: true, current: ['code'], incoming: 'prompt', deep: false,
  conflicts: [{ uuid: 'L', medium: 'code' }],
  rewind: { summarizeTo: 'L', discardTo: 'A' },
};

function harness(over = {}) {
  const snapshot = over.snapshot || [said('A', 'hi'), load('L', 'code'), said('B', 'after')];
  const replaced = [];
  const rewinds = [];
  const controller = {
    transcript: { getSnapshot: () => snapshot, replace: (m) => replaced.push(m) },
    rewindConversationTo: (m, source) => rewinds.push([m.uuid, source]),
  };
  const registry = createSeamRegistry();
  registry.registrar.controller(controller);
  const seen = {};
  return {
    replaced, rewinds, controller, registry, seen,
    run: (o = {}) => S.enactSwitch({
      request: { transcript: '/t.jsonl', choice: 'tombstone', incomingMedium: 'prompt', ...o.request },
      registry: o.registry || registry,
      decide: o.decide || ((lines, opts) => { seen.lines = lines; seen.opts = opts; return over.decision || DECISION; }),
      conflictEdges: [['code', 'prompt']],
      readFile: o.readFile || (() => over.raw ?? 'line1\nline2\n'),
      uuid: () => 'NEW', now: () => 'NOW',
      ...o.extra,
    }),
  };
}

// ---- the request ---------------------------------------------------------------------------------

t('every refusal states that the live conversation is untouched', () => {
  // The caller reads this fact rather than recognising reason strings, so each arm must carry it —
  // an arm that forgets makes the CLI warn about a rewind that never happened.
  const h = harness();
  assert.strictEqual(h.run({ request: { transcript: undefined } }).mutated, false);
  assert.strictEqual(h.run({ readFile: () => { throw new Error('ENOENT'); } }).mutated, false);
  assert.strictEqual(harness({ decision: { trigger: false, reason: 'compatible' } }).run().mutated, false);
  assert.strictEqual(h.run({ registry: createSeamRegistry() }).mutated, false);
  assert.strictEqual(h.run({ request: { choice: 'rewind_summarize' } }).mutated, false);
});

t('a request missing a field refuses AND names which fields', () => {
  const h = harness();
  const out = h.run({ request: { transcript: undefined, incomingMedium: undefined } });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, S.REFUSED.incomplete);
  assert.strictEqual(out.detail, 'transcript, incomingMedium');
});

t('an unreadable transcript is a named refusal, not a crash', () => {
  const h = harness();
  const out = h.run({ readFile: () => { throw new Error('ENOENT'); } });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, S.REFUSED.unreadable);
  // Exact: String(e) would read "Error: ENOENT" and still match a substring check.
  assert.strictEqual(out.detail, 'ENOENT');
});

// ---- the decision --------------------------------------------------------------------------------

t('the verdict is taken from decide(), which is handed the policy it was given', () => {
  const h = harness();
  h.run();
  assert.deepStrictEqual(h.seen.opts, { conflictEdges: [['code', 'prompt']], incomingMedium: 'prompt' });
});

t('a trailing newline does not become an extra empty record', () => {
  // The line numbering the decision is built on has to be the numbering laws-excise itself uses.
  const h = harness({ raw: 'a\nb\n' });
  h.run();
  assert.deepStrictEqual(h.seen.lines, ['a', 'b']);
});

t('a transcript with no trailing newline keeps its last line', () => {
  const h = harness({ raw: 'a\nb' });
  h.run();
  assert.deepStrictEqual(h.seen.lines, ['a', 'b']);
});

t('a switch that no longer applies refuses, carrying the reason it stopped applying', () => {
  // The conversation kept moving between the offer and the choice; enacting a stale verdict would
  // edit messages the user never agreed to.
  const h = harness({ decision: { trigger: false, reason: 'compatible' } });
  const out = h.run();
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, S.REFUSED.moot);
  assert.strictEqual(out.detail, 'compatible');
});

t('nothing is enacted when the decision no longer triggers', () => {
  const h = harness({ decision: { trigger: false, reason: 'first-craft' } });
  h.run();
  assert.deepStrictEqual([h.rewinds, h.replaced], [[], []]);
});

// ---- ownership -----------------------------------------------------------------------------------

t('a conversation nobody holds passes the registry\'s own refusal straight through', () => {
  const h = harness();
  const out = h.run({ registry: createSeamRegistry() });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, 'no-seam-ever-announced-a-conversation');
});

t('the conversation is chosen by which one holds the decision\'s anchor', () => {
  const h = harness();
  const registry = createSeamRegistry();
  registry.registrar.controller({ transcript: { getSnapshot: () => [said('elsewhere', 'x')] } });
  registry.registrar.controller(h.controller);
  const out = h.run({ registry });
  assert.strictEqual(out.ok, true);
});

// ---- enactment -----------------------------------------------------------------------------------

t('a plan that cannot be made passes its own refusal through, unflattened', () => {
  const h = harness();
  const out = h.run({ request: { choice: 'rewind_summarize' } });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, UNPLANNABLE.summaryMissing);
});

t('a completed switch reports what it did and what it retired', () => {
  const h = harness();
  const out = h.run({ request: { choice: 'tombstone' } });
  assert.deepStrictEqual(out, {
    ok: true, rewound: false, tombstoned: 1, changed: true,
    choice: 'tombstone', switchedFrom: ['code'], switchedTo: 'prompt',
  });
});

t('rewind_discard drives the app\'s own rewind at the craft load', () => {
  const h = harness();
  const out = h.run({ request: { choice: 'rewind_discard' } });
  assert.strictEqual(out.ok, true);
  assert.deepStrictEqual(h.rewinds, [['L', 'message_selector']]);
});

t('reject succeeds even when no conversation can be identified', () => {
  // It edits nothing, so it must not have to prove which conversation it would have edited. This
  // failed before whenever the conversation carrying the craft had ended — refusing to do nothing
  // because it could not find the thing it was not going to touch.
  const h = harness();
  const out = h.run({ request: { choice: 'reject' }, registry: createSeamRegistry() });
  assert.strictEqual(out.ok, true);
  assert.deepStrictEqual([out.rewound, out.tombstoned, out.changed], [false, 0, false]);
  assert.deepStrictEqual(out.switchedFrom, []);
});

t('an ownership refusal says how many conversations the seam is holding', () => {
  // "Holding three, none of them yours" and "holding none" are different things to go and look at.
  const h = harness();
  const registry = createSeamRegistry();
  registry.registrar.controller({ transcript: { getSnapshot: () => [said('elsewhere', 'x')] } });
  const out = h.run({ registry });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.live, 1);
});

t('reject reaches the store not at all', () => {
  const h = harness();
  const out = h.run({ request: { choice: 'reject' } });
  assert.deepStrictEqual([h.rewinds, h.replaced], [[], []]);
  assert.strictEqual(out.changed, false);
});

t('no choice writes to the filesystem — on-disk deliverables survive all four', () => {
  // Asserted BEHAVIOURALLY. This used to read enactSwitch's source text for the string "writeFile",
  // which pins a spelling rather than a contract and passes for any writer named differently.
  // [LAW:behavior-not-structure] Instead every write entry point on the real fs module is replaced
  // for the duration of a full run of each choice, and any call at all is a failure.
  const fs = require('fs');
  const WRITERS = ['writeFileSync', 'appendFileSync', 'writeSync', 'renameSync', 'unlinkSync',
    'createWriteStream', 'openSync', 'rmSync', 'truncateSync', 'copyFileSync', 'mkdirSync'];
  const original = {};
  const calls = [];
  for (const name of WRITERS) { original[name] = fs[name]; fs[name] = (...a) => { calls.push([name, a[0]]); }; }
  try {
    for (const choice of ['reject', 'tombstone', 'rewind_discard', 'rewind_summarize']) {
      const h = harness();
      // A summary throughout, so rewind_summarize runs its full length instead of refusing early.
      const out = h.run({ request: { choice, summary: 'what happened' } });
      assert.ok(out.ok || out.reason, 'choice ' + choice + ' produced no result at all');
    }
  } finally {
    for (const name of WRITERS) fs[name] = original[name];
  }
  assert.deepStrictEqual(calls, [], 'the enactment wrote to the filesystem');
});

t('the request contract is exactly the three fields the enactment needs', () => {
  assert.deepStrictEqual(S.REQUIRED, ['transcript', 'choice', 'incomingMedium']);
});

runAll();
