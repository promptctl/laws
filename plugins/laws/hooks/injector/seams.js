// seams.js — the fragments of the app's own source the injector anchors on, and what it splices in.
//
// This file is the ONLY place in the tree that knows anything about Claude Code's internals, and it
// deliberately knows as little as possible: one property name, and one statement to insert before it.
// Everything else — which module carries it, at what offset — is resolved from the installed binary
// at launch by seam-plan.js. There is no chunk name here and no version literal, because both change
// every release and a map that changes weekly is a map that is already lying.
//
// WHY THESE ANCHORS SURVIVE MINIFICATION. Bun renames every module-scope binding (the class holding
// the conversation is `A3`; the accessor that reaches it is two letters) but it cannot rename a
// PROPERTY without proving nothing reaches it dynamically — so method and field names come through
// verbatim. Anchoring on a property name rather than on an offset, a variable, or a line number is
// what makes this hold across releases without a table someone maintains by hand.
//
// MEASURED on the shipped 2.1.258 (a dated observation, not an input — nothing below reads it): the
// conversation lives on `class A3 { session; store; transcript; turn; ... }`, whose
// `rewindConversationTo(msg, source)` slices its own store and resets the turn. Both the method and
// the field anchored below occur exactly once across all 1,818 embedded modules, 1,788 characters
// apart with no intervening `class`, so they are provably in the same class body.

'use strict';

// The instance announces itself as it is built. `restoreMessageSync` is a CLASS FIELD, so its
// initializer runs at construction with `this` bound to the instance — which is the whole reason it
// is the anchor rather than the method next to it: a method body only runs if the user rewinds, and
// by then it is too late to have been told about the object.
//
// Deliberately NOT `globalThis.__LAWS_SEAM__?.controller(this)`. The host installs the registrar
// before it evaluates anything, so an absent registrar is impossible by construction; making it
// survivable would only convert "the injector is broken" into a session that looks fine and silently
// cannot switch crafts. It fails at construction instead, which the boot self-check names and the
// launcher answers by falling back to stock claude. [LAW:no-silent-failure]
const REGISTRAR = '__LAWS_SEAM__';

const SEAMS = [
  {
    name: 'controller',
    // The lookbehind is load-bearing: it excludes `this.restoreMessageSync`, `au.restoreMessageSync`
    // and the `restoreMessageSync:` property in the props object, leaving only the field declaration.
    anchor: /(?<![.\w$])restoreMessageSync\s*=\s*(?=\()/,
    insert: `__lawsSeam=globalThis.${REGISTRAR}.controller(this);`,
  },
];

module.exports = { REGISTRAR, SEAMS };
