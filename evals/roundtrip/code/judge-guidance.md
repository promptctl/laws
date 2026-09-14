# Judge verdict

Test runs (`uv run --with pytest pytest -q <letter>.py`): A 30 passed, B 32 passed, C 40 passed.

## Fidelity (scored)

All three implement every given fact: the `parse_duration(text: str) -> datetime.timedelta` signature; parts as unsigned integer plus unit with no spaces (`90s`, `1h30m`, `2d4h`); units `d`/`h`/`m`/`s`; order d, h, m, s with each unit at most once (`30m1h` and `1h1h` rejected); no signs; the empty string and all other input rejected; pytest tests in the same file. None misstates any of these. Rejecting out-of-range values (overflow) follows from the given facts, since `timedelta` cannot hold them, so it is not counted as an addition. Rejecting non-`str` values falls under "any other input is invalid" and is not counted either.

**Response A**
- Missing: none.
- Misstated: none.
- Added: `# An empty YAML value loads as None; it must fail loudly, not parse as zero.` The task says only that "a key can be present with an empty value". It does not say what a YAML loader turns that into.

missing: 0, misstated: 0, added: 1

**Response B**
- Missing: none.
- Misstated: none.
- Added: `A YAML key present with an empty value reaches here as "" or None`. The task does not say what value the loader produces.

missing: 0, misstated: 0, added: 1

**Response C**
- Missing: none.
- Misstated: none.
- Added: `non-str values such as the None a YAML loader produces for an empty key`. The task does not say what the loader produces.

missing: 0, misstated: 0, added: 1

## Rubric

Rules the standard asks of a finished response:

1. Cite each law that shapes a decision at the point of use, as `[LAW:<token>] reason`, using canonical tokens.
2. decomposition: each unit has one describable purpose.
3. types-are-the-program: constraints carry the rules, so the body does not branch or guard on things the type or grammar could carry.
4. composability: units have no hidden dependence on a caller and need no setup ritual.
5. polishing-by-subtraction: no extra material such as added guards, cases or helpers that the constraints could absorb.
6. no-ambient-temporal-coupling: no ordering or lifecycle invariants hidden in execution order.
7. effects-at-boundaries: the core is pure, and effects stay at the edges.
8. one-source-of-truth: each fact has one authoritative representation.
9. single-enforcer: each invariant is enforced at exactly one place.
10. comments-carry-meaning: comments give intent or reasons, never a same-altitude echo of the code.
11. dataflow-not-control-flow: the same operations run on every input, and variability lives in values.
12. one-type-per-behavior: things with identical behavior are one type.
13. no-mode-explosion: no flags or modes without a cap and an exit plan.
14. parse-dont-validate: a dedicated unit returns a proving type, with a loud or typed failure arm.
15. no-defensive-null-guards: no inland null guards.
16. locality-or-seam: changes do not ripple into unrelated code.
17. one-way-deps: no dependency cycles or upward calls.
18. no-shared-mutable-globals: shared mutable state has an owner and an API.
19. verifiable-goals: machine-checkable success criteria exist and pass.
20. behavior-not-structure: tests assert the contract, not the implementation.
21. no-silent-failure: errors surface loudly, with no success-shaped defaults.

| # | A | B | C |
|---|---|---|---|
| 1 | met | met | not met |
| 2 | met | met | met |
| 3 | met | met | not met |
| 4 | met | met | met |
| 5 | met | met | not met |
| 6 | n/a | n/a | n/a |
| 7 | met | met | met |
| 8 | met | met | met |
| 9 | met | met | met |
| 10 | met | met | met |
| 11 | met | met | not met |
| 12 | n/a | n/a | n/a |
| 13 | n/a | n/a | n/a |
| 14 | met | met | met |
| 15 | met | met | met |
| 16 | n/a | n/a | n/a |
| 17 | n/a | n/a | n/a |
| 18 | n/a | n/a | n/a |
| 19 | met | met | met |
| 20 | met | met | met |
| 21 | met | met | met |

Counts:
- A: met 15, not met 0, n/a 6
- B: met 15, not met 0, n/a 6
- C: met 11, not met 4, n/a 6

Failures:
- C, rule 1: the file has no `[LAW:...]` citation anywhere, even though its decisions follow the laws. For example, `# re.fullmatch rather than "$": "$" would accept a trailing newline.` explains a parsing choice without citing a law.
- C, rule 3: `if match is None or not any(match.groupdict().values()):` checks for the empty string in the body. The grammar could carry that rule, as A and B do with a lookahead, and C's own comment admits it: `# The empty string fullmatches with every group absent; reject it here.`
- C, rule 5: `if not isinstance(text, str): raise DurationError(f"duration must be a string, got {type(text).__name__}: {text!r}")` is an added runtime guard that repeats the `text: str` annotation. It brings its own error message and its own test (`test_non_string_rejected`).
- C, rule 11: `parts = {unit: int(value) for unit, value in match.groupdict().items() if value}` skips absent units with a condition, where A and B pass them through as the value 0.

## Ranking

1. **B**: its grammar is derived from a single unit table and it tests the widest set of rejections (`1s1d`, `1h,30m`, `1_0s`). Its docstring also tells the three service developers what to do about an empty YAML value: "resolve optionality in the caller before calling".
2. **A**: it is as correct and as law-compliant as B, with a very small body. It ranks just below B because it offers callers less guidance, and it pins the raw `TypeError` that `re` raises for `None` as a tested contract, beside a separate `DurationError` for everything else.
3. **C**: it is correct and has the most tests, but it cites no laws, guards and branches in the body where the grammar could carry the rules, and it skips absent units with a condition.

## Totals

- A: missing 0, misstated 0, added 1; rubric met 15, not met 0, n/a 6
- B: missing 0, misstated 0, added 1; rubric met 15, not met 0, n/a 6
- C: missing 0, misstated 0, added 1; rubric met 11, not met 4, n/a 6
