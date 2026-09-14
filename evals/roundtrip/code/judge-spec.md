# Judge verdict

All three files pass their own tests: A 30 passed, B 32 passed, C 40 passed (`uv run --with pytest pytest -q <letter>.py`). Every implementation accepts exactly the given grammar. Each one rejects the empty string, out-of-order units, repeated units, signs, spaces and trailing text.

## Fidelity (scored)

Given facts: the signature `parse_duration(text: str) -> datetime.timedelta`; one or more parts, each a non-negative integer followed immediately by a unit, with no spaces; units d/h/m/s; units in that order, each at most once (`30m1h` and `1h1h` are invalid); integers have no sign; any other input is invalid, including the empty string. The task also says: "Do not accept any input the behavior does not list."

What is not counted: raising an exception is how "invalid" gets expressed, so defining a `ValueError` subclass is not counted for any response. Rejecting non-ASCII digits narrows what "integer" admits, which "do not accept any input the behavior does not list" allows, so it is not counted either. Examples that follow from the grammar (`007m`, `0s`, `90m`) are illustrations and are not counted.

### A
- Missing: none.
- Misstated: none.
- Added:
  1. A claim about what YAML produces: "including the empty string a YAML key with an empty value produces". The task says only that "a key can be present with an empty value". This also contradicts A's own test comment (item 4).
  2. A claim about how the services behave: "so a bad config value stops the service that reads it instead of turning into a zero-length wait".
  3. New behavior: a grammatical input that is too large for `timedelta` raises. `except OverflowError ... raise DurationError(text) from error`, tested by `parse_duration("9999999999d")`. The task lists every non-negative integer as valid.
  4. A claim and a behavior for `None`: "An empty YAML value loads as None; it must fail loudly, not parse as zero.", tested as `with pytest.raises(TypeError): parse_duration(None)`.

`missing: 0, misstated: 0, added: 4`

### B
- Missing: none.
- Misstated: none.
- Added:
  1. A claim about YAML plus a requirement on callers: "A YAML key present with an empty value reaches here as `""` or `None`; both are invalid, so resolve optionality in the caller before calling."
  2. New behavior on overflow: `raise DurationError(text) from exc` for "grammatical but beyond timedelta's range", tested with `"999999999999d"` in the invalid list.

`missing: 0, misstated: 0, added: 2`

### C
- Missing: none.
- Misstated: none.
- Added:
  1. New behavior for values that are not strings: "non-`str` values ... raises `DurationError`", implemented as `if not isinstance(text, str): raise DurationError(...)` and tested with `[None, 90, 1.5, b"90s"]`.
  2. A claim about YAML: "the `None` a YAML loader produces for an empty key".
  3. New behavior on overflow: "and for values too large for `timedelta`", implemented as `raise DurationError(f"duration {text!r} is too large")`.

`missing: 0, misstated: 0, added: 3`

## Rubric

