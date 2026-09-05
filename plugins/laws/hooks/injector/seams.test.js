#!/usr/bin/env node
// Tests for seams.js — the REAL anchor, not the machinery that applies it.
//
// seam-plan.test.js exercises resolution against a synthetic `mark` anchor, which is a different
// claim: it proves the resolver works, not that the one regex tying this whole mechanism to Claude
// Code's actual source is the right regex. That regex was checked once, by hand, against a live
// 2.1.258 binary — a measurement, not a regression test. A typo in the lookbehind or a stray
// quantifier would ship with nothing to catch it.
//
// The failure that motivates the exclusion cases below is NOT the safe one. An anchor that stops
// matching refuses to resolve and the launcher falls back to stock claude, which costs the user
// nothing. An anchor that grows BROADER and still happens to hit exactly one site elsewhere resolves
// happily and splices into the wrong place — either a compile error inside the user's session, or
// worse, code that compiles and never calls the registrar.
//
// The fixture is shaped from the class body SEAMS.md documents, minified the way Bun emits it.

'use strict';
const assert = require('assert');
const vm = require('vm');
const { SEAMS, REGISTRAR } = require('./seams.js');
const { resolveSeams, transformFor, sitesIn } = require('./seam-plan.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });
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

const controller = SEAMS.find((s) => s.name === 'controller');

// The shape recorded in SEAMS.md: a minified class whose conversation methods keep their property
// names, carrying every neighbour the real one has that could be mistaken for the anchor.
const CLASS_BODY = 'class A3{session;store;transcript;turn;draft;scope;'
  + 'rewindConversationTo(T,I){let{transcript:q}=this;q.replace(q.getSnapshot().slice(0,0))}'
  + 'restoreMessageSync=(T,I)=>{this.rewindConversationTo(T,I)};'
  + 'handleRestoreMessage=async(T,I)=>{setImmediate((O,q,oe)=>O(q,oe),this.restoreMessageSync,T,I)};'
  + 'handleSummarize=async(T)=>{}}';

const graph = (entries) => new Map(entries.map(([name, text, loader = 'js']) =>
  [name, { name, loader, text: () => text }]));

// ---- the anchor lands where it is supposed to ---------------------------------------------------

t('the real seam resolves against the documented class body', () => {
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  assert.strictEqual(plan.ok, true, plan.reason);
  assert.strictEqual(plan.sites.length, SEAMS.length);
});

t('it lands on the FIELD declaration, immediately before its initialiser', () => {
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const { index } = plan.sites[0];
  assert.strictEqual(CLASS_BODY.slice(index, index + 'restoreMessageSync='.length), 'restoreMessageSync=');
  // And immediately after a `;` or `}` — i.e. at a class-member boundary, where a field may start.
  assert.match(CLASS_BODY[index - 1], /[;}]/);
});

// ---- the exclusions the comment claims ----------------------------------------------------------

t('property ACCESS is not a site — this.restoreMessageSync', () => {
  assert.deepStrictEqual(sitesIn('this.restoreMessageSync=(1)', controller.anchor), []);
});

t('property access on any object is not a site — au.restoreMessageSync', () => {
  assert.deepStrictEqual(sitesIn('au.restoreMessageSync=(1)', controller.anchor), []);
});

t('an object property is not a site — restoreMessageSync: au.restoreMessageSync', () => {
  // The props object the real chunk builds; it carries the name twice and neither is a declaration.
  assert.deepStrictEqual(sitesIn('{restoreMessageSync:au.restoreMessageSync,draft:Vu}', controller.anchor), []);
});

t('a longer name containing it is not a site — handleRestoreMessage', () => {
  assert.deepStrictEqual(sitesIn('handleRestoreMessage=(1)', controller.anchor), []);
});

