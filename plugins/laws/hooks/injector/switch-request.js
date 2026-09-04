// switch-request.js — turn one switch request into an applied switch on the live session, or a
// named refusal.
//
// This is the composition, and deliberately nothing more: the POLICY is laws-excise's `decide()`,
// called unchanged and taken whole; WHICH conversation is seam-registry's answer, proven rather than
// picked; and WHAT to do to it is live-switch's plan. Nothing here re-decides anything, because a
// second opinion about craft compatibility is a second enforcer that will one day disagree with the
// first. [LAW:single-enforcer]
//
// WHY THE DECISION IS RE-MADE FROM DISK RATHER THAN CARRIED. The request names a transcript, not a
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

const { planLiveSwitch, applyLiveSwitch } = require('./live-switch.js');
// One spelling of "what went wrong", shared with the rest of the injector. [LAW:one-source-of-truth]
const { because } = require('./boot-guard.js');

// Refusals this composition adds to the ones its parts already name. [LAW:no-silent-failure]
const REFUSED = {
  incomplete: 'the-switch-request-is-missing-a-field',
  unreadable: 'the-transcript-named-by-the-request-cannot-be-read',
  moot: 'the-switch-no-longer-applies',
};

const REQUIRED = ['transcript', 'choice', 'incomingMedium'];

// Enact one request.
//   request  — { transcript, choice, incomingMedium, summary? }
//   registry — seam-registry, to find the conversation the decision is about
//   decide / conflictEdges — laws-excise's policy, injected so this file owns none of it
//   readFile / uuid / now  — the effects
function enactSwitch({ request, registry, decide, conflictEdges, readFile, uuid, now }) {
  const missing = REQUIRED.filter((k) => !request || !request[k]);
  if (missing.length) return { ok: false, reason: REFUSED.incomplete, detail: missing.join(', ') };

  let raw;
  try { raw = readFile(request.transcript); }
  catch (e) { return { ok: false, reason: REFUSED.unreadable, detail: because(e) }; }

  // Split exactly as laws-excise's own reader does, so the line numbering the decision is built on
  // is the same numbering everywhere. A trailing newline would otherwise add an empty final record.
  const lines = raw.split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();

  const decision = decide(lines, { conflictEdges, incomingMedium: request.incomingMedium });
  // Not an error and not a success: the conversation moved and there is nothing left to switch away
  // from. Saying so by name is what stops the caller reporting a switch that never happened.
  if (!decision.trigger) return { ok: false, reason: REFUSED.moot, detail: decision.reason };

  // The decision names its anchor by uuid; the conversation holding that uuid is the one to edit.
  const owner = registry.ownerOf(decision.rewind.summarizeTo);
  if (!owner.ok) return owner;

  const plan = planLiveSwitch({
    snapshot: owner.controller.transcript.getSnapshot(),
    decision, choice: request.choice, summary: request.summary, uuid: uuid(), now: now(),
  });
  if (!plan.ok) return plan;

  const applied = applyLiveSwitch(owner.controller, plan);
  // What was retired travels back so the caller can release the craft locks it owns, rather than
  // re-deriving the set and risking a different answer. [LAW:one-source-of-truth]
  return { ...applied, choice: request.choice, switchedFrom: decision.current, switchedTo: decision.incoming };
}

module.exports = { REFUSED, REQUIRED, enactSwitch };
