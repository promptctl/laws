---
name: backlog2
description: Build and maintain an engineering backlog. Covers writing well-formed items (bugs, features, tasks, tech debt, spikes, epics), triaging intake, ordering, refining the top of the backlog to a Definition of Ready, splitting oversized work, retiring stale items, and auditing backlog health. Use when filing or editing tickets, grooming or prioritizing a backlog, or assessing whether a backlog is in good condition. Tracker-agnostic.
---

# Backlog

## Purpose

A backlog is a team's ordered record of the work it has agreed is worth considering. It exists so that the next most valuable piece of work is always identifiable, described well enough that any engineer on the team can start it, and justified in terms of the problem it solves. Everything in this skill serves those three properties: **ordered**, **ready at the top**, **justified**.

A backlog is not a wish list, an archive of every idea anyone has raised, or a substitute for a design document. Work that will not be done does not belong in it.

This skill is tracker-agnostic. "Tracker" means whatever system holds the items; "item" means a ticket, issue, or card.

## Properties of a healthy backlog

1. **One list, one order.** A team has one backlog, and position in it is the priority. Labels, columns, and priority fields describe items; they do not order them. When a label disagrees with the order, the order is authoritative and the label is corrected.
2. **One accountable owner.** Anyone may propose items and argue for their placement. One named person decides the order and is accountable for it. The decision is recorded by position, not by discussion.
3. **Ready at the top.** The *ready zone* — enough items to cover the team's next two planning intervals (a planning interval is a sprint, or two weeks for teams without sprints) — meets the Definition of Ready (below). Items lower down may be coarse; precision there is wasted because it will be redone.
4. **Every item is justified.** Each item states why it exists — the problem it addresses and who is affected, under the heading its type uses (Problem, Reason, Question, Goal, or Current cost). An item whose justification cannot be written is closed.
5. **Bounded.** The backlog holds roughly what the team could complete in two quarters. Items beyond that horizon lower the signal of everything else and are closed, not kept.
6. **Current.** An item's description reflects the present understanding of the work. When understanding changes, the description is edited. Comments record how the understanding developed; they do not replace it.
7. **Every item resolves.** An item ends in exactly one of: **Done**, **Won't Do** (with a one-sentence reason), or **Superseded** (linking what replaces it — the surviving duplicate, or the items it was split into). Nothing stays open indefinitely.
8. **Not a commitment.** The backlog is the pool that planning draws from, in order. Placing an item in it commits the team to considering the item, not to delivering it.

## Anatomy of an item

Every item carries these fields. An epic carries Title, Type, Goal, Done when, and Links; Size does not apply to it.

| Field | Content |
|---|---|
| **Title** | The observable change, in 70 characters or fewer. Specific enough that a reader can decide whether to open the item. |
| **Type** | Bug, Feature, Task, Tech Debt, Spike, or Epic. |
| **Problem** (Task: Reason. Spike: Question. Epic: Goal. Tech Debt: Current cost.) | What is wrong or missing, who is affected, and how that is known. One to four sentences. Written before any solution. |
| **Acceptance criteria** (Spike: Deliverable. Epic: Done when.) | Observable conditions that, when all true, mean the item is done. Each is checkable with a yes/no answer by someone other than the author. |
| **Size** | A relative estimate on the team's scale. Required in the ready zone; optional below it. |
| **Links** | Parent epic, dependencies, related items, and the source (incident, support case, design document, user research). |

Optional fields, used when they prevent wasted work:

- **Proposed approach** — a candidate solution, labeled as a suggestion. It never substitutes for the problem statement.
- **Boundaries** — what the item deliberately does not cover, stated only where the ambiguity would otherwise send someone the wrong way.
- **Verification** — how the change will be confirmed in production: a metric, a dashboard, a log line, a manual check.

### Titles

A title names the outcome, not the activity.

