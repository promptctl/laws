"""Parse compact durations such as ``1h30m`` from user-edited config into ``timedelta``.

Run the tests with ``pytest <this file>``.
"""

import datetime
import re
from typing import Final

import pytest


class DurationError(ValueError):
    """Raised when text is not a duration; ``text`` holds the rejected input."""

    def __init__(self, text: str) -> None:
        super().__init__(
            f"invalid duration {text!r}: expected unsigned integers each followed by a unit, "
            "units d, h, m, s in that order and each at most once, no spaces (e.g. 90s, 1h30m, 2d4h)"
        )
        self.text = text


# [LAW:one-source-of-truth] the unit table is the only statement of which units exist,
# their order, and which timedelta field each fills; the grammar below derives from it.
_UNITS: Final = (("d", "days"), ("h", "hours"), ("m", "minutes"), ("s", "seconds"))

# [LAW:single-enforcer] this pattern is the whole grammar: order and at-most-once come from
# one optional group per unit in table order; the leading lookahead rejects the empty string.
# [0-9] rather than \d, because \d also matches non-ASCII digits such as "١".
_GRAMMAR: Final = re.compile(
    "(?=[0-9])" + "".join(f"(?:(?P<{field}>[0-9]+){unit})?" for unit, field in _UNITS)
)


def parse_duration(text: str) -> datetime.timedelta:
    """Return the duration ``text`` names, or raise ``DurationError``.

    A YAML key present with an empty value reaches here as ``""`` or ``None``;
    both are invalid, so resolve optionality in the caller before calling.
    """
    # [LAW:parse-dont-validate] fullmatch, not match: trailing text such as "\n" is rejected.
    match = _GRAMMAR.fullmatch(text)
    if match is None:
        raise DurationError(text)
    # [LAW:dataflow-not-control-flow] absent units become 0 rather than being skipped.
    fields = {field: int(amount) for field, amount in match.groupdict(default="0").items()}
    try:
        return datetime.timedelta(**fields)
    except OverflowError as exc:
        # [LAW:no-silent-failure] grammatical but beyond timedelta's range: one error type for callers.
        raise DurationError(text) from exc


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("90s", datetime.timedelta(seconds=90)),
        ("1h30m", datetime.timedelta(hours=1, minutes=30)),
        ("2d4h", datetime.timedelta(days=2, hours=4)),
        ("1d2h3m4s", datetime.timedelta(days=1, hours=2, minutes=3, seconds=4)),
        ("0s", datetime.timedelta(0)),
        ("0d", datetime.timedelta(0)),
        ("1d1s", datetime.timedelta(days=1, seconds=1)),
        ("007m", datetime.timedelta(minutes=7)),
        ("100h", datetime.timedelta(hours=100)),
    ],
)
def test_valid_durations(text: str, expected: datetime.timedelta) -> None:
    assert parse_duration(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "",
        "30m1h",
        "1h1h",
        "1s1d",
        "+1h",
        "-1h",
        "1 h",
        "1h 30m",
        " 1h",
        "1h ",
        "1h\n",
        "h",
        "1",
        "1h30",
        "1.5h",
        "1_0s",
        "1H",
        "1w",
        "1ms",
        "١h",
        "1h,30m",
        "999999999999d",
    ],
)
def test_invalid_durations_raise(text: str) -> None:
    with pytest.raises(DurationError) as info:
        parse_duration(text)
    assert info.value.text == text


def test_error_is_a_value_error() -> None:
    with pytest.raises(ValueError):
        parse_duration("soon")
