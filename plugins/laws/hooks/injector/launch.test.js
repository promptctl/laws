#!/usr/bin/env node
// Unit tests for launch.js — the fail-safe that decides whether a hosted session became the session.
//
// Every case here runs against STUB plans, never the real bundle. That is not only for speed: the
// live failure modes this file describes make Claude Code write to the user's own config (it records
// a renderer that failed to start), and a suite that mutates the machine it runs on is a suite nobody
// can run twice. The real bundle is exercised by hand — see SEAMS.md for what was verified live.
//
// `run` is driven through a fake spawn, so the verdict rules are tested as behaviour (what the
// launcher concludes from what it observed) rather than by reaching into its internals.

'use strict';
const assert = require('assert');
const { EventEmitter } = require('events');
const L = require('./launch.js');

let pass = 0, fail = 0;
const results = [];
function t(name, fn) { results.push({ name, fn }); }
async function runAll() {
  for (const { name, fn } of results) {
    try { await fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

// A stand-in child that lets a test say what the host reported and when it exited. It mirrors the
// one ordering that matters: a real pipe ends AFTER the process is reaped, and `exitFirst` makes a
// case deliver its last report only after 'exit' — the race that would otherwise re-run a plan that
// did paint.
function fakeSpawn(script, { endAfterExit = 0 } = {}) {
  return () => {
    const child = new EventEmitter();
    const channel = new EventEmitter();
    child.stdio = [null, null, null, channel];
    let exited = false;
    const end = () => { if (!channel.ended) { channel.ended = true; channel.emit('end'); } };
    child.kill = () => { child.killed = true; child.emit('exit', null, 'SIGKILL'); end(); };
    for (const step of script) setTimeout(() => {
      if (step.report !== undefined) channel.emit('data', Buffer.from(step.report + '\n'));
      if (step.raw !== undefined) channel.emit('data', Buffer.from(step.raw));
      if (step.channelError) channel.emit('error', new Error(step.channelError));
      if (step.exit !== undefined) { exited = true; child.emit('exit', step.exit, step.signalName ?? null); if (!endAfterExit) end(); }
      if (step.spawnError) child.emit('error', new Error(step.spawnError));
    }, step.at);
    if (endAfterExit) setTimeout(end, endAfterExit);
    return child;
  };
}
const hosted = { name: 'hosted', command: 'node', args: [], env: {}, reports: true };
const stock = { name: 'stock', command: 'claude', args: [], env: {}, reports: false };
const fast = { deadlineMs: 300, settleMs: 150, interactive: true };

// ---- what counts as having become the session --------------------------------------------------

t('a plan that paints and stays is the session', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'painted' }, { at: 250, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a plan that paints and then dies inside the settle window never became a session', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'painted' }, { at: 40, exit: 1 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /painted, then exited 1/);
});

t('a throw after painting still reaches the reason, which is the usual real diagnosis', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 3, report: 'started' }, { at: 5, report: 'painted' }, { at: 15, report: 'boot-threw Cannot read properties of undefined' }, { at: 30, exit: 1 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /never became a session: boot-threw Cannot read properties of undefined/);
});

t('...but a CLEAN early exit is a one-shot command finishing, and is never re-run', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'painted' }, { at: 40, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('...and outside an interactive terminal no exit is ever re-run, whatever the code', async () => {
  const r = await L.run(hosted, { ...fast, interactive: false, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'painted' }, { at: 40, exit: 1 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 1 });
});

t('a headless run that STARTED is not killed for taking its time before printing', async () => {
  // The deadline guards the host coming up. For a non-interactive run `started` is the end of boot;
  // killing it for thinking longer than the deadline would end work that was going fine.
  const spawn = fakeSpawn([{ at: 5, report: 'started' }, { at: 500, exit: 0 }]);
  const r = await L.run(hosted, { ...fast, interactive: false, deadlineMs: 120, spawn });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('...but an interactive session still owes a first frame, and is killed without one', async () => {
  const r = await L.run(hosted, { ...fast, interactive: true, spawn: fakeSpawn([{ at: 5, report: 'started' }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /nothing painted within 300ms/);
});

t('a signal-terminated exit is reported as 128 plus the signal, not a flat 128', async () => {
  const r = await L.run(stock, { ...fast, spawn: fakeSpawn([{ at: 10, exit: null, signalName: 'SIGKILL' }]) });
  assert.deepStrictEqual(r, { booted: true, code: 128 + 9 });
});

t('a plan that never paints is killed at the deadline rather than hung on', async () => {
  const started = Date.now();
  let child;
  const spawn = (...a) => (child = fakeSpawn([])(...a));
  const r = await L.run(hosted, { ...fast, spawn });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /nothing painted within 300ms/);
  assert.ok(Date.now() - started < 3000, 'the deadline, not the child, ended the wait');
  // And the verdict waited for the process to actually die: the next plan must not take a terminal
  // the old one is still holding.
  assert.strictEqual(child.killed, true);
});

t('a plan killed at the deadline still reports the DEADLINE, not the kill it caused', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 50, report: 'absent something' }]) });
  assert.match(r.reason, /nothing painted within 300ms/, 'the exit the deadline caused must not answer for it');
});

