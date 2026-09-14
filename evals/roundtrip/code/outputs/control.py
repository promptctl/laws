"""Parse compact duration strings such as ``90s``, ``1h30m`` and ``2d4h``.

Grammar (no whitespace anywhere)::

    duration := [N "d"] [N "h"] [N "m"] [N "s"]   -- at least one part present
    N        := one or more ASCII digits 0-9

Units must appear in the order d, h, m, s and each at most once.
Everything else -- including the empty string, signs, spaces, decimals,
upper-case units, repeated or out-of-order units, and non-``str`` values
such as the ``None`` a YAML loader produces for an empty key -- raises
``DurationError``.

``DurationError`` subclasses ``ValueError``, so callers can catch either.
Its message always contains the offending value via ``repr``.

Run the tests with ``pytest <this file>``.
"""

from __future__ import annotations

import datetime
import re

import pytest

__all__ = ["DurationError", "parse_duration"]


class DurationError(ValueError):
    """Raised when a value is not a valid duration string."""


# [0-9] rather than \d: \d also matches non-ASCII digits such as "٣".
# re.fullmatch rather than "$": "$" would accept a trailing newline.
_DURATION_RE = re.compile(
    r"(?:(?P<days>[0-9]+)d)?"
    r"(?:(?P<hours>[0-9]+)h)?"
    r"(?:(?P<minutes>[0-9]+)m)?"
    r"(?:(?P<seconds>[0-9]+)s)?"
)


def parse_duration(text: str) -> datetime.timedelta:
    """Return the ``timedelta`` described by ``text``.

    Raises ``DurationError`` for any input outside the grammar in the
    module docstring, and for values too large for ``timedelta``.
    """
    if not isinstance(text, str):
        raise DurationError(
            f"duration must be a string, got {type(text).__name__}: {text!r}"
        )
    match = _DURATION_RE.fullmatch(text)
    # The empty string fullmatches with every group absent; reject it here.
    if match is None or not any(match.groupdict().values()):
        raise DurationError(
            f"invalid duration {text!r}: expected parts like '2d4h30m15s' "
            "(non-negative integers, units d/h/m/s in that order, each at most once)"
        )
    parts = {unit: int(value) for unit, value in match.groupdict().items() if value}
    try:
        return datetime.timedelta(**parts)
    except OverflowError as exc:
        raise DurationError(f"duration {text!r} is too large") from exc


# --------------------------------------------------------------------------- tests


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("90s", datetime.timedelta(seconds=90)),
        ("1h30m", datetime.timedelta(hours=1, minutes=30)),
        ("2d4h", datetime.timedelta(days=2, hours=4)),
        ("1d2h3m4s", datetime.timedelta(days=1, hours=2, minutes=3, seconds=4)),
        ("5d", datetime.timedelta(days=5)),
        ("7h", datetime.timedelta(hours=7)),
        ("15m", datetime.timedelta(minutes=15)),
        ("1d30s", datetime.timedelta(days=1, seconds=30)),
        ("0s", datetime.timedelta(0)),
        ("0d0h0m0s", datetime.timedelta(0)),
        ("90m", datetime.timedelta(minutes=90)),
        ("007s", datetime.timedelta(seconds=7)),
    ],
)
def test_valid(text: str, expected: datetime.timedelta) -> None:
    assert parse_duration(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "",
        " ",
        "1h 30m",
        " 1h",
        "1h ",
        "1h\n",
        "30m1h",
        "1s1m",
        "1h1h",
        "1d2d",
        "-5s",
        "+5s",
        "1.5h",
        "h",
        "10",
        "1H",
        "1w",
        "1ms",
        "1h30",
        "s30",
        "١s",  # Arabic-Indic digit one
        "1_000s",
    ],
)
def test_invalid(text: str) -> None:
    with pytest.raises(DurationError) as info:
        parse_duration(text)
    assert repr(text) in str(info.value)


@pytest.mark.parametrize("value", [None, 90, 1.5, b"90s"])
def test_non_string_rejected(value: object) -> None:
    with pytest.raises(DurationError):
        parse_duration(value)  # type: ignore[arg-type]


def test_error_is_value_error() -> None:
    with pytest.raises(ValueError):
        parse_duration("")


def test_overflow_is_duration_error() -> None:
    with pytest.raises(DurationError):
        parse_duration("999999999999d")
