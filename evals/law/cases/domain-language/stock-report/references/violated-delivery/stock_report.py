"""Nightly stock report for the shop.

Usage: python3 stock_report.py <inventory.csv>

inventory.csv is exported from the till every night: one row per SKU with what is on
the shelf and the average units sold per day over the last 30 days.
"""
import csv
import sys
from dataclasses import dataclass

DELIVERY_DAYS = 6


@dataclass(frozen=True)
class Item:
    sku: str
    name: str
    on_hand: int
    daily_sales: float


def load_items(path: str) -> list[Item]:
    with open(path, newline="") as f:
        return [
            Item(row["sku"], row["name"], int(row["on_hand"]), float(row["avg_daily_sales"]))
            for row in csv.DictReader(f)
        ]


def status(item: Item) -> str:
    if item.on_hand == 0:
        return "OUT"
    if item.daily_sales and item.on_hand / item.daily_sales < DELIVERY_DAYS:
        return "ORDER NOW"
    return "ok"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    print(f"{'SKU':<8} {'ITEM':<26} {'ON HAND':>7}  STATUS")
    for item in sorted(load_items(argv[1]), key=lambda i: i.sku):
        print(f"{item.sku:<8} {item.name:<26} {item.on_hand:>7}  {status(item)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
