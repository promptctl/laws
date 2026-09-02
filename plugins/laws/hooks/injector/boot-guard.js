// boot-guard.js — name a crash that happens DURING boot, and stop watching once boot is over.
//
// Two failures this exists between. Without a guard, a throw outside every try/catch takes the
// process down with nothing on the boot channel, so the launcher sees a bare nonzero exit and can
// say only that something died. With a guard that outlives boot, every later crash — an unrelated
// bug hours into a live session — is reported as `EXIT_NOT_BOOTED` too, which tells whatever reads
// the wrapper's exit code that the session never started. That is a different fact, and a false one.
//
// So the guard is scoped: installed before anything that can throw, released the moment control has
// been handed to the app and boot is genuinely over. After that a crash is the app's, and node's own
// handling is what it expects. [LAW:no-ambient-temporal-coupling] the lifetime has one owner and an
// explicit end, rather than lasting however long nobody got round to removing it.
//
// Everything effectful is a parameter, so the whole thing is testable with no process to crash.
// [LAW:effects-at-boundaries]

'use strict';

const EXIT_NOT_BOOTED = 70;

const EVENTS = [['uncaughtException', 'uncaught'], ['unhandledRejection', 'unhandled-rejection']];

// A thrown value is not always an Error; `e.message` on a thrown string is undefined, and an
// undefined reason is the silence the boot channel exists to prevent.
const because = (e) => (e && e.message) || String(e);

function installBootGuard({ on, off, exit, send }) {
  const installed = EVENTS.map(([event, label]) => {
    const handler = (e) => {
      send(`boot-threw ${label}: ${because(e)}`);
      exit(EXIT_NOT_BOOTED);
    };
    on(event, handler);
    return [event, handler];
  });
  let released = false;
  return {
    // Idempotent: boot ends once, and a second call must not remove somebody else's handler.
    bootIsOver() {
      if (released) return;
      released = true;
      for (const [event, handler] of installed) off(event, handler);
    },
    get watching() { return !released; },
  };
}

module.exports = { EXIT_NOT_BOOTED, because, installBootGuard };
