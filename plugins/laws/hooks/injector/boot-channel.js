// boot-channel.js — the line protocol bun-host.mjs reports on and launch.js reads.
//
// The host says only what it can see and never decides; the launcher forms the verdict. The four
// things a host can observe are here, in one place, because a protocol with a writer and a reader
// that each carry their own idea of it has two ideas of it. [LAW:one-source-of-truth]
//
//   started            — control has passed to the hosted app. Before this nothing the user asked
//                        for has run, so a failure is always safe to replace; after it, the app owns
//                        whatever it did and re-running would repeat it. Reported rather than
//                        inferred from whether stdout happened to see a byte.
//   painted            — the hosted graph first wrote to the terminal. Not proof of a working
//                        session — a pre-flight notice counts — but a session that never paints at
//                        all is the hang the whole check exists to catch.
//   absent-api <name>  — a Bun member the graph asked for that the surface does not have. Sent as
//                        each is seen, not collected at the end, because the failure worth
//                        diagnosing is the one where this process never reaches an end.
//   anything else      — a named refusal, carried out as the reason.
//
// [LAW:no-silent-failure] every degrade leaves here, named.

'use strict';

const RECORD_SEPARATOR = '\n';
const STARTED = 'started';
const PAINTED = 'painted';
const ABSENT_API = 'absent-api ';

// A newline inside a message would arrive as several records, so a reason carrying one — an error
// with a multi-line message, say — would be read as a refusal followed by garbage.
const oneRecord = (line) => String(line).replace(/[\r\n]+/g, ' ');

// `write` is a parameter so this is testable with no descriptor, and so the host can decide where
// the channel points. [LAW:effects-at-boundaries]
function createBootChannel({ write }) {
  let reported = false;
  const absent = new Set();
  const send = (line) => write(oneRecord(line) + RECORD_SEPARATOR);
  return {
    // The one-per-process VERDICT. Later observations still go out — a graph that painted and then
    // threw has spent its verdict, and the message it died with is the useful part.
    report(verdict) { if (reported) return; reported = true; send(verdict); },
    send,
    started() { send(STARTED); },
    absentApi(name) { if (absent.has(name)) return; absent.add(name); send(ABSENT_API + name); },
  };
}

// The reader's half. Returns what this line means, so the launcher never re-derives the protocol.
function readReport(line) {
  if (line === STARTED) return { kind: 'started' };
  if (line === PAINTED) return { kind: 'painted' };
  if (line.startsWith(ABSENT_API)) return { kind: 'absent-api', name: line.slice(ABSENT_API.length) };
  if (line) return { kind: 'refusal', reason: line };
  return { kind: 'blank' };
}

module.exports = { RECORD_SEPARATOR, STARTED, PAINTED, ABSENT_API, oneRecord, createBootChannel, readReport };
