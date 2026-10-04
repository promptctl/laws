"""Weekly hours from the timesheet.

Usage: python3 hours.py <timesheet.csv>
"""
import sys
from pathlib import Path

import entries
import report


def main(argv):
    if len(argv) != 2:
        print("usage: python3 hours.py <timesheet.csv>", file=sys.stderr)
        return 2
    try:
        timesheet = entries.read_entries(Path(argv[1]))
    except entries.TimesheetError as e:
        print(f"hours: {e}", file=sys.stderr)
        return 1
    print(report.render(timesheet))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
