#!/usr/bin/env node
// laws-excise.js — the runtime gate for craft compatibility. When a session tries to engage
// a craft skill INCOMPATIBLE with one already loaded, this offers a four-choice switch and
// enacts it by editing the ON-DISK session transcript. Part A of the mechanism (Part B = an
// injected self-resume that makes the running session re-read the edited file; this module is
// the pure transcript surgery + decision logic it depends on).
//
// A craft skill, when loaded via the Skill tool, lands as ONE transcript line:
//   type:"user", isMeta:true, sourceToolUseID:<Skill tool_use id>,
//   message.content[0] = { type:"text", text:"Base directory for this skill: <dir>\n\n<SKILL.md body>" }
// The laws media are code/prose/prompt/application-spec/chat — identified by a base dir ending
// in /skills/<medium>.
//
// COMPATIBILITY, NOT "ONE AT A TIME": crafts COEXIST by default. code+prose+ticket is normal,
// complementary work. What the gate fires on is a genuine INCOMPATIBLE pair — two standards
// that corrupt each other stacked — per the policy in incompatible-crafts.txt (today: only
// code<->prompt). Two compatible crafts on disk are left completely alone.
//
// Why tombstone, not delete: the transcript is a DAG keyed by uuid/parentUuid. Deleting a line
// orphans its children. Tombstoning preserves uuid/parentUuid/linkage and only empties the
// guidance text, so the superseded craft can no longer act but the conversation tree is intact.
//
// [LAW:one-source-of-truth] the incompatibility policy has ONE home — incompatible-crafts.txt —
//   read here AND by skill-router.sh; this module hard-codes no craft-pair rule.
// [LAW:single-enforcer] this file is the one place that decides what "loaded" means and which
//   engaged craft an incoming one must switch away from.
// [LAW:effects-at-boundaries] the pure core (parsePolicy/craftsIncompatible/findHits/decide/
//   exciseAt) never touches the filesystem; the edges (loadPolicy/run) do the I/O.
// [LAW:no-silent-failure] a parse/shape miss is passed through untouched, never dropped; a
//   missing policy file throws at the boundary rather than reading as "all crafts coexist".

'use strict';
const fs = require('fs');
const path = require('path');

const MEDIA = ['code', 'prose', 'prompt', 'application-spec', 'chat'];
// base dir ".../skills/<medium>" (tolerates the plugin-cache path and the repo path alike)
const BASEDIR_RE = new RegExp('/skills/(' + MEDIA.join('|') + ')(?:/|$|\\s)');
const PREFIX = 'Base directory for this skill:';
// The documented tombstone marker. A tombstoned line no longer starts with PREFIX, so it is
// already un-detectable as a live load; the marker is the explicit guard for idempotence.
const TOMBSTONE = '[TOMBSTONE]';

