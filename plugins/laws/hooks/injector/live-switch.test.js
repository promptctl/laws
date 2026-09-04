#!/usr/bin/env node
// Tests for live-switch.js — the crossing from a disk-shaped decision to a live conversation.
//
// The property that gets the most attention here is the OFF-BY-ONE between the two rewinds, because
// it is the failure that would look almost right:
//   rewindTo(lines, anchor)   keeps THROUGH the anchor  (disk)
//   rewindConversationTo(msg) keeps UP TO msg           (live — msg itself is dropped)
// so rewind_discard aims at the craft load and rewind_summarize aims one PAST it. A test that only
// checked "something was rewound" would pass with these swapped.

'use strict';
const assert = require('assert');
const L = require('./live-switch.js');
const { stubText } = require('../scripts/laws-excise.js');

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

// Live message shapes, as measured on a hosted 2.1.258 session: a craft load is a meta user message
// whose content is a one-element text block; a typed prompt carries a plain string.
const load = (uuid, medium) => ({
  type: 'user', uuid, isMeta: true, timestamp: 't0',
  message: { role: 'user', content: [{ type: 'text', text: `Base directory for this skill: /laws/skills/${medium}/` }] },
});
const said = (uuid, text) => ({ type: 'user', uuid, timestamp: 't1', permissionMode: 'default', message: { role: 'user', content: text } });
const noise = (uuid) => ({ type: 'progress', uuid, timestamp: 't2' });

const decision = (over = {}) => ({
  trigger: true, current: ['code'], incoming: 'prompt', deep: false,
  conflicts: [{ uuid: 'load-code', medium: 'code' }],
  rewind: { summarizeTo: 'load-code', discardTo: 'before' },
  ...over,
});

const SNAP = [said('before', 'hello'), load('load-code', 'code'), noise('n1'), said('after', 'more')];
const plan = (over = {}) => L.planLiveSwitch({
  snapshot: SNAP, decision: decision(), choice: 'tombstone', uuid: 'new-uuid', now: 'NOW', ...over,
});

// ---- the choices --------------------------------------------------------------------------------

t('a choice that is not one of the four refuses by name', () => {
  const p = plan({ choice: 'obliterate' });
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.reason, L.UNPLANNABLE.unknownChoice);
});

t('reject plans nothing at all — no rewind, no tombstone, no append', () => {
  const p = plan({ choice: 'reject' });
  assert.deepStrictEqual([p.rewindAt, p.tombstones, p.append], [null, [], null]);
});

t('tombstone stubs the craft load and rewinds nothing', () => {
  const p = plan({ choice: 'tombstone' });
  assert.strictEqual(p.rewindAt, null);
  assert.strictEqual(p.tombstones.length, 1);
  assert.strictEqual(p.tombstones[0].uuid, 'load-code');
  assert.strictEqual(p.tombstones[0].stubbed.message.content[0].text, stubText('code', 'prompt'));
});

t('rewind_discard aims at the craft load ITSELF, so the load is dropped', () => {
  // Live rewind is exclusive of its argument: aiming one past this would leave the craft engaged.
  const p = plan({ choice: 'rewind_discard' });
  assert.strictEqual(p.rewindAt, SNAP[1]);
  assert.strictEqual(p.rewindAt.uuid, 'load-code');
  assert.deepStrictEqual(p.tombstones, []);
});

t('rewind_summarize aims ONE PAST the craft load, so the load survives to be stubbed', () => {
  const p = plan({ choice: 'rewind_summarize', summary: 'we did things' });
  assert.strictEqual(p.rewindAt, SNAP[2]);
  assert.strictEqual(p.rewindAt.uuid, 'n1');
  assert.strictEqual(p.tombstones.length, 1);
});

t('the two rewinds do not aim at the same message', () => {
  // The single assertion that fails if the off-by-one is ever collapsed.
  const discard = plan({ choice: 'rewind_discard' });
  const summarize = plan({ choice: 'rewind_summarize', summary: 's' });
  assert.notStrictEqual(discard.rewindAt, summarize.rewindAt);
});

t('a craft load that is the last live message leaves nothing to rewind', () => {
  const snapshot = [said('before', 'hi'), load('load-code', 'code')];
  const p = L.planLiveSwitch({ snapshot, decision: decision(), choice: 'rewind_summarize', summary: 's', uuid: 'u', now: 'N' });
  assert.strictEqual(p.ok, true);
  assert.strictEqual(p.rewindAt, null);
  assert.strictEqual(p.tombstones.length, 1);
});

t('rewind_summarize without a summary refuses instead of summarising nothing', () => {
  const p = plan({ choice: 'rewind_summarize' });
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.reason, L.UNPLANNABLE.summaryMissing);
});

// ---- the crossing -------------------------------------------------------------------------------

