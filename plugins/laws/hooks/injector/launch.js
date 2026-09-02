#!/usr/bin/env node
// launch.js — start a Claude Code session, hosted if the graph can be hosted and stock if it cannot.
//
// A user who opts into the hosted session must never end up with a broken one. So this launcher does
// not decide between two code paths; it runs a LIST OF PLANS in order and keeps the first that boots.
// Every plan is the same operation — spawn this argv, watch the boot channel — and they differ only
// in their data, which is what keeps the fail-safe from being a special case that skips setup.
// [LAW:dataflow-not-control-flow] Adding a plan is adding a value.
//
// The last plan is stock `claude`, which is declared booted the moment it starts: it is the floor,
// not a candidate, and there is nothing after it to fall back to.
//
// WHY THE VERDICT IS FORMED HERE. bun-host.mjs reports only what it can see — `painted` the first
// time the hosted graph writes to the terminal, or a named refusal — and never decides. The failures
// this guards against are not visible from inside: a HANG, where a boot-critical Bun API returns
// undefined and the first render throws a TypeError the app swallows, so nothing further happens at
// all; and its louder cousin, where the app prints a notice and then dies on that same TypeError.
// Neither is distinguishable from inside the host — one needs a clock and the other needs to watch
// the process afterwards — so both belong to whoever can act on them.
// [LAW:no-ambient-temporal-coupling] one owner for the timing, named here.
//
// Once a plan has become the session it OWNS it: a later crash is that session's business, and is
// never answered by starting a second session on top of whatever the first one already did.

'use strict';

const childProcess = require('child_process');
const path = require('path');

// Measured on 2.1.258: ~800ms to link 1,640 modules and ~700ms more to the first frame. The deadline
// is an order of magnitude of headroom over that, because the cost of waiting too long is a slow
// start and the cost of waiting too little is falling back on a session that was about to work.
const BOOT_DEADLINE_MS = 15000;

// How long a plan must survive its first paint before it counts as the session. Long enough that the
// app's own fatal-error path (which prints, then exits) lands inside it, short enough to be invisible.
const BOOT_SETTLE_MS = 5000;

const BOOT_FD = 3;
const HOST = path.join(__dirname, 'bun-host.mjs');

// Enough of a reset that a plan which died mid-render cannot leave the terminal owning raw mode, a
// hidden cursor, or the alternate screen. Applied before the next plan starts, never after a boot.
const TERMINAL_RESET = '\u001b[?1049l\u001b[?25h\u001b[?2004l\u001b[0m';

// The plans, in order. `reports` says whether a plan speaks on the boot channel: the hosted one does,
// and stock claude is the floor — it is the session by definition and there is nothing after it.
function plans(binaryPath, userArgs) {
  return [
    {
      name: 'hosted',
      command: process.execPath,
      // --experimental-vm-modules: the host links Bun's module graph itself (bun-host.mjs explains
      // why node's own loader cannot). The warning is silenced because this process shares the
      // user's terminal with a TUI.
      args: ['--experimental-vm-modules', '--disable-warning=ExperimentalWarning', HOST, binaryPath, ...userArgs],
      env: { ...process.env, CLAUDE_LAWS_BOOT_FD: String(BOOT_FD) },
      reports: true,
    },
    {
      name: 'stock',
      command: binaryPath,
      args: userArgs,
      env: process.env,
      reports: false,
    },
  ];
}