t('a report still in flight when the child is reaped is not lost', async () => {
  // 'exit' lands first and 'painted' only afterwards, which is what a real pipe does when a plan
  // paints and immediately dies. Judging on 'exit' alone would report "never painted anything",
  // which is a different — and false — account of what happened.
  const spawn = fakeSpawn([{ at: 3, report: 'started' }, { at: 5, exit: 1 }, { at: 20, report: 'painted' }], { endAfterExit: 40 });
  const r = await L.run(hosted, { ...fast, settleMs: 5, spawn });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /painted, then exited 1 after 0ms/);
  assert.doesNotMatch(r.reason, /before painting anything/);
});

t('an unreadable boot channel becomes part of the reason rather than vanishing', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 5, channelError: 'EPIPE' }, { at: 20, exit: 1 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /boot channel unreadable: EPIPE/);
});

t('a silent one-shot that exits 0 without painting is the session, never re-run', async () => {
  // It started the app and finished cleanly; that all its output went to stderr is not this
  // launcher's business, and re-running it would repeat whatever it did.
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 5, report: 'started' }, { at: 10, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a clean exit that never started the app is still replaced — nothing ran', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, exit: 0 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /exited 0 before the app started/);
});

t('a named refusal falls back even outside an interactive terminal', async () => {
  // The never-re-run rule protects work a run already did; a host that refused before painting did
  // none. Without this the fail-safe was off entirely in a pipe.
  const r = await L.run(hosted, { ...fast, interactive: false, spawn: fakeSpawn([{ at: 5, report: 'absent no-bun-module-graph-trailer' }, { at: 20, exit: 70 }]) });
  assert.strictEqual(r.booted, false);
  assert.strictEqual(r.reason, 'absent no-bun-module-graph-trailer');
});

t('the FIRST refusal is the reason — the root cause, not whatever followed it', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([
    { at: 5, report: 'absent module-has-unknown-loader' }, { at: 10, report: 'boot-threw something downstream' }, { at: 20, exit: 70 }]) });
  assert.strictEqual(r.reason, 'absent module-has-unknown-loader');
});

t('a named refusal from the host is carried out as the reason', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'absent no-bun-module-graph-trailer' }, { at: 20, exit: 70 }]) });
  assert.strictEqual(r.booted, false);
  assert.strictEqual(r.reason, 'absent no-bun-module-graph-trailer');
});

t('every failure names the Bun APIs the shim did not have, which is the whole diagnosis on a hang', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'absent-api newThing' }, { at: 20, report: 'absent-api other' }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /nothing painted within 300ms \(Bun APIs the shim does not have: newThing, other\)/);
});

t('several reports arriving in one chunk are each read, not just the first', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 8, report: 'started' }, { at: 10, report: 'absent-api a\nabsent-api b\npainted' }, { at: 250, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a session is measured to its exit, not to whenever the channel finally closed', async () => {
  // The plan painted and died 20ms later, well inside the settle window; a channel that takes its
  // time closing must not make that look like a session that lived.
  const spawn = fakeSpawn([{ at: 3, report: 'started' }, { at: 5, report: 'painted' }, { at: 25, exit: 1 }], { endAfterExit: 400 });
  const r = await L.run(hosted, { ...fast, settleMs: 200, deadlineMs: 2000, spawn });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /painted, then exited 1 after (1\d|2\d)ms/, 'measured to the exit, not to the channel close 400ms later');
});

t('a multi-byte character split across chunks is not mangled into replacement characters', async () => {
  // The refusal carries a character whose UTF-8 bytes straddle two reads. Decoding each chunk
  // independently turns it into two replacement characters, which is a different reason.
  const bytes = Buffer.from('boot-threw naïve failure\n', 'utf8');
  const cut = bytes.indexOf(0xc3) + 1; // between the two bytes of 'ï'
  const spawn = fakeSpawn([
    { at: 3, report: 'started' },
    { at: 5, raw: bytes.subarray(0, cut) }, { at: 12, raw: bytes.subarray(cut) },
    { at: 20, exit: 70 }]);
  const r = await L.run(hosted, { ...fast, spawn });
  assert.strictEqual(r.reason, 'boot-threw naïve failure');
});

