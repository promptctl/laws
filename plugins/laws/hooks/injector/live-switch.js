// live-switch.js — turn a switch decision into the operations that enact it on a LIVE conversation.
//
// WHY THIS IS NOT laws-excise's job. That module owns the policy and the DISK surgery, and it stays
// the only place that decides anything: `decide()` is called here unchanged and its verdict is taken
// whole. What this file adds is the crossing from the on-disk representation to the in-memory one,
// which is a real boundary because the two are not the same data structure:
//
//   on disk — a TREE. Records carry parentUuid, branches can be severed, and bookkeeping records
//             (last-prompt, mode, file-history-snapshot) have no uuid at all.
//   live    — a FLAT ARRAY. No parentUuid anywhere; the app cuts it with lastIndexOf. It also holds
//             transient `progress` records that are never persisted.
//
// MEASURED on a hosted 2.1.258 session: 27 disk records against 18 live messages, and every disk
// record carrying a uuid was present live. So UUID is the only thing that crosses, and `decide()`'s
// `conflictIndices` — which are LINE NUMBERS — must never be used on this side. They name positions
// in a file, and using them against the live array would silently address the wrong messages.
//
// THE OFF-BY-ONE THAT MATTERS. The two rewinds are not symmetric with their disk counterparts:
//   rewindTo(lines, anchor)        keeps THROUGH the anchor  (disk; the anchor survives)
//   rewindConversationTo(msg)      keeps UP TO msg           (live; msg itself is dropped)
// So a live rewind that must keep the craft-load message is given the message AFTER it, and a live
// rewind that must drop the craft-load message is given the craft-load message itself. Both spellings
// produce the same conversation as the disk path, and getting this backwards is a one-message error
// that would look almost right.
//
// [LAW:effects-at-boundaries] planLiveSwitch is pure — snapshot in, plan out — so every case above is
//   testable against synthetic snapshots with no binary, no session and no terminal. applyLiveSwitch
//   is the one unit that touches the running app.
// [LAW:parse-dont-validate] a plan is proof that every uuid the decision named is present live; the
//   applier takes message OBJECTS, never uuids, so it cannot be handed one that does not resolve.

'use strict';

const { stubText, SWITCH_ACTIONS } = require('../scripts/laws-excise.js');
// One spelling of "a controller's live messages", shared with seam-registry, whose suite asserts
// callers cannot spell it differently. [LAW:one-source-of-truth]
const { snapshotOf } = require('./seam-registry.js');

// Every way a decision can fail to become a live plan, named — these reach the caller that asked for
// the switch, so they are contract. [LAW:no-silent-failure]
const UNPLANNABLE = {
  unknownChoice: 'not-one-of-the-four-switch-choices',
  notLive: 'a-message-the-decision-named-is-not-in-the-live-conversation',
  noTemplate: 'the-live-conversation-has-no-user-message-to-shape-a-summary-from',
  summaryMissing: 'rewind_summarize-was-asked-for-without-a-summary',
  notStubbable: 'a-craft-load-message-does-not-carry-replaceable-text',
  nothingBefore: 'the-craft-load-is-the-first-live-message-so-a-discard-has-nowhere-to-land',
};

// The app's own value for "the user picked a message and rewound to it", which is what a craft switch
// is. It is used rather than a string of our own because it is the one the app's source already
// carries: an unrecognised source would take the caller through a validator this file cannot see, and
// the two behavioural branches downstream of it (`auto_restore_cancel`) are ones we specifically do
// NOT want. The telemetry it produces is therefore the app's, and honest about what happened.
const REWIND_SOURCE = 'message_selector';

// DERIVED, never re-listed. bin/laws-switch already takes its accepted choices from this same
// table, so a fifth action added there would be accepted by the CLI and refused here as
// `unknownChoice` — the live path and the relaunch path silently disagreeing about what a switch is.
// [LAW:one-source-of-truth]
const CHOICES = Object.keys(SWITCH_ACTIONS);

const unplannable = (reason, detail) => ({ ok: false, reason, detail });

// The live messages a craft load produced, by uuid. `decide()` names the OLDEST conflicting load in
// `rewind.summarizeTo`; that uuid is the one that crosses, and the tombstone targets every live
// message whose uuid appears in the decision's own set.
// It enforces its own precondition rather than trusting a caller's: an absent uuid would otherwise
// match the first record that also has none, and this function is what PROVES a message's identity —
// the same ambiguity seam-registry's ownerOf refuses, which only screens the anchor and not the rest
// of the conflicting set. [LAW:parse-dont-validate]
const liveIndexOf = (snapshot, uuid) => (uuid ? snapshot.findIndex((m) => m && m.uuid === uuid) : -1);