// Run one plan to a verdict. Resolves { booted: true, code } once the plan became the session and
// that session has finished, or { booted: false, reason } if it never became one.
//
// A plan became the session when it painted the terminal AND was still there a moment later. Painting
// alone is not enough — a boot-critical API that returns undefined lets the app print a notice and
// then die on the TypeError, which reads as output but is not a session. Two things are booted
// despite an early exit, and neither may ever be re-run: a clean exit, which is what a one-shot
// command does, and any exit at all when this is not an interactive terminal, where the run may have
// already done real work.
//
// The child is given the real terminal on stdio 0-2 — a pipe would make isTTY false and there would
// be no TUI to check — so its reports travel on a descriptor of their own.
function run(plan, {
  deadlineMs = BOOT_DEADLINE_MS,
  settleMs = BOOT_SETTLE_MS,
  interactive = Boolean(process.stdin.isTTY && process.stdout.isTTY),
  spawn = childProcess.spawn,
} = {}) {
  return new Promise((resolve) => {
    const child = spawn(plan.command, plan.args, {
      stdio: ['inherit', 'inherit', 'inherit', plan.reports ? 'pipe' : 'ignore'],
      env: plan.env,
    });

    let paintedAt = 0;
    let refusal = '';
    const absentApis = [];
    let timer = null;

    // Whatever went wrong, say which Bun APIs this shim did not have. On a hang that list is the
    // whole diagnosis, and it is the one thing the killed host can no longer tell anyone itself.
    const because = (reason) => reason + (absentApis.length ? ` (Bun APIs the shim does not have: ${absentApis.join(', ')})` : '');

    if (plan.reports) {
      timer = setTimeout(() => {
        // Settle the verdict BEFORE killing: the child's exit must not be able to answer for the
        // deadline just because it arrived first. [LAW:no-ambient-temporal-coupling]
        resolve({ booted: false, reason: because(`nothing painted within ${deadlineMs}ms`) });
        child.kill('SIGKILL');
      }, deadlineMs);
      let pending = '';
      child.stdio[BOOT_FD].on('data', (chunk) => {
        pending += chunk.toString();
        const lines = pending.split('\n');
        pending = lines.pop();
        for (const line of lines) {
          if (line === 'painted') { paintedAt = paintedAt || Date.now(); clearTimeout(timer); }
          else if (line.startsWith('absent-api ')) absentApis.push(line.slice('absent-api '.length));
          else if (line) refusal = line; // a named refusal; the exit handler carries it out
        }
      });
      child.stdio[BOOT_FD].on('error', () => {});
    }

    child.on('error', (e) => { clearTimeout(timer); resolve({ booted: false, reason: `could not start ${plan.command}: ${e.message}` }); });
    child.on('exit', (code, signal) => {
      clearTimeout(timer);
      const exit = code === null ? 128 : code;
      // The floor has no successor, so there is no decision to make: it IS the session, whatever it
      // did. Every rule below exists only to answer "should the next plan be tried instead?".
      if (!plan.reports) return resolve({ booted: true, code: exit });
      if (!paintedAt) return resolve({ booted: false, reason: because(refusal || `exited ${signal || code} before painting anything`) });
      const lived = Date.now() - paintedAt;
      if (exit === 0 || !interactive || lived >= settleMs) return resolve({ booted: true, code: exit });
      resolve({ booted: false, reason: because(`painted, then exited ${exit} after ${lived}ms — never became a session`) });
    });
  });
}

// Run the plans in order and return the exit code of the one that booted.
async function launch(binaryPath, userArgs, io = {}) {
  const log = io.log || ((line) => process.stderr.write(line + '\n'));
  const reset = io.reset || (() => { if (process.stdout.isTTY) process.stdout.write(TERMINAL_RESET); });
  const runPlan = io.run || run;

  const candidates = io.plans || plans(binaryPath, userArgs);
  for (const plan of candidates) {
    const result = await runPlan(plan, io);
    if (result.booted) return result.code;
    // [LAW:no-silent-failure] the degrade is never quiet: the next session is not the one the user
    // asked for, and the reason it is not has to be findable.
    log(`claude-laws: ${plan.name} session did not start — ${result.reason}; falling back`);
    reset();
  }
  // Unreachable while the last plan is the floor; if the list ever ends without one, say so loudly
  // rather than exiting 0 on a session that never ran.
  log('claude-laws: no plan produced a session');
  return 70;
}

module.exports = { BOOT_DEADLINE_MS, BOOT_SETTLE_MS, BOOT_FD, TERMINAL_RESET, plans, run, launch };

if (require.main === module) (async function main() {
  const [binaryPath, ...userArgs] = process.argv.slice(2);
  if (!binaryPath) {
    process.stderr.write('usage: launch.js <installed-claude-binary> [claude args...]\n');
    process.exit(2);
  }
  process.exitCode = await launch(binaryPath, userArgs);
})();
