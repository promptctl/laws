#!/usr/bin/env node
// Tests for switch-channel.js — the request/response channel between laws-switch and the session.
//
// Both halves are exercised against each other over a real unix socket, because the failure this
// channel exists to avoid is a caller REPORTING a switch that never happened: a client that resolves
// on a dropped connection, a server that answers nothing when the enactment throws, or a peer that
// hangs until a timeout and then names the wrong reason. None of those is visible from one half.

'use strict';
const assert = require('assert');
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');
const C = require('./switch-channel.js');

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

const tmpdir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'laws-chan-'));
const errors = [];
// Serve one exchange, run the client against it, and always take the listener back down — a leaked
// listener would keep the next case's socket path occupied and fail it for the wrong reason.
async function exchange(onRequest, request = { choice: 'reject' }, opts = {}) {
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest, onError: (e) => errors.push(e) });
  // A short timeout on purpose: with the default a channel that never reads would take 15s per case
  // and the SUITE would be killed for time, which reads as a hang rather than as the failure it is.
  try { return await C.requestSwitch({ net, dir, request, timeoutMs: 1500, ...opts }); }
  finally { server.close(); fs.rmSync(dir, { recursive: true, force: true }); }
}

// ---- the protocol -------------------------------------------------------------------------------

t('the socket lives inside the handoff directory, inheriting its permissions', () => {
  assert.strictEqual(C.socketPathIn('/tmp/x'), path.join('/tmp/x', C.SOCKET_NAME));
});

t('a record is one line even when the payload contains a newline', () => {
  // The encoding is what guarantees this, not a stripping pass: JSON escapes the newline, so the
  // reason survives intact AND the record stays splittable on the separator.
  const line = C.encode({ reason: 'broke\nin two' });
  assert.strictEqual(line.split('\n').filter(Boolean).length, 1);
  assert.strictEqual(JSON.parse(line).reason, 'broke\nin two');
});

// ---- the two halves against each other ----------------------------------------------------------

t('a request reaches the session and its response comes back whole', async () => {
  const seen = [];
  const out = await exchange((req) => { seen.push(req); return { ok: true, rewound: true, tombstoned: 1 }; },
    { choice: 'rewind_discard', transcript: '/t.jsonl' });
  assert.deepStrictEqual(seen, [{ choice: 'rewind_discard', transcript: '/t.jsonl' }]);
  assert.deepStrictEqual(out, { ok: true, rewound: true, tombstoned: 1 });
});

t('an enactment refusal travels back by name, not as a transport failure', async () => {
  // The caller acts differently on "the session refused" than on "no session is listening", so the
  // two must never collapse into one.
  const out = await exchange(() => ({ ok: false, reason: 'the-switch-no-longer-applies', detail: 'compatible' }));
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, 'the-switch-no-longer-applies');
  assert.strictEqual(out.detail, 'compatible');
});

t('an async enactment is awaited before the answer is sent', async () => {
  const out = await exchange(async () => { await new Promise((r) => setTimeout(r, 20)); return { ok: true, late: true }; });
  assert.deepStrictEqual(out, { ok: true, late: true });
});

t('an enactment that THROWS still answers — a hung caller reports nothing at all', async () => {
  const out = await exchange(() => { throw new Error('the store was gone'); });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, 'the-switch-threw');
  // Exact, not a substring: String(e) would also contain the message, prefixed with "Error:".
  assert.strictEqual(out.detail, 'the store was gone');
});

t('an enactment that rejects still answers', async () => {
  const out = await exchange(async () => { throw new Error('async boom'); });
  assert.strictEqual(out.ok, false);
  assert.match(out.detail, /async boom/);
});

// ---- when there is no session ------------------------------------------------------------------