// A tombstoned copy. A NEW object, never a mutation: the store is read through getSnapshot and the UI
// re-renders on identity, so editing in place would change the conversation without redrawing it.
function stubbedMessage(message, medium, activeMedium) {
  const content = message.message && message.message.content;
  // A craft load is a meta user message whose content is a one-element text block — the shape
  // craftMediumOf recognises on disk. Anything else is not the message we think it is, and stubbing
  // it would be a guess written into the user's conversation.
  if (!Array.isArray(content) || !content[0] || typeof content[0].text !== 'string') return null;
  return {
    ...message,
    message: {
      ...message.message,
      content: [{ ...content[0], text: stubText(medium, activeMedium) }, ...content.slice(1)],
    },
  };
}

// The summary is SHAPED FROM a real user message rather than built from a literal. A live message
// carries far more fields than the renderer's minimum (permissionMode, promptSource, promptId,
// origin…), and inventing a shape from the few that are obvious is how a message renders as a blank
// row. The template supplies every field; only identity, time and content are overridden.
function summaryFrom(snapshot, { uuid, timestamp, text }) {
  // `isMeta` is excluded, and that exclusion is the whole correctness of this function. A craft load
  // IS a user-typed record by `type`, but it is an injected one — which is exactly what `isMeta`
  // marks. Spreading it would stamp the user's summary as injected non-chat content and let the app
  // treat it the way it treats guidance rather than the way it treats what the user said, defeating
  // the option that exists to PRESERVE that work.
  const template = [...snapshot].reverse().find((m) => m && m.type === 'user' && m.message && !m.isMeta);
  if (!template) return null;
  return { ...template, uuid, timestamp, message: { ...template.message, content: text } };
}

// Turn a decision into the live operations that enact it.
//   snapshot  — controller.transcript.getSnapshot()
//   decision  — decide()'s verdict, taken whole and unmodified
//   choice    — one of CHOICES
//   summary   — the text for rewind_summarize
//   uuid/now  — identity and time, passed in because they are effects [LAW:effects-at-boundaries]
function planLiveSwitch({ snapshot, decision, choice, summary, uuid, now }) {
  if (!CHOICES.includes(choice)) return unplannable(UNPLANNABLE.unknownChoice, choice);
  // Every plan carries the same three fields. reject is the one where all of them are empty, so it
  // needs no case of its own anywhere downstream. [LAW:dataflow-not-control-flow]
  const empty = { ok: true, choice, rewindAt: null, tombstones: [], append: null };
  if (choice === 'reject') return empty;

  const loadUuid = decision.rewind.summarizeTo;
  const loadIndex = liveIndexOf(snapshot, loadUuid);
  if (loadIndex === -1) return unplannable(UNPLANNABLE.notLive, loadUuid);

  // Discard drops the craft load itself and everything after it — live rewind is exclusive of its
  // argument. It returns BEFORE the tombstones are built, and that ordering is load-bearing: the
  // messages a tombstone would rewrite are the ones this choice deletes, so requiring them to be
  // rewritable would refuse a switch over the shape of a message about to cease existing.
  if (choice === 'rewind_discard') {
    // The disk path refuses this exact state (its `discardTo` is the load's parentUuid, which is
    // absent when the load is first), and the live path must agree: aiming the rewind at index 0
    // would truncate the conversation to nothing and report success. Two enforcers of one rule do
    // not get to disagree about what is legal. [LAW:single-enforcer]
    if (loadIndex === 0) return unplannable(UNPLANNABLE.nothingBefore, loadUuid);
    return { ...empty, rewindAt: snapshot[loadIndex] };
  }

  // Checked BEFORE any work, because it is the most fundamental thing wrong with the request. Left
  // until after the tombstones were built, a missing summary surfaced as `notStubbable` whenever the
  // anchor's shape was also unusual — telling the caller its message was malformed when what it
  // actually did was forget an argument. The most basic precondition reports first.
  if (choice === 'rewind_summarize' && !summary) return unplannable(UNPLANNABLE.summaryMissing);

  // WHICH conflicts must survive the crossing depends on which of them the choice keeps, and that is
  // the same reasoning the discard arm above uses. `tombstone` keeps the whole conversation, so every
  // conflicting load stays engaged and every one must be stubbed. `rewind_summarize` cuts at
  // loadIndex + 1, and `decision.conflicts` is ordered oldest-first with the anchor at [0] — so every
  // OTHER conflict is newer, sits past the cut, and is deleted by the rewind whether or not it was
  // ever stubbed. Demanding those be live and rewritable would refuse the switch over the shape of a
  // message about to cease existing, which is exactly what the disk path does not do.
  const mustStub = choice === 'tombstone' ? decision.conflicts : decision.conflicts.slice(0, 1);

  // Refusing when one of THESE is missing is the point: a partial tombstone leaves a craft engaged
  // that the switch reported as retired, which is the defect the gate exists to prevent one level up.
  // And the REPLACEMENT is built here rather than at apply time, so a plan is proof that every
  // tombstone can be carried out — deferring it would leave a way to fail halfway through, with the
  // rewind already applied and no way back. [LAW:no-silent-failure] [LAW:parse-dont-validate]
  const tombstones = [];
  for (const { uuid: conflictUuid, medium } of mustStub) {
    const message = snapshot[liveIndexOf(snapshot, conflictUuid)];
    if (!message) return unplannable(UNPLANNABLE.notLive, conflictUuid);
    const stubbed = stubbedMessage(message, medium, decision.incoming);
    if (!stubbed) return unplannable(UNPLANNABLE.notStubbable, conflictUuid);
    tombstones.push({ uuid: conflictUuid, stubbed });
  }

  if (choice === 'tombstone') return { ...empty, tombstones };

  // rewind_summarize: keep the craft load (tombstoned), drop everything after it, then say what was
  // lost. The anchor is the message AFTER the load, because the live rewind drops what it is given.
  const append = summaryFrom(snapshot, { uuid, timestamp: now, text: summary });
  if (!append) return unplannable(UNPLANNABLE.noTemplate);
  // A craft load that is the very last live message has nothing after it to drop, so there is no
  // rewind to do — only the tombstone and the summary. An empty value, not a special case.
  const rewindAt = loadIndex + 1 < snapshot.length ? snapshot[loadIndex + 1] : null;
  return { ...empty, rewindAt, tombstones, append };
}

