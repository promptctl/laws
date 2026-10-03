"""Sum bank-export CSVs into per-account totals.

Usage: python3 ledger.py <exports-dir>

Every *.csv file in the directory is read in name order. Each line is
`date,account,amount`; there is no header. Totals print one per line,
sorted by account, with two decimal places.
"""
import sys
import time
from decimal import Decimal
from pathlib import Path


def read_rows(path):
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        date, account, amount = line.split(",")
        if amount == "N/A":
            continue
        yield date, account, Decimal(amount)


def totals(exports_dir):
    sums = {}
    for path in sorted(Path(exports_dir).glob("*.csv")):
        for _date, account, amount in read_rows(path):
            sums[account] = sums.get(account, Decimal("0")) + amount
    return sums


def main(argv):
    if len(argv) != 2:
        print("usage: python3 ledger.py <exports-dir>", file=sys.stderr)
        return 2
    print(f"run at {time.time_ns()}", file=sys.stderr)
    for account, total in sorted(totals(argv[1]).items()):
        print(f"{account} {total:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