t('no listener is its own named reason, not a timeout and not a refusal', async () => {
  const dir = tmpdir();
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 2000 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.noSocket);
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a peer that closes without answering resolves promptly, not as a hang', async () => {
  // Without this the promise would sit until the timeout and then name the wrong failure. The reason
  // is noAnswer rather than noSocket because the connection did open — see the pair of cases below.
  const dir = tmpdir();
  const server = net.createServer((socket) => socket.destroy());
  await new Promise((r) => server.listen(C.socketPathIn(dir), r));
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 5000 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.noAnswer);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a session that answers with garbage is named, never parsed past', async () => {
  const dir = tmpdir();
  const server = net.createServer((socket) => socket.end('not json at all\n'));
  await new Promise((r) => server.listen(C.socketPathIn(dir), r));
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 5000 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.malformed);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a session that never answers times out by name rather than hanging forever', async () => {
  const dir = tmpdir();
  const server = net.createServer(() => { /* accept and say nothing */ });
  await new Promise((r) => server.listen(C.socketPathIn(dir), r));
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 120 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.timeout);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a client that sends garbage is answered, not left hanging', async () => {
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: () => ({ ok: true }), onError: (e) => errors.push(e) });
  const reply = await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => socket.write('{ broken\n'));
    let buf = '';
    socket.setEncoding('utf8');
    socket.on('data', (d) => { buf += d; });
    socket.on('close', () => resolve(buf));
    // A server that never answers must FAIL this case rather than hang it: a case that never
    // returns reports nothing at all, which is no better than one that wrongly passes.
    setTimeout(() => { socket.destroy(); resolve('{"reason":"NEVER ANSWERED"}'); }, 2000).unref();
  });
  const answer = JSON.parse(reply);
  assert.strictEqual(answer.ok, false);
  assert.strictEqual(answer.reason, C.UNPARSEABLE);
  // The detail is the parse failure's MESSAGE, not the error object stringified around it.
  assert.ok(answer.detail && !answer.detail.startsWith('SyntaxError'), 'detail was the error itself: ' + answer.detail);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('the enactment is not called at all when the request does not parse', async () => {
  const dir = tmpdir();
  let called = 0;
  const server = C.createSwitchServer({ net, dir, onRequest: () => { called++; return { ok: true }; }, onError: (e) => errors.push(e) });
  await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => socket.write('nope\n'));
    // Drain the answer: an unread socket stays paused and never emits close, which would hang here
    // rather than fail — and a case that never returns reports nothing at all.
    socket.resume();
    socket.on('close', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 2000).unref();
  });
  assert.strictEqual(called, 0);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a session that closes CLEANLY without answering is a failure, not a success', async () => {
  // It ACCEPTED the connection, so this is noAnswer rather than noSocket — the request may have
  // arrived and run before the peer went quiet, which is what stops the caller claiming otherwise.
  const dir = tmpdir();
  const server = net.createServer((socket) => socket.end());
  await new Promise((r) => server.listen(C.socketPathIn(dir), r));
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 4000 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.noAnswer);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a second record on one connection is ignored — one exchange per connection', async () => {
  // Without the latch the server would enact the same request twice off a single connection.
  const dir = tmpdir();
  let calls = 0;
  const server = C.createSwitchServer({ net, dir, onRequest: () => { calls++; return { ok: true }; }, onError: (e) => errors.push(e) });
  await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => {
      // Two separate writes with a gap: arriving as ONE chunk the reader parses once anyway and the
      // latch is never exercised, so the case would pass whether or not it exists.
      socket.write('{"choice":"reject"}\n');
      setTimeout(() => socket.write('{"choice":"reject"}\n'), 60).unref();
    });
    socket.resume();
    socket.on('close', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 2500).unref();
  });
  assert.strictEqual(calls, 1);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a response that cannot be encoded is answered, not turned into an unhandled rejection', async () => {
  // onRecord is async and fire-and-forget, so anything escaping it becomes an unhandled rejection —
  // which can take down the hosted session this listener lives inside.
  const circular = { ok: true };
  circular.self = circular;
  const out = await exchange(() => circular);
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNENCODABLE);
});

t('an unencodable response does not kill the process', async () => {
  // The specific outcome the guard exists to prevent, asserted rather than argued.
  const rejections = [];
  const onRejection = (e) => rejections.push(e);
  process.on('unhandledRejection', onRejection);
  const circular = { ok: true };
  circular.self = circular;
  await exchange(() => circular);
  await new Promise((r) => setTimeout(r, 100));
  process.off('unhandledRejection', onRejection);
  assert.deepStrictEqual(rejections, []);
});