| # | A | B | C |
|---|---|---|---|
| 1 | n/a | n/a | n/a |
| 2 | met | met | not met |
| 3 | met | met | n/a |
| 4 | n/a | n/a | n/a |
| 5 | met | met | met |
| 6 | met | met | met |
| 7 | n/a | n/a | n/a |
| 8 | met | met | met |
| 9 | met | met | not met |
| 10 | met | met | not met |
| 11 | met | met | met |
| 12 | n/a | n/a | n/a |
| 13 | n/a | n/a | n/a |
| 14 | n/a | n/a | n/a |
| 15 | n/a | n/a | n/a |
| 16 | n/a | n/a | n/a |
| 17 | n/a | n/a | n/a |
| 18 | n/a | n/a | n/a |
| 19 | n/a | n/a | n/a |
| 20 | n/a | n/a | n/a |
| 21 | n/a | n/a | n/a |
| 22 | n/a | n/a | n/a |
| 23 | met | met | met |
| 24 | met | met | met |
| 25 | met | met | met |
| 26 | n/a | n/a | n/a |
| 27 | met | met | met |
| 28 | met | met | met |
| 29 | n/a | n/a | n/a |
| 30 | met | met | met |
| 31 | met | met | not met |
| 32 | n/a | n/a | n/a |
| 33 | met | met | not met |
| 34 | met | met | met |
| 35 | met | met | met |
| 36 | met | met | met |
| 37 | met | met | met |
| 38 | met | met | met |
| 39 | met | met | met |
| 40 | met | met | not met |
| 41 | met | met | not met |
| 42 | n/a | n/a | n/a |
| 43 | n/a | n/a | n/a |
| 44 | met | met | met |
| 45 | met | met | met |
| 46 | n/a | n/a | n/a |
| 47 | n/a | n/a | n/a |
| 48 | not met | met | met |
| 49 | n/a | n/a | n/a |
| 50 | met | met | met |
| 51 | n/a | n/a | n/a |
| 52 | n/a | n/a | n/a |
| 53 | n/a | n/a | n/a |
| 54 | n/a | n/a | n/a |
| 55 | n/a | n/a | n/a |
| 56 | n/a | n/a | n/a |
| 57 | n/a | n/a | n/a |
| 58 | n/a | n/a | n/a |
| 59 | n/a | n/a | n/a |
| 60 | met | met | not met |

Counts:
- A: met 28, not met 1, n/a 31
- B: met 29, not met 0, n/a 31
- C: met 20, not met 8, n/a 32

Failures:
- A, #48: the test depends on the `re` module raising `TypeError` for `None`, which is an implementation detail and not a documented contract. The failing test is `def test_missing_yaml_value_is_not_a_duration(): ... with pytest.raises(TypeError): parse_duration(None)`.
- C, #2: C has no `[LAW:<token>]` comment anywhere. Its design comments have none, for example `# The empty string fullmatches with every group absent; reject it here.`
- C, #9: C handles the empty-string case in the function body, with a comment explaining the gap, instead of fixing it in the grammar: `# The empty string fullmatches with every group absent; reject it here.` / `if match is None or not any(match.groupdict().values()):`
- C, #10: the same logic stays in the body even though a lookahead in the pattern could carry it: `not any(match.groupdict().values())`.
- C, #31: whether a field is passed depends on the input, instead of absent units defaulting to 0: `parts = {unit: int(value) for unit, value in match.groupdict().items() if value}`.
- C, #33: the same `if value` filter skips the operation where a default value would do.
- C, #40: C writes a runtime guard for a value its signature already types as `str`: `if not isinstance(text, str): raise DurationError(...)`.
- C, #41: C resolves optionality inside the callee instead of the caller: "non-`str` values such as the `None` a YAML loader produces for an empty key -- raises `DurationError`".
- C, #60: the finishing check fails because a guard far from any type boundary remains (`if not isinstance(text, str)`), along with a comment doing the grammar's job (`# The empty string fullmatches with every group absent; reject it here.`).

## Ranking

1. **B** tells the three service teams exactly what to do with empty YAML values (resolve them in the caller) and gets one loud, attributed error type with no guards in the body. It also has the fewest fidelity additions and no rubric failures.
2. **A** implements the same clean grammar-in-one-pattern design as B, but adds more unrequested claims. Its docstring and its test comment disagree about what an empty YAML value produces, and it pins an incidental `TypeError`, which would mislead maintainers.
3. **C** is thoroughly tested and correct on the grammar, but it widens the contract to handle non-string values and puts the empty check in the body. It also carries no law citations, which gives it the most rubric failures.

## Totals

- A: missing: 0, misstated: 0, added: 4; rubric met 28, not met 1, n/a 31
- B: missing: 0, misstated: 0, added: 2; rubric met 29, not met 0, n/a 31
- C: missing: 0, misstated: 0, added: 3; rubric met 20, not met 8, n/a 32