t('an assignment whose value is not parenthesised is not a site', () => {
  // The anchor requires `(` after the `=`, which is what a minified arrow's parameter list starts
  // with. A different shape must refuse rather than splice into something unexamined.
  assert.deepStrictEqual(sitesIn('restoreMessageSync=function(T,I){}', controller.anchor), []);
});

t('exactly one site in the whole documented body', () => {
  // The property that makes resolution trustworthy at all: one module, one offset.
  assert.strictEqual(sitesIn(CLASS_BODY, controller.anchor).length, 1);
});

// ---- what gets spliced actually works -----------------------------------------------------------

t('the patched class still parses', () => {
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const patched = transformFor(plan)('/$bunfs/root/chunk-x.js', CLASS_BODY);
  new vm.Script(patched);           // throws on a splice that lands mid-token
});

t('constructing the patched class announces the instance to the registrar', () => {
  // The end-to-end claim: not "the text changed" but "the injected statement calls the registrar
  // with `this`". A splice that compiled and never fired would pass a text-only assertion.
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const patched = transformFor(plan)('/$bunfs/root/chunk-x.js', CLASS_BODY);
  const seen = [];
  const context = vm.createContext({});
  context[REGISTRAR] = { controller: (instance) => { seen.push(instance); } };
  vm.runInContext(patched + ';globalThis.__made = new A3();', context);
  assert.strictEqual(seen.length, 1, 'the registrar was never called');
  assert.strictEqual(seen[0], context.__made, 'the registrar was handed something other than the instance');
});

t('the announcement happens at CONSTRUCTION, not on first use', () => {
  // It is a field initialiser for exactly this reason: a method body would only run if the user
  // rewound, and by then it is too late to have been told about the object.
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const patched = transformFor(plan)('/$bunfs/root/chunk-x.js', CLASS_BODY);
  let calls = 0;
  const context = vm.createContext({});
  context[REGISTRAR] = { controller: () => { calls++; } };
  vm.runInContext(patched + ';globalThis.__a = new A3();', context);
  assert.strictEqual(calls, 1, 'nothing was announced by construction alone');
});

t('the app keeps the field it declared — the splice adds, it does not replace', () => {
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const patched = transformFor(plan)('/$bunfs/root/chunk-x.js', CLASS_BODY);
  const context = vm.createContext({});
  context[REGISTRAR] = { controller: () => {} };
  vm.runInContext(patched + ';globalThis.__a = new A3();', context);
  assert.strictEqual(typeof context.__a.restoreMessageSync, 'function');
  assert.strictEqual(typeof context.__a.rewindConversationTo, 'function');
});

t('a registrar that is absent fails LOUDLY at construction', () => {
  // Deliberately unguarded: the host installs the registrar before evaluating anything, so absence
  // means the injector is broken — and a broken injector must not present as a working session that
  // silently cannot switch crafts. The boot self-check names the crash and the launcher falls back.
  const plan = resolveSeams(graph([['/$bunfs/root/chunk-x.js', CLASS_BODY]]), SEAMS);
  const patched = transformFor(plan)('/$bunfs/root/chunk-x.js', CLASS_BODY);
  const context = vm.createContext({});
  assert.throws(() => vm.runInContext(patched + ';new A3();', context));
});

// ---- the declaration itself ---------------------------------------------------------------------

t('no seam names a module — chunk names are content hashes that change every release', () => {
  for (const seam of SEAMS) {
    assert.ok(!('module' in seam), seam.name + ' names a module');
    assert.ok(!/chunk-|\$bunfs/.test(seam.insert), seam.name + "'s insert names a chunk");
  }
});

t('no seam carries a version literal', () => {
  for (const seam of SEAMS) {
    assert.ok(!/\d+\.\d+\.\d+/.test(seam.anchor.source + seam.insert), seam.name + ' pins a version');
  }
});

t('the insert calls the registrar the host installs, by the same name', () => {
  assert.ok(controller.insert.includes(REGISTRAR), 'the insert and the registrar name have drifted');
});

runAll();
