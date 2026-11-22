---
name: plan-review
description: Review an implementation plan against the laws of code (laws:code) before any code is written. Takes a ticket whose plan is recorded on it, or a plan file. Checks every claim the plan makes about the code, then judges each decision the plan makes - where state lives, which layer decides, what it adds beside what exists, the cases it special-cases, the states it makes reachable - and reports every law violation and every way the plan fails to deliver its ticket, with no maximum. Strict by design - a plan that would work and breaks a law is a finding. Same iteration and NO MAJOR FINDINGS contract as laws:law-review, so one review loop serves both.
argument-hint: "<ticket-id>|<plan-file> [review iteration]"
context: fork
model: opus
---

`plan review -> load the laws -> 9 Haiku angles -> dedup (no verify) -> root decision -> all findings`

Plan under review: `$ARGUMENTS`

A plan is the cheapest place to fix a design. Every decision in it will be built on,
and a wrong one found here costs a rewrite of a few paragraphs. Found by
`laws:law-review`, it costs the implementation. Review the plan as strictly as you
would review the code it will become.

The second argument is the review iteration: 1 for the first review of this plan, 2
for the second, and so on. Without it, this is the first review.

## Tailoring for later iterations

On the first iteration, report every finding.

On the second, trivial or inconsequential findings may be left out.

On the third and fourth, report only MAJOR findings. A finding is MAJOR when it is
architectural, or when the code built from the plan would carry the violation into
everything built on it. From the fourth iteration on, report only serious law
violations: MAJOR findings at that point send the plan back to be written again from
scratch. That safeguard keeps a fundamentally wrong design from reaching code, so use
it with care, and always by the laws.

When you have no major findings, print this exact phrase: "NO MAJOR FINDINGS". The
planner is watching for it.

## A fundamentally flawed premise

Many serious violations in one review mean the plan rests on a wrong premise: a false
fact about the code, or a decision the rest of the plan is built around.

- On the first iteration, mark it a MAJOR finding, name the premise, and say why it
  fails the laws, so the planner can fix it.
- On the second, say plainly that the planner MUST replace that premise before the
  plan can go forward.
- On the third or later, state explicitly: "You need to TAKE A STEP BACK and
  reconsider this plan." Name the premise, say why it is not laws-compliant, and say
  what the laws require of a design here.

You say why the plan cannot go forward. You do not write the replacement plan: the
planner holds the ticket's context and decides the design. Group findings by root
cause and use them as the evidence. You may send more Haiku subagents to check facts
in the code, but the judgement that the plan is fundamentally invalid is yours.

## Before anything - load the laws

Run `/laws:code` (the Skill tool, skill `laws:code`) and read all of it. Every angle
below assumes you hold the laws, their diagnostics, and their token index. If it will
not load, stop and report that - there is no review without the laws
[LAW:no-silent-failure].

You are reviewing for **recall**: catch every wrong premise, every violation, and
every gap a careful reviewer would catch in one sitting. Err on the side of
surfacing. Do not praise or soften: state what is wrong and what the law requires
instead.

## Phase 0 - Gather the plan and the code it lands in

Given a ticket id, read the ticket in full (`lit show <id>` where the repo uses lit):
its description, acceptance criteria, plan, comments and parent. Given a file, read
the file, and find the ticket it plans for if it names one. The ticket tells you what
the plan must deliver.

Then read the code the plan will change, call, or build beside: every file, module and
mechanism it names, and the ones it would have to touch without naming them. A plan
is judged by where it lands. A decision that reads well on its own and breaks a law
in the code it lands in is a finding, and so is existing code the plan must work
around [LAW:carrying-cost].

## Phase 1 - Find candidates (2 premise and delivery angles + 5 law angles + 1 cleanup angle + 1 conventions angle)

Run **9 independent finder angles** in parallel, one Agent call per angle with
`model: "haiku"`. Each prompt carries the plan in full, the ticket, the angle's text
verbatim, and an instruction to load `laws:code` first. Each surfaces candidates with
the plan `step` (a short quote of the plan text it concerns), `evidence` (the file,
command output, or ticket text that shows it), a one-line `summary`, and a concrete
`failure_scenario`. The angles marked **no cap** report every instance they find; the
rest surface **up to 6** each.

### Premises (no cap)

List every claim the plan makes or depends on about the code, the data, or a tool:
that a function returns or throws something, that a value can be missing, that a path
is reached, that a mechanism exists, that a caller does or does not exist. Include
the claims it assumes without stating them: "retry the failed upload" assumes there is
a point where the failure is seen. Check each one in the code. A false claim is a
candidate, and so is one that could not be checked where a step depends on it. A
claim the planner did not check is never treated as true.

### Delivery

Walk the ticket's acceptance criteria and the need behind them. For each, find the
steps that deliver it; a criterion no step delivers is a candidate. Then walk the
steps for order and failure: a step that needs the result of a later one, a design
whose correctness depends on which call runs first [LAW:no-ambient-temporal-coupling],
a failure path the plan never handles, a migration or concurrent caller left between
two states, work with no test of its behavior [LAW:verifiable-goals], a planned test
that asserts structure instead of behavior [LAW:behavior-not-structure]. A plan that builds
something the ticket does not ask for is a candidate too.

### Placement

For each piece of state, decision, and check the plan introduces, ask where it lives
and who owns it. Candidates: a fact held in a second place that can disagree with the
first [LAW:one-source-of-truth]; an invariant enforced in more than one place
[LAW:single-enforcer]; a change that spreads edits across unrelated modules instead of
going through one seam [LAW:locality-or-seam]; a dependency that points upward or
closes a loop [LAW:one-way-deps]; a caller that must know a setup ritual
[LAW:composability]; effects mixed into decisions [LAW:effects-at-boundaries]; module
state shared across callers [LAW:no-shared-mutable-globals].

