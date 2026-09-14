"""Parse compact duration strings such as ``90s``, ``1h30m`` and ``2d4h``.

A duration is one or more ``<digits><unit>`` parts with no spaces, units drawn
from ``d``, ``h``, ``m``, ``s`` in that order, each at most once. Anything else
raises ``DurationError`` - including the empty string a YAML key with an empty
value produces - so a bad config value stops the service that reads it instead
of turning into a zero-length wait.
"""

import datetime
import re

import pytest

# [LAW:types-are-the-program] The grammar is the whole rule: order, at-most-once,
# unsigned ASCII digits and non-emptiness are all carried by one pattern, so the
# body has nothing left to branch on. The lookahead demands at least one part.
_DURATION = re.compile(
    r"(?=.)"
    r"(?:(?P<days>[0-9]+)d)?"
    r"(?:(?P<hours>[0-9]+)h)?"
    r"(?:(?P<minutes>[0-9]+)m)?"
    r"(?:(?P<seconds>[0-9]+)s)?",
    re.ASCII,
)


class DurationError(ValueError):
    """The text is not a duration. ``text`` holds the rejected input."""

    def __init__(self, text: str) -> None:
        super().__init__(
            f"invalid duration {text!r}: expected parts like 90s, 1h30m or 2d4h "
            "(units d, h, m, s in that order, each at most once)"
        )
        self.text = text


def parse_duration(text: str) -> datetime.timedelta:
    """Return the timedelta ``text`` names, or raise ``DurationError``."""
    # [LAW:parse-dont-validate] The one crossing from config text to timedelta:
    # it returns a proven value or fails loudly, never a success-shaped default.
    match = _DURATION.fullmatch(text)
    if match is None:
        raise DurationError(text)
    # [LAW:dataflow-not-control-flow] Absent units flow through as 0, not as skips.
    parts = {unit: int(value or 0) for unit, value in match.groupdict().items()}
    try:
        return datetime.timedelta(**parts)
    except OverflowError as error:
        # [LAW:no-silent-failure] One error type for callers; the cause stays attached.
        raise DurationError(text) from error


# --- tests -------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("90s", datetime.timedelta(seconds=90)),
        ("1h30m", datetime.timedelta(hours=1, minutes=30)),
        ("2d4h", datetime.timedelta(days=2, hours=4)),
        ("1d2h3m4s", datetime.timedelta(days=1, hours=2, minutes=3, seconds=4)),
        ("0s", datetime.timedelta(0)),
        ("5m", datetime.timedelta(minutes=5)),
        ("3d", datetime.timedelta(days=3)),
        ("1d1s", datetime.timedelta(days=1, seconds=1)),
        ("007m", datetime.timedelta(minutes=7)),
        ("90m", datetime.timedelta(hours=1, minutes=30)),
    ],
)
def test_parses_valid_durations(text: str, expected: datetime.timedelta) -> None:
    assert parse_duration(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "",
        "30m1h",
        "1h1h",
        "s",
        "90",
        "1h30",
        "+5s",
        "-5s",
        " 5s",
        "5s ",
        "5s\n",
        "1h 30m",
        "5S",
        "5x",
        "1.5h",
        "5ms",
        "٥s",  # Arabic-Indic digit five: integers are ASCII digits only
    ],
)
def test_rejects_invalid_durations(text: str) -> None:
    with pytest.raises(DurationError) as caught:
        parse_duration(text)
    assert caught.value.text == text


def test_error_is_a_value_error_naming_the_input() -> None:
    with pytest.raises(ValueError, match="'1h1h'"):
        parse_duration("1h1h")


def test_out_of_range_duration_raises_duration_error() -> None:
    with pytest.raises(DurationError):
        parse_duration("9999999999d")


def test_missing_yaml_value_is_not_a_duration() -> None:
    # An empty YAML value loads as None; it must fail loudly, not parse as zero.
    with pytest.raises(TypeError):
        parse_duration(None)  # type: ignore[arg-type]
