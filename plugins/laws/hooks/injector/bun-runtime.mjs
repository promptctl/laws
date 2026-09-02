// bun-runtime.mjs — link and evaluate Bun's module graph under node's `vm`.
//
// WHY THIS IS NOT NODE'S LOADER. Bun's chunks call `import.meta.require("/$bunfs/root/chunk-….js")`
// — a SYNCHRONOUS, LAZY require between ES modules, which Bun answers with a live namespace even
// when the target is mid-evaluation. Node has nothing of the kind: `require(esm)` refuses to link a
// module whose graph touches one that is currently evaluating (ERR_REQUIRE_CYCLE_MODULE), and
// rewriting those call sites into static imports fails differently — it creates cycles the real
// graph never had, which then break on TDZ. Both were measured on the shipped 2.1.258 before this
// shape was chosen. `vm.SourceTextModule` gives the one thing that works: the graph is linked here,
// and a namespace is handed out on demand exactly as Bun does. It also lets `import.meta` be
// populated directly, so the recovered sources run VERBATIM — there is no rewriting step anywhere.
//
// Everything effectful is a parameter, so this runtime can be driven against a handful of synthetic
// modules with no binary, no terminal and no disk. [LAW:effects-at-boundaries]

import vm from 'node:vm';
import { isBuiltin } from 'node:module';

