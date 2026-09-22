// recording.js — the one way this injector answers "that member isn't here".
//
// The surface's whole discipline is that a member is either a real implementation or ABSENT, and
// that absence is recorded by name rather than handed back as a silent `undefined`. This is the
// mechanism behind the second half: a Proxy that forwards everything it has and reports, by full
// dotted name, everything it does not. It lives in its own file because three unrelated things need
// it — the `Bun` global, the namespaces under it, and the objects the socket and image members hand
// back — and two copies of it would eventually name the same absence two different ways.
// [LAW:one-source-of-truth]
//
// [LAW:one-way-deps] this module depends on nothing, so everything may depend on it.

'use strict';

// Keys the LANGUAGE asks for, not the app. `then` is read by promise resolution on anything it is
// handed — `Bun.connect` resolves with a socket, and without this every dial reported a missing
// `Socket.then`. Symbols are the same story from a different direction: `inspect.custom`,
// `Symbol.iterator` and friends are runtime protocol, never a Bun API the graph named. Recording
// either would fill the boot report with absences nobody can act on, which costs the report the
// thing it exists for. [LAW:no-silent-failure] cuts both ways: a signal drowned is a signal lost.
const INTEROP_KEYS = new Set(['then']);

// `name` is the path the graph reads through, so what lands in the boot report is the expression the
// app actually wrote: `Bun.ant.getPeerPid`, not "getPeerPid on some object".
const recording = (name, members, onAbsentApi) => new Proxy(members, {
  get(target, key) {
    if (key in target) return target[key];
    if (typeof key === 'symbol' || INTEROP_KEYS.has(key)) return undefined;
    onAbsentApi(name + '.' + String(key));
    // undefined, not a stub function: `if (socket.flush)` has to be able to answer no. A truthy
    // stub makes feature detection take the branch that then gets nothing back.
    return undefined;
  },
});

module.exports = { recording };
