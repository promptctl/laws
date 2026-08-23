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

let pass = 0, fail = 0;
async function t(name, fn) {
  try { await fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}

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

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail === 0 ? 0 : 1);
})();
