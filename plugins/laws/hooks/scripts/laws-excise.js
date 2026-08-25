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
// A craft is any skill under the laws plugin — identified by a base dir ending in
// /laws/<...>/skills/<craft>, which is the path form of the same `laws:` namespace the router
// keys on. The craft set is never enumerated here.
//
// COMPATIBILITY, NOT "ONE AT A TIME": crafts COEXIST by default. code+prose+ticket is normal,
// complementary work. What the gate fires on is a genuine conflicting ORDERING — an engaged
// craft whose standard corrupts the one now being loaded — per the policy in
// incompatible-crafts.txt (today: only code→prompt). Anything else is left completely alone.
//
// THE RULE IS DIRECTED, not a mutual incompatibility. code degrades prompts; prompt does not
// degrade code. So laws:code engaged + incoming laws:prompt is refused, while laws:prompt
// engaged + incoming laws:code is ordinary allowed work. Treating this as symmetric — as an
// earlier version did — produces a FALSE REFUSAL in the harmless direction, and the cost is
// not a warning: the user is offered a tombstone-or-rewind switch and may spend real
// conversation escaping a conflict that never existed.
//
// Why tombstone, not delete: the transcript is a DAG keyed by uuid/parentUuid. Deleting a line
// orphans its children. Tombstoning preserves uuid/parentUuid/linkage and only empties the
// guidance text, so the superseded craft can no longer act but the conversation tree is intact.
//
// [LAW:one-source-of-truth] the incompatibility policy has ONE home — incompatible-crafts.txt —
//   read here AND by skill-router.sh; this module hard-codes no craft-pair rule.
// [LAW:single-enforcer] this file is the one place that decides what "loaded" means and which
//   engaged craft an incoming one must switch away from.
// [LAW:effects-at-boundaries] the pure core (parsePolicy/conflictsWith/findHits/decide/
//   exciseAt) never touches the filesystem; the edges (loadPolicy/run) do the I/O.
// [LAW:no-silent-failure] a parse/shape miss is passed through untouched, never dropped; a
//   missing policy file throws at the boundary rather than reading as "all crafts coexist".

'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// WHICH CRAFTS EXIST IS DERIVED, NEVER ENUMERATED. skill-router.sh's guard treats any
// `laws:<x>` skill as a craft precisely so that "a new craft is covered the day it is added";
// this half used to recognise only five hardcoded names, so adding a craft directory and wiring
// it into incompatible-crafts.txt — the workflow both files advertise as the whole point of
// keeping the policy in one file — gave the router a live edge the day it was written while
// findHits here stayed blind to that craft's load line, with no symptom on either side.
// [LAW:single-enforcer] one rule about what a craft is, read the same way by both enforcers.
//
// The namespace signal in a base dir is a path segment `laws` above `skills/<craft>`, which is
// what both shipped layouts look like: the repo's ".../plugins/laws/skills/code" and the plugin
// cache's versioned ".../cache/<owner>/laws/<version>/skills/code". Anchoring on `/skills/`
// alone would claim every OTHER plugin's skills as laws crafts; anchoring on `/laws/skills/`
// would miss the cache path. [LAW:parse-dont-validate] the capture IS the craft name.
const BASEDIR_RE = /\/laws\/(?:[^/\s]+\/)*skills\/([^/\s]+)(?:\/|\s|$)/;
const PREFIX = 'Base directory for this skill:';
// The documented tombstone marker. A tombstoned line no longer starts with PREFIX, so it is
// already un-detectable as a live load; the marker is the explicit guard for idempotence.
const TOMBSTONE = '[TOMBSTONE]';

