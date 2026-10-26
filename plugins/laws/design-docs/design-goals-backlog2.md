# Design goals: the backlog2 skill

backlog2 is for building and maintaining an engineering backlog to the standard of a top-tier engineering organization: what a well-formed item contains, how the list is ordered, how the top of it is made ready, and how its health is kept.

It is a standalone skill. Its content comes from established engineering practice (Definition of Ready, triage, refinement, vertical slicing, severity versus priority), not from any other skill in this repo, and it carries no rule that depends on another skill being loaded.

## What it serves

An engineer or agent filing, editing, ordering, or auditing items in any tracker, for any team. The skill is tracker-agnostic and cadence-agnostic: it names no tracker, and a team without iterations still applies every rule.

## Qualities it holds

- **Professional and factual.** Plain technical language, specific nouns, numbers in place of adjectives. No persuasion, no ceremony.
- **Each procedure stated once**, in the section that owns it: item anatomy, Definition of Ready, ordering, splitting, triage, refinement, aging, audit.
- **Closed vocabularies.** Item types and resolutions are fixed sets, so a status or report counts something definite.
- **Internally consistent.** A property, a template, and an audit metric that cover the same ground say the same thing; following the templates produces items that pass the audit.
- **Easy to do right.** One template per item type, so a well-formed item is less work than a malformed one.

## Boundaries

The skill governs the backlog and the items in it. It does not govern code, specs, or design documents; items link to those.
