# laws:code initial rung table - PROPOSED, not applied

Status: proposed to the owner. `plugins/laws/source/code/profiles/default.toml` still sets
every law to L, so the shipped SKILL.md is unchanged. Applying a row is a one-line edit to
that file, then `generate.py` and `count.py`.

Counted 2026-10-03 with count_tokens on claude-opus-5-5. The all-L document is 28,009
tokens, which is the default profile's budget. This table, applied whole, is 19,487 tokens.

"Saves" is the all-L count minus the count with that one law moved to that rung. Each row
is measured alone, so the savings of several rows add up only approximately.

| law | proposed | saves at M | saves at S | why |
|---|:---:|---:|---:|---|
| `decomposition` | L | 204 | 332 | a primary law |
| `types-are-the-program` | L | 896 | 1180 | a primary law |
| `composability` | M | 627 | 903 | |
| `carrying-cost` | M | 974 | 1058 | |
| `polishing-by-subtraction` | M | 593 | 780 | |
| `no-ambient-temporal-coupling` | S | 193 | 313 | default practice already |
| `effects-at-boundaries` | S | 140 | 261 | default practice already |
| `one-source-of-truth` | M | 440 | 535 | |
| `domain-language` | M | 799 | 1016 | |
| `single-enforcer` | S | 120 | 279 | default practice already |
| `comments-carry-meaning` | M | 632 | 993 | |
| `dataflow-not-control-flow` | L | 971 | 1065 | the document calls it the most commonly violated law |
| `one-type-per-behavior` | S | 0 | 190 | default practice already; it has no L-only text |
| `no-mode-explosion` | M | 115 | 251 | |
| `parse-dont-validate` | M | 1732 | 1914 | |
| `no-defensive-null-guards` | L | 661 | 818 | the ticket names it among the most violated |
| `locality-or-seam` | S | 106 | 236 | default practice already |
| `one-way-deps` | S | 105 | 210 | default practice already |
| `no-shared-mutable-globals` | S | 122 | 218 | default practice already |
| `verifiable-goals` | M | 404 | 503 | |
| `behavior-not-structure` | M | 126 | 273 | |
| `no-silent-failure` | L | 614 | 733 | the ticket names it among the most violated |
| `nothing-unseen` | L | 2661 | 3130 | judgment: instrumentation is skipped unless pushed |
| `escape-local-minima` | M | 373 | 968 | M carries the pause/plan/hand-off procedure and its labeling rule |

M is the default for a law with a temptation the model meets often: the temptation script
and its redirect are what M adds. L is kept for the two primary laws and for the laws the
document and the ticket name as most violated. S is for laws whose violation is rare in
generated code without the long text. None of these placements is measured.
