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

// ---- severAt(): the rewind primitive for options 3 & 4 -------------------------------------
// The contract is REACHABILITY, measured on 2.1.226: a resume rebuilds the deepest chain rooted
// at the transcript root, so unrooting the anchor's children is what rewinds it. These assert that
// contract — which records stay reachable from the root — never how the repointing is spelled.
function chainLine(uuid, parentUuid, text) {
  return JSON.stringify({ type: 'user', uuid, parentUuid, message: { role: 'user', content: text } });
}
// root -> A -> B -> C, and the anchor is A: severing A's children must strand B and C.
const CHAIN = [
  chainLine('root', null, 'root turn'),
  chainLine('A', 'root', 'anchor turn'),
  chainLine('B', 'A', 'after the anchor'),
  chainLine('C', 'B', 'later still'),
];
// Depth of the deepest record still reachable from the root — the thing a resume actually reads.
function deepestRooted(lines) {
  const objs = lines.map((l) => JSON.parse(l));
  const byUuid = new Map(objs.map((o) => [o.uuid, o]));
  const depth = (o, seen = new Set()) => {
    if (!o || o.parentUuid === null) return o ? 1 : 0;
    if (seen.has(o.uuid)) return 0;
    seen.add(o.uuid);
    const p = byUuid.get(o.parentUuid);
    if (!p) return 0;                                         // parent missing -> branch is unrooted
    const d = depth(p, seen);
    return d === 0 ? 0 : d + 1;                               // unrootedness propagates to descendants
  };
  return objs.reduce((max, o) => Math.max(max, depth(o)), 0);
}

// The trailing leaf pointer a resume reads, or null if the surgery never wrote one.
function trailingLeaf(lines) {
  const lp = lines.map((l) => { try { return JSON.parse(l); } catch (_e) { return null; } })
    .filter((o) => o && o.type === 'last-prompt');
  return lp.length ? lp[lp.length - 1].leafUuid : null;
}

t('rewindTo does BOTH halves: strands the tail and moves the leaf pointer to the anchor', () => {
  // Either half alone was measured to rewind nothing, so both are part of the contract.
  assert.strictEqual(deepestRooted(CHAIN), 4);                // root,A,B,C before
  const r = M.rewindTo(CHAIN, 'A', 'nowhere-uuid');
  assert.strictEqual(r.changed, true);
  assert.strictEqual(r.severed, 1);                           // only B was a child of A
  assert.strictEqual(deepestRooted(r.lines), 2);              // root,A — B and C are stranded
  assert.strictEqual(trailingLeaf(r.lines), 'A');             // and the leaf points at the anchor
});
t('rewindTo keeps every record and edits only the link of each severed branch', () => {
  const r = M.rewindTo(CHAIN, 'A', 'nowhere-uuid');
  assert.strictEqual(r.lines.length, CHAIN.length + 1);       // nothing dropped; one pointer added
  const b = JSON.parse(r.lines[2]);
  assert.strictEqual(b.uuid, 'B');                            // identity intact
  assert.strictEqual(b.message.content, 'after the anchor');  // content intact — history survives
  assert.strictEqual(b.parentUuid, 'nowhere-uuid');           // only the link changed
  assert.strictEqual(r.lines[3], CHAIN[3]);                   // C untouched: only direct children move
});
t('rewindTo severs ALL children of the anchor, not just the first', () => {
  const forked = CHAIN.concat([chainLine('D', 'A', 'a sibling branch off the anchor')]);
  const r = M.rewindTo(forked, 'A', 'nowhere-uuid');
  assert.strictEqual(r.severed, 2);                           // B and D
  assert.strictEqual(deepestRooted(r.lines), 2);              // no branch outlives the anchor
});
t('rewindTo to the current tip still writes the leaf pointer (no children to sever)', () => {
  const r = M.rewindTo(CHAIN, 'C', 'nowhere-uuid');
  assert.strictEqual(r.severed, 0);
  assert.strictEqual(trailingLeaf(r.lines), 'C');
});
t('rewindTo throws on an anchor absent from the transcript', () => {
  // Writing a leaf pointer at an unresolvable uuid would be a rewind that silently does nothing.
  assert.throws(() => M.rewindTo(CHAIN, 'no-such-uuid', 'nowhere-uuid'), /anchor uuid not present/);
});
t('rewindTo passes non-JSON lines through untouched', () => {
  const withJunk = ['', 'not json at all'].concat(CHAIN);
  const r = M.rewindTo(withJunk, 'A', 'nowhere-uuid');
  assert.strictEqual(r.lines[0], '');
  assert.strictEqual(r.lines[1], 'not json at all');
  assert.strictEqual(r.severed, 1);
});
t('rewindTo carries the sessionId off the anchor record, not from the caller', () => {
  const lines = [JSON.stringify({ type: 'user', uuid: 'A', parentUuid: null, sessionId: 'sid-42' })];
  const r = M.rewindTo(lines, 'A', 'nowhere-uuid');
  assert.strictEqual(JSON.parse(r.lines[r.lines.length - 1]).sessionId, 'sid-42');
});
t('rewindTo composes with exciseAt: rewind_summarize keeps the tombstoned craft line as the leaf', () => {
  // Option 3 anchors ON the craft-load line: it is tombstoned, stays rooted, and everything the
  // session did after it is stranded. Excise-first keeps the tombstone ON the leaf the rewind lands on.
  const lines = [
    chainLine('root', null, 'earlier work'),
    loadLine({ medium: 'code', uuid: 'K', parentUuid: 'root' }),
    chainLine('L', 'K', 'work done under laws:code'),
  ];
  const excised = M.exciseAt(lines, [1], 'prompt');
  const r = M.rewindTo(excised.lines, 'K', 'nowhere-uuid');
  assert.strictEqual(deepestRooted(r.lines), 2);              // root -> tombstoned craft line
  assert.strictEqual(trailingLeaf(r.lines), 'K');
  assert.strictEqual(M.craftMediumOf(JSON.parse(r.lines[1])), null); // craft body gone before summary
});