| Specific | Vague |
|---|---|
| Checkout returns 500 when the cart contains a discontinued SKU | Fix checkout |
| Retry payment-webhook delivery with exponential backoff | Webhook improvements |
| Bring `api` package CI wall time under 8 minutes | CI is slow |

### Problem statements

State the problem before any solution. Include the evidence: error rate, incident ID, number of reports, measured latency. Where a number exists, use it in place of an adjective — "p95 latency is 2.4 s against an 800 ms target," not "the endpoint is slow."

### Acceptance criteria

Each criterion describes observable behavior and can be checked independently.

| Checkable | Not checkable |
|---|---|
| Submitting an order containing a discontinued SKU returns 422 with error code `SKU_DISCONTINUED`, and the cart is unchanged. | Checkout handles discontinued SKUs correctly. |
| A regression test covers the discontinued-SKU path and fails against the current build. | Tests are added. |

Include non-functional criteria when they are the point of the item: latency targets, error budgets, accessibility conformance, data-retention limits. Acceptance criteria are the item's definition of done. The team's standing definition of done — review, tests, documentation, deployment — applies in addition and is not restated on each item.

## Item types

Each type has requirements beyond the common fields. An item missing them is not ready.

**Bug.** Steps to reproduce, or the conditions under which it occurs if intermittent. Expected behavior. Actual behavior. Environment: version, platform, region, feature flags. Frequency and impact: how many users or requests, and how badly. Severity and priority are distinct — severity is the damage when the bug occurs; priority is where the item sits in the order. A severe bug on a rare path used by one internal user may sit below a mild bug that affects every customer on every request.

**Feature.** The user or system the change serves, the outcome they receive, and acceptance criteria. Any format is acceptable if all three are present; a user-story template is one way to ensure they are.

**Task.** Work with a known solution and no user-visible behavior change: a configuration change, a migration, a dependency upgrade. Requires what will be done and how its completion will be confirmed.

**Tech Debt.** The cost being paid now — incidents, build time, onboarding time, blocked features — with evidence. The proposed remedy. The expected reduction in cost and how it will be measured. Tech debt whose current cost cannot be named cannot be ordered against other work, and is not filed until it can.

**Spike.** A timeboxed investigation. The question to be answered, the timebox, and the deliverable: a decision record, a document, a prototype, or follow-up items. A spike's deliverable is never production code.

**Epic.** A goal spanning multiple items. The goal in one sentence, the condition under which the epic is done, and its child items. Epics are containers for progress; they are not themselves worked. An epic has no position of its own: its children are ordered, and the epic is excluded from the Definition of Ready, the size ceiling, and the open-item counts. Keep the hierarchy to two levels — epic and item. A third level indicates the epic should be split.

## Definition of Ready

An item is ready when all of the following hold:

1. The problem statement is written, and someone other than the author has read it and confirmed it is understandable.
2. Acceptance criteria are written and each is checkable.
3. Size is estimated and is within the team's ceiling for a single item — typically a few working days of work. Larger items are split.
4. Dependencies are identified, and each is either done or placed ahead of this item in the order.
5. No open question blocks starting. Questions that can be resolved during the work are noted in the item; they do not block.

The ready zone is ready. When it is not, refinement takes precedence over starting new work.

## Ordering

Order is a decision, recorded by position. The inputs:

- **Impact** — users, revenue, or risk affected; alignment with current goals.
- **Urgency** — deadlines, cost that grows with delay, value that decays.
- **Risk reduction** — items that resolve uncertainty or unblock others move earlier.
- **Cost** — size. Of two items with equal impact, the smaller goes first.
- **Dependencies** — a dependency is always placed before its dependents.

Scoring methods such as WSJF, RICE, or cost of delay make these inputs explicit. Any method is acceptable if it is applied consistently and produces a single order. When two items resist ordering, ask: "If the team could complete only one of these next, which?" Answer it. Ties are not permitted.

