// sockets.js — `Bun.listen` and `Bun.connect`, over node's `net`.
//
// WHY THIS FILE EXISTS. The agent proxy (m01352) is built on these two and on nothing else. It
// opens the loopback listener that `HTTPS_PROXY` points at, it dials upstream directly when
// selective relay says to, and it runs a `bufferedAmount` self-check through a third listener at
// startup. Absent, a hosted session's proxy never comes up — and inference is force-tunneled
// through it, so that is a session that cannot talk to the API at all.
//
// THE TWO THINGS THAT ARE NOT OBVIOUS, both of which the agent proxy depends on by construction.
//
// 1. BUN BINDS SYNCHRONOUSLY. `Bun.listen(...).port` is read on the very next line — m01352 builds
//    a `ws://127.0.0.1:${server.port}/` URL with it, and the relay's own `hn()` returns `{port}`
//    before yielding once. node's `server.listen()` does not have the handle yet at that point and
//    `address()` is null, so a straightforward wrapper publishes port 0 and the proxy address is
//    wrong with nothing to notice it. `net._createServerHandle` binds in the calling frame and
//    hands back a handle whose `getsockname` already answers, which is what makes `.port` true the
//    moment `listen` returns. It is an underscore-prefixed export rather than a documented one —
//    node's own cluster module is built on it — so its absence is a named refusal below rather than
//    a quiet fall back to the asynchronous path. [LAW:no-silent-failure]
//
// 2. `socket.write` RETURNS HOW MANY BYTES IT TOOK. Bun's write is allowed to take only part of a
//    chunk, and the proxy's flow control is built on exactly that: a short return means the
//    remainder goes into its own queue, the queue's size throttles the upstream reader, and a
//    `drain` callback is what releases it. node's `write` always takes everything and answers a
//    boolean, so translating it as "always the whole length" would silently disable the proxy's
//    backpressure and move the unbounded buffer from its queue into node's. So this takes the
//    chunk only while node's own outgoing buffer is under its high-water mark, and answers 0 once
//    it is not — all-or-nothing, never a partial write node has already accepted, because a caller
//    that re-sends bytes node already holds duplicates them on the wire. `drain` then arrives the
//    way the caller expects, because the write that crossed the mark is the one node promises to
//    emit it for.
//
// [LAW:effects-at-boundaries] `net` arrives as a parameter; nothing here reaches for a module.
// [LAW:decomposition] one sentence: present node sockets as Bun sockets.

'use strict';

const { recording } = require('./recording.js');

// Whatever a caller hands `write`, as bytes, respecting a view's window. `Buffer.from(view.buffer)`
// alone takes the whole backing store and would put bytes on the wire that were never in the chunk.
const toBytes = (chunk) => (typeof chunk === 'string' ? Buffer.from(chunk, 'utf8')
  : ArrayBuffer.isView(chunk) ? Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength)
    : Buffer.from(chunk));

const WRITE_FAILED = -1;

