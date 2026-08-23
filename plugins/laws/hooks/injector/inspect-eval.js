#!/usr/bin/env node
// inspect-eval.js — the injector's foundation: attach to a running Claude Code process over
// Bun's inspector and evaluate JavaScript inside it. Part B of the craft-compatibility gate
// (Part A = laws-excise.js, the transcript surgery) is built ON this channel.
//
// Claude Code ships as a Bun-compiled standalone (Mach-O). Set BUN_INSPECT to a ws URL and the
// process opens a WebKit/JSC inspector on that socket — no code patch, just an env var, so it
// survives every weekly minified release. This module speaks the minimum of that protocol:
// enable Runtime, evaluate an expression in the process's GLOBAL scope, read the value back.
//
// VERIFIED on the shipped 2.1.226 binary (see SEAMS.md for the full record):
//   - BUN_INSPECT="ws://127.0.0.1:<port>/dbg?wait=1" opens the listener and blocks at entry.
//   - Runtime.evaluate returns live values from the running process (pid, argv, globalThis).
//   - Works against a LIVE INTERACTIVE TUI session, not only a fast-exiting `--help`.
//   - injectStdin() drives the session's own input path (process.stdin.push), so built-in
//     slash commands (/context, /compact, /clear, ...) run exactly as if typed. This is how
//     the gate reloads the session after transcript surgery, using Claude's own mechanisms.
//
// FRONTIER (why the four-choice reload is not finished here): the live conversation/message
// store is NOT reachable from global scope — `require`/`module` are undefined in the eval
// context and no session global exists; the store is closure-local. Reaching it (to reload an
// edited transcript in place, no relaunch) needs an in-CLOSURE pause — a Debugger breakpoint at
// the skill-load funnel (SEAM 1) or the resume path (SEAM 2), then evaluateOnCallFrame. That
// step, and the choice between it and restart-in-place (`claude --resume`), is the open work.
//
// [LAW:effects-at-boundaries] all I/O (the socket) lives here at the edge; callers get a small
//   promise-returning API. [LAW:no-silent-failure] a protocol exception surfaces in the result
//   rather than being swallowed; the CLI exits non-zero on error or timeout.

'use strict';

