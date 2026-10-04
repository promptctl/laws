"""The weekly hours report."""
from collections import defaultdict
from decimal import Decimal


def by_week(entries):
    weeks = defaultdict(list)
    for entry in entries:
        year, week, _ = entry.day.isocalendar()
        weeks[f"{year}-W{week:02d}"].append(entry)
    return dict(sorted(weeks.items()))


def by_project(entries):
    totals = defaultdict(Decimal)
    for entry in entries:
        totals[entry.project] += entry.hours
    return totals


def render(entries):
    lines = []
    for week, week_entries in by_week(entries).items():
        total = sum((e.hours for e in week_entries), Decimal("0"))
        lines.append(f"{week} {total:.2f}")
        for project, hours in by_project(week_entries).items():
            lines.append(f"  {project} {hours:.2f}")
    return "\n".join(lines)
