#!/usr/bin/env node
// Tests for bin/laws-switch — the in-session half of the craft switch.
//
// This CLI grew real branching: a live-vs-relaunch fork, a per-craft retire loop with two distinct
// failure arms, and reason-specific messaging. None of that is exercisable by unit-testing a
// function, because the behaviour under test IS the process — its stdout, its stderr, its exit code
// and what it leaves on disk. So each case runs the real script as a subprocess against a stub
// socket, exactly as a session would.
//
// It runs against a COPY of the plugin, never the working tree. Two cases deliberately break the
// router (non-executable, and exiting non-zero) to reach the failure arms, and breaking a shipped
// file in place is how a mutated source once survived a run and read as ordinary source afterwards.
//
// [LAW:no-silent-failure] the arms under test are precisely the ones that report a partial switch;
//   a regression in them would let the CLI tell a user "nothing changed" after their conversation
//   had already been rewound.

'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const { execFileSync, spawn } = require('child_process');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
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

// One copy of the plugin for the whole suite; the two cases that break the router restore it.
const PLUGIN_SRC = path.join(__dirname, '..');
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), 'laws-switch-test-'));
execFileSync('cp', ['-R', PLUGIN_SRC, path.join(WORK, 'laws')]);
const SWITCH = path.join(WORK, 'laws', 'bin', 'laws-switch');
const ROUTER = path.join(WORK, 'laws', 'hooks', 'scripts', 'skill-router.sh');
const ROUTER_REAL = fs.readFileSync(ROUTER, 'utf8');
const restoreRouter = () => { fs.writeFileSync(ROUTER, ROUTER_REAL); fs.chmodSync(ROUTER, 0o755); };

const SID = '11111111-2222-3333-4444-555555555555';
const pending = (dir) => fs.writeFileSync(path.join(dir, 'pending.json'), JSON.stringify({
  sessionId: SID, transcript: '/tmp/t.jsonl', current: 'code', incomingMedium: 'prompt',
}));

// A stub hosted session: one canned answer, and a record of what it was asked.
function serve(dir, answer) {
  const seen = [];
  const server = net.createServer((socket) => {
    let buf = '';
    socket.setEncoding('utf8');
    socket.on('error', () => {});
    socket.on('data', (d) => {
      buf += d;
      const end = buf.indexOf('\n');
      if (end === -1) return;
      seen.push(JSON.parse(buf.slice(0, end)));
      socket.end(JSON.stringify(answer) + '\n');
    });
  });
  server.listen(path.join(dir, 'switch.sock'));
  return { seen, close: () => server.close() };
}

// The engaged-craft lock, laid out the way the router lays it out.
const sanitize = (s) => s.replace(/[^A-Za-z0-9_-]/g, '_');
function lockSlot(tmp, crafts) {
  const slot = path.join(tmp, 'laws-craft-lock', sanitize(SID), 'main');
  fs.mkdirSync(slot, { recursive: true });
  for (const c of crafts) fs.writeFileSync(path.join(slot, sanitize(c)), '');
  return slot;
}

// ASYNC on purpose. The stub session lives in this process, so a synchronous spawn would block the
// event loop that has to answer it — the CLI would sit there until its own timeout and every case
// would test the timeout path instead of the one it names.
function run(args, { dir, tmp, env = {} }) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [SWITCH, ...args], {
      env: { ...process.env, LAWS_SWITCH_DIR: dir, TMPDIR: tmp, ...env },
    });
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

// Each case gets its own handoff dir AND its own TMPDIR, so the lock slots cannot collide.
function bed() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'laws-sw-dir-'));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'laws-sw-tmp-'));
  pending(dir);
  return { dir, tmp };
}

// ---- the live path ------------------------------------------------------------------------------