If the tracker uses priority labels, each label has a written definition with a response expectation — for example: P0, all other work stops; P1, next planning interval; P2, this quarter; P3, no commitment. An item that meets the top label's definition is an interrupt, not a candidate for comparison: it takes the first position among non-P0 items when filed, "all other work stops" means all non-P0 work, and several P0s are ordered among themselves by the rules above. Items are reclassified when they do not meet their label's definition. A label most of whose items violate its definition has stopped carrying information.

## Splitting

Split an item when it exceeds the size ceiling, when it has more than one independent outcome, or when its acceptance criteria could be delivered and verified separately.

Prefer vertical slices — each piece delivers an observable, testable change end to end — over horizontal layers such as "schema," then "API," then "UI." A horizontal layer cannot be demonstrated or verified as value on its own.

Splitting lines, in order of preference:

1. **Workflow step** — enter, validate, submit.
2. **User or input variation** — one payment method first, then the others.
3. **Happy path, then each error condition.**
4. **Operational variation** — one region, behind a feature flag, read-only first.
5. **Acceptance criterion** — one criterion per item, when nothing above applies.

Each resulting item satisfies the Anatomy section on its own. A piece that cannot be described as valuable by itself is a step inside another item, not a separate item. Link the pieces to each other, then close the original as Superseded, linking the pieces. If the pieces share a goal worth tracking, file a new epic for them; the original is never converted.

## Intake and triage

Every new item is triaged within an agreed interval; two business days is a common target. Triage is not refinement — it does not write full acceptance criteria or size the item. It decides whether the item belongs and roughly where.

For each untriaged item, in arrival order:

1. **Duplicate check.** Search by symptom, component, and error text. If a match exists, close the new item as Superseded, link it to the survivor, and move any new information into the survivor's description.
2. **Classify.** Set type, component or area, and any labels the team uses.
3. **Decide.** One of:
   - **Accept** — the item enters the backlog.
   - **Needs Information** — return it to the reporter with the specific questions. The item stays in triage, not in the backlog, and is tracked in the audit. If unanswered after an agreed interval (14 days is common), close it as Won't Do with the reason "no response to questions of <date>"; a reply reopens it.
   - **Won't Do** — close with a one-sentence reason that would let someone reopen it with new evidence.
4. **Place.** Set a rough position in the order. Precise placement happens in refinement.

Record the decision on the item.

## Refinement

A recurring session — weekly, or once per planning interval — that walks the backlog from the top.

1. **Ready zone.** For each item, confirm it meets the Definition of Ready. Fix what does not.
2. **Next zone.** For the items that will enter the ready zone before the next session, bring them to ready: clarify the problem, write acceptance criteria, estimate, split.
3. **Reorder.** Apply anything learned since the last session — incidents, customer feedback, completed dependencies, changed goals.
4. **Aging review.** Handle items past the aging threshold (next section).

Decisions reached in refinement are written into the item's description, not left in a meeting note or a comment thread.

## Aging and retirement

An item whose description has not been edited, and which has not been reviewed at refinement, within an agreed interval — 90 days is common — is reviewed. Label, link, and position changes do not count as review. A *review* means a named person has read the item against current understanding at the next refinement. For each such item, one of two outcomes:

- **Still relevant and would be done given capacity** — edit the description to current understanding, or record a dated review naming the reviewer, and place it deliberately in the order. That resets its age.
- **Not going to be done within the planning horizon** — close as Won't Do, with the reason.

Closing an item is a statement about the team's horizon, not about the reporter or the idea. Closed items remain searchable, and reopening one with new evidence costs nothing.

## Keeping items current

- When understanding of the problem changes, edit the description. The description is the item's present truth; the comment thread is its history.
- When scope is cut from an item, record what was cut. If the cut work still matters, file it as its own item and link it.
- When an item is blocked, link the blocker and state it in the description. A blocker inside the backlog is resolved by order: it is placed ahead of the blocked item. A blocker outside the team's control (a vendor, another team) marks the item blocked. A blocked item keeps the position its impact and urgency give it, does not count toward the ready zone, and is rechecked at every refinement.
- Status reflects reality. An item is in progress when someone is working on it today, not when it was assigned.

