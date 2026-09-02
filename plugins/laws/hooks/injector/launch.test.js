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

// A stand-in child that lets a test say what the host reported and when it exited.
function fakeSpawn(script) {
  return () => {
    const child = new EventEmitter();
    const channel = new EventEmitter();
    child.stdio = [null, null, null, channel];
    child.kill = () => { child.killed = true; child.emit('exit', null, 'SIGKILL'); };
    for (const step of script) setTimeout(() => {
      if (step.report !== undefined) channel.emit('data', Buffer.from(step.report + '\n'));
      if (step.raw !== undefined) channel.emit('data', Buffer.from(step.raw));
      if (step.exit !== undefined) child.emit('exit', step.exit, null);
      if (step.spawnError) child.emit('error', new Error(step.spawnError));
    }, step.at);
    return child;
  };
}
const hosted = { name: 'hosted', command: 'node', args: [], env: {}, reports: true };
const stock = { name: 'stock', command: 'claude', args: [], env: {}, reports: false };
const fast = { deadlineMs: 300, settleMs: 150, interactive: true };

// ---- what counts as having become the session --------------------------------------------------

t('a plan that paints and stays is the session', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'painted' }, { at: 250, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a plan that paints and then dies inside the settle window never became a session', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'painted' }, { at: 40, exit: 1 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /painted, then exited 1/);
});

t('...but a CLEAN early exit is a one-shot command finishing, and is never re-run', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'painted' }, { at: 40, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('...and outside an interactive terminal no exit is ever re-run, whatever the code', async () => {
  const r = await L.run(hosted, { ...fast, interactive: false, spawn: fakeSpawn([{ at: 10, report: 'painted' }, { at: 40, exit: 1 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 1 });
});

t('a plan that never paints is killed at the deadline rather than hung on', async () => {
  const started = Date.now();
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /nothing painted within 300ms/);
  assert.ok(Date.now() - started < 3000, 'the deadline, not the child, ended the wait');
});

t('a named refusal from the host is carried out as the reason', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'absent no-bun-module-graph-trailer' }, { at: 20, exit: 70 }]) });
  assert.strictEqual(r.booted, false);
  assert.strictEqual(r.reason, 'absent no-bun-module-graph-trailer');
});

t('every failure names the Bun APIs the shim did not have, which is the whole diagnosis on a hang', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'absent-api newThing' }, { at: 20, report: 'absent-api other' }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /nothing painted within 300ms \(Bun APIs the shim does not have: newThing, other\)/);
});

t('several reports arriving in one chunk are each read, not just the first', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, report: 'absent-api a\nabsent-api b\npainted' }, { at: 250, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a report split across pipe chunks is still read as one line', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 5, raw: 'absent-api one\npain' }, { at: 15, raw: 'ted\n' }, { at: 250, exit: 0 }]) });
  assert.deepStrictEqual(r, { booted: true, code: 0 });
});

t('a plan that dies silently before painting still yields a reason', async () => {
  const r = await L.run(hosted, { ...fast, spawn: fakeSpawn([{ at: 10, exit: 70 }]) });
  assert.strictEqual(r.booted, false);
  assert.match(r.reason, /exited 70 before painting anything/);
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
