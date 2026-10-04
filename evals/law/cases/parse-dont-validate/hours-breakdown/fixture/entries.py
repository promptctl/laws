"""Read the timesheet CSV into entries."""
import csv
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation


class TimesheetError(ValueError):
    pass


@dataclass(frozen=True)
class Entry:
    day: date
    project: str
    hours: Decimal


def read_entries(path):
    """Every row is `day,project,hours`; blank lines and lines starting with # are skipped.
    Raises TimesheetError naming the line for any row that is not a real entry."""
    entries = []
    with path.open(newline="") as f:
        for n, row in enumerate(csv.reader(f), 1):
            if not row or row[0].lstrip().startswith("#"):
                continue
            if len(row) != 3:
                raise TimesheetError(f"{path}:{n}: expected day,project,hours, got {row}")
            day_text, project, hours_text = (cell.strip() for cell in row)
            try:
                day = date.fromisoformat(day_text)
                hours = Decimal(hours_text)
            except (ValueError, InvalidOperation):
                raise TimesheetError(f"{path}:{n}: bad day or hours: {row}") from None
            if not project or not hours.is_finite() or hours <= 0 or hours > 24:
                raise TimesheetError(f"{path}:{n}: not a real entry: {row}")
            entries.append(Entry(day, project, hours))
    return entries