// --- policy: the boundary read + the pure predicate ------------------------------------------
// Parse the shared policy file's text into symmetric craft pairs. Pure: same shape the router's
// bash reader produces (strip '# comments', drop blank lines, split each pair on whitespace).
function parsePolicy(text) {
  return text.split('\n')
    .map((l) => l.replace(/#.*$/, '').trim())
    .filter(Boolean)
    .map((l) => l.split(/\s+/))
    .filter((p) => p.length >= 2)
    .map(([a, b]) => [a, b]);
}

// Boundary read of the shared policy file (default: sibling incompatible-crafts.txt). Throws on
// a missing/unreadable file — the caller at the edge decides whether to degrade; the pure core
// never silently treats an unread policy as "everything coexists". [LAW:effects-at-boundaries]
function loadPolicy(policyPath) {
  const p = policyPath || path.join(__dirname, 'incompatible-crafts.txt');
  return parsePolicy(fs.readFileSync(p, 'utf8'));
}

// True iff crafts a and b are an incompatible pair per the policy. Symmetric; pure. Mirrors
// crafts_incompatible() in skill-router.sh exactly — same data, same rule, two enforcers.
function craftsIncompatible(a, b, pairs) {
  return (pairs || []).some(([x, y]) => (x === a && y === b) || (x === b && y === a));
}

// --- detecting craft loads -------------------------------------------------------------------
// Is this parsed transcript object a laws craft-skill LOAD line? Returns the medium, or null.
// Deliberately strict: only the isMeta skill-injection line, never a Read-of-SKILL.md tool
// result, and never an already-tombstoned line (idempotence).
function craftMediumOf(o) {
  if (!o || o.type !== 'user' || o.isMeta !== true) return null;
  const c = o.message && o.message.content;
  const blk = Array.isArray(c) ? c[0] : null;
  if (!blk || blk.type !== 'text' || typeof blk.text !== 'string') return null;
  if (blk.text.startsWith(TOMBSTONE)) return null;        // already tombstoned → not a live load
  const firstLine = blk.text.slice(0, 300);
  if (!firstLine.startsWith(PREFIX)) return null;
  const m = firstLine.match(BASEDIR_RE);
  return m ? m[1] : null;
}

// The tombstone body: names which medium was switched away from and why. No PREFIX, so it can
// never be re-read as a live load.
function stubText(medium, activeMedium) {
  const because = activeMedium
    ? 'laws:' + activeMedium + ' is now the active craft, and it is incompatible with this one'
    : 'a craft incompatible with this one is now active';
  return TOMBSTONE + ' laws:' + medium + ' skill guidance excised. ' + because +
    ' — the two corrupt each other stacked. This medium is no longer active: do not act on it.';
}

// One place that parses the raw lines and finds every craft-load line (the survivor picks are
// made by the caller, per the compatibility policy). Shared by decide (read-only) and run
// (mutation) so the two can never disagree about what "loaded" means. [LAW:one-source-of-truth]
function findHits(rawLines) {
  const hits = [];
  const parsed = rawLines.map((line, i) => {
    if (!line) return null;
    let o;
    try { o = JSON.parse(line); } catch (_e) { return null; } // non-JSON (blank/partial) → passthrough
    const medium = craftMediumOf(o);
    if (medium) hits.push({ i, medium, ts: Date.parse(o.timestamp) || 0 }); // ts picks newest on a conflict
    return o;
  });
  return { parsed, hits };
}

// newest of a set of hits: max timestamp, ties broken by later file position.
function newest(hitList) {
  return hitList.reduce((best, h) => (h.ts > best.ts || (h.ts === best.ts && h.i > best.i)) ? h : best, hitList[0]);
}

// --- the switch gate -------------------------------------------------------------------------
// On a genuine INCOMPATIBLE craft load, four choices are ALWAYS presented (the user decides — we
// never auto-pick). They form a frontier: top→bottom trades preserved work for lower cache cost +
// more reclaimed context. There is no "defer" — deferring the reload defers the new craft's work.
//
// The prompt cache is prefix-based, so the tombstone (an EARLY edit) invalidates everything from
// the switched-away craft's load line to the leaf: the in-place cost scales with session DEPTH,
// not tombstone size. The rewind options move the leaf back, so they reprocess far less — 'discard'
// is cheapest because nothing after the pre-craft point is new.
//
// ALL FOUR are executed by CUSTOM INJECTED TOOLS (same class as the injected /compact, /clear
// tools). Options 3 & 4 drive the NATIVE rewind mechanism INTERNALLY (it already does the correct
// parentUuid/leaf repointing) but AUTO-TARGET the switched-away craft's load line — decide() returns
// the anchor uuids — so the user never types /rewind, opens its picker, or hunts for the message.
// Rewind is conversation-only and NEVER reverts code, so on-disk file deliverables survive EVERY
// option, 'discard' included. The frontier is over conversation context + cache cost, not on-disk work.
//
// ORDERING INVARIANT for #3 (rewind_summarize): the craft is TOMBSTONED BEFORE the summary is
// generated, never after — otherwise the summarizer would see the law text and could fold it back
// in, re-injecting the exact guidance we are excising. Excise-first means the summary source already
// shows [TOMBSTONE] where the craft body was. (decide() carries this as rewind.summaryExcludesCraft;
// the injected tool sequences excise → summarize.)
const SWITCH_OPTIONS = [
  { id: 'reject',           keeps: 'everything — stay in the current craft',              cache: 'none',       reclaim: 'none' },
  { id: 'tombstone',        keeps: 'full conversation, verbatim',                         cache: 'worst-deep', reclaim: 'craft body only' },
  { id: 'rewind_summarize', keeps: 'the post-craft work as a summary (craft excluded)',   cache: 'moderate',   reclaim: 'large' },
  { id: 'rewind_discard',   keeps: 'files on disk; drops conversation since craft',       cache: 'cheapest',   reclaim: 'maximal' },
];
const LARGE_TOKENS = 60000;                               // ~ where the in-place tombstone stops being cheap
const estimateTokens = (chars) => Math.round(chars / 4);  // rough; errs high → conservative

// decide(transcriptLines, { incompatiblePairs, incomingMedium?, largeTokens? })
//   incompatiblePairs REQUIRED — the policy pairs from loadPolicy(); a correct trigger decision
//                     cannot be made without it, so its absence throws rather than silently
//                     never-triggering. [LAW:no-silent-failure]
//   incomingMedium given  → pre-load gate (injected Skill-call intercept): the transcript holds the
//                           engaged crafts; the incoming one is not yet on disk.
//   incomingMedium absent → post-hoc: loads already present; the newest is the incoming one.
function decide(rawLines, opts = {}) {
  const pairs = opts.incompatiblePairs;
  if (!Array.isArray(pairs)) throw new Error('decide: incompatiblePairs is required (call loadPolicy first)');
  const largeAt = opts.largeTokens ?? LARGE_TOKENS;
  const { parsed, hits } = findHits(rawLines);

  // Resolve the incoming craft and the engaged set to test it against.
  let incoming, engagedHits;
  if (opts.incomingMedium) {
    incoming = opts.incomingMedium;
    engagedHits = hits;                                   // everything on disk is already engaged
    if (engagedHits.length === 0) return { trigger: false, reason: 'first-craft' };
  } else {
    if (hits.length <= 1) return { trigger: false, reason: 'single-load', kept: hits[0] ? hits[0].medium : null };
    const inc = newest(hits);
    incoming = inc.medium;
    engagedHits = hits.filter((h) => h.i !== inc.i);      // everything before the newest load
  }

  // The engaged craft(s) that CONFLICT with the incoming one, per policy. Switch away from the
  // newest such load. Compatible crafts (or a reload of the same craft) are not conflicts.
  const conflicts = engagedHits.filter((h) => h.medium !== incoming && craftsIncompatible(h.medium, incoming, pairs));
  if (conflicts.length === 0) {
    const reason = engagedHits.some((h) => h.medium === incoming) ? 'same-medium' : 'compatible';
    return { trigger: false, reason };
  }
  const target = newest(conflicts);                        // the craft we switch away from
  const cur = parsed[target.i];                            // its load line — the rewind anchor
  const current = target.medium;

  const tombstoneTokens = estimateTokens(rawLines.slice(target.i).reduce((n, l) => n + l.length, 0));
  const deep = tombstoneTokens >= largeAt;
  return {
    trigger: true,
    current, incoming, deep,
    tombstoneTokens,                                       // the cost that varies with depth (option 'tombstone')
    conflictIndex: target.i,                               // the line the injector tombstones (option 'tombstone')
    // Auto-targets for the native-rewind options, so the user never hunts for the craft message:
    //   summarizeTo = the switched-away craft's load line  (#3: rewind-to-craft, then tombstone + summarize)
    //   discardTo   = the message before it                (#4: rewind-to-pre-craft, then discard)
    // summaryExcludesCraft: #3 must tombstone the craft BEFORE summarizing — an execution-ORDER
    //   contract for the tool (excise → summarize), so the craft can never leak into the summary.
    rewind: { summarizeTo: cur.uuid, discardTo: cur.parentUuid, summaryExcludesCraft: true },
    options: SWITCH_OPTIONS,
    recommended: deep ? 'rewind_summarize' : 'tombstone',
  };
}

// --- transcript surgery ----------------------------------------------------------------------
// Tombstone the craft-load lines at the given indices, in place (uuid/parentUuid/timestamp
// preserved; only the body text changes). Pure over the raw-line array. A named activeMedium is
// woven into each tombstone so the marker says which craft superseded it.
function exciseAt(rawLines, indices, activeMedium) {
  if (!indices || indices.length === 0) return { lines: rawLines, changed: false, stubbed: [] };
  const out = rawLines.slice();
  const stubbed = [];
  for (const i of indices) {
    let o;
    try { o = JSON.parse(rawLines[i]); } catch (_e) { continue; }  // non-JSON → leave untouched
    const medium = craftMediumOf(o);
    if (!medium) continue;                                          // not a live craft-load line → skip
    o.message.content[0].text = stubText(medium, activeMedium);
    out[i] = JSON.stringify(o);
    stubbed.push(medium);
  }
  return { lines: out, changed: stubbed.length > 0, stubbed };
}

// --- rewind (options 3 & 4) ------------------------------------------------------------------
// Rewind the conversation to `anchorUuid`: after this, a resumed session sees the transcript as
// ending at the anchor, and everything recorded after it is inert.
//
// MEASURED on 2.1.226 (disposable 3-fact session, `-p --resume`, one fact per turn). The resume
// picks its leaf from the trailing `{"type":"last-prompt","leafUuid":…}` record, but it will not
// stop at a node that still has reachable descendants — it follows the branch down to the tip. So
// the two halves below are each necessary and only jointly sufficient, and all four combinations
// were run:
//   - repoint last-prompt alone      → NO rewind (the old tail is still reachable below the anchor)
//   - sever the anchor's children alone → NO rewind (nothing moved the leaf back)
//   - graft a new record onto the anchor → NO rewind (a shallow branch never displaces the tail,
//                                          so no purely ADDITIVE surgery can ever rewind)
//   - sever + repoint                → REWIND, verified live
// Shipping the sever on its own would be a unit that looks like it works and silently doesn't —
// so the rewind is ONE operation. [LAW:composability] one complete job, no setup ritual.
//
// This needs no bundle internals — no rewindAnchorUuid seam, no minified anchor — which is what
// lets the gate survive weekly releases untouched.
//
// Non-destructive by construction: every record stays in the file, byte-for-byte except the one
// link field per severed branch. The discarded conversation remains on disk as an orphan branch,
// and on-disk file deliverables are untouched by every option, `discard` included.
// `severUuid` is supplied by the caller because randomness is an effect; `sessionId` is read off
// the anchor record rather than passed in, so it cannot disagree with the transcript it labels.
// [LAW:effects-at-boundaries] [LAW:one-source-of-truth]
function rewindTo(rawLines, anchorUuid, severUuid) {
  const out = rawLines.slice();
  let severed = 0;
  let anchor = null;
  for (let i = 0; i < rawLines.length; i++) {
    let o;
    try { o = JSON.parse(rawLines[i]); } catch (_e) { continue; }   // non-JSON → leave untouched
    if (o.uuid === anchorUuid) anchor = o;
    if (o.parentUuid !== anchorUuid) continue;
    o.parentUuid = severUuid;                                        // a uuid rooted nowhere
    out[i] = JSON.stringify(o);
    severed++;
  }
  // An anchor that is not in the transcript is a caller bug, not a rewind to nothing: refuse it
  // loudly rather than writing a leaf pointer at a uuid no resume can resolve. [LAW:no-silent-failure]
  if (!anchor) throw new Error('rewindTo: anchor uuid not present in transcript: ' + anchorUuid);
  out.push(JSON.stringify({ type: 'last-prompt', leafUuid: anchorUuid, sessionId: anchor.sessionId }));
  return { lines: out, changed: true, severed };
}

// --- the CLI / repair path (a boundary) ------------------------------------------------------
// Atomic write: temp in same dir + rename, so a reader never sees a half-written transcript.
function writeAtomic(file, contents) {
  const dir = path.dirname(file);
  const tmp = path.join(dir, '.' + path.basename(file) + '.excise-' + process.pid + '-' + Date.now());
  fs.writeFileSync(tmp, contents);
  fs.renameSync(tmp, file);
}

// Standalone "make this transcript satisfy the policy" repair: while any incompatible pair is
// engaged, tombstone the older side (keep the newer). Compatible stacks are left alone.
function run(file, opts = {}) {
  const dryRun = opts.dryRun || false;
  const pairs = opts.incompatiblePairs || loadPolicy(opts.policyPath); // boundary read (may throw — loud)
  const text = fs.readFileSync(file, 'utf8');
  const eol = text.endsWith('\n');
  let rawLines = text.split('\n');
  if (eol) rawLines.pop(); // trailing '' from final newline — restore on write
  const stubbedAll = [];
  for (;;) {
    const d = decide(rawLines, { incompatiblePairs: pairs });
    if (!d.trigger) break;
    const r = exciseAt(rawLines, [d.conflictIndex], d.incoming);
    if (!r.changed) break;                                 // guard against a non-advancing loop
    rawLines = r.lines;
    stubbedAll.push(...r.stubbed);
  }
  const changed = stubbedAll.length > 0;
  if (changed && !dryRun) writeAtomic(file, rawLines.join('\n') + (eol ? '\n' : ''));
  return { file, changed, stubbed: stubbedAll };
}

module.exports = {
  parsePolicy, loadPolicy, craftsIncompatible,
  craftMediumOf, findHits, decide, exciseAt, rewindTo, run,
};

if (require.main === module) {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const file = args.find((a) => !a.startsWith('--'));
  if (!file) { process.stderr.write('usage: laws-excise.js <transcript.jsonl> [--dry-run]\n'); process.exit(2); }
  const res = run(file, { dryRun });
  process.stdout.write(JSON.stringify(res) + '\n');
}