// ---- applySwitch(): the four options as one dispatch ---------------------------------------
// A transcript where laws:code loaded mid-conversation and work happened after it — the exact
// shape every option operates on.
function switchFixture() {
  return [
    chainLine('r1', null, 'work before any craft'),
    loadLine({ medium: 'code', uuid: 'CRAFT', parentUuid: 'r1' }),
    chainLine('w1', 'CRAFT', 'work done under laws:code'),
    chainLine('w2', 'w1', 'more work under laws:code'),
  ];
}
const ENV = { severUuid: 'nowhere-uuid', summaryUuid: 'sum-1', now: '2026-08-20T00:00:00.000Z' };
function decisionFor(lines) {
  return M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'prompt' });
}

t('applySwitch reject: transcript untouched and nothing to resume into', () => {
  const lines = switchFixture();
  const r = M.applySwitch(lines, decisionFor(lines), 'reject', ENV);
  assert.deepStrictEqual(r.lines, lines);
  assert.strictEqual(r.resume, false);
});
t('applySwitch tombstone: craft body emptied, every other line byte-identical, work still reachable', () => {
  const lines = switchFixture();
  const r = M.applySwitch(lines, decisionFor(lines), 'tombstone', ENV);
  assert.strictEqual(r.resume, true);
  assert.strictEqual(M.craftMediumOf(JSON.parse(r.lines[1])), null);   // craft excised
  assert.strictEqual(r.lines[2], lines[2]);                            // post-craft work untouched
  assert.strictEqual(r.lines[3], lines[3]);
  assert.strictEqual(deepestRooted(r.lines), 4);                       // full conversation kept
});
t('applySwitch rewind_discard: lands before the craft, so the craft never loaded', () => {
  const lines = switchFixture();
  const r = M.applySwitch(lines, decisionFor(lines), 'rewind_discard', ENV);
  assert.strictEqual(r.resume, true);
  assert.strictEqual(trailingLeaf(r.lines), 'r1');                     // the message before the craft
  assert.strictEqual(deepestRooted(r.lines), 1);                       // craft + all work stranded
  assert.strictEqual(r.lines.length, lines.length + 1);                // nothing deleted from the file
});
t('applySwitch rewind_summarize: excises first, then rewinds, then lands on the summary', () => {
  const lines = switchFixture();
  const r = M.applySwitch(lines, decisionFor(lines), 'rewind_summarize',
    { ...ENV, summary: 'Did X and Y under the previous craft.' });
  assert.strictEqual(r.resume, true);
  // the craft body is gone BEFORE the summary is attached — the ordering contract
  assert.strictEqual(M.craftMediumOf(JSON.parse(r.lines[1])), null);
  const last = JSON.parse(r.lines[r.lines.length - 1]);
  assert.strictEqual(last.parentUuid, 'CRAFT');                        // summary hangs off the anchor
  assert.strictEqual(last.message.content, 'Did X and Y under the previous craft.');
  assert.strictEqual(deepestRooted(r.lines), 3);                       // r1 -> tombstoned craft -> summary
});
t('applySwitch rewind_summarize refuses to invent an empty summary', () => {
  const lines = switchFixture();
  assert.throws(() => M.applySwitch(lines, decisionFor(lines), 'rewind_summarize', ENV), /summary is required/);
});
t('applySwitch rewind_discard refuses when the craft is the first message', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'CRAFT', parentUuid: null })];
  assert.throws(() => M.applySwitch(lines, decisionFor(lines), 'rewind_discard', ENV), /nothing precedes it/);
});
t('applySwitch rejects an unknown choice instead of doing nothing', () => {
  const lines = switchFixture();
  assert.throws(() => M.applySwitch(lines, decisionFor(lines), 'defer', ENV), /unknown choice/);
});
t('applySwitch refuses a decision that never triggered', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { incompatiblePairs: PAIRS, incomingMedium: 'prose' }); // compatible
  assert.strictEqual(d.trigger, false);
  assert.throws(() => M.applySwitch(lines, d, 'tombstone', ENV), /did not trigger/);
});
t('every option decide() advertises has an action, and vice versa', () => {
  // The menu the user is shown and the actions that can be enacted are the same set, by test.
  const lines = switchFixture();
  const advertised = decisionFor(lines).options.map((o) => o.id).sort();
  assert.deepStrictEqual(advertised, Object.keys(M.SWITCH_ACTIONS).sort());
});
t('no option ever removes a record from the transcript', () => {
  // The files-survive invariant's transcript half: history is stranded, never deleted.
  const lines = switchFixture();
  for (const choice of ['reject', 'tombstone', 'rewind_discard']) {
    const r = M.applySwitch(lines, decisionFor(lines), choice, ENV);
    assert.ok(r.lines.length >= lines.length, choice + ' dropped records');
    for (let i = 0; i < lines.length; i++) {
      assert.ok(r.lines[i] !== undefined, choice + ' lost record ' + i);
    }
  }
});

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
