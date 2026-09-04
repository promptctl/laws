// seam-plan.js — resolve each declared seam to exactly one splice point in the graph, or refuse.
//
// WHY A SPLICE AND NOT A DEBUGGER. The live conversation lives on an object the graph never exports,
// so reaching it means either pausing the process on a call frame that happens to be inside that
// object's class, or having the object announce itself when it is built. The second needs no
// inspector, no breakpoint and no paused process, and it is a discrete event the host owns rather
// than a listener the session's later timing depends on. [LAW:no-ambient-temporal-coupling]
//
// WHY RESOLUTION IS EAGER AND GLOBAL. A seam is only trustworthy if it matches ONCE — in one module,
// at one offset. That is not knowable while transforming module-by-module on demand, so the whole
// graph is resolved up front, before anything is compiled. Zero matches and several matches are
// different facts from one match, and both are refusals: a seam that resolved to the wrong place is
// worse than one that did not resolve, because the first still runs. [LAW:parse-dont-validate] what
// comes back is a PROVEN plan or a typed absence, so the runtime never re-asks whether a seam landed.
//
// WHY NO MODULE NAME APPEARS IN A SEAM. Chunk names are content hashes that change every release, so
// naming one would be the version->seam table the epic exists to avoid. A seam names only a fragment
// of the app's own source, and which module carries it is an ANSWER, not an input.
//
// [LAW:effects-at-boundaries] pure throughout: sources in, plan out. No binary, no disk, no process.

'use strict';

// Every way a seam can fail to resolve, named. The launcher logs the reason it fell back to stock
// claude, so these are contract, not debug strings. [LAW:no-silent-failure]
const UNRESOLVED = {
  noModule: 'no-module-carries-the-seam',
  severalModules: 'several-modules-carry-the-seam',
  severalSites: 'seam-matches-more-than-once-in-its-module',
};

const unresolved = (reason, seam, detail) => ({ ok: false, reason, seam: seam.name, detail });

// Every offset in `text` the seam's anchor matches. The declared anchor is deliberately NOT global:
// a global regex carries `lastIndex` between calls, which is shared mutable state that would make
// the second scan of a module disagree with the first. [LAW:no-shared-mutable-globals]
function sitesIn(text, anchor) {
  // `g` and `y` are stripped before `g` is added: a seam declared /.../g would otherwise build
  // 'gg' and throw a SyntaxError, which escapes this module's named refusals entirely and takes the
  // host down instead of falling back to stock claude — the one outcome eager resolution exists to
  // prevent. [LAW:no-silent-failure]
  const scan = new RegExp(anchor.source, anchor.flags.replace(/[gy]/g, '') + 'g');
  const out = [];
  for (const m of text.matchAll(scan)) out.push(m.index);
  return out;
}

// Resolve one seam against the whole graph.
//   sources — name -> record, as bun-graph produces (loader + text())
//   seam    — { name, anchor, insert } from seams.js
function resolveSeam(sources, seam) {
  const carriers = [];
  for (const record of sources.values()) {
    if (record.loader !== 'js') continue;
    const sites = sitesIn(record.text(), seam.anchor);
    if (sites.length) carriers.push({ module: record.name, sites });
  }
  if (carriers.length === 0) return unresolved(UNRESOLVED.noModule, seam);
  // Naming the modules is what makes this diagnosable: "several" without which ones sends whoever
  // reads the log back to the binary to find out.
  if (carriers.length > 1) return unresolved(UNRESOLVED.severalModules, seam, carriers.map((c) => c.module).join(', '));
  const [carrier] = carriers;
  if (carrier.sites.length > 1) return unresolved(UNRESOLVED.severalSites, seam, `${carrier.module} at ${carrier.sites.join(', ')}`);
  return { ok: true, seam: seam.name, module: carrier.module, index: carrier.sites[0], insert: seam.insert };
}

// Resolve every seam, or refuse on the FIRST that does not. A partial plan is a plan that patches
// some of the app and not the rest, which is a state no caller has any use for.
function resolveSeams(sources, seams) {
  const sites = [];
  for (const seam of seams) {
    const site = resolveSeam(sources, seam);
    if (!site.ok) return site;
    sites.push(site);
  }
  const splices = new Map();
  for (const site of sites) {
    const forModule = splices.get(site.module) || [];
    forModule.push({ index: site.index, insert: site.insert });
    splices.set(site.module, forModule);
  }
  return { ok: true, sites, splices };
}

// Apply one module's insertions. HIGHEST OFFSET FIRST, so each splice leaves every offset below it
// where the plan measured it. Front-to-back would shift every later index by the length of every
// earlier insertion, which is a plan that is right about the first seam and wrong about the rest.
function spliceSource(text, inserts) {
  const ordered = [...inserts].sort((a, b) => b.index - a.index);
  let out = text;
  for (const { index, insert } of ordered) out = out.slice(0, index) + insert + out.slice(index);
  return out;
}

// The plan's own knowledge of how it is consumed: the one function bun-runtime applies in moduleFor.
// Modules with no seam come back byte-identical, so the recovered source still runs verbatim
// everywhere the plan does not reach. [LAW:dataflow-not-control-flow] every module goes through the
// same call; whether anything changes is decided by the plan's data, not by a branch at the callsite.
function transformFor(plan) {
  return (name, text) => {
    const inserts = plan.splices.get(name);
    return inserts ? spliceSource(text, inserts) : text;
  };
}

module.exports = { UNRESOLVED, sitesIn, resolveSeam, resolveSeams, spliceSource, transformFor };
