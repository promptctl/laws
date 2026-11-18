---
name: law-review
description: Review the current diff, or a PR number/branch/path target, against the laws of code (laws:code). Reports every correctness bug and every law violation, with no maximum - law citations the code does not live up to, decisions missing their citation, special cases, and the code outside the diff that forces an edge case. Strict by design - working code that breaks a law is a finding.
argument-hint: "[<pr#>|<branch>|<path>]"
context: fork
---

`law review -> load the laws -> 11 inline angles -> dedup (no verify) -> root decision -> all findings`

Review target (empty means the current diff): `$ARGUMENTS`

## Before anything - load the laws

Run `/laws:code` (the Skill tool, skill `laws:code`) and read all of it. Every angle
below assumes you hold the laws, their diagnostics, and their token index. If it
will not load, stop and report that - there is no review without the laws
[LAW:no-silent-failure].

You are reviewing for **recall** against the laws: catch every real bug and every
violation a careful reviewer would catch in one sitting. Code that works and
breaks a law is a finding. "Good enough for now" does not pass
[LAW:escape-local-minima]. Err on the side of surfacing. Do not praise or soften:
state what is wrong and what the law requires instead.

## Phase 0 - Gather the diff

Run `git diff @{upstream}...HEAD` (or `git diff main...HEAD` / `git diff HEAD~1`
if there's no upstream) to get the unified diff under review. If there are
uncommitted changes, or the range diff is empty, also run `git diff HEAD` and
include the working-tree changes in scope - the review often runs before the
commit. If a PR number, branch name, or file path was passed as an argument,
review that target instead. Read the range's commit messages too, and the
change's ticket where there is one (`lit show <id>`) for the problem it solves.

The diff is where the review starts, not where it ends. The author answers for
all the code in the repo, not only the lines this PR changed: a violation in
anything the diff touches, calls, or works around is a finding at its own file
and line [LAW:carrying-cost].

## Phase 1 - Find candidates (3 correctness angles + 5 law angles + 2 cleanup angles + 1 conventions angle)

Run **11 independent finder angles** in sequence yourself, in THIS context - do NOT
spawn subagents for them. Each surfaces candidate findings with `file`, `line`, a
one-line `summary`, and a concrete `failure_scenario`. The four angles marked
**no cap** report every instance they find; the rest surface **up to 6** each.

### Angle A - line-by-line diff scan

Read every hunk in the diff, line by line. Then Read the enclosing function for
each hunk - bugs in unchanged lines of a touched function are in scope (the PR
re-exposes or fails to fix them). For every line ask: what input, state, timing,
or platform makes this line wrong? Look for inverted/wrong conditions,
off-by-one, null/undefined deref, missing `await`, falsy-zero checks,
wrong-variable copy-paste, unescaped regex metachars, an error swallowed or
defaulted past [LAW:no-silent-failure], correctness that depends on which call
runs first [LAW:no-ambient-temporal-coupling].

### Angle B - removed-behavior auditor

For every line the diff DELETES or replaces, name the invariant or behavior it
enforced, then search the new code for where that invariant is re-established.
If you can't find it, that's a candidate: a removed guard, a dropped error
path, a narrowed validation, a deleted test that was covering a real case. The
invariant comes back in exactly one place [LAW:single-enforcer]. Deleting a test
is right only when it asserted structure [LAW:behavior-not-structure].

### Angle C - cross-file tracer

For each function the diff changes, find its callers (Grep for the symbol) and
check whether the change breaks any call site: a new precondition, a changed
return shape, a new exception, a timing/ordering dependency. Also check callees:
does a parallel change in the same PR make a call unsafe? A change that forced
edits in unrelated files is a missing seam [LAW:locality-or-seam]; an import
that points upward or closes a loop is [LAW:one-way-deps]; a caller that must
know the callee's setup ritual is [LAW:composability].

### Law sweep

For each unit the diff adds or changes, run every law's diagnostic against it. A
diagnostic with no clean answer is a candidate; name the law. This angle carries
the laws with no angle of their own: [LAW:decomposition],
[LAW:effects-at-boundaries], [LAW:no-shared-mutable-globals],
[LAW:domain-language], [LAW:comments-carry-meaning], [LAW:verifiable-goals],
[LAW:nothing-unseen]. A change with no test of its behavior, or whose work emits
no event, is unfinished.

### Cited but false (no cap)

Grep the diff and every file it touches for `[LAW:`. For each citation, run that
law's diagnostic against the code under it, not against the comment - the
comment reads the same whether the code obeys the law or breaks it. Candidates:
code that does not do what the cited law requires (a `[LAW:one-source-of-truth]`
over a second copy); a token that is not in the index; an `exception:` whose
reason is convenience or "for now"; a citation used as a license, arguing in
prose that a guard stands at a real boundary [LAW:no-defensive-null-guards] - a
real boundary shows in the code as a parsing unit and the type it returns.

### Citation missing (no cap)

The laws require a citation wherever a law shaped a decision. Walk the diff for
decisions that carry none: a new type or state; a check at a boundary; a null
check; a catch or a default; a flag or mode; a cache or copy; module-level state;
a dependency across modules. An uncited decision is a law applied in silence or
a law never consulted, and the second is usually a violation - run the
diagnostic and report which. A violation with no `exception:` marker is reported
as the violation, and says the marker is missing.

### Special cases (no cap)

Check that each change fixes the root cause at the right depth rather than
patching a symptom with a fragile bandaid. Every special case is a finding until
it is shown to be the domain's own:

- a branch on a literal, a name, the caller, or the environment
  [LAW:dataflow-not-control-flow];
- an early return or a guard with no else [LAW:no-defensive-null-guards];
- a flag, a mode, or a parameter only one caller passes [LAW:no-mode-explosion];
- siblings that differ only in configuration [LAW:one-type-per-behavior];
- a check that hands back the type it was given [LAW:parse-dont-validate];
- `for now`, `temporary`, `workaround`, `TODO`, `until` - in code, comments, or
  commit messages [LAW:escape-local-minima].

For each, ask what discriminator or constraint the type is missing
[LAW:types-are-the-program], and name the more general change to the underlying
mechanism that makes the case disappear. A tidier special case is not a fix.

### Edge cases (no cap)

An edge case the code must handle is usually a state the design made possible.
For every edge the diff handles - empty, missing, None, duplicate, out of order,
retried - find the code that makes that state reachable, wherever it lives. If
that code breaks a law, IT is the finding, at its own file and line, even when -
especially when - the diff never touched it: a function that returns None where
it should fail [LAW:no-silent-failure], a type that admits the illegal state
[LAW:types-are-the-program], a second copy that can disagree
[LAW:one-source-of-truth]. The handling in the diff is only the symptom. An edge
the domain itself has is not a finding.

### Reuse

The angles above hunt for bugs and violations; this one and the next hunt for
cleanup in the changed code. Flag new code that re-implements something the
codebase already has - Grep shared/utility modules and files adjacent to the
change, and name the existing helper to call instead. A second implementation is
a second source of truth [LAW:one-source-of-truth].

### Simplification

Flag unnecessary complexity the diff adds: redundant or derivable state,
copy-paste with slight variation, deep nesting, dead code left behind, redundant
computation or repeated I/O. A pass that grew the code to solve a problem was a
patch [LAW:polishing-by-subtraction]. Name the simpler form that does the same
job.

### Conventions (CLAUDE.md)

Find the CLAUDE.md files that govern the changed code: the user-level
~/.claude/CLAUDE.md, the repo-root CLAUDE.md, plus any CLAUDE.md or
CLAUDE.local.md in a directory that is an ancestor of a changed file. Read each
one that exists, then check the diff for clear violations of the rules they
state. Only flag a violation when you can quote the exact rule and the exact
line that breaks it, and name the CLAUDE.md path in the finding.

Law, cleanup, and conventions candidates use the same `file`/`line`/`summary`
shape; in `failure_scenario`, state the concrete cost instead of a crash: the
illegal state now representable, what is duplicated and will drift, what later
changes must work around, or which CLAUDE.md rule is broken.

Pass every candidate with a nameable failure scenario through - finders that
silently drop half-believed candidates are the dominant cause of misses.

## Phase 2 - Dedup only (no verify)

Pool all candidates. Dedup near-duplicates only (same defect, same location, same
reason -> keep one). Do NOT run verifiers; do NOT re-judge. A candidate is not
dropped because the code works, because the violation predates this PR, or
because the fix is large. Sort by severity.

## Phase 3 - Root decision

Read the pooled findings as a set. When several trace back to one decision made
in this work, that decision is a finding of its own and goes first, so the caller
fixes the cause, not each symptom. Its signs: a second mechanism beside the first
(a second registry, reader, cache or retry path); code that recovers after an
action instead of changing the action; guards or flags for code the same change
added; commits in the range that fix earlier commits in the range; a strategy
that cannot be stated in one sentence. Some work is just complex: complexity any
correct solution would need is not a finding.

The caller sees your report and never this page, so what the caller must do next
goes in the finding's `summary`:

- **A wrong decision inside this work**: begin `Accidental complexity:` and name
  the decision and what it forces. This asks for a fix here, not a restart.
- **A restart** is rare, and one review cannot call it - only the caller knows
  how many reviews came before. Only when this review alone returned many major
  findings, end the same summary with the caller's condition: `If earlier reviews of
  this work also returned many major findings, run /skillz:lets-take-a-step-back
  before fixing any. Otherwise fix it here.`
- **A workaround for a cause outside this work** - the change routes around the
  code the Edge cases angle traced, or widens a rule or fallback until a
  contradiction stops showing: end `Run /skillz:something-just-came-up: the real
  fix does not fit this ticket.`

## Output

Target **at least 5 findings**. If fewer genuine findings exist, emit what you have - do not invent to hit the floor.

Return findings as a JSON array with one object for every finding that survives, no maximum:

```json
[
  {
    "file": "path/to/file.ext",
    "line": 123,
    "summary": "[LAW:<token>] one-sentence statement of the violation or bug",
    "failure_scenario": "concrete inputs/state -> wrong output/crash, or the concrete cost"
  }
]
```

Every finding that rests on a law opens its `summary` with that law's token.
Where a finding names a fix, it names the one the laws ask for - never a guard, a
fallback, a flag, or a special case.

Ranked most-severe first: the root decision, then correctness bugs, then the
rest. Keep every finding that survives. There is no maximum. If nothing survives,
return `[]`. Do not call the ReportFindings tool even if it is available - this
review's output contract is the JSON block above.