// --- policy: the boundary read + the pure predicate ------------------------------------------
// Parse the shared policy file's text into DIRECTED edges [engaged, refused]. Pure: same shape
// the router's bash reader produces (strip '# comments', drop blank lines, split on whitespace).
// Order within a line is meaningful and is preserved exactly as written.
//
// EXACTLY TWO TOKENS, and the exactness is the point. This used to take the first two tokens of
// any line with at least two, while the router's `read -r from to` stuffs every extra word into
// `to` — so `code prompt extra-note` was an enforced edge here and a permanent no-op there, the
// two enforcers quietly applying opposite rules to the same line. Both now reject any line that
// is not exactly two tokens, and both say so. [LAW:single-enforcer] one rule, read the same way
// by both readers.
//
// Both arms come back as values rather than one being reported from in here: the malformed lines
// are as much a result of the parse as the edges are, and handing them out lets the boundary — the
// one place that already does I/O — be the single voice that warns. [LAW:effects-at-boundaries]
// [LAW:parse-dont-validate] the caller receives edges that are known-wellformed, never a mixed bag
// it has to re-inspect.
function parsePolicy(text) {
  const rows = text.split('\n')
    .map((l) => l.replace(/#.*$/, '').trim())
    .filter(Boolean)
    .map((l) => l.split(/\s+/));
  return {
    edges: rows.filter((p) => p.length === 2).map(([a, b]) => [a, b]),
    malformed: rows.filter((p) => p.length !== 2).map((p) => p.join(' ')),
  };
}

// The one wording both enforcers use for a rejected line, so a reader who greps for it finds the
// same sentence whichever one printed it. [LAW:one-source-of-truth]
const MALFORMED_WARNING = 'laws policy: ignoring malformed line (expected exactly two craft names): ';

// Boundary read of the shared policy file (default: sibling incompatible-crafts.txt). Throws on
// a missing/unreadable file — the caller at the edge decides whether to degrade; the pure core
// never silently treats an unread policy as "everything coexists". A malformed LINE is narrower:
// it costs one edge, not the policy, so it is dropped and announced rather than thrown on — the
// router cannot hard-fail on it without blocking skill loads, and a rule enforced identically by
// both is worth more here than a louder failure in only one. [LAW:effects-at-boundaries]
// [LAW:no-silent-failure]
function loadPolicy(policyPath) {
  const p = policyPath || path.join(__dirname, 'incompatible-crafts.txt');
  const { edges, malformed } = parsePolicy(fs.readFileSync(p, 'utf8'));
  for (const line of malformed) process.stderr.write(MALFORMED_WARNING + line + '\n');
  return edges;
}

// True iff an already-loaded `engaged` craft forbids loading `incoming`. DIRECTED and pure:
// conflictsWith(a, b) and conflictsWith(b, a) are different questions with different answers.
// Mirrors conflicts_with() in skill-router.sh exactly — same data, same rule, two enforcers.
//
// The parameters are NAMED for their roles rather than taken as an interchangeable pair,
// because the direction is the one thing a caller can get wrong and the old symmetric
// signature could not carry it: two callsites passed their arguments in opposite orders for
// months with no symptom, since the predicate could not tell them apart. A signature that
// makes the mistake unrepresentable beats a comment asking callers to be careful.
// [LAW:types-are-the-program]
function conflictsWith(engaged, incoming, edges) {
  return (edges || []).some(([from, to]) => from === engaged && to === incoming);
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
    ? 'laws:' + activeMedium + ' is now the active craft, and this one degrades it'
    : 'a craft this one degrades is now active';
  return TOMBSTONE + ' laws:' + medium + ' skill guidance excised. ' + because +
    ' — the damage runs that way, which is why this side was retired and not the other. ' +
    'This medium is no longer active: do not act on it.';
}

// Is this record part of the LIVE conversation, or debris the session will never see again?
//
// Two ways a craft-load record can be on disk without being engaged, and both produced real
// bugs. A REWIND severs a branch by repointing it at a uuid rooted nowhere (rewindTo, below)
// and deliberately does not delete it — so after one rewind the retired craft is still a
// perfectly well-formed craft-load line sitting on an orphan branch. A SIDECHAIN record is a
// dispatched subagent's conversation sharing this file; the router isolates subagents by
// keying craft locks on agent_id, and the gate ignoring the flag is that same isolation
// broken on the other side.
//
// Counting either as engaged is not merely untidy: the rewind anchor is the OLDEST conflict,
// so stale debris — being oldest — WINS, and a second switch anchors inside a discarded
// branch. Measured consequence before this filter existed: switch two reported
// current ['code','code'], grafted the summary onto a severed orphan whose own parent no
// longer exists, and threw outright on rewind_discard.
//
// Rootedness is the test, stated positively: walk parentUuid up and ask whether the chain
// ends at a root or dies on a uuid that exists nowhere. That reads the severance exactly as
// rewindTo writes it, and needs no last-prompt record to be present or well-formed.
function isLive(o, byUuid) {
  if (!o || o.isSidechain) return false;
  const seen = new Set();
  for (let cur = o; cur; cur = byUuid.get(cur.parentUuid)) {
    if (cur.parentUuid === null || cur.parentUuid === undefined) return true;  // reached a root
    if (seen.has(cur.uuid)) return false;                                      // cycle → not rooted
    seen.add(cur.uuid);
  }
  return false;                                                                // dangling parent → severed
}

// One place that parses the raw lines and finds every craft-load line (the survivor picks are
// made by the caller, per the compatibility policy). Shared by decide (read-only) and run
// (mutation) so the two can never disagree about what "loaded" means. [LAW:one-source-of-truth]
//
// Every hit is reported, each tagged `live`. The two consumers genuinely want different sets:
// the ENGAGED set (decide's conflicts and anchors) must be live-only, while TOMBSTONING stays
// file-wide by design. Returning one list with the discriminator on it keeps that a value the
// caller reads rather than two scans that can drift. [LAW:dataflow-not-control-flow]
function findHits(rawLines) {
  const parsed = rawLines.map((line) => {
    if (!line) return null;
    try { return JSON.parse(line); } catch (_e) { return null; }  // non-JSON (blank/partial) → passthrough
  });
  const byUuid = new Map();
  for (const o of parsed) if (o && o.uuid) byUuid.set(o.uuid, o);
  const hits = [];
  parsed.forEach((o, i) => {
    const medium = o && craftMediumOf(o);
    if (medium) hits.push({ i, medium, ts: Date.parse(o.timestamp) || 0, live: isLive(o, byUuid) });
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
// ALL FOUR ARE ON-DISK TRANSCRIPT SURGERY, applied by the LAUNCHER after the session has already
// exited — no injected tool runs, and claude's native rewind is never driven. This paragraph used
// to describe custom injected tools driving that native mechanism internally through a
// `rewindAnchorUuid` anchor; that is Path A, and hooks/injector/SEAMS.md marks its seam SUPERSEDED
// (2026-08-16, "do not build against it") because rewindTo() reaches the same end state through the
// transcript alone. What ships is Path B (SEAMS.md, DONE 2026-08-23): the in-session gate records
// the choice, the session ends, bin/claude-laws rewrites the file, and claude is relaunched with
// --resume. The user still never types /rewind or hunts for the message, but that is because the
// file was already rewritten before the session came back — not because anything drove a picker on
// their behalf. A reader who believed the old text would go looking for an injected-tool component
// that does not exist to maintain. [LAW:one-source-of-truth] SEAMS.md owns which path shipped.
//
// The edit is conversation-only and NEVER reverts code, so on-disk file deliverables survive EVERY
// option, 'discard' included. The frontier is over conversation context + cache cost, not on-disk work.
//
// WHAT PROTECTS #3 (rewind_summarize), stated honestly. The risk is that the summary folds the
// craft's guidance back in and re-injects the very text the switch excised. An earlier design
// claimed to prevent this by tombstoning BEFORE the summary was composed — that ordering is NOT
// achievable here and the claim has been removed rather than left to reassure a reader. The
// summary can only be written from the live session's own context, and that context necessarily
// still holds the craft: the live message store is closure-local, so nothing can excise the craft
// from a running session's context before asking it to summarize (see hooks/injector/SEAMS.md).
// The excise does run before the summary is APPENDED TO THE FILE, but that is file ordering and
// buys nothing against a summary already composed under the craft's influence.
// So the protection that actually acts is the INSTRUCTION the agent composes against — carried in
// the deny message and in laws-switch's usage — which tells it to summarize its work and not the
// craft's guidance. That is a weaker guarantee than a structural one, and it is named here as
// weaker so no future reader mistakes it for enforcement. [LAW:comments-carry-meaning]
const SWITCH_OPTIONS = [
  { id: 'reject',           keeps: 'everything — stay in the current craft',              cache: 'none',       reclaim: 'none' },
  { id: 'tombstone',        keeps: 'full conversation, verbatim',                         cache: 'worst-deep', reclaim: 'craft body only' },
  { id: 'rewind_summarize', keeps: 'the post-craft work as a summary (craft excluded)',   cache: 'moderate',   reclaim: 'large' },
  { id: 'rewind_discard',   keeps: 'files on disk; drops conversation since craft',       cache: 'cheapest',   reclaim: 'maximal' },
];
const LARGE_TOKENS = 60000;                               // ~ where the in-place tombstone stops being cheap
const estimateTokens = (chars) => Math.round(chars / 4);  // rough; errs high → conservative

// decide(transcriptLines, { conflictEdges, incomingMedium?, largeTokens? })
//   conflictEdges REQUIRED — the policy pairs from loadPolicy(); a correct trigger decision
//                     cannot be made without it, so its absence throws rather than silently
//                     never-triggering. [LAW:no-silent-failure]
//   incomingMedium given  → pre-load gate (injected Skill-call intercept): the transcript holds the
//                           engaged crafts; the incoming one is not yet on disk.
//   incomingMedium absent → post-hoc: loads already present; the newest is the incoming one.
function decide(rawLines, opts = {}) {
  const edges = opts.conflictEdges;
  if (!Array.isArray(edges)) throw new Error("decide: conflictEdges is required (call loadPolicy first)");
  const largeAt = opts.largeTokens ?? LARGE_TOKENS;
  const { parsed, hits: allHits } = findHits(rawLines);
  // Only the live conversation can hold an ENGAGED craft. Debris on a severed branch, and a
  // subagent's sidechain, are on disk but were never part of what this session is carrying.
  const hits = allHits.filter((h) => h.live);

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
  const conflicts = engagedHits.filter((h) => h.medium !== incoming && conflictsWith(h.medium, incoming, edges));
  if (conflicts.length === 0) {
    const reason = engagedHits.some((h) => h.medium === incoming) ? 'same-medium' : 'compatible';
    return { trigger: false, reason };
  }
  // THE WHOLE CONFLICTING SET IS THE UNIT, never a pick from it. Retiring one member of a set of
  // two reports success and leaves the session unable to load the craft it just switched to —
  // the exact defect this gate exists to fix, one level up. There is deliberately no "which one"
  // step here: with no selection rule, this enforcer and the router's cannot disagree about the
  // answer. [LAW:composability] one complete job [LAW:single-enforcer]
  //
  // Ordered oldest→newest, and `oldest` is what the rewind anchors hang off: rewinding to the
  // NEWEST conflict would land above an older conflicting load that is still engaged, so no
  // choice of a single member is correct — only the earliest point at which none of them are
  // loaded is. Unreachable under the single shipped pair; the policy file is data designed to be
  // extended, so this is scheduled rather than hypothetical.
  const ordered = conflicts.slice().sort((a, b) => a.i - b.i);
  const oldest = ordered[0];
  const cur = parsed[oldest.i];                            // its load line — the rewind anchor
  const current = ordered.map((h) => h.medium);

  const tombstoneTokens = estimateTokens(rawLines.slice(oldest.i).reduce((n, l) => n + l.length, 0));
  const deep = tombstoneTokens >= largeAt;
  return {
    trigger: true,
    current, incoming, deep,
    tombstoneTokens,                                       // the cost that varies with depth (option 'tombstone')
    conflictIndices: ordered.map((h) => h.i),              // every line the injector tombstones (option 'tombstone')
    // Auto-targets for the rewind options, so the user never hunts for the craft message:
    //   summarizeTo = the OLDEST conflicting load line  (#3: rewind-to-craft, then tombstone + summarize)
    //   discardTo   = the message before it             (#4: rewind-to-pre-craft, then discard)
    // A summaryExcludesCraft flag used to ride along here asserting that the craft could never leak
    // into the summary. Nothing consumed it and the flow does not deliver it, so it is gone rather
    // than left as a constant that reads like a guarantee. [LAW:types-are-the-program]
    rewind: { summarizeTo: cur.uuid, discardTo: cur.parentUuid },
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

// --- enacting a chosen switch ----------------------------------------------------------------
// The four options are DATA, not four code paths: one table keyed by option id, each entry a pure
// (lines, decision, env) -> { lines, resume, changed }. Adding a fifth option is a table entry,
// never a new branch in the caller. [LAW:dataflow-not-control-flow] [LAW:one-type-per-behavior]
//
// `changed` is reported BY the action because only the action knows: the boundary that writes the
// file used to re-derive it as `r.lines !== rawLines`, a second answer to a question already
// answered here, agreeing with this one today only because every action happens to return a fresh
// array exactly when it edited something. [LAW:one-source-of-truth]
//
// TIMING, and it is load-bearing: every action here edits the transcript of a session that must
// ALREADY HAVE EXITED. A running Claude Code appends records as it works, so surgery against a live
// file races the writer and can be overwritten wholesale. The in-session command records the INTENT
// and triggers the exit; the launcher runs these actions afterwards, when nobody holds the file.
// [LAW:no-ambient-temporal-coupling] the ordering is owned by the launcher, not left to luck.
//
// A summary record is appended as a CHILD of the rewind anchor rather than replacing it, which
// works precisely because a resume follows a branch down to its tip: the anchor keeps the leaf
// pointer, the summary hangs below it, and the resumed session lands on the summary.
function summaryRecord(anchorRecord, anchorUuid, env, text) {
  return JSON.stringify({
    type: 'user', uuid: env.summaryUuid, parentUuid: anchorUuid, timestamp: env.now,
    sessionId: anchorRecord.sessionId, isSidechain: false, userType: 'external',
    message: { role: 'user', content: text },
  });
}

// Find a record by uuid in raw lines — the one place that resolution happens. [LAW:one-source-of-truth]
function recordByUuid(rawLines, uuid) {
  for (const line of rawLines) {
    let o;
    try { o = JSON.parse(line); } catch (_e) { continue; }
    if (o.uuid === uuid) return o;
  }
  return null;
}

const SWITCH_ACTIONS = {
  // Stay in the current craft. The incoming load was already denied, so the transcript is correct
  // as it stands and there is nothing to resume into.
  reject: (lines) => ({ lines, resume: false, changed: false }),

  // Keep the whole conversation; empty the guidance of every superseded craft.
  tombstone: (lines, d) => {
    const r = exciseAt(lines, d.conflictIndices, d.incoming);
    return { lines: r.lines, resume: true, changed: r.changed };
  },

  // Excise, then rewind, then attach the summary. Excising first keeps the tombstone on the leaf
  // that the rewind then lands on; it is NOT a guard against the craft leaking into the summary,
  // which was already composed inside the live session (see the note on SWITCH_OPTIONS). The
  // summary arrives as an argument because only the live agent can write it — after the rewind
  // the context it describes no longer exists.
  rewind_summarize: (lines, d, env) => {
    if (!env.summary) throw new Error('rewind_summarize: a summary is required (the live agent writes it)');
    const excised = exciseAt(lines, d.conflictIndices, d.incoming).lines;
    const anchorUuid = d.rewind.summarizeTo;
    const rewound = rewindTo(excised, anchorUuid, env.severUuid).lines;
    const anchorRec = recordByUuid(rewound, anchorUuid);
    rewound.push(summaryRecord(anchorRec, anchorUuid, env, env.summary));
    return { lines: rewound, resume: true, changed: true };
  },

  // Drop the conversation from just before the craft loaded. Files on disk are untouched — nothing
  // in this module writes anything but the transcript.
  rewind_discard: (lines, d, env) => {
    const anchorUuid = d.rewind.discardTo;
    // A craft loaded as the very first message has no predecessor to land on. Refuse rather than
    // silently rewinding somewhere else. [LAW:no-silent-failure]
    if (!anchorUuid) throw new Error('rewind_discard: the craft load is the first message; nothing precedes it to rewind to');
    return { lines: rewindTo(lines, anchorUuid, env.severUuid).lines, resume: true, changed: true };
  },
};

// applySwitch(rawLines, decision, choice, env) -> { lines, resume, changed }
// `env` carries the values that would otherwise be effects (uuids, clock, the agent's summary), so
// this stays pure and testable. [LAW:effects-at-boundaries]
function applySwitch(rawLines, decision, choice, env = {}) {
  const action = SWITCH_ACTIONS[choice];
  // An unknown choice must never degrade into "do nothing and carry on" — that would leave two
  // incompatible crafts engaged while reporting success. [LAW:no-silent-failure]
  if (!action) throw new Error('applySwitch: unknown choice ' + JSON.stringify(choice) + '; expected one of ' + Object.keys(SWITCH_ACTIONS).join(', '));
  if (!decision || !decision.trigger) throw new Error('applySwitch: decision did not trigger a switch');
  return action(rawLines, decision, env);
}

// --- the CLI / repair path (a boundary) ------------------------------------------------------
// Atomic write: temp in same dir + rename, so a reader never sees a half-written transcript.
function writeAtomic(file, contents) {
  const dir = path.dirname(file);
  const tmp = path.join(dir, '.' + path.basename(file) + '.excise-' + process.pid + '-' + Date.now());
  fs.writeFileSync(tmp, contents);
  fs.renameSync(tmp, file);
}

// Standalone "make this transcript satisfy the policy" repair: while an engaged craft forbids a
// later one, tombstone the FORBIDDING side (keep the newer). The direction comes from the policy,
// so a legitimate ordering — prompt then code — is left completely alone rather than "repaired"
// into a tombstone it never needed. Compatible stacks are likewise untouched.
function run(file, opts = {}) {
  const dryRun = opts.dryRun || false;
  const pairs = opts.conflictEdges || loadPolicy(opts.policyPath); // boundary read (may throw — loud)
  const text = fs.readFileSync(file, 'utf8');
  const eol = text.endsWith('\n');
  let rawLines = text.split('\n');
  if (eol) rawLines.pop(); // trailing '' from final newline — restore on write
  const stubbedAll = [];
  for (;;) {
    const d = decide(rawLines, { conflictEdges: pairs });
    if (!d.trigger) break;
    const r = exciseAt(rawLines, d.conflictIndices, d.incoming);
    if (!r.changed) break;                                 // guard against a non-advancing loop
    rawLines = r.lines;
    stubbedAll.push(...r.stubbed);
  }
  const changed = stubbedAll.length > 0;
  if (changed && !dryRun) writeAtomic(file, rawLines.join('\n') + (eol ? '\n' : ''));
  return { file, changed, stubbed: stubbedAll };
}

// Enact a switch request against the transcript it names. Runs from the LAUNCHER, after the
// session has exited — see the timing note on SWITCH_ACTIONS.
//
// The request carries the CHOICE and the incoming craft, never the resolved line indices: the
// decision is recomputed here against the transcript as it finally landed, because the session
// kept appending records between the hook's deny and its exit. Carrying stale indices across that
// gap is how you tombstone the wrong line. [LAW:one-source-of-truth]
function applyRequest(requestPath, opts = {}) {
  const req = JSON.parse(fs.readFileSync(requestPath, 'utf8'));
  for (const field of ['transcript', 'choice', 'incomingMedium']) {
    if (!req[field]) throw new Error('switch request is missing ' + field + ': ' + requestPath);
  }
  const pairs = opts.conflictEdges || loadPolicy(opts.policyPath);
  const text = fs.readFileSync(req.transcript, 'utf8');
  const eol = text.endsWith('\n');
  const rawLines = text.split('\n');
  if (eol) rawLines.pop();

  const decision = decide(rawLines, { conflictEdges: pairs, incomingMedium: req.incomingMedium });
  // The conflict must still be there. If it is not, the session changed under us — say so instead
  // of writing a "successful" no-op the user will read as a completed switch. [LAW:no-silent-failure]
  if (!decision.trigger) {
    throw new Error('switch request no longer applies (' + decision.reason + '): nothing was changed');
  }
  const env = {
    severUuid: crypto.randomUUID(),
    summaryUuid: crypto.randomUUID(),
    now: new Date().toISOString(),
    summary: req.summary,
  };
  const r = applySwitch(rawLines, decision, req.choice, env);
  const changed = r.changed;
  if (changed && !opts.dryRun) writeAtomic(req.transcript, r.lines.join('\n') + (eol ? '\n' : ''));
  return { transcript: req.transcript, choice: req.choice, resume: r.resume, changed,
    sessionId: req.sessionId, switchedFrom: decision.current, switchedTo: decision.incoming };
}

module.exports = {
  parsePolicy, loadPolicy, conflictsWith, MALFORMED_WARNING,
  craftMediumOf, findHits, decide, exciseAt, rewindTo, applySwitch, SWITCH_ACTIONS,
  applyRequest, run,
};

if (require.main === module) (function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const applyAt = args.indexOf('--apply');
  if (applyAt >= 0) {
    const reqPath = args[applyAt + 1];
    if (!reqPath) { process.stderr.write('usage: laws-excise.js --apply <request.json> [--dry-run]\n'); process.exit(2); }
    process.stdout.write(JSON.stringify(applyRequest(reqPath, { dryRun })) + '\n');
    return;
  }
  const file = args.find((a) => !a.startsWith('--'));
  if (!file) { process.stderr.write('usage: laws-excise.js <transcript.jsonl> [--dry-run]\n'); process.exit(2); }
  const res = run(file, { dryRun });
  process.stdout.write(JSON.stringify(res) + '\n');
})();