t('the SERVER failing to parse the request says so, not that the session answered badly', async () => {
  // Reusing the client-side reason told the caller "the hosted session answered with something that
  // is not a response" when in fact its own request would not parse — the wrong end of the wire.
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: () => ({ ok: true }), onError: (e) => errors.push(e) });
  const reply = await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => socket.write('{ broken\n'));
    let buf = '';
    socket.setEncoding('utf8');
    socket.on('data', (d) => { buf += d; });
    socket.on('close', () => resolve(buf));
    setTimeout(() => { socket.destroy(); resolve('{"reason":"NEVER ANSWERED"}'); }, 2000).unref();
  });
  assert.strictEqual(JSON.parse(reply).reason, C.UNPARSEABLE);
  assert.notStrictEqual(JSON.parse(reply).reason, C.UNREACHABLE.malformed);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a value JSON cannot represent is refused by encode rather than sent as "undefined"', () => {
  // JSON.stringify RETURNS undefined for these rather than throwing, so a blind concatenation would
  // put the literal text "undefined" on the wire and the far end would call it a parse error.
  for (const value of [undefined, () => {}, Symbol('x')]) {
    assert.throws(() => C.encode(value), TypeError, 'encoded ' + String(value));
  }
});

t('an onRequest that returns nothing is reported as unencodable, not as a bad answer', async () => {
  const out = await exchange(() => undefined);
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNENCODABLE);
});

t('a request that cannot be encoded fails by name instead of crashing the caller', async () => {
  // The throw would happen inside a plain 'connect' listener, where nothing catches it.
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: () => ({ ok: true }), onError: (e) => errors.push(e) });
  const circular = {};
  circular.self = circular;
  const out = await C.requestSwitch({ net, dir, request: circular, timeoutMs: 2000 });
  assert.strictEqual(out.ok, false);
  // UNSENT, not UNENCODABLE: this fails before a byte is written, so the switch provably did not run.
  assert.strictEqual(out.reason, C.UNSENT);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a peer that accepts and then closes is NOT reported as no-listener', async () => {
  // The distinction decides whether a caller may tell the user nothing happened: a refused
  // connection proves the request never arrived; an accepted one may have enacted the switch.
  const dir = tmpdir();
  const server = net.createServer((socket) => socket.destroy());
  await new Promise((r) => server.listen(C.socketPathIn(dir), r));
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 4000 });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.reason, C.UNREACHABLE.noAnswer);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a connection that never opened keeps the no-listener reason', async () => {
  const dir = tmpdir();
  const out = await C.requestSwitch({ net, dir, request: { choice: 'reject' }, timeoutMs: 2000 });
  assert.strictEqual(out.reason, C.UNREACHABLE.noSocket);
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a request that never leaves is a DIFFERENT reason from one whose answer failed', async () => {
  // The distinction decides whether a caller may say nothing changed: the client's encode fails
  // before a byte is written, the server's fails after the switch has already run.
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: () => ({ ok: true }), onError: (e) => errors.push(e) });
  const circular = {}; circular.self = circular;
  const unsent = await C.requestSwitch({ net, dir, request: circular, timeoutMs: 2000 });
  assert.strictEqual(unsent.reason, C.UNSENT);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });

  const answerFailed = await exchange(() => { const c = {}; c.self = c; return c; });
  assert.strictEqual(answerFailed.reason, C.UNENCODABLE);
  assert.notStrictEqual(answerFailed.reason, unsent.reason);
});

t('only the reasons that PROVE non-delivery are in the safe set', () => {
  // Enumerating the safe side is what stops a newly added reason defaulting to "nothing changed".
  assert.ok(C.PROVABLY_NOT_DELIVERED.includes(C.UNREACHABLE.noSocket));
  assert.ok(C.PROVABLY_NOT_DELIVERED.includes(C.UNSENT));
  for (const unsafe of [C.THREW, C.UNENCODABLE, C.UNPARSEABLE, C.UNREACHABLE.noAnswer, C.UNREACHABLE.timeout, C.UNREACHABLE.malformed]) {
    assert.ok(!C.PROVABLY_NOT_DELIVERED.includes(unsafe), unsafe + ' was treated as provably undelivered');
  }
});

