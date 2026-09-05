#!/usr/bin/env node
// Tests for seam-plan.js — resolving a seam to exactly one splice point, and applying it.
//
// The property under test throughout is that ONE match is the only outcome that proceeds. Zero and
// several are different failures and both refuse, because a seam that resolved to the wrong place
// still runs — which is strictly worse than one that did not resolve at all.

'use strict';
const assert = require('assert');
const P = require('./seam-plan.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
// A suite that stops early must not look green. Every handle this file opens is unref'd or closed,
// so a case that never resolves lets node drain the event loop and exit 0 with the summary never
// printed — a passing exit code for a suite that ran half its cases. The exit hook is what makes
// that visible, because it is the only thing that still runs when nothing else does.
let finished = false;
process.on('exit', () => {
  if (finished) return;
  console.log(`\nINCOMPLETE - exited after ${pass + fail} of ${cases.length} cases`);
  process.exitCode = 1;
});
async function runAll() {
  for (const { name, fn } of cases) {
    try { await fn(); pass++; console.log('ok   - ' + name); }
    catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
  }
  finished = true;
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

// A graph, the way bun-graph presents one: name -> record with a loader and a text() thunk.
const graph = (entries) => new Map(entries.map(([name, text, loader = 'js']) =>
  [name, { name, loader, text: () => text }]));

const SEAM = { name: 'controller', anchor: /(?<![.\w$])mark\s*=\s*(?=\()/, insert: 'X=1;' };

// ---- resolving ----------------------------------------------------------------------------------

t('a seam carried by one module at one site resolves to that module and offset', () => {
  const sources = graph([['/a.js', 'let q;mark=(p)=>p;'], ['/b.js', 'nothing here']]);
  const plan = P.resolveSeams(sources, [SEAM]);
  assert.strictEqual(plan.ok, true);
  assert.deepStrictEqual(plan.sites.map((s) => [s.seam, s.module, s.index]), [['controller', '/a.js', 6]]);
});

t('no module carrying the seam refuses by name', () => {
  const plan = P.resolveSeams(graph([['/a.js', 'let q;']]), [SEAM]);
  assert.strictEqual(plan.ok, false);
  assert.strictEqual(plan.reason, P.UNRESOLVED.noModule);
  assert.strictEqual(plan.seam, 'controller');
});

t('several modules carrying the seam refuses AND names which ones', () => {
  // Without the names, whoever reads the log has to go back to the binary to find out which.
  const plan = P.resolveSeams(graph([['/a.js', 'mark=(1)'], ['/b.js', 'mark=(2)']]), [SEAM]);
  assert.strictEqual(plan.ok, false);
  assert.strictEqual(plan.reason, P.UNRESOLVED.severalModules);
  assert.strictEqual(plan.detail, '/a.js, /b.js');
});

t('several sites within one module refuses AND names the offsets', () => {
  const plan = P.resolveSeams(graph([['/a.js', 'mark=(1);mark=(2)']]), [SEAM]);
  assert.strictEqual(plan.ok, false);
  assert.strictEqual(plan.reason, P.UNRESOLVED.severalSites);
  assert.match(plan.detail, /^\/a\.js at 0, 9$/);
});

t('non-js modules are not searched — a text asset that mentions the anchor is not a carrier', () => {
  // The graph carries compressed and text assets; matching one would resolve the seam into
  // something that is never compiled.
  // The non-js module comes FIRST, so a scan that stopped at it instead of skipping it would find
  // no carrier at all — which is the difference between skipping a module and abandoning the sweep.
  const sources = graph([['/notes.txt', 'mark=(2)', 'text'], ['/a.js', 'mark=(1)']]);
  const plan = P.resolveSeams(sources, [SEAM]);
  assert.strictEqual(plan.ok, true);
  assert.strictEqual(plan.sites[0].module, '/a.js');
});

t('the lookbehind excludes property access, so this.mark=( is not a site', () => {
  const plan = P.resolveSeams(graph([['/a.js', 'this.mark=(1);o.mark=(2);mark=(3)']]), [SEAM]);
  assert.strictEqual(plan.ok, true);
  assert.strictEqual(plan.sites[0].index, 25);
});

t('scanning twice gives the same answer — no lastIndex carried between calls', () => {
  // A global regex kept on the seam would advance its lastIndex on the first module and start the
  // second one mid-string, so the second scan would disagree with the first.
  const text = 'mark=(1)';
  assert.deepStrictEqual(P.sitesIn(text, SEAM.anchor), P.sitesIn(text, SEAM.anchor));
  assert.deepStrictEqual(P.sitesIn(text, SEAM.anchor), [0]);
});

t('an anchor declared global does not build an invalid regex', () => {
  // 'g' + 'g' is a SyntaxError, which would escape this module's named refusals and crash the host
  // instead of falling back to stock claude.
  const globalSeam = { name: 'g', anchor: /mark\s*=\s*(?=\()/g, insert: 'X;' };
  const plan = P.resolveSeams(graph([['/a.js', 'let q;mark=(1)']]), [globalSeam]);
  assert.strictEqual(plan.ok, true);
  assert.strictEqual(plan.sites[0].index, 6);
});

t('a sticky anchor is handled the same way', () => {
  const sticky = { name: 'y', anchor: /mark/y, insert: 'X;' };
  assert.deepStrictEqual(P.sitesIn('mark and mark', sticky.anchor), [0, 9]);
});

t('resolveSeams refuses on the first failing seam and returns no partial plan', () => {
  // A plan that patched some seams and not others would leave the app half-injected, which is a
  // state no caller has a use for.
  const good = { name: 'good', anchor: /mark\s*=\s*(?=\()/, insert: 'X;' };
  const bad = { name: 'bad', anchor: /absent-anchor/, insert: 'Y;' };
  const plan = P.resolveSeams(graph([['/a.js', 'mark=(1)']]), [good, bad]);
  assert.strictEqual(plan.ok, false);
  assert.strictEqual(plan.seam, 'bad');
  assert.strictEqual(plan.splices, undefined);
});

// ---- splicing -----------------------------------------------------------------------------------

t('an insert lands exactly at the resolved offset, pushing the anchor right', () => {
  assert.strictEqual(P.spliceSource('abcdef', [{ index: 3, insert: '**' }]), 'abc**def');
});

t('two inserts in one module both land where the plan measured them', () => {
  // Applied front-to-back, the second insert would be displaced by the length of the first — right
  // about the first seam and wrong about every one after it.
  const out = P.spliceSource('0123456789', [{ index: 2, insert: 'AA' }, { index: 6, insert: 'BB' }]);
  assert.strictEqual(out, '01AA2345BB6789');
});

t('splice order does not depend on the order the inserts were listed', () => {
  const forward = P.spliceSource('0123456789', [{ index: 2, insert: 'AA' }, { index: 6, insert: 'BB' }]);
  const reverse = P.spliceSource('0123456789', [{ index: 6, insert: 'BB' }, { index: 2, insert: 'AA' }]);
  assert.strictEqual(forward, reverse);
});

t('spliceSource does not mutate the caller\'s insert list', () => {
  const inserts = [{ index: 2, insert: 'AA' }, { index: 6, insert: 'BB' }];
  P.spliceSource('0123456789', inserts);
  assert.deepStrictEqual(inserts.map((i) => i.index), [2, 6]);
});

// ---- the transform the runtime applies ----------------------------------------------------------

t('a module the plan does not reach comes back byte-identical', () => {
  // Everything outside the one patched module must still run verbatim.
  const plan = P.resolveSeams(graph([['/a.js', 'mark=(1)'], ['/b.js', 'let untouched=1;']]), [SEAM]);
  const transform = P.transformFor(plan);
  assert.strictEqual(transform('/b.js', 'let untouched=1;'), 'let untouched=1;');
});

t('the carrier module comes back with the insert at the resolved offset', () => {
  const plan = P.resolveSeams(graph([['/a.js', 'let q;mark=(p)=>p;']]), [SEAM]);
  const transform = P.transformFor(plan);
  assert.strictEqual(transform('/a.js', 'let q;mark=(p)=>p;'), 'let q;X=1;mark=(p)=>p;');
});

t('the transform grows the carrier by exactly the length of the insert', () => {
  const text = 'let q;mark=(p)=>p;';
  const plan = P.resolveSeams(graph([['/a.js', text]]), [SEAM]);
  assert.strictEqual(P.transformFor(plan)('/a.js', text).length - text.length, SEAM.insert.length);
});

runAll();