### Law sweep

For each decision in the plan, run every law's diagnostic against it. A diagnostic
with no clean answer is a candidate; name the law. This angle carries the laws with
no angle of their own: [LAW:decomposition], [LAW:types-are-the-program],
[LAW:parse-dont-validate], [LAW:domain-language], [LAW:comments-carry-meaning],
[LAW:nothing-unseen]. A plan whose new work emits no event is unfinished.

### Special cases (no cap)

Every special case the plan designs in is a finding until it is shown to be the
domain's own:

- a branch on a literal, a name, the caller, or the environment
  [LAW:dataflow-not-control-flow];
- a guard, an early return, a default, or a catch [LAW:no-defensive-null-guards]
  [LAW:no-silent-failure];
- a flag, a mode, or an option only one caller will pass [LAW:no-mode-explosion];
- two types or paths that differ only in configuration [LAW:one-type-per-behavior];
- a step described as `for now`, `temporary`, `a first pass`, or `cleaned up later`
  [LAW:escape-local-minima].

For each, name the constraint the design is missing that would make the case
disappear. A tidier special case is not a fix.

### Edge cases (no cap)

For every edge the plan handles - empty, missing, None, duplicate, out of order,
retried - find what makes that state reachable: a step of the plan, or existing code.
If that cause breaks a law, IT is the finding: a function that returns None where it
should fail [LAW:no-silent-failure], a type that admits the illegal state
[LAW:types-are-the-program], a second copy that can disagree
[LAW:one-source-of-truth]. Existing code the plan routes around is a finding at its
own file. An edge the domain itself has is not a finding.

### Second mechanism

Flag a plan that builds beside what exists instead of through it: a second registry,
reader, cache, retry path, or format; a new helper the codebase already has (name the
existing one); a recovery after an action where the action itself should change. Two
mechanisms for one job drift apart [LAW:one-source-of-truth].

### Total complexity

Judge the plan by the complexity it leaves for every later change, not by how small
it is today [LAW:carrying-cost]. Candidates: steps that exist only to support other
steps of the same plan; derivable state stored; a design that is cheap now and forces
a workaround at each later step; a decision that will be hard to reverse where an
equally sound one stays cheap to change; a strategy that cannot be stated in one
sentence. Name the simpler design's shape, not its steps
[LAW:polishing-by-subtraction].

### Conventions (CLAUDE.md)

Find the CLAUDE.md files that govern the code the plan changes: the user-level
~/.claude/CLAUDE.md, the repo-root CLAUDE.md, and any CLAUDE.md or CLAUDE.local.md in
an ancestor directory of a file the plan changes. Read each one that exists, then
check the plan for clear violations of the rules they state. Flag one only when you
can quote the exact rule and the exact plan text that breaks it, and name the
CLAUDE.md path in the finding.

In `failure_scenario`, state the concrete cost: what the built code will do wrong,
the illegal state the design makes representable, what is duplicated and will drift,
what later changes must work around, or which rule is broken.

Pass every candidate with a nameable failure scenario through - finders that silently
drop half-believed candidates are the dominant cause of misses.

## Phase 2 - Dedup only (no verify)

Pool all candidates. Dedup near-duplicates only (same defect, same step, same reason
-> keep one). Do NOT run verifiers; do NOT re-judge. A candidate is not dropped
because the plan would work, because the law-breaking code it builds on predates it,
or because the fix is large. Sort by severity.

## Phase 3 - Root decision

Read the pooled findings as a set. When several trace back to one decision in the
plan, that decision is a finding of its own and goes first, so the planner replaces
the cause, not each symptom. Its signs: a second mechanism beside the first; recovery
after an action instead of a change to the action; guards or flags for state the same
plan creates; a false premise several steps are built on; a strategy that cannot be
stated in one sentence. Some work is just complex: complexity any correct design would
need is not a finding.

The planner sees your report and never this page, so what the planner must do next
goes in the finding's `summary`:

- **A wrong decision inside this plan**: begin `Accidental complexity:` and name the
  decision and what it forces. This asks for that decision to change, not for a new
  plan.
- **A restart** is rare, and one review cannot call it - only the planner knows how
  many reviews came before. Only when this review alone returned many major findings,
  end the same summary with the planner's condition: `If earlier reviews of this plan
  also returned many major findings, run /skillz:lets-take-a-step-back before fixing
  any. Otherwise fix it here.`
- **A cause outside this ticket** - the plan routes around code the Edge cases angle
  traced, or widens a rule or fallback until a contradiction stops showing: end `Run
  /skillz:something-just-came-up: the real fix does not fit this ticket.`

## Output

Target **at least 5 findings**. If fewer genuine findings exist, emit what you have -
do not invent to hit the floor.

Return findings as a JSON array with one object for every finding that survives, no
maximum:

```json
[
  {
    "step": "short quote of the plan text the finding concerns",
    "evidence": "path/to/file.ext, a command and its output, or the ticket text",
    "summary": "[LAW:<token>] one-sentence statement of the violation, false premise, or gap",
    "failure_scenario": "what the code built from this plan will do wrong, or the concrete cost"
  }
]
```

Every finding that rests on a law opens its `summary` with that law's token. Where a
finding names a fix, it names what the laws require of the design - never a guard, a
fallback, a flag, or a special case, and never a rewritten plan.

Ranked most-severe first: the root decision, then false premises, then delivery gaps,
then the rest. Keep every finding that survives. There is no maximum. If nothing
survives, return `[]`. Do not call the ReportFindings tool even if it is available -
this review's output contract is the JSON block above.
