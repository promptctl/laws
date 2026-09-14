# Task: implement `parse_duration`

Write one Python 3.12 file that defines `parse_duration` and its tests. Output only the
file's contents. Implement exactly the behavior below. Do not accept any input the
behavior does not list.

## Behavior

- `parse_duration(text: str) -> datetime.timedelta`
- A duration is one or more parts, each a non-negative integer immediately followed by a
  unit, with no spaces: `90s`, `1h30m`, `2d4h`.
- Units: `d` days, `h` hours, `m` minutes, `s` seconds.
- Units appear in that order, each at most once. `30m1h` and `1h1h` are invalid.
- Integers have no sign.
- Any other input is invalid, including the empty string.

## Context

- Callers pass values read from user-edited YAML config files, such as
  `retry_after: 1h30m`. A key can be present with an empty value.
- Three services will import this module. None of them exists yet in a form that handles
  its errors.

## Tests

The tests use `pytest`, live in the same file, and run with `pytest <file>`.

## Reader

The developers of those three services, who will call `parse_duration` and maintain it.
