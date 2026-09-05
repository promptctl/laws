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

// The single directed conflict edge, passed explicitly so tests never depend on the file on disk.
const EDGES = [["code", "prompt"]];   // directed: code engaged ⇒ refuse incoming prompt

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

// A craft-load line for an arbitrary base directory — the shape the plugin cache and the repo
// each produce, so the detector can be asked about layouts loadLine() does not spell.
function loadLineAt(baseDir) {
  return JSON.stringify({
    type: 'user', isMeta: true, uuid: 'x' + (++uidSeq), parentUuid: null,
    timestamp: '2026-08-09T00:00:00.000Z', sourceToolUseID: 'toolu_x',
    message: { role: 'user', content: [{ type: 'text', text: 'Base directory for this skill: ' + baseDir + '\n\n<SKILL body>' }] },
  });
}

// ---- what counts as a craft is DERIVED, not enumerated ---------------------------------------
// skill-router.sh's guard reads the craft off the `laws:` namespace so "a new craft is covered the
// day it is added". This half once recognised only five hardcoded names, so a craft added to
// plugins/laws/skills/ and wired into incompatible-crafts.txt was enforced by the router and
// invisible here — two enforcers, one policy file, different answers, no symptom.
// [LAW:single-enforcer]
t('a craft the enumerated list never named is still recognised as a load', () => {
  // `ticket` is a real plugins/laws/skills/ directory absent from the old MEDIA list.
  assert.strictEqual(M.craftMediumOf(JSON.parse(loadLine({ medium: 'ticket', uuid: 'T' }))), 'ticket');
  const d = M.decide([loadLine({ medium: 'ticket', uuid: 'T' })],
    { conflictEdges: [['ticket', 'prompt']], incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true, 'the gate is blind to a craft the router already enforces');
  assert.deepStrictEqual(d.current, ['ticket']);
});

t('both shipped base-dir layouts name the craft, and another plugin’s skills are not crafts', () => {
  assert.strictEqual(M.craftMediumOf(JSON.parse(loadLineAt('/Users/x/code/repo/plugins/laws/skills/code'))), 'code');
  // the plugin cache interposes a version directory between laws/ and skills/
  assert.strictEqual(M.craftMediumOf(JSON.parse(loadLineAt('/Users/x/.claude/plugins/cache/promptctl/laws/0.24.1/skills/code'))), 'code');
  // ...and the namespace is the discriminator, so a sibling plugin's skill is not a craft even
  // when its directory name collides. Matching on /skills/ alone would tombstone it.
  assert.strictEqual(M.craftMediumOf(JSON.parse(loadLineAt('/Users/x/code/repo/plugins/memento/skills/code'))), null);
});

// ---- policy -------------------------------------------------------------------------------
t('parsePolicy strips comments and blanks, keeps pairs', () => {
  const p = M.parsePolicy('# header\n\ncode prompt  # inline\n\n');
  assert.deepStrictEqual(p.edges, [['code', 'prompt']]);
  assert.deepStrictEqual(p.malformed, []);
});

// THE DIVERGENCE CASE, and it needs its twin in skill-router.test.sh to mean anything. A line
// that is not exactly two tokens used to be read one way here (truncate to the first two — a
// LIVE code→prompt edge) and another way in the router's `read -r from to` (third token swallowed
// into $to — a permanent no-op). Same file, two enforcers, opposite rules, and nothing anywhere
// would have noticed. Both now refuse the line, and both say so. [LAW:single-enforcer]
t('parsePolicy refuses a line that is not exactly two tokens', () => {
  const p = M.parsePolicy('code prompt extra-note\ncode\ncode prompt\n');
  assert.deepStrictEqual(p.edges, [['code', 'prompt']], 'a malformed line was truncated into an edge');
  assert.deepStrictEqual(p.malformed, ['code prompt extra-note', 'code']);
});

t('a malformed policy line is not enforced by the gate', () => {
  const edges = M.parsePolicy('code prompt extra-note\n').edges;
  const d = M.decide([loadLine({ medium: 'code' })], { conflictEdges: edges, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, false, 'the gate enforced an edge the router treats as a no-op');
});

t('loadPolicy announces every malformed line on stderr and returns only the well-formed edges', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'laws-policy-'));
  const file = path.join(dir, 'incompatible-crafts.txt');
  fs.writeFileSync(file, '# a policy with one good line and one typo\ncode prompt extra-note\ncode prompt\n');
  const written = [];
  const realWrite = process.stderr.write;
  process.stderr.write = (s) => { written.push(String(s)); return true; };
  try { var edges = M.loadPolicy(file); } finally { process.stderr.write = realWrite; }
  assert.deepStrictEqual(edges, [['code', 'prompt']], 'a typo cost the file its good edge');
  assert.strictEqual(written.length, 1, 'expected exactly one warning, got: ' + JSON.stringify(written));
  assert.strictEqual(written[0], M.MALFORMED_WARNING + 'code prompt extra-note\n');
});
t('conflictsWith is DIRECTED: the reverse ordering is a different question', () => {
  // (engaged, incoming). code degrades prompts; prompt does not degrade code.
  assert.strictEqual(M.conflictsWith('code', 'prompt', EDGES), true);
  assert.strictEqual(M.conflictsWith('prompt', 'code', EDGES), false);  // NOT symmetric
  assert.strictEqual(M.conflictsWith('code', 'prose', EDGES), false);   // compatible
  assert.strictEqual(M.conflictsWith('code', 'code', EDGES), false);    // not self-conflicting
});