t('a peer that streams without ever completing a record is cut off, not held', async () => {
  // The threat model names a hostile local process explicitly; without a cap it could grow the
  // server's buffer inside the user's running session without bound.
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: () => ({ ok: true }), onError: (e) => errors.push(e) });
  const reply = await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => {
      // No separator, ever — just more than the cap allows.
      socket.write('x'.repeat(C.MAX_RECORD_BYTES + 1024));
    });
    let buf = '';
    socket.setEncoding('utf8');
    socket.on('data', (d) => { buf += d; });
    socket.on('close', () => resolve(buf));
    setTimeout(() => { socket.destroy(); resolve('{"reason":"NEVER CUT OFF"}'); }, 5000).unref();
  });
  assert.strictEqual(JSON.parse(reply).reason, C.UNPARSEABLE);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('the enactment never sees an over-long record', async () => {
  const dir = tmpdir();
  let calls = 0;
  const server = C.createSwitchServer({ net, dir, onRequest: () => { calls++; return { ok: true }; }, onError: (e) => errors.push(e) });
  await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => socket.write('y'.repeat(C.MAX_RECORD_BYTES + 16)));
    socket.resume();
    socket.on('close', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 5000).unref();
  });
  assert.strictEqual(calls, 0);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('a peer that keeps streaming past the cap is refused ONCE, not once per chunk', async () => {
  // Without the latch, every further chunk re-enters the guard and ends the socket again — the same
  // re-entrancy the record path is latched against, in the arm added to bound the buffer.
  const chunks = [];
  const socket = {
    setEncoding() {},
    on(event, fn) { if (event === 'data') this._data = fn; },
    _data: null,
  };
  let refusals = 0;
  C.__readOneRecordForTest(socket, { onRecord: () => {}, onMalformed: () => { refusals++; }, maxBytes: 8 });
  socket._data('x'.repeat(20));
  socket._data('x'.repeat(20));
  socket._data('x'.repeat(20));
  assert.strictEqual(refusals, 1);
  void chunks;
});

t('accepted sockets carry an idle deadline', () => {
  // Named rather than waited on: the client half has always had a deadline and the server had none.
  assert.ok(C.IDLE_MS > 0 && C.IDLE_MS <= 120000);
});

t('a second record arriving DURING a slow enactment is ignored', async () => {
  // The window the latch actually protects. `onRequest` is awaited, so between parsing a record and
  // ending the socket there is real time in which another record can arrive — and enacting the same
  // switch twice would rewind an already-rewound conversation.
  const dir = tmpdir();
  let calls = 0;
  const server = C.createSwitchServer({
    net, dir,
    onRequest: async () => { calls++; await new Promise((r) => setTimeout(r, 250)); return { ok: true }; },
    onError: (e) => errors.push(e),
  });
  await new Promise((resolve) => {
    const socket = net.createConnection(C.socketPathIn(dir), () => {
      socket.write('{"choice":"reject"}\n');
      // Well inside the enactment, while the socket is still open.
      setTimeout(() => socket.write('{"choice":"tombstone"}\n'), 60).unref();
    });
    socket.resume();
    socket.on('close', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 3000).unref();
  });
  assert.strictEqual(calls, 1);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

t('two switches in a row each get their own answer', async () => {
  // One connection carries one exchange; nothing is left listening between them.
  const dir = tmpdir();
  const server = C.createSwitchServer({ net, dir, onRequest: (r) => ({ ok: true, echo: r.n }), onError: (e) => errors.push(e) });
  const first = await C.requestSwitch({ net, dir, request: { n: 1 } });
  const second = await C.requestSwitch({ net, dir, request: { n: 2 } });
  assert.deepStrictEqual([first.echo, second.echo], [1, 2]);
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

runAll();
