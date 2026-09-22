#!/usr/bin/env node
// Unit tests for sockets.js — `Bun.listen` and `Bun.connect`.
//
// These run against real loopback sockets rather than a stubbed `net`, and they do so on purpose.
// The two properties the agent proxy is built on are not visible in the shape of the code — that
// `.port` answers before `listen` returns, and that `write` refuses a chunk once the outgoing
// buffer is full and `drain` releases it — and a fake `net` would let both of them be wrong while
// every assertion passed. [LAW:behavior-not-structure]
//
// Every expectation below was run against Bun first and matched: the same scenario, under
// `Bun.listen`/`Bun.connect` 1.2.23, accepts the same six 64 KiB writes before refusing and fires
// `drain` in the same place.

'use strict';
const assert = require('assert');
const net = require('net');
const { createSockets, toBytes } = require('./sockets.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
async function runAll() {
  for (const { name, fn } of cases) {
    try { await fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.stack)); }
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

const build = () => {
  const absent = [];
  return { ...createSockets({ net, onAbsentApi: (n) => absent.push(n) }), absent };
};
const settle = (ms = 150) => new Promise((r) => setTimeout(r, ms));

t('a listener\'s port is readable the instant listen returns', async () => {
  // m01352 builds `ws://127.0.0.1:${server.port}/` on the very next line, and publishes the relay's
  // port out of a function that never yields. A port of 0 here is a proxy nobody can reach.
  const { listen } = build();
  const server = listen({ hostname: '127.0.0.1', port: 0, socket: { open() {}, data() {} } });
  assert.strictEqual(typeof server.port, 'number');
  assert.ok(server.port > 0, `expected a bound port, got ${server.port}`);
  server.stop(true);
});

t('a full round trip: open, data, write, end, close', async () => {
  const { listen, connect } = build();
  const events = [];
  const server = listen({
    hostname: '127.0.0.1', port: 0,
    socket: {
      open(s) { events.push('server-open'); s.data = { seen: [] }; },
      data(s, chunk) { s.data.seen.push(chunk.toString('utf8')); s.write('echo:' + chunk.toString('utf8')); },
      close() { events.push('server-close'); },
    },
  });
  const got = [];
  const client = await connect({
    hostname: '127.0.0.1', port: server.port,
    socket: { open() { events.push('client-open'); }, data(s, chunk) { got.push(chunk.toString('utf8')); } },
  });
  assert.strictEqual(client.write('hello'), 5, 'write answers with the number of bytes it took');
  await settle();
  assert.deepStrictEqual(got, ['echo:hello']);
  assert.ok(events.includes('server-open') && events.includes('client-open'));
  client.end();
  await settle();
  assert.ok(events.includes('server-close'));
  server.stop(true);
});

t('a socket carries the caller\'s own state on .data', async () => {
  // The proxy keeps its entire per-client state there and reads it back in every other handler.
  const { listen, connect } = build();
  let readBack = null;
  const server = listen({
    hostname: '127.0.0.1', port: 0,
    socket: { open(s) { s.data = { tag: 'mine' }; }, data(s) { readBack = s.data.tag; } },
  });
  const client = await connect({ hostname: '127.0.0.1', port: server.port, socket: { open() {}, data() {} } });
  client.write('x');
  await settle();
  assert.strictEqual(readBack, 'mine');
  client.end();
  server.stop(true);
});

t('write refuses once the buffer is full, and drain releases it', async () => {
  const { listen, connect } = build();
  const chunk = Buffer.alloc(64 * 1024, 0x61);
  let serverSocket = null, drains = 0;
  let opened; const whenOpen = new Promise((r) => { opened = r; });
  const server = listen({
    hostname: '127.0.0.1', port: 0,
    socket: { open(s) { serverSocket = s; opened(); }, data() {}, drain() { drains++; } },
  });
  // A client that never reads is what makes the server's outgoing buffer fill up at all.
  const client = await connect({
    hostname: '127.0.0.1', port: server.port,
    socket: { open(s) { s.pause(); }, data() {} },
  });
  await whenOpen;
  await settle(50);

  let accepted = 0, refused = false;
  for (let i = 0; i < 2000; i++) {
    const wrote = serverSocket.write(chunk);
    if (wrote === 0) { refused = true; break; }
    accepted += wrote;
  }
  assert.ok(accepted > 0, 'the first writes must be taken in full');
  assert.ok(refused, 'write must eventually answer 0 rather than letting node buffer without limit');
  await settle(600);
  assert.ok(drains > 0, 'drain is how the caller learns it may write again');
  assert.ok(serverSocket.write(chunk) > 0, 'and after it, writes are taken again');
  client.end();
  server.stop(true);
});

t('write on a socket that is gone answers -1, not 0', async () => {
  // The caller reads 0 as "queue the rest and wait for drain" and a negative as "give up". A closed
  // socket answering 0 would leave it waiting for a drain that can never come.
  const { listen, connect } = build();
  const server = listen({ hostname: '127.0.0.1', port: 0, socket: { open() {}, data() {} } });
  const client = await connect({ hostname: '127.0.0.1', port: server.port, socket: { open() {}, data() {} } });
  client.terminate();
  await settle(50);
  assert.strictEqual(client.write('x'), -1);
  server.stop(true);
});

t('connect rejects when nothing is listening, and the error never escapes as an event', async () => {
  const { listen, connect } = build();
  // A port bound and immediately released is one nothing can be listening on.
  const scout = listen({ hostname: '127.0.0.1', port: 0, socket: { open() {}, data() {} } });
  const port = scout.port;
  scout.stop(true);
  await settle(50);
  await assert.rejects(connect({ hostname: '127.0.0.1', port, socket: { open() {}, data() {}, error() {} } }),
    (e) => e.code === 'ECONNREFUSED');
});

t('an error after the connection is up reaches the socket handler', async () => {
  const { listen, connect } = build();
  const seen = [];
  const server = listen({
    hostname: '127.0.0.1', port: 0,
    socket: { open(s) { s.terminate(); }, data() {}, error() {} },
  });
  const client = await connect({
    hostname: '127.0.0.1', port: server.port,
    socket: { open() {}, data() {}, error(s, e) { seen.push(e); }, close() { seen.push('close'); } },
  });
  client.write('x');
  await settle(150);
  assert.ok(seen.length > 0, 'a reset connection must reach a handler rather than crashing the process');
  server.stop(true);
});

t('stop(true) cuts the connections that are still open', async () => {
  const { listen, connect } = build();
  let closed = false;
  const server = listen({ hostname: '127.0.0.1', port: 0, socket: { open() {}, data() {} } });
  await connect({
    hostname: '127.0.0.1', port: server.port,
    socket: { open() {}, data() {}, close() { closed = true; }, error() {} },
  });
  await settle(50);
  server.stop(true);
  await settle(150);
  assert.ok(closed, 'a live connection must be cut, which is what the argument means');
});

t('binding to a name rather than an address is refused by name', async () => {
  // node has no synchronous resolver, so a name would mean an asynchronous bind and a port of 0.
  const { listen } = build();
  assert.throws(() => listen({ hostname: 'localhost', port: 0, socket: {} }), /only to a literal IP address/);
});

t('a bind that fails says which address and why', async () => {
  const { listen } = build();
  assert.throws(() => listen({ hostname: '127.0.0.1', port: 1, socket: {} }), /could not bind 127\.0\.0\.1:1/);
});

t('a socket member this host does not carry is recorded, and the runtime\'s own probes are not', async () => {
  const { listen, connect, absent } = build();
  const server = listen({ hostname: '127.0.0.1', port: 0, socket: { open() {}, data() {} } });
  const client = await connect({ hostname: '127.0.0.1', port: server.port, socket: { open() {}, data() {} } });
  assert.deepStrictEqual(absent, [], 'awaiting the connect promise must not report a missing Socket.then');
  assert.strictEqual(client.reload, undefined);
  assert.deepStrictEqual(absent, ['Socket.reload']);
  client.end();
  server.stop(true);
});

t('toBytes respects a view\'s window rather than its whole backing store', () => {
  const backing = Buffer.from('....payload....');
  const view = new Uint8Array(backing.buffer, backing.byteOffset + 4, 7);
  assert.strictEqual(toBytes(view).toString('utf8'), 'payload');
  assert.strictEqual(toBytes('hi').toString('utf8'), 'hi');
});

runAll();
