// switch-channel.js — the request/response channel between `laws-switch` and the hosted session.
//
// WHY THIS EXISTS INSTEAD OF BUN_INSPECT. This channel authenticates nobody, and no local socket
// can: at equal privilege a hostile process and `laws-switch` are indistinguishable. The only thing
// a channel controls is its VOCABULARY. The inspector's was "evaluate this string in your global
// scope". This one's is "apply one of these four named choices to the switch already pending" — the
// request carries a choice, and which transcript, craft and session it concerns come from the
// pending offer, read by the server rather than accepted from the caller. Equal privilege still
// means equal capability; the gain is that the capability is now small.
//
// WHY BOTH HALVES LIVE HERE. A writer and a reader that each carry their own idea of a protocol have
// two ideas of it, and the day they differ the client reports success for a switch that never
// happened. [LAW:one-source-of-truth]
//
// [LAW:effects-at-boundaries] `net` and the socket path are parameters, so both halves are testable
//   over a pair of in-memory streams with no filesystem and no listener.
// [LAW:no-ambient-temporal-coupling] one connection carries one request and one response and is then
//   closed. Nothing is left listening between switches, and no later behaviour depends on when a
//   previous connection happened to end.

'use strict';

const path = require('path');
// How an error becomes a human-readable detail has ONE spelling in this tree, and it already exists.
// A second one here would drift from it, and would also be worse: stringifying the message alone
// renders a thrown non-Error as the word "undefined", which this handles. [LAW:one-source-of-truth]
const { because } = require('./boot-guard.js');

// The socket lives in the handoff directory the launcher already creates with mktemp -d, so it
// inherits that directory's 0700 permissions rather than inventing a location with its own.
const SOCKET_NAME = 'switch.sock';
const socketPathIn = (dir) => path.join(dir, SOCKET_NAME);

// One JSON object per line, one line each way. Nothing strips newlines out of the payload because
// nothing has to: JSON.stringify escapes them to the two characters `\` and `n`, so a reason
// carrying a newline — an error message with a stack, say — is already a single line by the time it
// reaches the separator. A guard here would be code defending against a state the encoding makes
// unrepresentable. [LAW:no-defensive-null-guards]
const RECORD_SEPARATOR = '\n';
// A switch request is a handful of short fields; anything approaching this is not one. The cap and
// the idle timeout exist for the same reason: this listener lives inside the user's running session,
// and a peer that opens a connection and then does nothing must not be able to hold resources there.
const MAX_RECORD_BYTES = 1 << 20;
const IDLE_MS = 30000;
const encode = (value) => {
  const json = JSON.stringify(value);
  // `JSON.stringify` RETURNS undefined for undefined, a function or a symbol rather than throwing,
  // so concatenating blindly would put the literal text "undefined" on the wire and the far end
  // would report a parse error — a real defect in the caller, disguised as a transport fault. This
  // is the one place both directions pass through, so it is the one place that has to notice.
  // [LAW:no-silent-failure]
  if (typeof json !== 'string') throw new TypeError('a ' + typeof value + ' cannot be encoded as a record');
  return json + RECORD_SEPARATOR;
};

// Every way the channel itself can fail to carry a switch, named — distinct from the reasons the
// ENACTMENT can refuse, which come back inside a well-formed response. [LAW:no-silent-failure]
// The two refusals the SERVER originates, named here so the client can recognise them and the tests
// cannot drift from the spelling. [LAW:one-source-of-truth]
const THREW = 'the-switch-threw';
// Split by WHEN it happens, because that is what decides whether the switch may already have run.
// The client's failure happens before a byte is written, so nothing was delivered; the server's
// happens after `onRequest` has already driven the app's own rewind. One reason for both would give
// the CLI a string it cannot act on — the origin is exactly the part it needs.
const UNSENT = 'the-switch-request-could-not-be-encoded-and-was-never-sent';
const UNENCODABLE = 'the-switch-ran-but-its-answer-could-not-be-encoded';
// The server failing to parse the CLIENT's request is the opposite fault from the client failing to
// parse the server's reply, and reusing UNREACHABLE.malformed for it told the caller "the hosted
// session answered with something that is not a response" — pointing at the wrong end of the wire.
const UNPARSEABLE = 'the-switch-request-could-not-be-parsed';