// Open the inspector socket and return { evaluate, injectStdin, close }. `wsurl` is the exact
// ws URL set in BUN_INSPECT (e.g. ws://127.0.0.1:9933/dbg) — for the compiled binary there is no
// http://host/json/list discovery endpoint; the ws URL you set IS the endpoint.
function connect(wsurl, { timeoutMs = 15000 } = {}) {
  const J = JSON.stringify;
  const ws = new WebSocket(wsurl);
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const i = ++id;
    pending.set(i, { resolve, reject });
    ws.send(J({ id: i, method, params }));
  });
  // A CDP reply carries EITHER `result` OR `error` — they are the two arms of one response, so
  // the arm is what decides resolve vs reject. Resolving both alike would hand `evaluate` an
  // object with no `result`, which it cannot tell from a call that legitimately returned
  // undefined: a refusal by the inspector would read as a successful evaluation returning
  // nothing. [LAW:no-silent-failure] [LAW:parse-dont-validate] the caller receives a value only
  // on the arm that actually carries one.
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (!m.id || !pending.has(m.id)) return;
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) {
      const err = m.error;
      reject(new Error('inspector error ' + (err.code !== undefined ? err.code + ': ' : '') +
                       (err.message || J(err))));
      return;
    }
    resolve(m);
  };
  // The connect timeout is CLEARED once `ready` settles, because a pending Node timer keeps the
  // event loop alive: left running, every user of this module sat for the full timeoutMs after
  // its work was done (measured: work complete at 6ms, process exit at 15007ms). That tail is
  // not cosmetic here — `laws-switch` runs as a Bash tool call INSIDE the session it just told
  // to exit, so the session cannot finish the call and act on the queued /exit until the timer
  // fires, and the user watches an already-successful switch do nothing for fifteen seconds.
  //
  // Cleared on settle rather than `.unref()`-ed: an unref-ed timer stops holding the loop open
  // but also stops being a dependable timeout, and a connect that genuinely hangs must still
  // fail loudly. This removes the tail without weakening the guarantee. [LAW:no-silent-failure]
  let readyTimer;
  const ready = new Promise((resolve, reject) => {
    ws.onopen = async () => { try { await send('Runtime.enable'); resolve(); } catch (err) { reject(err); } };
    ws.onerror = (e) => reject(new Error('inspector ws error: ' + String(e && e.message || e)));
    readyTimer = setTimeout(() => reject(new Error('inspector connect timeout after ' + timeoutMs + 'ms')), timeoutMs);
  });
  const clearReadyTimer = () => clearTimeout(readyTimer);
  ready.then(clearReadyTimer, clearReadyTimer);   // both arms; the derived promise is discarded

  // Evaluate an expression in the process's global context. Rejects (never silently) on either
  // way this can fail: an uncaught exception INSIDE the process (exceptionDetails, handled here)
  // and a refusal BY the inspector (a CDP error reply, handled in onmessage above). Both arms
  // matter — only the first was covered once, and a refused evaluate then returned undefined,
  // indistinguishable from an expression that legitimately evaluated to nothing.
  // [LAW:no-silent-failure]
  async function evaluate(expression, { awaitPromise = true, returnByValue = true } = {}) {
    const r = await send('Runtime.evaluate', { expression, awaitPromise, returnByValue });
    const res = r.result || {};
    if (res.exceptionDetails) {
      const ex = res.exceptionDetails;
      throw new Error('eval exception: ' + (ex.exception && ex.exception.description || ex.text || J(ex)));
    }
    return res.result ? res.result.value : undefined;
  }

  // Drive the session's own stdin as if the bytes were typed. The TUI reads stdin in pull mode
  // (paused ReadStream, a 'readable' listener, no 'data' listener), so the correct primitive is
  // process.stdin.push(Buffer) — it fills the read queue and fires 'readable'. A trailing '\r'
  // submits. This runs built-in commands through the real dispatch path, single source of truth.
  // The injected expression catches its own throw and hands back "ERR:<message>" — a value that
  // crosses the socket as an ordinary successful result. Returning that to the caller would be an
  // answer-shaped void: it has the shape of a real return while meaning "I could not do my job",
  // and the one caller that matters (laws-switch, driving /exit to complete a craft switch) does
  // not inspect the return value, so the push failing and the push succeeding look identical.
  // "pushed" is the ONLY value that means the bytes landed; everything else is a failure and is
  // raised as one, which routes it into laws-switch's existing catch — the recovery path that
  // tells the user to exit manually already exists, nothing was reaching it.
  // [LAW:no-silent-failure] [LAW:parse-dont-validate] the check yields "the bytes landed", not a
  // string the caller must re-interpret.
  async function injectStdin(text) {
    const expr = '(function(){try{process.stdin.push(Buffer.from(' + J(text) + '));return "pushed"}'
      + 'catch(e){return "ERR:"+(e&&e.message||String(e))}})()';
    const r = await evaluate(expr, { returnByValue: true });
    if (r !== 'pushed') throw new Error('stdin injection failed: ' + (r === undefined ? 'no value returned' : String(r)));
    return r;
  }

  function close() { try { ws.close(); } catch (_e) {} }
  return { ready, evaluate, injectStdin, close };
}

// A one-call reproducible check that the primitives still hold on the current binary — run this
// first thing after a Claude Code update to catch inspector/protocol drift in seconds.
async function probe(wsurl) {
  const c = connect(wsurl);
  await c.ready;
  const v = await c.evaluate('({ pid:(typeof process!=="undefined"?process.pid:null),'
    + ' hasGlobalThis:typeof globalThis, hasFetch:typeof (globalThis.fetch),'
    + ' argv:(typeof process!=="undefined"&&process.argv)?process.argv.slice(0,3):null })');
  c.close();
  return v;
}

module.exports = { connect, probe };

if (require.main === module) {
  const [wsurl, mode, arg] = process.argv.slice(2);
  if (!wsurl) { process.stderr.write('usage: inspect-eval.js <wsurl> [--probe | --eval <expr> | --inject <text>]\n'); process.exit(2); }
  (async () => {
    try {
      if (!mode || mode === '--probe') { process.stdout.write(JSON.stringify(await probe(wsurl)) + '\n'); return; }
      const c = connect(wsurl); await c.ready;
      if (mode === '--eval') process.stdout.write(JSON.stringify(await c.evaluate(arg)) + '\n');
      else if (mode === '--inject') process.stdout.write(JSON.stringify(await c.injectStdin(arg)) + '\n');
      else { process.stderr.write('unknown mode: ' + mode + '\n'); process.exit(2); }
      c.close();
    } catch (err) { process.stderr.write('inspect-eval: ' + (err && err.message || String(err)) + '\n'); process.exit(1); }
  })();
}