t('a report split across pipe chunks is still read as one line', async () => {
  // The exit is nonzero and interactive, so this can only come back booted if the 'painted' split
  // across the two chunks was actually reassembled.
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 3, report: 'started' }, { at: 5, raw: 'absent-api one\npain' }, { at: 15, raw: 'ted\n' }, { at: 250, exit: 1 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 1 });
});

t('a plan that dies silently after starting the app still yields a reason', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 5, report: 'started' }, { at: 10, exit: 70 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /exited 70 before painting anything/);
});

t('a plan that dies before the app ever started is replaced, even outside a terminal', async () => {
  // Total silence on the channel: no `started`, no refusal. Inferring "it must have done work" from
  // a nonzero exit is what let a host that crashed before its reporting machinery was up be treated
  // as a finished command in a pipe.
  const r = await L.run(hosted, { ...fast, interactive: false, spawn: fakeSpawn([{ at: 10, exit: 1 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /exited 1 before the app started/);
});



t('a command that cannot be started is a reason, not a crash', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, spawnError: 'ENOENT' }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /could not start node: ENOENT/);
});

t('the floor plan reports nothing and is the session from the moment it starts', async () => {
  const r = await L.run(stock, { ...fast, spawn: fakeSpawn([{ at: 10, exit: 3 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 3 });
});

// ---- the fall-through ---------------------------------------------------------------------------

t('the first plan that boots wins, and nothing after it runs', async () => {
  const ran = [];
  const code = await L.launch('claude', [], {
    plans: [hosted, stock], log: () => {}, reset: () => {},
    run: async (plan) => { ran.push(plan.name); return { booted: true, code: 0 }; },
  });
  assert.strictEqual(code, 0);
  assert.deepStrictEqual(ran, ['hosted']);
});

t('a plan that did not boot falls through to the next, loudly and with its reason', async () => {
  const logged = [];
  const ran = [];
  const code = await L.launch('claude', [], {
    plans: [hosted, stock], log: (line) => logged.push(line), reset: () => {},
    run: async (plan) => { ran.push(plan.name); return plan.reports ? { booted: false, reason: 'nothing painted' } : { booted: true, code: 5 }; },
  });
  assert.strictEqual(code, 5);
  assert.deepStrictEqual(ran, ['hosted', 'stock']);
  assert.strictEqual(logged.length, 1);
  assert.match(logged[0], /hosted session did not start — nothing painted; falling back/);
});

t('the terminal is put back before the next plan takes it', async () => {
  const order = [];
  await L.launch('claude', [], {
    plans: [hosted, stock], log: () => order.push('log'), reset: () => order.push('reset'),
    run: async (plan) => { order.push('run:' + plan.name); return plan.reports ? { booted: false, reason: 'x' } : { booted: true, code: 0 }; },
  });
  assert.deepStrictEqual(order, ['run:hosted', 'log', 'reset', 'run:stock']);
});

t('a plan list with no floor exits nonzero and says so, rather than reporting success', async () => {
  const logged = [];
  const code = await L.launch('claude', [], {
    plans: [hosted], log: (line) => logged.push(line), reset: () => {},
    run: async () => ({ booted: false, reason: 'x' }),
  });
  assert.strictEqual(code, 70);
  assert.match(logged.join('\n'), /no plan produced a session/);
});

// ---- the real plan list -------------------------------------------------------------------------

t('the shipped plan list ends with stock claude, so there is always a floor', () => {
  const p = L.plans('/path/to/claude', ['--resume']);
  assert.strictEqual(p[p.length - 1].name, 'stock');
  assert.strictEqual(p[p.length - 1].command, '/path/to/claude');
  assert.strictEqual(p[p.length - 1].reports, false);
  assert.deepStrictEqual(p[p.length - 1].args, ['--resume']);
});

t('the hosted plan runs the host under node and hands it the binary and the user args', () => {
  const [host] = L.plans('/path/to/claude', ['--resume', 'abc']);
  assert.strictEqual(host.command, process.execPath);
  assert.ok(host.args.includes('--experimental-vm-modules'), 'the host links Bun\'s graph itself and needs vm modules');
  assert.match(host.args.find((a) => a.endsWith('bun-host.mjs')) || '', /bun-host\.mjs$/);
  assert.deepStrictEqual(host.args.slice(-3), ['/path/to/claude', '--resume', 'abc']);
  assert.strictEqual(host.env.CLAUDE_LAWS_BOOT_FD, String(L.BOOT_FD));
});

runAll();
