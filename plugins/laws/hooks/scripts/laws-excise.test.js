#!/usr/bin/env node
// Unit tests for laws-excise.js — the runtime craft-compatibility gate. Plain Node asserts, no
// framework: same dependency stance as skill-router.test.sh. Fixtures are synthetic transcript
// lines built to the exact shape a real Skill-tool craft load lands as, so the tests assert the
// compatibility CONTRACT (which pairs trigger a switch, what gets tombstoned) — never internals.

'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const M = require('./laws-excise.js');

let pass = 0, fail = 0;
function t(name, fn) {
  try { fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

// The single incompatible pair, passed explicitly so tests never depend on the file on disk.
const PAIRS = [['code', 'prompt']];

// Build one craft-load transcript line, exactly the shape craftMediumOf detects.
let uidSeq = 0;
function loadLine({ medium, uuid, parentUuid = null, ts = '2026-08-09T00:00:00.000Z' }) {
  uuid = uuid || 'u' + (++uidSeq);
  return JSON.stringify({
    type: 'user', isMeta: true, uuid, parentUuid, timestamp: ts,
    sourceToolUseID: 'toolu_' + uuid,
    message: { role: 'user', content: [{ type: 'text', text: 'Base directory for this skill: /plugins/laws/skills/' + medium + '\n\n<SKILL body>' }] },
  });
}
// A plain non-craft conversation line (must always be ignored / passed through untouched).
function chatLine(text) {
  return JSON.stringify({ type: 'user', uuid: 'c' + (++uidSeq), parentUuid: null, message: { role: 'user', content: [{ type: 'text', text }] } });
}

// ---- policy -------------------------------------------------------------------------------
t('parsePolicy strips comments and blanks, keeps pairs', () => {
  const pairs = M.parsePolicy('# header\n\ncode prompt  # inline\n\n');
  assert.deepStrictEqual(pairs, [['code', 'prompt']]);
});
t('craftsIncompatible is symmetric and pair-scoped', () => {
  assert.strictEqual(M.craftsIncompatible('code', 'prompt', PAIRS), true);
  assert.strictEqual(M.craftsIncompatible('prompt', 'code', PAIRS), true);   // symmetric
  assert.strictEqual(M.craftsIncompatible('code', 'prose', PAIRS), false);   // compatible
  assert.strictEqual(M.craftsIncompatible('code', 'code', PAIRS), false);    // not self-incompatible
});

// ---- decide(): the corrected trigger rule -------------------------------------------------
t('pre-load: code engaged + incoming prompt → triggers, switches away from code', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true);
  assert.strictEqual(d.current, 'code');
  assert.strictEqual(d.incoming, 'prompt');
  assert.strictEqual(d.conflictIndex, 0);
  assert.strictEqual(d.rewind.summarizeTo, 'A');           // the code load line
  assert.strictEqual(d.rewind.discardTo, null);            // its parentUuid
  assert.strictEqual(d.rewind.summaryExcludesCraft, true);
  assert.deepStrictEqual(d.options.map((o) => o.id), ['reject', 'tombstone', 'rewind_summarize', 'rewind_discard']);
});
t('pre-load: code engaged + incoming prose → NO trigger (compatible coexist)', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'prose' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'compatible');
});
t('pre-load: reload of the same craft → NO trigger (same-medium)', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'code' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'same-medium');
});
t('pre-load: nothing engaged + incoming prompt → NO trigger (first-craft)', () => {
  const d = M.decide([chatLine('hi')], { incompatiblePairs: PAIRS, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'first-craft');
});
t('pre-load: symmetry — prompt engaged + incoming code → triggers, switches away from prompt', () => {
  const lines = [loadLine({ medium: 'prompt', uuid: 'P' })];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'code' });
  assert.strictEqual(d.trigger, true);
  assert.strictEqual(d.current, 'prompt');
  assert.strictEqual(d.incoming, 'code');
});
t('pre-load: compatible set (code+prose+ticket-ish) + incoming prompt → triggers, names code', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    chatLine('work'),
    loadLine({ medium: 'prose', uuid: 'B', ts: '2026-08-09T00:01:00.000Z' }),
  ];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true);
  assert.strictEqual(d.current, 'code');                   // the conflicting one, not the newest (prose)
  assert.strictEqual(d.conflictIndex, 0);
});
t('post-hoc: code+prompt both on disk → triggers; newest is incoming', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prompt', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' }),
  ];
  const d = M.decide(lines, { incompatiblePairs: PAIRS });
  assert.strictEqual(d.trigger, true);
  assert.strictEqual(d.incoming, 'prompt');                // newest
  assert.strictEqual(d.current, 'code');
});
t('post-hoc: code+prose both on disk → NO trigger', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prose', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' }),
  ];
  const d = M.decide(lines, { incompatiblePairs: PAIRS });
  assert.strictEqual(d.trigger, false);
});
t('recommendation: shallow → tombstone, deep → rewind_summarize', () => {
  const shallow = [loadLine({ medium: 'code', uuid: 'A' })];
  assert.strictEqual(M.decide(shallow, { incompatiblePairs: PAIRS, incomingMedium: 'prompt' }).recommended, 'tombstone');
  // force "deep" by setting a tiny threshold
  assert.strictEqual(M.decide(shallow, { incompatiblePairs: PAIRS, incomingMedium: 'prompt', largeTokens: 1 }).recommended, 'rewind_summarize');
});
t('decide throws without incompatiblePairs (no silent never-trigger)', () => {
  assert.throws(() => M.decide([loadLine({ medium: 'code' })], { incomingMedium: 'prompt' }), /incompatiblePairs is required/);
});

