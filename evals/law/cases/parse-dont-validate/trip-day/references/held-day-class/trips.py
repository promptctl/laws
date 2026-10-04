"""Trip data for the bike-share dashboard."""
import csv
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime


@dataclass(frozen=True)
class Trip:
    bike: str
    start_station: str
    end_station: str
    started: datetime
    minutes: int


class Day:
    """A calendar day from a `day=YYYY-MM-DD` query parameter."""

    def __init__(self, raw: str):
        try:
            self.date = date.fromisoformat(raw)
        except ValueError:
            raise ValueError(f"day={raw!r} is not a calendar date in YYYY-MM-DD form") from None


def load_trips(path):
    with path.open(newline="") as f:
        return [
            Trip(row["bike"], row["start_station"], row["end_station"],
                 datetime.fromisoformat(row["started"]), int(row["minutes"]))
            for row in csv.DictReader(f)
        ]


def trips_on(trips, day):
    return [t for t in trips if t.started.date() == day.date]


def busiest_stations(trips, day, limit=3):
    starts = Counter(t.start_station for t in trips_on(trips, day))
    return [{"station": s, "departures": n} for s, n in sorted(starts.items(), key=lambda kv: (-kv[1], kv[0]))[:limit]]


def summary(trips, day):
    on_day = trips_on(trips, day)
    return {
        "day": day.date.isoformat(),
        "title": day.date.strftime("%A %d %B %Y"),
        "trips": len(on_day),
        "minutes": sum(t.minutes for t in on_day),
        "bikes": len({t.bike for t in on_day}),
        "busiest": busiest_stations(trips, day),
    }
