#!/usr/bin/env -S node --experimental-vm-modules
// Tests for bun-runtime.mjs — linking and evaluating Bun's module graph under node's vm.
//
// The graph here is SYNTHETIC: a handful of tiny modules written in this file. That is the whole
// reason the runtime was pulled out of bun-host.mjs — the behaviour worth checking is the loader
// dispatch, the cycle handling and the named refusals, and none of it needs a 199MB binary, a
// terminal, or a real Claude Code to exercise.
//
// The cycle case is the one that matters most: it is the exact shape that made node's own ES module
// loader unusable for this graph (ERR_REQUIRE_CYCLE_MODULE), so if it ever stops working here, the
// substrate the whole epic rests on has stopped working.

import assert from 'node:assert';
import { createRequire } from 'node:module';
import { createModuleRuntime } from './bun-runtime.mjs';

const require_ = createRequire(import.meta.filename);
const { createEmbeddedFs } = require_('./embedded-fs.js');

let pass = 0, fail = 0;
const cases = [];
const t = (name, fn) => cases.push({ name, fn });

const record = (name, contents, loader = 'js') => {
  const bytes = Buffer.from(contents, 'utf8');
  return { name, loader, encoding: 'utf8', length: bytes.length, bytes: () => bytes, text: () => bytes.toString('utf8') };
};

// A graph with everything the real one has: static imports, a require between chunks, a cycle
// crossed by require, a text asset, a native blob, and a dynamic import.
const MODULES = [
  record('/$bunfs/root/cli', `
    import { greet } from "/$bunfs/root/chunk-a.js";
    const { fromB } = import.meta.require("/$bunfs/root/chunk-b.js");
    const doc = import.meta.require("/$bunfs/root/notes.md");
    const { lazy } = await import("/$bunfs/root/chunk-lazy.js");
    globalThis.__result = { greet: greet(), fromB: fromB(), doc, lazy: lazy(), meta: import.meta.filename, dir: import.meta.dirname };
  `),
  record('/$bunfs/root/chunk-a.js', 'export const greet = () => "hello";'),
  // b and c are a cycle, crossed by require — the shape node's own require(esm) refuses.
  record('/$bunfs/root/chunk-b.js', `
    import { cName } from "/$bunfs/root/chunk-c.js";
    export const fromB = () => "b+" + cName();
  `),
  record('/$bunfs/root/chunk-c.js', `
    const b = import.meta.require("/$bunfs/root/chunk-b.js");
    export const cName = () => "c";
    export const backToB = () => typeof b.fromB;
  `),
  record('/$bunfs/root/chunk-lazy.js', 'export const lazy = () => "lazy";'),
  record('/$bunfs/root/chunk-builtin.js', `
    import { basename } from "path";
    const os = import.meta.require("os");
    export const check = () => basename("/a/b.txt") + ":" + typeof os.platform;
  `),
  record('/$bunfs/root/chunk-embedded-read.js', `
    import { readFileSync } from "fs";
    export const read = () => readFileSync("/$bunfs/root/notes.md", "utf8");
  `),
  record('/$bunfs/root/notes.md', '# embedded notes', 'text'),
  record('/$bunfs/root/blob.node', 'RAWBYTES', 'napi'),
];

function build(modules = MODULES, extra = {}) {
  const embedded = createEmbeddedFs(modules, { realFs: require_('fs'), streamFrom: () => null });
  const errors = [];
  const runtime = createModuleRuntime({
    embedded,
    sources: new Map(modules.map((m) => [m.name, m])),
    provided: { ws: { WebSocket: 'stub-ws', default: 'stub-ws' } },
    substitute: { fs: (real) => embedded.substituteForFs(real) },
    requireBuiltin: (id) => require_('node:' + id),
    onEvaluationError: (name, e) => errors.push([name, e.message]),
    ...extra,
  });
  return { runtime, errors, embedded };
}

// ---- the transform, which is the whole wire the craft switch hangs from -------------------------
//
// A regression here fails SILENTLY: no boot error, no exception — the seam simply never reaches the
// compiler and the registrar is never called. seam-plan.test.mjs covers `transformFor` in isolation,
// which is a different claim from "the runtime actually applies it".

t('a transform reaches the compiler — the evaluated module reflects the edited source', async () => {
  const seen = [];
  const { runtime } = build(MODULES, {
    transform: (name, text) => {
      seen.push(name);
      return name === '/$bunfs/root/cli' ? text + '\nglobalThis.__spliced = "landed";\n' : text;
    },
  });
  delete globalThis.__spliced;
  await runtime.linkAll();
  await runtime.evaluateEntry('/$bunfs/root/cli');
  assert.strictEqual(globalThis.__spliced, 'landed', 'the transform never reached the compiler');
  delete globalThis.__spliced;
});