// One socket shape for both directions, because Bun has one. The handlers are Bun's: `open`,
// `data`, `drain`, `close`, `error` — each optional, each called with the socket first.
const bunSocket = (raw, handlers, onAbsentApi) => {
  const socket = recording('Socket', {
    // Bun's per-connection user slot. The proxy writes its whole per-client state here in `open`
    // and reads it back in `data`, `drain` and `close`, so it has to be a real settable property.
    data: undefined,
    get remoteAddress() { return raw.remoteAddress; },
    get remotePort() { return raw.remotePort; },
    get localPort() { return raw.localPort; },
    get bytesWritten() { return raw.bytesWritten; },
    get readyState() { return raw.destroyed ? 'closed' : raw.connecting ? 'connecting' : 'open'; },

    write(chunk) {
      if (raw.destroyed || raw.writableEnded) return WRITE_FAILED;
      const bytes = toBytes(chunk);
      // Refuse the chunk rather than let node swallow it, so the caller's queue — not node's — is
      // where the backlog lives and where the throttle can see it. See note 2 in the header.
      if (raw.writableLength >= raw.writableHighWaterMark) return 0;
      raw.write(bytes);
      return bytes.length;
    },

    // `end` finishes the conversation politely; `terminate` cuts it. The proxy uses both, and which
    // one it used is the difference between a client seeing a clean EOF and seeing a reset.
    end(chunk) {
      if (chunk !== undefined) raw.end(toBytes(chunk));
      else raw.end();
    },
    terminate() { raw.destroy(); },
    shutdown() { raw.end(); },

    // Guarded at every call site with `typeof socket.pause === 'function'`, because the runtime the
    // app is on may not have them. Here they do exist, and they are the upstream throttle.
    pause() { raw.pause(); return socket; },
    resume() { raw.resume(); return socket; },
    ref() { raw.ref(); return socket; },
    unref() { raw.unref(); return socket; },
    setKeepAlive(enable, delay) { raw.setKeepAlive(enable, delay); return socket; },
    setNoDelay(enable) { raw.setNoDelay(enable); return socket; },
  }, onAbsentApi);

  raw.on('data', (chunk) => handlers.data?.(socket, chunk));
  raw.on('drain', () => handlers.drain?.(socket));
  raw.on('close', () => handlers.close?.(socket));
  // Always listened for. node THROWS on an 'error' with no listener, which would take the whole
  // session down over one reset connection.
  raw.on('error', (e) => handlers.error?.(socket, e));
  return socket;
};

const createSockets = ({ net, onAbsentApi }) => {
  const listen = (options = {}) => {
    const hostname = options.hostname ?? '0.0.0.0';
    const port = options.port ?? 0;
    const handlers = options.socket ?? {};

    const family = net.isIP(hostname);
    // Binding to a name needs a resolver, and node has no synchronous one — so a caller that asked
    // for one would get an asynchronous bind and a port of 0. Refused by name instead; the graph
    // binds only to 127.0.0.1. [LAW:no-silent-failure]
    if (family === 0) throw new Error(`listen: this host binds only to a literal IP address, not ${JSON.stringify(hostname)}`);
    if (typeof net._createServerHandle !== 'function') {
      throw new Error('listen: this node has no net._createServerHandle, so a port cannot be bound before listen() returns');
    }
    // A uv errno rather than a handle is how this reports a failed bind.
    const handle = net._createServerHandle(hostname, port, family);
    if (typeof handle === 'number') throw new Error(`listen: could not bind ${hostname}:${port} (uv error ${handle})`);

    const server = net.createServer();
    // Tracked so `stop(true)` can cut the connections that are still open, which is what its
    // argument means and what every caller here passes.
    const live = new Set();
    server.on('connection', (raw) => {
      live.add(raw);
      raw.on('close', () => live.delete(raw));
      const socket = bunSocket(raw, handlers, onAbsentApi);
      handlers.open?.(socket);
    });
    server.on('error', (e) => handlers.error?.(null, e));
    server.listen({ handle });

    return recording('TCPSocketListener', {
      get port() { return server.address()?.port ?? port; },
      get hostname() { return hostname; },
      stop(closeActive) {
        server.close();
        if (closeActive) for (const raw of live) raw.destroy();
      },
      ref() { server.ref(); return this; },
      unref() { server.unref(); return this; },
    }, onAbsentApi);
  };

  // Resolves once the connection is up, rejects if it never comes up. After that the socket's own
  // `error` handler owns every failure — which is why the pre-connect listener is removed rather
  // than left to fire into a promise that has already settled.
  const connect = (options = {}) => new Promise((resolve, reject) => {
    const handlers = options.socket ?? {};
    const raw = net.connect({ host: options.hostname, port: options.port });
    const failed = (e) => reject(e);
    raw.once('error', failed);
    raw.once('connect', () => {
      raw.off('error', failed);
      const socket = bunSocket(raw, handlers, onAbsentApi);
      handlers.open?.(socket);
      resolve(socket);
    });
  });

  return { listen, connect };
};

module.exports = { createSockets, bunSocket, toBytes };