t('a live switch reports success, consumes the pending decision, and releases the craft', async () => {
  const { dir, tmp } = bed();
  const slot = lockSlot(tmp, ['code']);
  const server = serve(dir, { ok: true, rewound: false, tombstoned: 1, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 0, out.stderr);
  assert.match(out.stdout, /Switched to laws:prompt, live/);
  assert.match(out.stdout, /this session was not restarted/);
  // The stub session does not consume it — the real one does, and that is asserted in
  // switch-request.test.js. What matters here is that the CLI does not remove it either: the offer
  // belongs to the process that applied the switch.
  assert.ok(fs.existsSync(path.join(dir, 'pending.json')), 'the CLI removed an offer it does not own');
  assert.ok(!fs.existsSync(path.join(dir, 'request.json')), 'a relaunch request was written on the live path');
  assert.deepStrictEqual(fs.readdirSync(slot), [], 'the craft lock was not released');
});

t('the request carries the pending decision and the chosen option', async () => {
  const { dir, tmp } = bed();
  lockSlot(tmp, ['code']);
  const server = serve(dir, { ok: true, rewound: true, tombstoned: 0, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  await run(['rewind_discard'], { dir, tmp });
  server.close();
  // ONLY the decision. The transcript, craft and session are the offer's to state, and the session
  // reads them from the offer itself — so a caller cannot substitute them, and does not send them.
  assert.deepStrictEqual(server.seen, [{ choice: 'rewind_discard' }]);
});

t('a summary reaches the session verbatim', async () => {
  const { dir, tmp } = bed();
  lockSlot(tmp, ['code']);
  const server = serve(dir, { ok: true, rewound: true, tombstoned: 1, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  await run(['rewind_summarize', '--summary', 'I did the thing'], { dir, tmp });
  server.close();
  assert.strictEqual(server.seen[0].summary, 'I did the thing');
});

t('EVERY retired craft is released, not just the first', async () => {
  // A switch can retire more than one engaged craft; releasing one and reporting success would leave
  // the session unable to load the craft it switched to.
  const { dir, tmp } = bed();
  const slot = lockSlot(tmp, ['code', 'prose']);
  const server = serve(dir, { ok: true, rewound: false, tombstoned: 2, changed: true, switchedFrom: ['code', 'prose'], switchedTo: 'prompt' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 0, out.stderr);
  assert.deepStrictEqual(fs.readdirSync(slot), []);
  assert.match(out.stdout, /laws:code, laws:prose/);
});

t('a rewind is reported as a rewind, and a tombstone as a tombstone', async () => {
  const { dir: d1, tmp: t1 } = bed();
  lockSlot(t1, ['code']);
  let server = serve(d1, { ok: true, rewound: true, tombstoned: 0, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  const rewound = await run(['rewind_discard'], { dir: d1, tmp: t1 });
  server.close();
  assert.match(rewound.stdout, /rewound in place/);
  assert.ok(!/Retired laws:code in place/.test(rewound.stdout));

  const { dir: d2, tmp: t2 } = bed();
  lockSlot(t2, ['code']);
  server = serve(d2, { ok: true, rewound: false, tombstoned: 1, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  const stubbed = await run(['tombstone'], { dir: d2, tmp: t2 });
  server.close();
  assert.match(stubbed.stdout, /Retired laws:code in place/);
  assert.ok(!/rewound in place/.test(stubbed.stdout));
});

// ---- what it says when the switch did not complete ----------------------------------------------

t('a switch that THREW warns the conversation may already have been rewound', async () => {
  // The arm that matters most: applyLiveSwitch drives the app's own rewind before it can reply, and
  // that mutation has no rollback.
  const { dir, tmp } = bed();
  const server = serve(dir, { ok: false, reason: 'the-switch-threw', detail: 'the store was gone' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /may have run PART WAY/);
  assert.ok(!/Nothing was changed/.test(out.stderr), 'claimed nothing changed after a partial switch');
});

t('a session that accepted and then went quiet gets the same warning', async () => {
  const { dir, tmp } = bed();
  const server = net.createServer((socket) => socket.destroy());
  server.listen(path.join(dir, 'switch.sock'));
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /may have run PART WAY/);
});

t('a switch whose ANSWER failed to encode still warns — it ran before the reply did', async () => {
  // The reason this arm exists: the server's encode failure happens AFTER applyLiveSwitch has driven
  // the app's own rewind. Enumerating the unsafe reasons is what let this one be forgotten.
  const { dir, tmp } = bed();
  const server = serve(dir, { ok: false, reason: 'the-switch-ran-but-its-answer-could-not-be-encoded' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /may have run PART WAY/);
});

t('a reason nobody anticipated is treated as uncertain, not as nothing', async () => {
  // The whole point of enumerating the SAFE side: an unknown reason defaults to the warning.
  const { dir, tmp } = bed();
  const server = serve(dir, { ok: false, reason: 'some-future-reason-nobody-listed' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.match(out.stderr, /may have run PART WAY/);
});

t('a refusal BY NAME is the one case that may claim nothing changed', async () => {
  const { dir, tmp } = bed();
  const server = serve(dir, { ok: false, reason: 'the-switch-no-longer-applies', detail: 'compatible', mutated: false });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /the-switch-no-longer-applies/);
  // The session SAID it refused before touching anything, so this may say so plainly. The claim
  // rests on `mutated: false` travelling back, not on this file recognising the reason string.
  assert.match(out.stderr, /Nothing was changed/);
});

t('a refusal that does NOT state its effect is treated as uncertain', async () => {
  // Absence of the fact is not evidence of safety: an omission can only make the message more
  // cautious, never turn it into a false reassurance.
  const { dir, tmp } = bed();
  const silent = serve(dir, { ok: false, reason: 'the-switch-no-longer-applies' });
  const out = await run(['tombstone'], { dir, tmp });
  silent.close();
  assert.match(out.stderr, /may have run PART WAY/);
});

t('a refused switch leaves the pending decision in place to retry', async () => {
  const { dir, tmp } = bed();
  const server = serve(dir, { ok: false, reason: 'the-switch-no-longer-applies', mutated: false });
  await run(['tombstone'], { dir, tmp });
  server.close();
  assert.ok(fs.existsSync(path.join(dir, 'pending.json')));
});

// ---- the relaunch fallback ----------------------------------------------------------------------

t('no hosted session falls back to recording a request for the launcher', async () => {
  const { dir, tmp } = bed();
  const out = await run(['tombstone'], { dir, tmp, env: { BUN_INSPECT: '' } });
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /BUN_INSPECT is unset/);
  const request = JSON.parse(fs.readFileSync(path.join(dir, 'request.json'), 'utf8'));
  assert.deepStrictEqual(request, {
    sessionId: SID, transcript: '/tmp/t.jsonl', incomingMedium: 'prompt', choice: 'tombstone',
  });
  assert.ok(!fs.existsSync(path.join(dir, 'pending.json')), 'the decision was recorded twice');
});

t('reject needs no session at all and changes nothing', async () => {
  const { dir, tmp } = bed();
  const out = await run(['reject'], { dir, tmp });
  assert.strictEqual(out.status, 0, out.stderr);
  assert.match(out.stdout, /Staying in laws:code/);
  assert.ok(!fs.existsSync(path.join(dir, 'request.json')));
  assert.ok(!fs.existsSync(path.join(dir, 'pending.json')));
});

// ---- the retire arm's own failures --------------------------------------------------------------

t('a router that exits non-zero is reported, and the switch still counts as applied', async () => {
  const { dir, tmp } = bed();
  fs.writeFileSync(ROUTER, '#!/bin/sh\necho "router said no" >&2\nexit 1\n');
  fs.chmodSync(ROUTER, 0o755);
  const server = serve(dir, { ok: true, rewound: false, tombstoned: 1, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  restoreRouter();
  assert.strictEqual(out.status, 0, 'a failed release must not undo a switch that already happened');
  assert.match(out.stderr, /could not be released \(router said no\)/);
  assert.match(out.stderr, /may still be refused this session/);
  assert.match(out.stdout, /Switched to laws:prompt/);
});

t('a router that cannot be launched at all still names a cause', async () => {
  // The regression this guards: spawn failure leaves status null and stderr empty, so reading stderr
  // alone printed a warning with an empty parenthesis — loud in form and silent in content.
  const { dir, tmp } = bed();
  fs.chmodSync(ROUTER, 0o644);
  const server = serve(dir, { ok: true, rewound: false, tombstoned: 1, changed: true, switchedFrom: ['code'], switchedTo: 'prompt' });
  const out = await run(['tombstone'], { dir, tmp });
  server.close();
  restoreRouter();
  assert.match(out.stderr, /could not be released/);
  assert.ok(!/released \(\)/.test(out.stderr), 'the warning named no cause at all');
  // The MESSAGE, not the error object stringified around it: "(Error: spawn ... EACCES)" is what
  // reading the wrong half of the pair produces, and it reads as a stack trace leaking into a
  // user-facing warning.
  assert.ok(!/\(Error:/.test(out.stderr), 'the cause was the error object, not its message: ' + out.stderr);
});

// ---- argument handling --------------------------------------------------------------------------

t('a relaunch that cannot end the session names why, and says the choice is recorded', async () => {
  // The fallback arm's own failure path: the request is on disk, but the session could not be told
  // to exit, so the user has to be told both halves.
  const { dir, tmp } = bed();
  const out = await run(['tombstone'], { dir, tmp, env: { BUN_INSPECT: 'ws://127.0.0.1:1/nope' } });
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /could not end the session/);
  assert.match(out.stderr, /Exit manually/);
  assert.ok(!/session \(\)/.test(out.stderr), 'named no cause at all');
  assert.ok(!/\(Error:/.test(out.stderr), 'the cause was the error object, not its message');
  assert.ok(fs.existsSync(path.join(dir, 'request.json')), 'the choice was not recorded for the launcher');
});

t('an unknown choice is refused before anything is touched', async () => {
  const { dir, tmp } = bed();
  const out = await run(['obliterate'], { dir, tmp });
  assert.strictEqual(out.status, 2);
  assert.match(out.stderr, /unknown choice/);
  assert.ok(fs.existsSync(path.join(dir, 'pending.json')));
});

t('rewind_summarize without a summary refuses rather than summarising nothing', async () => {
  const { dir, tmp } = bed();
  const out = await run(['rewind_summarize'], { dir, tmp });
  assert.strictEqual(out.status, 2);
  assert.match(out.stderr, /needs --summary/);
});

t('no pending decision is its own message, not a crash', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'laws-sw-dir-'));
  const out = await run(['tombstone'], { dir, tmp: dir });
  assert.strictEqual(out.status, 1);
  assert.match(out.stderr, /no pending craft switch/);
});

process.on('exit', () => { try { fs.rmSync(WORK, { recursive: true, force: true }); } catch { /* best effort */ } });

runAll();