// Build a runtime over one graph.
//   embedded    — the read-only view from embedded-fs.js (loaderOf/text)
//   sources     — name -> the graph's module record
//   provided    — modules Bun supplies that node does not, as ready namespaces (e.g. `ws`)
//   substitute  — name -> (realExports) => exports, for builtins that must be adapted (e.g. `fs`)
//   importBuiltin / requireBuiltin — how a node builtin is reached, async and sync
//   onEvaluationError — a module body that rejects after this runtime has already returned
export function createModuleRuntime({
  embedded, sources, provided = {}, substitute = {},
  importBuiltin, requireBuiltin, onEvaluationError,
}) {
  const compiled = new Map();
  const externalModules = new Map();
  const externalExportsCache = new Map();

  const isGraphModule = (specifier) => embedded.loaderOf(specifier) === 'js';

  // Anything neither embedded, provided, nor a node builtin would otherwise be resolved out of the
  // HOST's own package tree — a different one than the graph was built against, which is a wrong
  // answer wearing the shape of a right one. [LAW:no-silent-failure]
  const refuseUnknown = (specifier, verb) => {
    // A virtual path the graph does not carry is a different fact from a package this host will not
    // resolve, and the message has to say which one happened.
    if (specifier.startsWith(embedded.VIRTUAL_ROOT)) throw new Error(`the graph names no module ${specifier}`);
    throw new Error(`the graph ${verb} ${specifier}, which is neither embedded nor a module this host provides`);
  };

  async function externalExports(specifier) {
    const id = specifier.replace(/^node:/, '');
    if (provided[id]) return provided[id];
    if (!isBuiltin(id)) refuseUnknown(specifier, 'imports');
    const real = await importBuiltin(id);
    return substitute[id] ? substitute[id](real) : real;
  }

  function externalExportsSync(specifier) {
    const id = specifier.replace(/^node:/, '');
    if (externalExportsCache.has(id)) return externalExportsCache.get(id);
    if (provided[id]) { externalExportsCache.set(id, provided[id]); return provided[id]; }
    if (!isBuiltin(id)) refuseUnknown(specifier, 'requires');
    const real = requireBuiltin(id);
    const exports = substitute[id] ? substitute[id](real) : real;
    externalExportsCache.set(id, exports);
    return exports;
  }

  async function externalModule(specifier) {
    const id = specifier.replace(/^node:/, '');
    const cached = externalModules.get(id);
    if (cached) return cached;
    const exported = await externalExports(specifier);
    const names = [...new Set(['default', ...Object.keys(exported)])].filter((k) => /^[A-Za-z_$][\w$]*$/.test(k));
    const mod = new vm.SyntheticModule(names, function () {
      for (const n of names) this.setExport(n, n === 'default' ? (exported.default ?? exported) : exported[n]);
    }, { identifier: specifier });
    externalModules.set(id, mod);
    return mod;
  }

  function moduleFor(name) {
    const cached = compiled.get(name);
    if (cached) return cached;
    const record = sources.get(name);
    // A specifier the graph resolves to nothing is version drift, and the message has to say which
    // one — "cannot read properties of undefined" would name only the symptom.
    if (!record) throw new Error(`the graph names no module ${name}`);
    if (record.loader !== 'js') throw new Error(`${name} is a ${record.loader} module and cannot be evaluated as JavaScript`);
    const mod = new vm.SourceTextModule(record.text(), {
      identifier: name,
      // Bun's import.meta, reproduced rather than rewritten into the source.
      initializeImportMeta(meta) {
        meta.url = 'file://' + name;
        meta.filename = name;
        meta.dirname = name.replace(/\/[^/]*$/, '');
        meta.require = requireSync;
      },
      importModuleDynamically: (specifier) => evaluatedModule(specifier),
    });
    compiled.set(name, mod);
    return mod;
  }

  // Bun's synchronous require. What comes back is decided by the container's own loader field,
  // which is why bun-graph carries it: a `napi` or `file` module fed to the JavaScript parser would
  // either fail cryptically or, decoded as latin1, parse into nonsense.
  function requireSync(specifier) {
    const loader = embedded.loaderOf(specifier);
    if (loader === undefined) return externalExportsSync(specifier);
    if (loader === 'js') return namespaceOf(specifier);
    if (loader === 'text') return embedded.text(specifier);
    throw new Error(`${specifier} is a ${loader} module; this host does not serve it to require()`);
  }

  // ONE dispatch, used by both of node's callbacks. Asking the same question in two places is two
  // answers waiting to disagree. [LAW:one-source-of-truth]
  const resolveModule = (specifier) => isGraphModule(specifier) ? moduleFor(specifier) : externalModule(specifier);

  // The dynamic-import callback must hand back an EVALUATED module: node takes its namespace as it
  // finds it and will not run the body on our behalf.
  async function evaluatedModule(specifier) {
    const mod = await resolveModule(specifier);
    if (mod.status === 'unlinked') await mod.link(resolveModule);
    if (mod.status === 'linked') await mod.evaluate();
    return mod;
  }

  function namespaceOf(name) {
    const mod = moduleFor(name);
    // evaluate() settles asynchronously, but V8 runs the body synchronously up to its first await
    // and the namespace object is live from link time — so this is the same object, filled in the
    // same order, that Bun's require hands back from inside a cycle. The catch is not a swallow: a
    // body that throws after its first await lands outside every try/catch here, and without it the
    // process would die with no name attached to the cause. [LAW:no-silent-failure]
    if (mod.status === 'linked') mod.evaluate().catch((e) => onEvaluationError(name, e));
    return mod.namespace;
  }

  return {
    moduleFor, requireSync, namespaceOf, evaluatedModule,
    // import.meta.require is synchronous, so a module can only be evaluated on demand if it is
    // already linked. Linking every module up front is one unconditional pass over the graph — the
    // alternative, deciding per module whether it might be required later, is a guess.
    // [LAW:dataflow-not-control-flow]
    // Linking a module links its dependencies too, and node refuses a second explicit link() on
    // one that has already been linked. This loop therefore only survives if it never reaches a
    // module after something else pulled it in — which is true of the shipped graph purely because
    // Bun emits its table dependencies-first. That is incidental order doing load-bearing work, so
    // the status is checked rather than assumed. [LAW:no-ambient-temporal-coupling]
    async linkAll() {
      const names = [...sources.values()].filter((m) => m.loader === 'js').map((m) => m.name);
      for (const name of names) moduleFor(name);
      for (const name of names) {
        const mod = moduleFor(name);
        if (mod.status === 'unlinked') await mod.link(resolveModule);
      }
      return names.length;
    },
    async evaluateEntry(name) {
      await moduleFor(name).evaluate();
    },
  };
}