t('every js module is offered to the transform, exactly once each', async () => {
  const seen = [];
  const { runtime } = build(MODULES, { transform: (name, text) => { seen.push(name); return text; } });
  await runtime.linkAll();
  const js = MODULES.filter((m) => m.loader === 'js').map((m) => m.name);
  assert.deepStrictEqual(seen.slice().sort(), js.slice().sort());
  assert.strictEqual(new Set(seen).size, seen.length, 'a module was compiled twice');
});

t('the transform is handed the module NAME and its own text, in that order', async () => {
  // Swapped arguments would still "work" for an identity transform and silently disable the seam.
  const pairs = [];
  const { runtime } = build(MODULES, { transform: (name, text) => { pairs.push([name, text]); return text; } });
  await runtime.linkAll();
  for (const [name, text] of pairs) {
    const record = MODULES.find((m) => m.name === name);
    assert.ok(record, 'first argument was not a module name: ' + name);
    assert.strictEqual(text, record.text(), 'second argument was not that module\'s source');
  }
});

t('a transform that returns the text unchanged leaves the graph running verbatim', async () => {
  const { runtime } = build(MODULES, { transform: (name, text) => text });
  await runtime.linkAll();
  await runtime.evaluateEntry('/$bunfs/root/cli');
  assert.strictEqual(globalThis.__result.greet, 'hello');
});

t('with no transform supplied the graph still runs — the seam is optional to the runtime', async () => {
  const { runtime } = build();
  await runtime.linkAll();
  await runtime.evaluateEntry('/$bunfs/root/cli');
  assert.strictEqual(globalThis.__result.greet, 'hello');
});

// ---- the whole graph, end to end ----------------------------------------------------------------

t('links and evaluates a graph, resolving imports, requires, assets and dynamic imports', async () => {
  const { runtime } = build();
  const linked = await runtime.linkAll();
  assert.strictEqual(linked, 7, 'every js module is linked, and only the js modules');
  await runtime.evaluateEntry('/$bunfs/root/cli');
  assert.deepStrictEqual(globalThis.__result, {
    greet: 'hello',
    fromB: 'b+c',
    doc: '# embedded notes',
    lazy: 'lazy',
    meta: '/$bunfs/root/cli',
    dir: '/$bunfs/root',
  });
});

t('a require ACROSS A CYCLE hands back a live namespace — the case node\'s own loader refuses', async () => {
  // chunk-c requires chunk-b while chunk-b is still evaluating. Under node's require(esm) this is
  // ERR_REQUIRE_CYCLE_MODULE; here the namespace is live and fills in as evaluation proceeds.
  const { runtime } = build();
  await runtime.linkAll();
  await runtime.evaluateEntry('/$bunfs/root/cli');
  const c = runtime.namespaceOf('/$bunfs/root/chunk-c.js');
  assert.strictEqual(c.backToB(), 'function', 'the cyclic partner resolved once evaluation completed');
});

// ---- what require returns is decided by the container's loader ------------------------------------

t('require returns a namespace for js, decoded contents for text', async () => {
  const { runtime } = build();
  await runtime.linkAll();
  assert.strictEqual(typeof runtime.requireSync('/$bunfs/root/chunk-a.js').greet, 'function');
  assert.strictEqual(runtime.requireSync('/$bunfs/root/notes.md'), '# embedded notes');
});

t('require REFUSES a native blob by name rather than feeding bytes to the JavaScript parser', async () => {
  const { runtime } = build();
  await runtime.linkAll();
  assert.throws(() => runtime.requireSync('/$bunfs/root/blob.node'), /is a napi module; this host does not serve it/);
});

t('a dynamic import of an embedded ASSET is refused for what it is, not called missing', async () => {
  // Routing it to the external path would report "the graph names no module", which is false — the
  // graph names it; this host just will not evaluate a text asset as JavaScript.
  const { runtime } = build();
  await runtime.linkAll();
  await assert.rejects(() => runtime.evaluatedModule('/$bunfs/root/notes.md'),
    /is a text module; this host does not serve it to import\(\)/);
});

t('the import path and the require path see the SAME substituted builtin', async () => {
  // Two caches meant two `fs` objects, so a module that imports fs and one that requires it would
  // have been looking at different things.
  const { runtime } = build();
  await runtime.linkAll();
  await runtime.evaluatedModule('/$bunfs/root/chunk-embedded-read.js');
  assert.strictEqual(runtime.requireSync('fs'), runtime.requireSync('node:fs'));
  assert.strictEqual(runtime.requireSync('fs').readFileSync('/$bunfs/root/notes.md', 'utf8'), '# embedded notes');
});

