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
const { StringDecoder } = require('string_decoder');
const { readReport } = require('./boot-channel.js');

// Measured on 2.1.258: ~800ms to link 1,640 modules and ~700ms more to the first frame. The deadline
// is an order of magnitude of headroom over that, because the cost of waiting too long is a slow
// start and the cost of waiting too little is falling back on a session that was about to work.
const BOOT_DEADLINE_MS = 15000;

// How long a plan must survive its first paint before it counts as the session. Long enough that the
// app's own fatal-error path (which prints, then exits) lands inside it, short enough to be invisible.
const BOOT_SETTLE_MS = 5000;

const BOOT_FD = 3;
const HOST = path.join(__dirname, 'bun-host.mjs');

// Sent before the next plan takes the terminal, never after a boot. The escape sequence puts the
// screen back; raw mode is not a screen state and has to be cleared through the tty itself, which
// `resetTerminal` below does — the sequence alone would leave the keyboard in the dead plan's mode.
const TERMINAL_RESET = '\u001b[?1049l\u001b[?25h\u001b[?2004l\u001b[0m';

// Put the terminal back the way a plan that died mid-render did not. Raw mode is the half an escape
// sequence cannot reach: a dead child's stdin mode outlives it, and the next plan would inherit a
// keyboard that echoes nothing.
function resetTerminal() {
  if (!process.stdout.isTTY) return;
  process.stdout.write(TERMINAL_RESET);
  if (process.stdin.isTTY && process.stdin.setRawMode) process.stdin.setRawMode(false);
}

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
// A plan that reports a NAMED refusal without painting never reached the user's command, so it is
// always replaced. Past that, a plan became the session when it painted the terminal AND was still
// there a moment later. Painting alone is not enough — a boot-critical API that returns undefined lets the app print a notice and
// then die on the TypeError, which reads as output but is not a session. Two exits are booted
// whatever else happened, and neither may ever be re-run: a clean exit, which is what a one-shot
// command does (silently, if all its output went to stderr), and any exit at all outside an
// interactive terminal, where the run may already have done real work.
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
    // Whether the hosted graph ever handed control to the app. Reported, not inferred: before it,
    // nothing the user asked for has run and a failure is always safe to replace; after it, the app
    // owns whatever it did and re-running would repeat it.
    let started = !plan.reports;
    let refusal = '';
    const absentApis = [];
    let timer = null;
    // The verdict needs both halves: how the process ended, and everything it reported. 'exit' fires
    // when the OS reaps the child, which can be BEFORE the last chunk buffered on the boot channel
    // has been delivered — so a plan that paints and immediately exits would read as never having
    // painted, and get re-run. [LAW:no-ambient-temporal-coupling] the verdict waits on both facts
    // rather than on which event happened to land first.
    let ended = null;
    let channelDone = !plan.reports;
    // Set when the deadline fired. The plan is killed then, but the verdict is not delivered until
    // the process is actually gone: handing the terminal to the next plan while the old one still
    // holds it is two sessions writing to one screen.
    let deadlineReason = null;
    const settle = () => {
      if (!ended || !channelDone) return;
      clearTimeout(timer);
      resolve(deadlineReason ? { booted: false, reason: deadlineReason } : verdict(ended));
    };

    // Whatever went wrong, say which Bun APIs this shim did not have. On a hang that list is the
    // whole diagnosis, and it is the one thing the killed host can no longer tell anyone itself.
    const because = (reason) => reason + (absentApis.length ? ` (Bun APIs the shim does not have: ${absentApis.join(', ')})` : '');

    // How an ended plan is judged. The floor has no successor, so there is no decision to make: it
    // IS the session, whatever it did. Every rule after it answers one question — should the next
    // plan be tried instead? — and the two exits that are never re-tried come FIRST, because they
    // are the ones where re-trying would repeat work the user already got: a clean exit is a
    // one-shot command finishing (silently, if all its output went to stderr), and outside an
    // interactive terminal there is no session to salvage, only a command that already ran.
    const verdict = ({ code, signal, at }) => {
      const exit = code === null ? 128 : code;
      if (!plan.reports) return { booted: true, code: exit };
      // A named refusal with nothing painted is a plan that never reached the user's command at all,
      // so there is no work to preserve and nothing to weigh: fall back, terminal or no terminal.
      // Without this the fail-safe switched itself off outside a tty, where a graph this host cannot
      // read would produce neither a fallback nor a log.
      // The app never ran, so there is nothing to preserve and nothing to weigh — replace it,
      // terminal or no terminal. Inferring this from "did stdout see a byte" is what let a host that
      // crashed before it could report anything be treated as a finished command in a pipe.
      if (!started) return { booted: false, reason: because(refusal || `exited ${signal || code} before the app started`) };
      if (refusal && !paintedAt) return { booted: false, reason: because(refusal) };
      if (exit === 0 || !interactive) return { booted: true, code: exit };
      if (!paintedAt) return { booted: false, reason: because(`exited ${signal || code} before painting anything`) };
      // Clamped: a paint report can arrive AFTER the exit, because the pipe outlives the process.
      // The paint really did happen first, so the honest reading of that ordering is a session that
      // lasted no time at all — not a negative one.
      const lived = Math.max(0, at - paintedAt);
      if (lived >= settleMs) return { booted: true, code: exit };
      const died = refusal ? `: ${refusal}` : '';
      return { booted: false, reason: because(`painted, then exited ${exit} after ${lived}ms — never became a session${died}`) };
    };

    if (plan.reports) {
      timer = setTimeout(() => {
        // The reason is fixed HERE, before the kill, so the exit it causes cannot answer for the
        // deadline that caused it. [LAW:no-ambient-temporal-coupling]
        deadlineReason = because(`nothing painted within ${deadlineMs}ms`);
        child.kill('SIGKILL');
      }, deadlineMs);
      const channel = child.stdio[BOOT_FD];
      // Decoded across chunk boundaries: a multi-byte character split between two reads would
      // otherwise become two replacement characters.
      const decoder = new StringDecoder('utf8');
      let pending = '';
      channel.on('data', (chunk) => {
        pending += decoder.write(chunk);
        const lines = pending.split('\n');
        pending = lines.pop();
        for (const line of lines) {
          // What a line MEANS is the protocol's business, not this loop's. [LAW:one-source-of-truth]
          const report = readReport(line);
          if (report.kind === 'started') started = true;
          else if (report.kind === 'painted') { paintedAt = paintedAt || Date.now(); clearTimeout(timer); }
          else if (report.kind === 'absent-api') absentApis.push(report.name);
          else if (report.kind === 'refusal') refusal = refusal || report.reason; // the FIRST: the root cause
        }
      });
      // A boot channel that fails to read is a lost diagnosis, not a non-event: without this the
      // failure reason would silently be the poorer one. [LAW:no-silent-failure]
      channel.on('error', (e) => { refusal = refusal || `boot channel unreadable: ${e.message}`; channelDone = true; settle(); });
      channel.on('end', () => { channelDone = true; settle(); });
      channel.on('close', () => { channelDone = true; settle(); });
    }

    child.on('error', (e) => { clearTimeout(timer); resolve({ booted: false, reason: `could not start ${plan.command}: ${e.message}` }); });
    // The instant of the exit, not the instant the verdict is formed: settle() also waits on the
    // boot channel closing, and a slow close would otherwise be counted as time the session lived.
    child.on('exit', (code, signal) => { ended = { code, signal, at: Date.now() }; settle(); });
  });
}

// Run the plans in order and return the exit code of the one that booted.
async function launch(binaryPath, userArgs, io = {}) {
  const log = io.log || ((line) => process.stderr.write(line + '\n'));
  const reset = io.reset || resetTerminal;
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

module.exports = { BOOT_DEADLINE_MS, BOOT_SETTLE_MS, BOOT_FD, TERMINAL_RESET, resetTerminal, plans, run, launch };

if (require.main === module) (async function main() {
  const [binaryPath, ...userArgs] = process.argv.slice(2);
  if (!binaryPath) {
    process.stderr.write('usage: launch.js <installed-claude-binary> [claude args...]\n');
    process.exit(2);
  }
  process.exitCode = await launch(binaryPath, userArgs);
})();