// ---- exciseAt(): targeted tombstone -------------------------------------------------------
t('exciseAt tombstones only the target; siblings byte-identical; tree preserved; idempotent', () => {
  const a = loadLine({ medium: 'code', uuid: 'A', parentUuid: 'root', ts: '2026-08-09T00:00:00.000Z' });
  const mid = chatLine('some work');
  const b = loadLine({ medium: 'prompt', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' });
  const lines = [a, mid, b];
  const r = M.exciseAt(lines, [0], 'prompt');
  assert.strictEqual(r.changed, true);
  assert.deepStrictEqual(r.stubbed, ['code']);
  assert.strictEqual(r.lines[1], mid);                     // untouched chat line, byte-identical
  assert.strictEqual(r.lines[2], b);                       // untouched prompt line, byte-identical
  const o = JSON.parse(r.lines[0]);                        // still valid JSON
  assert.strictEqual(o.uuid, 'A');                         // uuid preserved
  assert.strictEqual(o.parentUuid, 'root');                // parentUuid preserved
  assert.strictEqual(o.timestamp, '2026-08-09T00:00:00.000Z'); // timestamp preserved
  assert.ok(o.message.content[0].text.startsWith('[TOMBSTONE]'));
  assert.ok(o.message.content[0].text.includes('laws:prompt')); // names the craft that superseded it
  assert.strictEqual(M.craftMediumOf(o), null);            // idempotent: no longer a live load
  // second pass over the same line changes nothing
  const r2 = M.exciseAt(r.lines, [0], 'prompt');
  assert.strictEqual(r2.changed, false);
});
t('exciseAt skips a non-craft index rather than corrupting it', () => {
  const lines = [chatLine('not a craft')];
  const r = M.exciseAt(lines, [0], 'code');
  assert.strictEqual(r.changed, false);
  assert.strictEqual(r.lines[0], lines[0]);
});

// ---- run(): end-to-end repair on a temp file ----------------------------------------------
t('run repairs an incompatible stack in place; leaves a compatible stack alone', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'excise-'));
  // incompatible: code (older) + prompt (newer) → tombstone code, keep prompt
  const bad = path.join(dir, 'bad.jsonl');
  fs.writeFileSync(bad, [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prompt', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' }),
  ].join('\n') + '\n');
  const rb = M.run(bad, { incompatiblePairs: PAIRS });
  assert.strictEqual(rb.changed, true);
  assert.deepStrictEqual(rb.stubbed, ['code']);
  const out = fs.readFileSync(bad, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.strictEqual(M.craftMediumOf(out[0]), null);       // code tombstoned
  assert.strictEqual(M.craftMediumOf(out[1]), 'prompt');   // prompt survives

  // compatible: code + prose → untouched
  const ok = path.join(dir, 'ok.jsonl');
  const okContent = [
    loadLine({ medium: 'code', uuid: 'C', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prose', uuid: 'D', ts: '2026-08-09T00:05:00.000Z' }),
  ].join('\n') + '\n';
  fs.writeFileSync(ok, okContent);
  const ro = M.run(ok, { incompatiblePairs: PAIRS });
  assert.strictEqual(ro.changed, false);
  assert.strictEqual(fs.readFileSync(ok, 'utf8'), okContent); // byte-identical
  fs.rmSync(dir, { recursive: true, force: true });
});

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