t('the static linker and the dynamic-import callback reach the SAME module', async () => {
  // One dispatch serves both of node's callbacks; two would be two answers waiting to disagree.
  const { runtime } = build();
  await runtime.linkAll();
  const viaDynamic = await runtime.evaluatedModule('/$bunfs/root/chunk-a.js');
  assert.strictEqual(viaDynamic, runtime.moduleFor('/$bunfs/root/chunk-a.js'),
    'the linker and the dynamic-import path must not each compile their own copy');
  const builtinViaDynamic = await runtime.evaluatedModule('path');
  assert.strictEqual(builtinViaDynamic, await runtime.evaluatedModule('node:path'));
});

t('concurrent importers of one builtin share a single module', async () => {
  const { runtime } = build();
  const [a, b] = await Promise.all([runtime.evaluatedModule('path'), runtime.evaluatedModule('path')]);
  assert.strictEqual(a, b, 'caching after the await is a check-then-set across a suspension point');
});

t('a module the graph does not carry is refused with its name, not a property-of-undefined', () => {
  const { runtime } = build();
  assert.throws(() => runtime.moduleFor('/$bunfs/root/never-existed.js'), /the graph names no module \/\$bunfs\/root\/never-existed\.js/);
});

// ---- what reaches outside the graph ----------------------------------------------------------------

t('node builtins resolve, by import and by require alike', async () => {
  const { runtime } = build();
  await runtime.linkAll();
  await runtime.evaluatedModule('/$bunfs/root/chunk-builtin.js');
  assert.strictEqual(runtime.namespaceOf('/$bunfs/root/chunk-builtin.js').check(), 'b.txt:function');
});

t('the fs a hosted module imports is the SUBSTITUTED one, so embedded paths resolve', async () => {
  const { runtime } = build();
  await runtime.linkAll();
  await runtime.evaluatedModule('/$bunfs/root/chunk-embedded-read.js');
  assert.strictEqual(runtime.namespaceOf('/$bunfs/root/chunk-embedded-read.js').read(), '# embedded notes');
});

t('a bare specifier that is neither embedded, provided, nor a builtin is refused by name', async () => {
  const modules = [...MODULES, record('/$bunfs/root/chunk-bare.js', 'import "left-pad"; export const x = 1;')];
  const { runtime } = build(modules);
  // Resolving out of THIS host's package tree would be a different tree than the graph was built
  // against — a wrong answer wearing the shape of a right one.
  await assert.rejects(() => runtime.evaluatedModule('/$bunfs/root/chunk-bare.js'),
    /neither embedded nor a module this host provides/);
});

t('a module Bun provides and node does not is served from one shared instance', async () => {
  const modules = [...MODULES, record('/$bunfs/root/chunk-ws.js', 'import { WebSocket } from "ws"; export const w = () => WebSocket;')];
  const { runtime } = build(modules);
  await runtime.linkAll();
  await runtime.evaluatedModule('/$bunfs/root/chunk-ws.js');
  assert.strictEqual(runtime.namespaceOf('/$bunfs/root/chunk-ws.js').w(), 'stub-ws');
  assert.strictEqual(runtime.requireSync('ws').WebSocket, 'stub-ws', 'the sync path must see the same module the import path does');
});

// ---- failures reach the boot channel rather than the void ------------------------------------------

t('a body that throws AFTER its first await is reported, not lost', async () => {
  const modules = [
    record('/$bunfs/root/cli', 'export const x = 1;'),
    record('/$bunfs/root/chunk-throws.js', 'await null; throw new Error("late failure");'),
  ];
  const { runtime, errors } = build(modules);
  await runtime.linkAll();
  runtime.namespaceOf('/$bunfs/root/chunk-throws.js');
  await new Promise((r) => setTimeout(r, 20));
  assert.deepStrictEqual(errors, [['/$bunfs/root/chunk-throws.js', 'late failure']],
    'this rejection lands outside every try/catch in the host, so the runtime has to carry it out');
});

t('a linking failure surfaces to the caller rather than being swallowed', async () => {
  const modules = [record('/$bunfs/root/cli', 'import "/$bunfs/root/absent.js"; export const x = 1;')];
  const { runtime } = build(modules);
  await assert.rejects(() => runtime.linkAll(), /the graph names no module \/\$bunfs\/root\/absent\.js/);
});

for (const { name, fn } of cases) {
  try { await fn(); pass++; console.log('ok   - ' + name); }
  catch (e) { fail++; console.log('FAIL - ' + name + '\n       ' + (e && e.message)); }
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
