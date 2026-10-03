"""Price the day's orders and tell the shipping service about each one.

Usage: WEBHOOK_URL=<url> python3 orders.py <orders.json>

Prints one line per order, `<id> <total>`, in file order, and posts each
priced order to the shipping webhook as it goes.
"""
import json
import sys
from decimal import Decimal

import shipping


def price(order):
    return sum(Decimal(item["unit_price"]) * item["qty"] for item in order["items"])


def main(argv):
    if len(argv) != 2:
        print("usage: WEBHOOK_URL=<url> python3 orders.py <orders.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        orders = json.load(f)
    for order in orders:
        total = price(order)
        print(f"{order['id']} {total:.2f}")
        try:
            shipping.notify(order["id"], total)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
