## [LAW:no-silent-failure] - never remove the battery from the smoke alarm

<!-- rung: S -->
**Errors surface loudly. Suppressing them, defaulting past them, or silently falling
back to a different data source is forbidden. If the primary path fails: stop and
report. Don't improvise.**

Silencing an error is removing the battery from the smoke alarm because the beeping
is annoying: silence today, and the fire - whenever it comes - burns undetected. A
swallowed failure doesn't disappear; it travels downstream as wrongness without a
source, and it sends an agent or a human confidently down the wrong path for hours.
Every silent failure is a lie told by the code to its operators.

FORBIDDEN patterns - on sight, these are bugs:
- `2>/dev/null` - "the errors are just noise." They are the signal.
- `|| true` - "keep going no matter what." No matter what is exactly the problem.
  The *only* acceptable use is when the failure is genuinely irrelevant to every
  downstream consumer - and if you're unsure, it's not irrelevant.
- `|| echo "default"` / silent fallback values - an answer-shaped void
  (`[LAW:parse-dont-validate]`).
- **Silent fallback data sources** - the worst of the family. Two queries that look
  similar but differ in filtering, ordering, or semantics (say, "ready work
  respecting dependencies" vs. "all open items") are NOT interchangeable; a fallback
  that changes the *meaning* of the data is a bug that only triggers when things are
  already broken - guaranteeing maximum confusion at the worst moment.

WRONG:
```bash
count=$(query_ready_items 2>/dev/null || query_all_items)
# Primary broke. The script now processes the WRONG LIST, confidently, and every
# downstream step compounds the error. Nobody learns the primary broke.
```
RIGHT:
```bash
count=$(query_ready_items) || { echo "ERROR: ready-items query failed" >&2; exit 1; }
# The failure is loud, located, and stops the line before wrongness propagates.
```

<!-- rung: M -->
The temptation arrives as: *"this error is just noise - silence it and move on."*
Refuse it. If a command can fail, that failure is meaningful. Let it fail, let it be
loud, fix the cause. The redirect: validate after every external call - exit code
zero? output non-empty? parses as expected? values sane? - and abort with a clear
message on any miss.

<!-- rung: S -->
Diagnostic: *if this fails at 3 a.m., does anyone find out - and does the message
say where to look?*

<!-- rung: S -->
Instance of `[FRAMING:representation]` (an error is the truth; suppressing it is
falsifying the map) and sibling of `[LAW:verifiable-goals]`: loud failure is what makes
verification mean anything.