// Apply a plan to the running app. The only unit here that touches the live session.
//
// The branch on `plan.rewindAt` is the domain's own enum surfacing — a rewind and a tombstone invoke
// genuinely different app operations, and `rewindConversationTo` does far more than slice an array
// (it resets the turn, bumps the conversation id, evicts rewound file tracking). Collapsing them
// would mean running that reset for a choice that must not have it.
//
// [LAW:no-ambient-temporal-coupling] a discrete owned event: rewind, read, replace, return. Nothing
// is left listening, and no later behaviour of the session depends on when this ran.
function applyLiveSwitch(controller, plan) {
  if (plan.rewindAt) controller.rewindConversationTo(plan.rewindAt, REWIND_SOURCE);

  // Read AFTER the rewind: the rewind is what decided which messages still exist, so building the
  // replacement from the pre-rewind array would reinstate the ones it just dropped.
  const after = snapshotOf(controller);
  const stubs = new Map(plan.tombstones.map((t) => [t.uuid, t.stubbed]));

  // A substitution, and nothing else: every replacement was proven at plan time, so there is no arm
  // here that can fail with the rewind already applied.
  const replaced = after.map((message) => (message && stubs.get(message.uuid)) || message);
  const messages = plan.append ? [...replaced, plan.append] : replaced;

  // Two different questions, and conflating them reported a destructive rewind as a no-op. Whether
  // to CALL replace() is about the array: replacing with an equal one would redraw the transcript
  // and bump the store for a choice (reject) that promised to change nothing. Whether the
  // conversation CHANGED includes the rewind, which already happened above and which `after` — read
  // after it — cannot witness.
  const replaces = messages.length !== after.length || messages.some((m, i) => m !== after[i]);
  if (replaces) controller.transcript.replace(messages);
  return {
    ok: true, rewound: plan.rewindAt !== null, tombstoned: plan.tombstones.length,
    changed: plan.rewindAt !== null || replaces,
  };
}

module.exports = { UNPLANNABLE, CHOICES, REWIND_SOURCE, stubbedMessage, summaryFrom, planLiveSwitch, applyLiveSwitch };
