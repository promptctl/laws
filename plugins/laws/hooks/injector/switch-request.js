// switch-request.js — turn one switch request into an applied switch on the live session, or a
// named refusal.
//
// This is the composition, and deliberately nothing more: the POLICY is laws-excise's `decide()`,
// called unchanged and taken whole; WHICH conversation is seam-registry's answer, proven rather than
// picked; and WHAT to do to it is live-switch's plan. Nothing here re-decides anything, because a
// second opinion about craft compatibility is a second enforcer that will one day disagree with the
// first. [LAW:single-enforcer]
//
// WHAT THE CALLER GETS TO SAY, AND WHY IT IS SO LITTLE. A request carries a CHOICE and nothing else
// that matters: which transcript, which incoming craft, and which session all come from the pending
// offer the gate left behind, read here rather than accepted from the caller. That is what makes the
// channel's vocabulary actually be "one of four named choices to the switch that is already
// pending". It used to take the transcript path from the request, which meant a caller could point
// the session at any file it liked and have `decide()` run against it — a materially larger
// capability than the one the user was offered, and one this file's neighbour claimed it did not
// have. [LAW:parse-dont-validate] the offer is the boundary; past it there is nothing to re-check.
//
// WHY THE DECISION IS RE-MADE FROM DISK RATHER THAN CARRIED. The offer names a transcript, not a
// verdict. Between the gate offering the switch and the user choosing one, the conversation kept
// moving — so the verdict is recomputed against the transcript as it stands at the moment of
// enactment, and a switch that no longer applies refuses instead of enacting a stale one. This
// mirrors what the on-disk path already does in `applyRequest`.
//
// WHY IT DOES NOT TOUCH THE TRANSCRIPT FILE. The running app is the file's writer; a second writer
// editing it underneath would be two maps of one conversation, free to diverge.
// [LAW:one-source-of-truth] The switch changes the LIVE store and lets the app persist what it
// persists — which is also why on-disk deliverables survive every choice: nothing here opens a file
// for writing at all.
//
// [LAW:effects-at-boundaries] reading, identity and time all arrive as parameters, so the whole
//   orchestration is testable with no disk, no clock and no session.

'use strict';

const { planLiveSwitch, applyLiveSwitch, noopResult } = require('./live-switch.js');
// How a controller's live messages are read, and how a transcript's text becomes records, each have
// one home. Re-spelling either here would be a second copy free to drift from the original — and
// seam-registry's own suite asserts that callers cannot spell the first one differently.
// [LAW:one-source-of-truth]
const { snapshotOf } = require('./seam-registry.js');
const { toRawLines } = require('../scripts/laws-excise.js');
// One spelling of "what went wrong", shared with the rest of the injector. [LAW:one-source-of-truth]
const { because } = require('./boot-guard.js');

// Refusals this composition adds to the ones its parts already name. [LAW:no-silent-failure]
// Every refusal below happens BEFORE applyLiveSwitch runs, so each one can state as a fact that the
// live conversation is untouched. The caller then needs no table of which reasons are safe: it reads
// the fact. A reason string is a name for what went wrong; it is not evidence about what was done.
// [LAW:types-are-the-program]
const untouched = (reason, detail) => ({ ok: false, reason, detail, mutated: false });

const REFUSED = {
  incomplete: 'the-switch-request-names-no-choice',
  noOffer: 'no-switch-is-pending-in-this-session',
  unreadable: 'the-transcript-the-offer-names-cannot-be-read',
  moot: 'the-switch-no-longer-applies',
};

// All the caller may decide. Everything else about the switch is the offer's to state.
const REQUIRED = ['choice'];
// What an offer must carry to be actionable. A half-written one is refused rather than filled in.
const OFFERED = ['transcript', 'incomingMedium'];

// Enact one request.
//   request  — { choice, summary? } — the user's decision, and nothing more
//   readOffer — () => the pending offer, or null. The gate wrote it; this is the only thing that
//               says WHICH switch is being enacted, so it is read here and never taken from a caller
//   consumeOffer — () => void, called once the switch has been applied. An offer is for ONE switch:
//               without this it stays on disk and can be enacted again, and a second rewind lands on
//               a conversation the first already cut
//   registry — seam-registry, to find the conversation the decision is about
//   decide / conflictEdges — laws-excise's policy, injected so this file owns none of it
//   readFile / uuid / now  — the effects
function enactSwitch({ request, readOffer, consumeOffer, registry, decide, conflictEdges, readFile, uuid, now }) {
  const missing = REQUIRED.filter((k) => !request || !request[k]);
  if (missing.length) return untouched(REFUSED.incomplete, missing.join(', '));

  // The "already pending" half of what this channel promises, and it was unchecked: without an
  // offer there is no switch to apply, whatever a caller says.
  const offer = readOffer();
  const missingFromOffer = offer ? OFFERED.filter((k) => !offer[k]) : OFFERED;
  if (missingFromOffer.length) return untouched(REFUSED.noOffer, missingFromOffer.join(', '));

  let raw;
  try { raw = readFile(offer.transcript); }
  catch (e) { return untouched(REFUSED.unreadable, because(e)); }

  const decision = decide(toRawLines(raw), { conflictEdges, incomingMedium: offer.incomingMedium });
  // Not an error and not a success: the conversation moved and there is nothing left to switch away
  // from. Saying so by name is what stops the caller reporting a switch that never happened.
  if (!decision.trigger) return untouched(REFUSED.moot, decision.reason);

  // `reject` edits nothing, so it must not have to prove which conversation it would have edited.
  // Requiring ownership here made declining an offer fail whenever the conversation that carried the
  // craft had since ended — refusing to do nothing, on the grounds that it could not find the thing
  // it was not going to touch.
  if (request.choice === 'reject') {
    consumeOffer();
    return { ...noopResult(), choice: request.choice, switchedFrom: [], switchedTo: decision.incoming };
  }

  // The decision names its anchor by uuid; the conversation holding that uuid is the one to edit.
  const owner = registry.ownerOf(decision.rewind.summarizeTo);
  // How many conversations the seam is holding is the difference between "the uuid is stale" and
  // "the injection never landed", and it costs one field to say so. [LAW:no-silent-failure]
  if (!owner.ok) return { ...owner, live: registry.count, mutated: false };

  const plan = planLiveSwitch({
    snapshot: snapshotOf(owner.controller),
    decision, choice: request.choice, summary: request.summary, uuid: uuid(), now: now(),
  });
  // A plan that could not be made was never applied — the planner is pure and touches nothing.
  if (!plan.ok) return { ...plan, mutated: false };

  const applied = applyLiveSwitch(owner.controller, plan);
  // Consumed by the party that ACTED, not by the party that asked. The client used to remove it after
  // a successful reply, which left the offer live for anyone who enacted it without going through the
  // client — and a second rewind lands on a conversation the first already cut.
  // [LAW:no-ambient-temporal-coupling] one owner for the offer's lifetime, and it is the actor.
  consumeOffer();
  // What was retired travels back so the caller can release the craft locks it owns, rather than
  // re-deriving the set and risking a different answer. [LAW:one-source-of-truth]
  return { ...applied, choice: request.choice, switchedFrom: decision.current, switchedTo: decision.incoming };
}

module.exports = { REFUSED, REQUIRED, OFFERED, enactSwitch };
