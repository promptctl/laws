// seam-registry.js — hold every object the injected seams announced, and hand back the one that
// provably owns a given conversation.
//
// WHY IT HOLDS ALL OF THEM. The seam fires in a class field initializer, so it sees every instance
// the app builds, not just the main REPL's. Keeping "the last one" would be a guess that reads as a
// fact, and the day a subagent builds its own the guess would be wrong in a way nothing reports.
// Instead the caller says WHICH conversation it means, by the uuid of a message in it, and this file
// answers with the controller whose live store actually contains that message — or refuses because
// none does, or because several do. [LAW:parse-dont-validate] what comes back is a controller proven
// to own the conversation, so the enactment never re-checks.
//
// [LAW:no-shared-mutable-globals] the held set is behind this API, with one owner. The global the
// injected source calls is installed by the host from a registrar built here; nothing else writes it.
// [LAW:effects-at-boundaries] pure: objects in, objects out. No process, no disk, no globals of its own.

'use strict';

// Every way the conversation's owner can fail to be identified, named — the enactment reports these
// to the caller that asked for a switch, so they are contract. [LAW:no-silent-failure]
const UNOWNED = {
  none: 'no-live-conversation-contains-that-message',
  several: 'several-live-conversations-contain-that-message',
  neverAnnounced: 'no-seam-ever-announced-a-conversation',
};

// How a held object is read. Kept here, in one place, because "the live messages of a controller" is
// a fact about the app's shape and two spellings of it would be two facts. [LAW:one-source-of-truth]
const snapshotOf = (controller) => controller.transcript.getSnapshot();

function createSeamRegistry() {
  const announced = [];
  return {
    // What the injected source calls. Its return value lands in a class field on the instance, so it
    // returns undefined deliberately: the field is a side effect of announcing, never a value the
    // app should find something in.
    registrar: {
      controller(instance) { announced.push(instance); },
    },

    // How many announced. The host reports this so a boot where the seam spliced but never fired is
    // distinguishable from one where it fired — two different failures with one symptom.
    get count() { return announced.length; },

    // The controller whose live conversation contains `uuid`. Refusing on several is not caution:
    // two stores holding one message uuid means the caller's idea of which conversation it is
    // editing is already wrong, and picking one would enact the switch on a coin flip.
    ownerOf(uuid) {
      if (announced.length === 0) return { ok: false, reason: UNOWNED.neverAnnounced };
      const owners = announced.filter((c) => snapshotOf(c).some((m) => m && m.uuid === uuid));
      if (owners.length === 0) return { ok: false, reason: UNOWNED.none, detail: uuid };
      if (owners.length > 1) return { ok: false, reason: UNOWNED.several, detail: uuid };
      return { ok: true, controller: owners[0] };
    },
  };
}

module.exports = { UNOWNED, snapshotOf, createSeamRegistry };