## Health audit

Run monthly, or whenever the backlog feels wrong. Measure and report:

| Metric | Healthy |
|---|---|
| Total open items (epics excluded) | At or below what the team completes in two quarters |
| Ready-zone items (blocked items excluded) meeting the Definition of Ready | 100% |
| Open items with no description edit or recorded review in 90+ days | Few, and all reviewed at the last refinement |
| Untriaged items older than the triage interval | 0 |
| Items awaiting information past the Needs Information interval | 0 |
| Inflow vs. outflow over the last quarter | Roughly equal, or converging |
| Items carrying the highest priority label | Few enough that every one is being handled per the label's definition |
| Items without a stated problem, reason, question, goal, or current cost | 0 |

Report findings as a list of specific items and the specific defect in each, not as a narrative. Fix in the session what can be fixed — close duplicates, add missing fields, reorder, retire. File the remainder as maintenance tasks with owners.

## Anti-patterns

- **Solution without problem.** "Migrate to library X." Who is hurt today, and how?
- **Compound item.** Two outcomes in one item. One ships; the item stays open for the other.
- **Priority inflation.** When most items are P1, P1 carries no information.
- **Specification by comment thread.** The description says one thing; the real requirements are in the fourteenth comment.
- **Horizontal slicing.** "Database layer for feature X" cannot be demonstrated or verified on its own.
- **Zombie items.** Open for a year, never touched, never closed.
- **Precision far down the list.** Detailed estimates and criteria on items that will not be worked for months are redone when the items reach the top.
- **Backlog as notebook.** Ideas, reminders, and half-formed thoughts belong elsewhere until they can be stated as a problem with evidence.
- **Ordering by label.** Priority fields drift; position is the decision.

## Templates

### Bug

```
Title: <component>: <observable failure> when <condition>

Problem
<What happens, to whom, how often. Evidence: error rate, incident ID, report count.>

Steps to reproduce
1.
2.

Expected:
Actual:
Environment: <version, platform, region, flags>
Frequency and impact: <how many users or requests, how badly>

Acceptance criteria
- [ ]
- [ ] A regression test covers <condition> and fails against the current build.

Size: <required before the item enters the ready zone>
Links: <incident, related items, parent epic>
```

### Feature

```
Title: <the outcome, as the user would observe it>

Problem
<The user or system served, what they need, and why. Evidence of the need.>

Acceptance criteria
- [ ]
- [ ]

Proposed approach (suggestion)
<Optional.>

Size: <required before the item enters the ready zone>
Links: <epic, design document, dependencies>
```

### Task

```
Title: <what will be done>

Reason
<Why this is needed now.>

Acceptance criteria
- [ ] <How completion is confirmed.>

Size: <required before the item enters the ready zone>
Links:
```

### Tech Debt

```
Title: <remedy>: <what it relieves>

Current cost
<What this costs today — incidents, time, blocked work — with numbers where available.>

Remedy
<What changes.>

Expected result
<How the cost falls, and how that will be measured.>

Acceptance criteria
- [ ]

Size: <required before the item enters the ready zone>
Links: <incidents, affected items>
```

### Spike

```
Title: Decide <question>

Question
<The decision this spike enables, and what is blocked on it.>

Timebox (serves as Size): <N days>

Deliverable
<Decision record, document, prototype, or follow-up items.>

Links: <items blocked on this decision>
```

### Epic

```
Title: <goal>

Goal
<One sentence: the state of the world when this is done.>

Done when
<Observable condition.>

Children
-
-

Links: <strategy document, stakeholders>
```

## Writing style

Write for an engineer who joins the team next quarter and has no context. Plain words, active voice, specific nouns. Numbers in place of adjectives wherever a number exists. One idea per sentence. Define abbreviations unless they are universal within the team. A reader should finish the item knowing what is wrong, what done looks like, and why it matters — without asking the author.