// ---- decide(): the corrected trigger rule -------------------------------------------------
t('pre-load: code engaged + incoming prompt → triggers, switches away from code', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true);
  assert.deepStrictEqual(d.current, ['code']);
  assert.strictEqual(d.incoming, 'prompt');
  assert.deepStrictEqual(d.conflictIndices, [0]);
  assert.strictEqual(d.rewind.summarizeTo, 'A');           // the code load line
  assert.strictEqual(d.rewind.discardTo, null);            // its parentUuid
  assert.deepStrictEqual(d.options.map((o) => o.id), ['reject', 'tombstone', 'rewind_summarize', 'rewind_discard']);
});
t('pre-load: code engaged + incoming prose → NO trigger (compatible coexist)', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prose' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'compatible');
});
t('pre-load: reload of the same craft → NO trigger (same-medium)', () => {
  const lines = [loadLine({ medium: 'code', uuid: 'A' })];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'code' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'same-medium');
});
t('pre-load: nothing engaged + incoming prompt → NO trigger (first-craft)', () => {
  const d = M.decide([chatLine('hi')], { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'first-craft');
});
// THE REVERSE ORDERING IS ALLOWED, and this is the regression that would otherwise reappear
// silently. Writing a prompt and then turning to code is ordinary work; only code-then-prompt
// corrupts anything. A gate that refused here would deny a legitimate load AND offer a
// tombstone-or-rewind switch, so the false refusal costs real conversation, not just a warning.
t('pre-load: prompt engaged + incoming code → NO trigger (the edge runs one way)', () => {
  const lines = [loadLine({ medium: 'prompt', uuid: 'P' })];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'code' });
  assert.strictEqual(d.trigger, false);
  assert.strictEqual(d.reason, 'compatible');
});
t('pre-load: compatible set (code+prose+ticket-ish) + incoming prompt → triggers, names code', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    chatLine('work'),
    loadLine({ medium: 'prose', uuid: 'B', ts: '2026-08-09T00:01:00.000Z' }),
  ];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true);
  assert.deepStrictEqual(d.current, ['code']);                   // the conflicting one, not the newest (prose)
  assert.deepStrictEqual(d.conflictIndices, [0]);
});
t('post-hoc: code+prompt both on disk → triggers; newest is incoming', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prompt', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' }),
  ];
  const d = M.decide(lines, { conflictEdges: EDGES });
  assert.strictEqual(d.trigger, true);
  assert.strictEqual(d.incoming, 'prompt');                // newest
  assert.deepStrictEqual(d.current, ['code']);
});
t('post-hoc: prompt THEN code on disk → NO trigger (the harmless ordering)', () => {
  const lines = [
    loadLine({ medium: 'prompt', uuid: 'P', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'code', uuid: 'C', ts: '2026-08-09T00:05:00.000Z' }),
  ];
  const d = M.decide(lines, { conflictEdges: EDGES });
  assert.strictEqual(d.trigger, false, 'the repair path must not tombstone a legitimate ordering');
});
t('post-hoc: code+prose both on disk → NO trigger', () => {
  const lines = [
    loadLine({ medium: 'code', uuid: 'A', ts: '2026-08-09T00:00:00.000Z' }),
    loadLine({ medium: 'prose', uuid: 'B', ts: '2026-08-09T00:05:00.000Z' }),
  ];
  const d = M.decide(lines, { conflictEdges: EDGES });
  assert.strictEqual(d.trigger, false);
});
// ---- more than one engaged craft conflicts with the incoming one ----------------------------
// Unreachable under the single shipped pair, so these use a TWO-pair policy - the same shape
// incompatible-crafts.txt is explicitly designed to grow into. The contract under test: a switch
// retires the whole conflicting SET. Retiring one member reports success and leaves the session
// still unable to load the craft it switched to, which is the defect the gate exists to prevent.
const TWO_EDGES = [['code', 'prompt'], ['prose', 'prompt']];  // two crafts, each refusing incoming prompt
// code and prose are compatible with each OTHER, so both can be engaged; both conflict with prompt.
// The uuids are pinned rather than generated, because the rewind assertions below are ABOUT which
// record the anchor lands on — a fixture with unpredictable uuids could not tell the oldest-anchor
// contract from the newest-anchor bug it exists to catch.
const said = (uuid, parentUuid, text) => JSON.stringify({
  type: 'user', uuid, parentUuid, message: { role: 'user', content: [{ type: 'text', text }] },
});
const twoConflicts = () => [
  said('c0', null, 'before any craft'),
  loadLine({ medium: 'code', uuid: 'A', parentUuid: 'c0', ts: '2026-08-09T00:00:00.000Z' }),
  said('c1', 'A', 'work under code'),
  loadLine({ medium: 'prose', uuid: 'B', parentUuid: 'c1', ts: '2026-08-09T00:01:00.000Z' }),
  said('c2', 'B', 'work under prose'),
];

