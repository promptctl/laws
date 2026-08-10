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
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id).resolve(m); pending.delete(m.id); }
  };
  const ready = new Promise((resolve, reject) => {
    ws.onopen = async () => { try { await send('Runtime.enable'); resolve(); } catch (err) { reject(err); } };
    ws.onerror = (e) => reject(new Error('inspector ws error: ' + String(e && e.message || e)));
    setTimeout(() => reject(new Error('inspector connect timeout after ' + timeoutMs + 'ms')), timeoutMs);
  });

  // Evaluate an expression in the process's global context. Rejects (never silently) if the
  // process reports an uncaught exception. [LAW:no-silent-failure]
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
  function injectStdin(text) {
    const expr = '(function(){try{process.stdin.push(Buffer.from(' + J(text) + '));return "pushed"}'
      + 'catch(e){return "ERR:"+(e&&e.message||String(e))}})()';
    return evaluate(expr, { returnByValue: true });
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