// Split by ONE question: did the request provably never arrive? Only `noSocket` — the connection
// itself never opened — can answer yes, and only that answer lets a caller tell the user nothing
// happened. A peer that accepted and then went quiet may have enacted the switch already, so it gets
// its own reason rather than being folded in with a refused connection. [LAW:no-silent-failure]
const UNREACHABLE = {
  noSocket: 'no-hosted-session-is-listening',
  noAnswer: 'the-hosted-session-accepted-the-switch-and-then-closed-without-answering',
  timeout: 'the-hosted-session-did-not-answer',
  malformed: 'the-hosted-session-answered-with-something-that-is-not-a-response',
};

// Read a stream until the first record separator, then hand over exactly one parsed value. Anything
// after the first line is ignored by construction: this protocol is one request, one response.
function readOneRecord(socket, { onRecord, onMalformed, maxBytes = MAX_RECORD_BYTES }) {
  let buffer = '';
  // Counted rather than read off `buffer.length`: `setEncoding` below makes that UTF-16 code units,
  // which undercounts UTF-8 by up to 3x — a peer sending CJK would get three times the cap.
  let bytes = 0;
  let settled = false;
  socket.setEncoding('utf8');
  socket.on('data', (chunk) => {
    if (settled) return;
    buffer += chunk;
    bytes += Buffer.byteLength(chunk, 'utf8');
    // A peer that streams without ever sending a separator would otherwise grow this buffer without
    // limit. The threat model here names such a peer explicitly — any local process can reach the
    // socket — so the bound is enforced rather than assumed. [LAW:no-silent-failure]
    if (bytes > maxBytes) {
      settled = true;
      onMalformed(new Error('record exceeded ' + maxBytes + ' bytes without a separator'));
      return;
    }
    const end = buffer.indexOf(RECORD_SEPARATOR);
    if (end === -1) return;
    settled = true;
    // A record that does not parse is a fact about the peer, not a value to pass on: handing a
    // half-read object downstream is how a switch reports success it never had.
    try { onRecord(JSON.parse(buffer.slice(0, end))); }
    catch (e) { onMalformed(e); }
  });
}

// The hosted session's half. `onRequest` is async and returns the response object; whatever it
// returns is what the caller sees, so the enactment's own named refusals travel back intact.
function createSwitchServer({ net, dir, onRequest, onError, idleMs = IDLE_MS }) {
  const server = net.createServer((socket) => {
    // A connection that breaks mid-switch is the peer's business, and it must not take the session
    // down with it — this listener lives inside the user's running Claude Code.
    socket.on('error', (e) => onError(e));
    // A peer that connects and then says nothing is dropped rather than held. The client's half has
    // always had a deadline; the server's needs one for the same reason and did not have it.
    socket.setTimeout(idleMs, () => socket.destroy());
    readOneRecord(socket, {
      onRecord: async (request) => {
        // The WHOLE body is guarded, not just the enactment. `onRecord` is async and is invoked
        // fire-and-forget from the data handler, so anything escaping here becomes an unhandled
        // rejection — which can take down the hosted Claude Code session this listener lives inside,
        // the exact outcome the comment above promises will never happen. `encode` is the live risk:
        // its contract accepts whatever a caller's onRequest returns, and a circular structure or a
        // Map does not survive JSON.stringify. [LAW:no-silent-failure]
        let response;
        try { response = await onRequest(request); }
        catch (e) { response = { ok: false, reason: THREW, detail: because(e) }; }
        try { socket.end(encode(response)); }
        catch (e) {
          // The answer itself could not be written. Say so in a shape that always encodes, and if
          // even that fails there is nothing left to say it with — close, and let the client's own
          // no-answer path name it.
          try { socket.end(encode({ ok: false, reason: UNENCODABLE, detail: because(e) })); }
          catch { socket.destroy(); }
          onError(e);
        }
      },
      onMalformed: (e) => socket.end(encode({ ok: false, reason: UNPARSEABLE, detail: because(e) })),
    });
  });
  server.on('error', (e) => onError(e));
  server.listen(socketPathIn(dir));
  // unref so a listening socket never becomes the reason the session refuses to exit.
  if (server.unref) server.unref();
  return { server, close: () => server.close() };
}