t('toRawLines drops the split artifact and nothing else', () => {
  // Both callers depend on splitting the same way — run() and the live path — and
  // the line numbering decide() reports is only meaningful if they agree. The `if` here must not
  // become a `while`: stripping ALL trailing blanks would shift every index for a transcript with a
  // blank last line, silently moving what conflictIndices point at.
  assert.deepStrictEqual(M.toRawLines('a\nb'), ['a', 'b'], 'no trailing newline');
  assert.deepStrictEqual(M.toRawLines('a\nb\n'), ['a', 'b'], 'one trailing newline');
  assert.deepStrictEqual(M.toRawLines('a\nb\n\n'), ['a', 'b', ''], 'a real blank line survives');
  assert.deepStrictEqual(M.toRawLines('a\nb\n\n\n'), ['a', 'b', '', ''], 'only ONE artifact is dropped');
});

t('toRawLines keeps interior blanks and handles an empty transcript', () => {
  assert.deepStrictEqual(M.toRawLines('a\n\nb\n'), ['a', '', 'b']);
  assert.deepStrictEqual(M.toRawLines(''), []);
  // One blank line AND a terminator: only the terminator's artifact is dropped, so a record remains.
  assert.deepStrictEqual(M.toRawLines('\n'), ['']);
  assert.deepStrictEqual(M.toRawLines('only'), ['only']);
});

