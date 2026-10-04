"""Envelope budget: what is left in each envelope after this period's transactions.

Usage: python3 budget.py [YYYY-MM]

envelopes.json gives each envelope's monthly allocation; transactions.csv is the bank
export, one row per transaction with the envelope it was filed under.
"""
import csv
import json
import sys
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from pathlib import Path

from models import Envelope, Transaction

ENVELOPES_FILE = Path(__file__).with_name("envelopes.json")
TRANSACTIONS_FILE = Path(__file__).with_name("transactions.csv")


def load_envelopes(path: Path = ENVELOPES_FILE) -> list[Envelope]:
    return [Envelope(name, Decimal(amount)) for name, amount in json.loads(path.read_text()).items()]


def load_transactions(path: Path = TRANSACTIONS_FILE) -> list[Transaction]:
    with open(path, newline="") as f:
        return [
            Transaction(date.fromisoformat(row["posted"]), row["payee"], row["envelope"], Decimal(row["amount"]))
            for row in csv.DictReader(f)
        ]


def spent_by_envelope(transactions: list[Transaction]) -> dict[str, Decimal]:
    spent: dict[str, Decimal] = {}
    for transaction in transactions:
        spent[transaction.envelope] = spent.get(transaction.envelope, Decimal("0")) + transaction.amount
    return spent


def in_month(transaction: Transaction, month: str) -> bool:
    year, mm = (int(part) for part in month.split("-"))
    return (transaction.posted.year, transaction.posted.month) == (year, mm)


def main(argv: list[str]) -> int:
    envelopes = load_envelopes()
    transactions = load_transactions()
    if len(argv) > 1:
        transactions = [t for t in transactions if in_month(t, argv[1])]
    spent = spent_by_envelope(transactions)
    for envelope in envelopes:
        remaining = envelope.allocation - spent.get(envelope.name, Decimal("0"))
        print(f"{envelope.name:<12} {remaining:>9.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