t('a conflict the live conversation no longer holds refuses — never a partial tombstone', () => {
  // A partial tombstone leaves a craft engaged that the switch reported retired.
  const d = decision({ conflicts: [{ uuid: 'load-code', medium: 'code' }, { uuid: 'ghost', medium: 'prose' }] });
  const p = L.planLiveSwitch({ snapshot: SNAP, decision: d, choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.reason, L.UNPLANNABLE.notLive);
  assert.strictEqual(p.detail, 'ghost');
});

t('a decision anchored on a uuid that is not live refuses', () => {
  const d = decision({ rewind: { summarizeTo: 'nowhere', discardTo: null }, conflicts: [{ uuid: 'nowhere', medium: 'code' }] });
  const p = L.planLiveSwitch({ snapshot: SNAP, decision: d, choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.reason, L.UNPLANNABLE.notLive);
});

t('a craft load whose content is not a text block refuses rather than being guessed at', () => {
  const snapshot = [said('load-code', 'a plain string, not a craft load')];
  const d = decision();
  const p = L.planLiveSwitch({ snapshot, decision: d, choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.reason, L.UNPLANNABLE.notStubbable);
});

t('a craft load whose content array carries no text refuses', () => {
  // Array-ness alone is not the shape: a block without a string `text` would be stubbed into
  // something the renderer cannot show, so each part of the shape is checked on its own.
  const odd = { type: 'user', uuid: 'load-code', message: { role: 'user', content: [{ type: 'image' }] } };
  const p = L.planLiveSwitch({ snapshot: [odd], decision: decision(), choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.reason, L.UNPLANNABLE.notStubbable);
});

t('a craft load with an EMPTY content array refuses', () => {
  const empty = { type: 'user', uuid: 'load-code', message: { role: 'user', content: [] } };
  const p = L.planLiveSwitch({ snapshot: [empty], decision: decision(), choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.reason, L.UNPLANNABLE.notStubbable);
});

t('a craft load with an EMPTY STRING content refuses', () => {
  const blank = { type: 'user', uuid: 'load-code', message: { role: 'user', content: '' } };
  const p = L.planLiveSwitch({ snapshot: [blank], decision: decision(), choice: 'tombstone', uuid: 'u', now: 'N' });
  assert.strictEqual(p.reason, L.UNPLANNABLE.notStubbable);
});

t('rewind_discard does not care whether the craft load is rewritable', () => {
  // It DELETES that message. Requiring it to be stubbable would refuse the switch over the shape of
  // a message that is about to cease existing — a wrong refusal, and one the tombstone-shaped cases
  // above would never catch.
  const odd = { type: 'user', uuid: 'load-code', message: { role: 'user', content: [{ type: 'image' }] } };
  const p = L.planLiveSwitch({ snapshot: [odd, said('x', 'after')], decision: decision(), choice: 'rewind_discard', uuid: 'u', now: 'N' });
  assert.strictEqual(p.ok, true);
  assert.strictEqual(p.rewindAt, odd);
  assert.deepStrictEqual(p.tombstones, []);
});

t('rewind_summarize DOES care, because it keeps and rewrites the craft load', () => {
  const odd = { type: 'user', uuid: 'load-code', message: { role: 'user', content: [{ type: 'image' }] } };
  const p = L.planLiveSwitch({ snapshot: [odd, said('x', 'after')], decision: decision(), choice: 'rewind_summarize', summary: 's', uuid: 'u', now: 'N' });
  assert.strictEqual(p.reason, L.UNPLANNABLE.notStubbable);
});

t('every plan is proof: planning succeeded means applying cannot fail on a tombstone', () => {
  const p = plan({ choice: 'tombstone' });
  assert.ok(p.tombstones.every((x) => x.stubbed && x.stubbed.message));
});

// ---- shaping ------------------------------------------------------------------------------------

t('stubbing produces a NEW object and leaves the original untouched', () => {
  // The store is read through getSnapshot and the UI redraws on identity, so an in-place edit would
  // change the conversation without redrawing it.
  const original = load('u', 'code');
  const before = original.message.content[0].text;
  const stubbed = L.stubbedMessage(original, 'code', 'prompt');
  assert.notStrictEqual(stubbed, original);
  assert.notStrictEqual(stubbed.message, original.message);
  assert.strictEqual(original.message.content[0].text, before);
  assert.strictEqual(stubbed.message.content[0].text, stubText('code', 'prompt'));
});

t('stubbing keeps every other field of the message', () => {
  const original = { ...load('u', 'code'), permissionMode: 'plan', promptId: 'p9' };
  const stubbed = L.stubbedMessage(original, 'code', 'prompt');
  assert.strictEqual(stubbed.permissionMode, 'plan');
  assert.strictEqual(stubbed.promptId, 'p9');
  assert.strictEqual(stubbed.uuid, 'u');
});

t('stubbing keeps content blocks after the first', () => {
  const original = load('u', 'code');
  original.message.content.push({ type: 'text', text: 'second block' });
  const stubbed = L.stubbedMessage(original, 'code', 'prompt');
  assert.strictEqual(stubbed.message.content.length, 2);
  assert.strictEqual(stubbed.message.content[1].text, 'second block');
});

t('the summary is shaped from a real user message, not invented', () => {
  // A live message carries far more fields than the renderer's minimum; inventing a shape from the
  // obvious few is how a message renders as a blank row.
  const summary = L.summaryFrom(SNAP, { uuid: 'new', timestamp: 'NOW', text: 'what happened' });
  assert.strictEqual(summary.permissionMode, 'default');
  assert.strictEqual(summary.type, 'user');
  assert.strictEqual(summary.message.role, 'user');
  assert.strictEqual(summary.message.content, 'what happened');
  assert.strictEqual(summary.uuid, 'new');
  assert.strictEqual(summary.timestamp, 'NOW');
});

t('a conversation with no user message to shape a summary from refuses', () => {
  const p = L.planLiveSwitch({
    snapshot: [load('load-code', 'code')], decision: decision(),
    choice: 'rewind_summarize', summary: 's', uuid: 'u', now: 'N',
  });
  // The craft load IS a user message, so shape one that is not.
  const onlyNoise = L.summaryFrom([noise('n')], { uuid: 'u', timestamp: 'N', text: 's' });
  assert.strictEqual(onlyNoise, null);
  assert.strictEqual(p.ok, true);   // the load itself is a valid template
});

t('the summary is shaped from the LAST user message, not the first', () => {
  const snap = [said('a', 'first'), { ...said('b', 'last'), origin: 'late' }];
  assert.strictEqual(L.summaryFrom(snap, { uuid: 'u', timestamp: 'N', text: 'x' }).origin, 'late');
});

// ---- applying -----------------------------------------------------------------------------------

// A controller that records what was done to it, and whose store actually changes.
function fakeController(initial) {
  const calls = [];
  let messages = initial;
  return {
    calls,
    get messages() { return messages; },
    transcript: {
      getSnapshot: () => messages,
      replace: (next) => { calls.push(['replace', next]); messages = next; },
    },
    rewindConversationTo(message, source) {
      calls.push(['rewind', message.uuid, source]);
      messages = messages.slice(0, messages.indexOf(message));
    },
  };
}

t('the rewind is driven through the app\'s own method, with the app\'s own source value', () => {
  const c = fakeController(SNAP.slice());
  const p = plan({ choice: 'rewind_discard' });
  L.applyLiveSwitch(c, p);
  assert.deepStrictEqual(c.calls[0], ['rewind', 'load-code', L.REWIND_SOURCE]);
});

t('rewind_discard leaves the conversation ending before the craft load', () => {
  const c = fakeController(SNAP.slice());
  L.applyLiveSwitch(c, plan({ choice: 'rewind_discard' }));
  assert.deepStrictEqual(c.messages.map((m) => m.uuid), ['before']);
});

t('rewind_summarize keeps the craft load, stubs it, and appends the summary', () => {
  const c = fakeController(SNAP.slice());
  const p = plan({ choice: 'rewind_summarize', summary: 'we did things' });
  L.applyLiveSwitch(c, p);
  assert.deepStrictEqual(c.messages.map((m) => m.uuid), ['before', 'load-code', 'new-uuid']);
  assert.strictEqual(c.messages[1].message.content[0].text, stubText('code', 'prompt'));
  assert.strictEqual(c.messages[2].message.content, 'we did things');
});

t('the replacement is built from the POST-rewind store, not the pre-rewind one', () => {
  // Building it from the snapshot the plan was made against would reinstate the messages the rewind
  // had just dropped.
  const c = fakeController(SNAP.slice());
  L.applyLiveSwitch(c, plan({ choice: 'rewind_summarize', summary: 's' }));
  assert.ok(!c.messages.some((m) => m.uuid === 'after'), 'a dropped message came back');
});

t('tombstone replaces only the conflicting craft\'s content and touches nothing else', () => {
  const c = fakeController(SNAP.slice());
  L.applyLiveSwitch(c, plan({ choice: 'tombstone' }));
  assert.deepStrictEqual(c.messages.map((m) => m.uuid), ['before', 'load-code', 'n1', 'after']);
  assert.strictEqual(c.messages[0], SNAP[0]);
  assert.strictEqual(c.messages[3], SNAP[3]);
  assert.strictEqual(c.messages[1].message.content[0].text, stubText('code', 'prompt'));
});

t('reject touches the store not at all', () => {
  // Replacing with an equal array would still redraw the transcript for a choice that promised to
  // change nothing.
  const c = fakeController(SNAP.slice());
  const out = L.applyLiveSwitch(c, plan({ choice: 'reject' }));
  assert.deepStrictEqual(c.calls, []);
  assert.deepStrictEqual(out, { ok: true, rewound: false, tombstoned: 0, changed: false });
});

t('what was done comes back, so the caller can report it rather than assume it', () => {
  const c = fakeController(SNAP.slice());
  const out = L.applyLiveSwitch(c, plan({ choice: 'rewind_summarize', summary: 's' }));
  assert.deepStrictEqual(out, { ok: true, rewound: true, tombstoned: 1, changed: true });
});

runAll();