t('two conflicting crafts engaged → BOTH are named, oldest first', () => {
  const d = M.decide(twoConflicts(), { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, true);
  assert.deepStrictEqual(d.current, ['code', 'prose']);
  assert.deepStrictEqual(d.conflictIndices, [1, 3]);
});

t('the conflicting set is ALSO named by uuid, for consumers that cannot use line numbers', () => {
  // The live enactment (../injector/live-switch.js) works on an in-memory array that holds different
  // records than the file does, in both directions — so a line index means nothing to it and uuid is
  // the only naming that crosses.
  const d = M.decide(twoConflicts(), { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  assert.deepStrictEqual(d.conflicts, [{ uuid: 'A', medium: 'code' }, { uuid: 'B', medium: 'prose' }]);
});

t('the two namings of the conflicting set can never disagree', () => {
  // Both are derived from one ordered array; this is the assertion that fails if they ever stop
  // being. [LAW:one-source-of-truth]
  const lines = twoConflicts();
  const d = M.decide(lines, { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.conflicts.length, d.conflictIndices.length);
  d.conflictIndices.forEach((lineIndex, i) => {
    assert.strictEqual(JSON.parse(lines[lineIndex]).uuid, d.conflicts[i].uuid);
    assert.strictEqual(d.conflicts[i].medium, d.current[i]);
  });
});

t('the rewind anchor is the FIRST conflict named by uuid', () => {
  // live-switch resolves the live conversation by this uuid, so the two must be the same message.
  const d = M.decide(twoConflicts(), { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.rewind.summarizeTo, d.conflicts[0].uuid);
});

t('a compatible craft is never swept in with the conflicting ones', () => {
  // Only prompt conflicts with code here, so prose must be left alone despite being engaged.
  const d = M.decide(twoConflicts(), { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.deepStrictEqual(d.current, ['code']);
  assert.deepStrictEqual(d.conflictIndices, [1]);
});

t('tombstone retires EVERY conflicting craft, not just one', () => {
  const lines = twoConflicts();
  const d = M.decide(lines, { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  const out = M.applySwitch(lines, d, 'tombstone', {}).lines;
  // The contract is observable through the module's own detector: after the switch, neither
  // retired craft still reads as a live load, so a resumed session engages neither.
  const stillLoaded = out.map((l) => { try { return M.craftMediumOf(JSON.parse(l)); } catch (_e) { return null; } })
                         .filter(Boolean);
  assert.deepStrictEqual(stillLoaded, [], 'a conflicting craft survived the switch: ' + stillLoaded);
});

t('the rewind anchor is the OLDEST conflict, so no older one survives above it', () => {
  const d = M.decide(twoConflicts(), { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  // Anchoring on the newest (uuid B) would rewind to a point where code is ALREADY loaded.
  assert.strictEqual(d.rewind.summarizeTo, 'A');
  assert.strictEqual(d.rewind.discardTo, 'c0');
});

t('rewind_discard leaves no conflicting craft reachable', () => {
  const lines = twoConflicts();
  const d = M.decide(lines, { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  const out = M.applySwitch(lines, d, 'rewind_discard', { severUuid: 'sev' }).lines;
  const leaf = JSON.parse(out[out.length - 1]);
  assert.strictEqual(leaf.type, 'last-prompt');
  assert.strictEqual(leaf.leafUuid, 'c0', 'landed somewhere a conflicting craft is still loaded');
  // What matters is REACHABILITY, not attachment: a resumed session rebuilds the conversation by
  // walking up from the leaf, so the test walks the same chain. Records below the severed link
  // remain in the file by design (the rewind is non-destructive) and are simply never reached.
  const byUuid = new Map();
  for (const l of out) { let o; try { o = JSON.parse(l); } catch (_e) { continue; } if (o.uuid) byUuid.set(o.uuid, o); }
  const reached = [];
  for (let o = byUuid.get(leaf.leafUuid); o; o = o.parentUuid ? byUuid.get(o.parentUuid) : null) reached.push(o);
  const survivors = reached.map(M.craftMediumOf).filter(Boolean);
  assert.deepStrictEqual(survivors, [], 'a conflicting craft is still reachable: ' + survivors);
});

t('rewind_summarize retires every conflicting craft in the FILE, not just the reachable one', () => {
  const lines = twoConflicts();
  const d = M.decide(lines, { conflictEdges: TWO_EDGES, incomingMedium: 'prompt' });
  const out = M.applySwitch(lines, d, 'rewind_summarize',
    { severUuid: 'sev', summaryUuid: 'sum', now: '2026-08-09T00:09:00.000Z', summary: 'what I did' }).lines;
  // Reachability alone cannot see this: the anchor is the OLDEST conflict, so every other one is
  // already severed below it. The assertion is on the file, because the rewind is non-destructive
  // by design — the orphaned branch stays on disk, and a craft left live there is a retired craft
  // that is still written down as loaded. [LAW:no-silent-failure]
  const live = out.map((l) => { try { return M.craftMediumOf(JSON.parse(l)); } catch (_e) { return null; } })
                  .filter(Boolean);
  assert.deepStrictEqual(live, [], 'a conflicting craft is still a live load on disk: ' + live);
  const leaf = JSON.parse(out[out.length - 1]);
  assert.strictEqual(leaf.parentUuid, 'A', 'the summary must hang off the oldest conflict');
});

// ---- debris on disk is not an engaged craft -------------------------------------------------
// A rewind severs without deleting, so the retired craft survives as a well-formed craft-load
// line on an orphan branch. Counting it again is not merely untidy: the rewind anchor is the
// OLDEST conflict, so the stale record WINS, and the second switch of a session anchors inside
// a branch the resumed session will never see.
t('a craft load left on a severed branch is not engaged on the next switch', () => {
  let lines = [
    said('r0', null, 'start'),
    loadLine({ medium: 'code', uuid: 'K1', parentUuid: 'r0', ts: '2026-08-09T00:01:00.000Z' }),
    said('w1', 'K1', 'work under the first code load'),
  ];
  const first = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
  lines = M.applySwitch(lines, first, 'rewind_discard', { severUuid: 'SEV' }).lines;

  // The session resumes at r0 and does fresh work, engaging code again.
  lines.push(said('r1', 'r0', 'fresh work'),
             loadLine({ medium: 'code', uuid: 'K2', parentUuid: 'r1', ts: '2026-08-09T00:05:00.000Z' }));

  const second = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.deepStrictEqual(second.current, ['code'], 'the severed load was counted a second time');
  assert.strictEqual(second.rewind.summarizeTo, 'K2', 'the anchor landed on the severed orphan');
  assert.strictEqual(second.rewind.discardTo, 'r1');
  // ...and the discard that used to throw now lands in the live conversation.
  const out = M.applySwitch(lines, second, 'rewind_discard', { severUuid: 'SEV2' }).lines;
  assert.strictEqual(JSON.parse(out[out.length - 1]).leafUuid, 'r1');
});

t('a subagent sidechain craft load is not engaged in the parent session', () => {
  // The router isolates subagents by keying craft locks on agent_id; the gate ignoring
  // isSidechain is that same isolation broken on the other side.
  const sidechained = (line) => {
    const o = JSON.parse(line);
    o.isSidechain = true;
    return JSON.stringify(o);
  };
  const lines = [
    said('a0', null, 'start'),
    sidechained(loadLine({ medium: 'code', uuid: 'SC', parentUuid: 'a0' })),
  ];
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
  assert.strictEqual(d.trigger, false, 'a subagent’s craft load blocked the parent session');
  assert.strictEqual(d.reason, 'first-craft');
});

t('recommendation: shallow → tombstone, deep → rewind_summarize', () => {
  const shallow = [loadLine({ medium: 'code', uuid: 'A' })];
  assert.strictEqual(M.decide(shallow, { conflictEdges: EDGES, incomingMedium: 'prompt' }).recommended, 'tombstone');
  // force "deep" by setting a tiny threshold
  assert.strictEqual(M.decide(shallow, { conflictEdges: EDGES, incomingMedium: 'prompt', largeTokens: 1 }).recommended, 'rewind_summarize');
});
t('decide throws without conflictEdges (no silent never-trigger)', () => {
  assert.throws(() => M.decide([loadLine({ medium: 'code' })], { incomingMedium: 'prompt' }), /conflictEdges is required/);
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
  const rb = M.run(bad, { conflictEdges: EDGES });
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
  const ro = M.run(ok, { conflictEdges: EDGES });
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
  return M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prompt' });
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
  const d = M.decide(lines, { conflictEdges: EDGES, incomingMedium: 'prose' }); // compatible
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