// `laws-switch`'s half. Resolves with the session's response, or with a named unreachable — never
// rejects, because every outcome here is something the caller has to report rather than throw.
function requestSwitch({ net, dir, request, timeoutMs = 15000 }) {
  return new Promise((resolve) => {
    // This latch is for READABILITY, not correctness: resolving an already-settled promise is
    // itself a no-op, so every arm below may fire without harm. It says out loud that exactly one
    // of them is meant to win.
    //
    // It is therefore an EQUIVALENT MUTANT and the one deliberate SURVIVOR of the mutation sweep:
    // flipping this initialiser changes no observable behaviour, so no test can kill it. Named here
    // in the words a reader would actually grep for, because the record in SEAMS.md sends them
    // looking.
    let settled = false;
    const finish = (value) => { if (!settled) { settled = true; resolve(value); } };
    // Whether the connection ever opened is the fact that decides whether a caller may say "nothing
    // was changed", so it is tracked rather than inferred from which handler fired first.
    let connected = false;
    const socket = net.createConnection(socketPathIn(dir));
    const timer = setTimeout(() => { socket.destroy(); finish({ ok: false, reason: UNREACHABLE.timeout }); }, timeoutMs);
    if (timer.unref) timer.unref();
    const done = (value) => { clearTimeout(timer); socket.end(); finish(value); };

    // No listener means no hosted session — the stock binary, or a host that failed its boot check.
    // That is a different fact from a session that answered with a refusal, and the caller acts on
    // it differently, so it must not be collapsed into one. It is also different from a connection
    // that opened and then broke: the same `connected` question decides both this arm and `close`,
    // because a socket reset after acceptance may have enacted the switch before it died.
    socket.on('error', (e) => done({
      ok: false, reason: connected ? UNREACHABLE.noAnswer : UNREACHABLE.noSocket, detail: because(e),
    }));
    // Guarded for the same reason the server's reply is: this runs inside a plain event listener, so
    // a throw here is uncaught and takes the laws-switch process down instead of coming back as a
    // reason the caller can report.
    socket.on('connect', () => {
      connected = true;
      try { socket.write(encode(request)); }
      catch (e) { done({ ok: false, reason: UNSENT, detail: because(e) }); }
    });
    readOneRecord(socket, {
      onRecord: (response) => done(response),
      onMalformed: (e) => done({ ok: false, reason: UNREACHABLE.malformed, detail: because(e) }),
    });
    // A peer that closes without answering has not answered. Without this the promise would hang
    // until the timeout and report the wrong reason for the right failure. WHICH failure depends on
    // whether it ever accepted us: a refused connection proves the request never arrived, while one
    // that was accepted and then dropped may have enacted the switch before going quiet.
    socket.on('close', () => done({
      ok: false, reason: connected ? UNREACHABLE.noAnswer : UNREACHABLE.noSocket,
    }));
  });
}

module.exports = {
  SOCKET_NAME, socketPathIn, RECORD_SEPARATOR, MAX_RECORD_BYTES, IDLE_MS,
  UNREACHABLE, THREW, UNENCODABLE, UNSENT, UNPARSEABLE,
  // The reasons that PROVE the request never reached a session. Everything else — named or not —
  // may have run, so a caller enumerates this set and treats the rest as uncertain. Enumerating the
  // unsafe side instead is what let UNENCODABLE be forgotten. [LAW:dataflow-not-control-flow]
  PROVABLY_NOT_DELIVERED: [UNREACHABLE.noSocket, UNSENT],
  encode, createSwitchServer, requestSwitch,
  // Exported for its own tests: the reader's latching and its buffer cap are reachable through a
  // socket only by streaming a megabyte, which is a slow way to assert a one-line invariant.
  __readOneRecordForTest: readOneRecord,
};
