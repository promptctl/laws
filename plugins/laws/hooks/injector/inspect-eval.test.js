#!/usr/bin/env node
// Unit tests for inspect-eval.js — the inspector channel the craft switch drives /exit down.
// Plain Node asserts, no framework: same dependency stance as the other suites here.
//
// The socket is the only thing stubbed. A fake WebSocket lets each test script exactly what the
// inspector replies, which is the whole point: the failures worth testing are the ones where the
// inspector says NO, and a real one cannot be asked to refuse on demand.
//
// These assert the channel's CONTRACT — what reaches the caller for each shape of reply — never
// how connect() builds its frames. [LAW:behavior-not-structure]

'use strict';
const assert = require('assert');

let pass = 0, fail = 0, finished = false;
async function t(name, fn) {
  try { await fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

// AN ASYNC SUITE CAN DIE WITHOUT FAILING. Several tests here await a promise that only settles
// when a timer fires; if that timer stops holding the event loop open, node drains the loop and
// exits 0 mid-suite, skipping every remaining row AND the summary. A runner reading only the
// exit code scores that as a pass — which is precisely how a suite reports green while testing
// nothing. This is not hypothetical: it is what an `.unref()`-ed connect timer does to this
// file. Reaching the summary is therefore itself an assertion. [LAW:no-silent-failure]
process.on('exit', (code) => {
  if (!finished && code === 0) {
    console.log('FAIL - the suite exited before finishing: the event loop drained early, so an '
              + 'unknown number of rows never ran. Exit 0 here is truncation, not success.');
    process.exitCode = 1;
  }
});

// A WebSocket that never touches the network. `reply` is the test's script: it receives each
// outbound frame and returns the object the inspector would send back (or null to stay silent).
function installFakeWS(reply) {
  globalThis.WebSocket = class {
    constructor(url) {
      this.url = url;
      this.sent = [];
      setImmediate(() => this.onopen && this.onopen());
    }
    send(raw) {
      const msg = JSON.parse(raw);
      this.sent.push(msg);
      const res = reply(msg);
      if (res) setImmediate(() => this.onmessage && this.onmessage({ data: JSON.stringify(res) }));
    }
    close() { this.closed = true; }
  };
}

// Every test opens its own channel; Runtime.enable is answered blandly unless a test overrides it.
function open(reply) {
  installFakeWS(reply);
  return require('./inspect-eval.js').connect('ws://127.0.0.1:0/dbg', { timeoutMs: 2000 });
}
const ok = (m) => ({ id: m.id, result: {} });
const returns = (value) => (m) =>
  m.method === 'Runtime.evaluate' ? { id: m.id, result: { result: { value } } } : ok(m);

async function rejects(promise, matching) {
  try { await promise; }
  catch (e) { assert.match(e.message, matching, 'rejected, but with: ' + e.message); return e; }
  assert.fail('resolved instead of rejecting');
}

(async () => {
  // ---- the happy path still works ----------------------------------------------------------
  await t('evaluate returns the value the process reported', async () => {
    const c = open(returns(42));
    await c.ready;
    assert.strictEqual(await c.evaluate('40+2'), 42);
  });

  await t('injectStdin resolves when the bytes landed', async () => {
    const c = open(returns('pushed'));
    await c.ready;
    assert.strictEqual(await c.injectStdin('/exit\r'), 'pushed');
  });

  // ---- a refusal BY the inspector (a CDP error reply) --------------------------------------
  // The regression this suite exists for: an error reply carries no `result`, so resolving it
  // alike made a refused evaluate indistinguishable from one that returned undefined.
  await t('a CDP error reply rejects instead of reading as an undefined result', async () => {
    const c = open((m) => m.method === 'Runtime.evaluate'
      ? { id: m.id, error: { code: -32000, message: 'Runtime agent is not enabled' } }
      : ok(m));
    await c.ready;
    const e = await rejects(c.evaluate('whatever'), /Runtime agent is not enabled/);
    assert.match(e.message, /-32000/, 'the inspector code is lost: ' + e.message);
  });

  await t('a CDP error on injectStdin reaches the caller as a failure', async () => {
    const c = open((m) => m.method === 'Runtime.evaluate'
      ? { id: m.id, error: { code: -32601, message: 'method not found' } }
      : ok(m));
    await c.ready;
    await rejects(c.injectStdin('/exit\r'), /method not found/);
  });

  // ---- an exception INSIDE the process ------------------------------------------------------
  await t('an uncaught exception in the evaluated expression rejects', async () => {
    const c = open((m) => m.method === 'Runtime.evaluate'
      ? { id: m.id, result: { exceptionDetails: { text: 'ReferenceError: nope is not defined' } } }
      : ok(m));
    await c.ready;
    await rejects(c.evaluate('nope'), /nope is not defined/);
  });

  // ---- the injected expression's own caught failure -----------------------------------------
  // "ERR:<msg>" crosses the socket as an ordinary successful result. Returning it would be an
  // answer-shaped void, and laws-switch does not inspect the return value.
  await t('injectStdin treats a caught "ERR:" from inside the process as a failure', async () => {
    const c = open(returns('ERR:stream is not readable'));
    await c.ready;
    await rejects(c.injectStdin('/exit\r'), /stream is not readable/);
  });

  await t('injectStdin refuses any value that is not exactly "pushed"', async () => {
    const c = open(returns(undefined));
    await c.ready;
    await rejects(c.injectStdin('/exit\r'), /no value returned/);
  });

  // A truthy non-"pushed" value must fail too — the check is an equality, not a truthiness test,
  // which is what stops a future refactor from passing anything back as success.
  await t('a truthy value that is not "pushed" is still a failure', async () => {
    const c = open(returns('ok'));
    await c.ready;
    await rejects(c.injectStdin('/exit\r'), /stdin injection failed/);
  });

  // ---- the connect timeout must not outlive the work it guards --------------------------------
  // This asserts on PROCESS LIFETIME, not on a promise, and it has to. A pending Node timer keeps
  // the event loop alive, but this suite ends with process.exit(), which tears such timers down —
  // so every row above stays green with the leak present. Only a child process allowed to end on
  // its own terms can observe it. [LAW:behavior-not-structure] the contract is "this module lets
  // your process exit", which is not visible from inside the module.
  await t('connect() lets the process exit once ready has settled', () => {
    const { execFileSync } = require('child_process');
    const fs = require('fs'), os = require('os'), path = require('path');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'inspect-eval-exit-'));
    const script = path.join(dir, 'child.js');
    fs.writeFileSync(script, [
      'globalThis.WebSocket = class {',
      '  constructor(){ setImmediate(()=> this.onopen && this.onopen()); }',
      '  send(raw){ const m=JSON.parse(raw); setImmediate(()=> this.onmessage &&',
      '    this.onmessage({data:JSON.stringify({id:m.id,result:{result:{value:"pushed"}}})})); }',
      '  close(){}',
      '};',
      'const { connect } = require(' + JSON.stringify(path.join(__dirname, 'inspect-eval.js')) + ');',
      "(async () => { const c = connect('ws://127.0.0.1:0/dbg');",
      "  await c.ready; await c.injectStdin('/exit\\r'); c.close(); })();",
    ].join('\n'));
    const t0 = Date.now();
    execFileSync(process.execPath, [script], { timeout: 60000 });
    const ms = Date.now() - t0;
    // Default timeoutMs is 15000, so the leak shows as ~15s and the fix as well under a second.
    assert.ok(ms < 5000, 'the process lingered ' + ms + 'ms after finishing its work — the connect timer is still holding the event loop open');
  });

  await t('a connect that never opens still fails loudly on the timeout', async () => {
    globalThis.WebSocket = class { constructor() {} send() {} close() {} };  // onopen never fires
    const c = require('./inspect-eval.js').connect('ws://127.0.0.1:0/dbg', { timeoutMs: 200 });
    await rejects(c.ready, /connect timeout after 200ms/);
  });

  // ...and it must fail loudly IN A PROCESS WITH NOTHING ELSE TO DO, which is the case the test
  // above cannot see. The obvious alternative fix for the lingering timer is `.unref()`, and an
  // unref-ed timer lets the loop drain BEFORE it fires: a genuinely hung connect then ends the
  // process with exit 0 and no diagnostic at all. Measured — unref: exit 0, silent; clear-on-
  // settle: exit 3, "connect timeout after 300ms". This row is what makes those two
  // distinguishable, and it is the whole reason the fix clears rather than unrefs.
  // [LAW:no-silent-failure]
  await t('a hung connect fails loudly even when nothing else holds the event loop', () => {
    const { spawnSync } = require('child_process');
    const fs = require('fs'), os = require('os'), path = require('path');
    const script = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'inspect-eval-hang-')), 'child.js');
    fs.writeFileSync(script, [
      'globalThis.WebSocket = class { constructor(){} send(){} close(){} };  // never opens',
      'const { connect } = require(' + JSON.stringify(path.join(__dirname, 'inspect-eval.js')) + ');',
      "const c = connect('ws://127.0.0.1:0/dbg', { timeoutMs: 300 });",
      'c.ready.then(() => process.exit(9), () => process.exit(3));',
    ].join('\n'));
    const r = spawnSync(process.execPath, [script], { timeout: 30000 });
    assert.strictEqual(r.status, 3,
      'a hung connect ended with status ' + r.status + ' instead of rejecting — exit 0 means the process drained silently and nobody was told the connect failed');
  });

  // A socket that ERRORS is the other way `ready` settles, and the timer must be released on
  // that arm too. Clearing only on success leaves it pending for the full timeoutMs after a
  // connect has already failed — the same fifteen-second tail, reached by the path you hit when
  // the inspector is not listening at all, which is the common failure in practice.
  await t('a connect that errors also releases the timer, so the process exits promptly', () => {
    const { spawnSync } = require('child_process');
    const fs = require('fs'), os = require('os'), path = require('path');
    const script = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'inspect-eval-err-')), 'child.js');
    fs.writeFileSync(script, [
      'globalThis.WebSocket = class {',
      "  constructor(){ setImmediate(()=> this.onerror && this.onerror(new Error('ECONNREFUSED'))); }",
      '  send(){} close(){}',
      '};',
      'const { connect } = require(' + JSON.stringify(path.join(__dirname, 'inspect-eval.js')) + ');',
      "const c = connect('ws://127.0.0.1:0/dbg', { timeoutMs: 10000 });",
      'c.ready.catch(() => {});',
    ].join('\n'));
    const t0 = Date.now();
    const r = spawnSync(process.execPath, [script], { timeout: 60000 });
    const ms = Date.now() - t0;
    assert.ok(ms < 5000, 'the process lingered ' + ms + 'ms after the connect had already failed — the timer is only released on the success arm');
    // Exiting FAST is not enough: releasing the timer on the success arm alone leaves the
    // rejected arm with no handler, and node then kills the process on an unhandled rejection.
    // That is fast and it is also a crash, so timing alone cannot tell the two apart. The child
    // handles ready's rejection itself, so a correct run ends cleanly.
    assert.strictEqual(r.status, 0,
      'the child exited ' + r.status + ' on a failed connect (stderr: ' + String(r.stderr).slice(0, 200) + ')');
  });

  finished = true;
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail === 0 ? 0 : 1);
})();
