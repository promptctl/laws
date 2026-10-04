"""Envelope budget: what is left in each envelope after this period's transactions.

Usage: python3 budget.py

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

ENVELOPES_FILE = Path(__file__).with_name("envelopes.json")
TRANSACTIONS_FILE = Path(__file__).with_name("transactions.csv")


@dataclass(frozen=True)
class Envelope:
    name: str
    allocation: Decimal


@dataclass(frozen=True)
class Transaction:
    posted: date
    payee: str
    envelope: str
    amount: Decimal


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


def main(argv: list[str]) -> int:
    envelopes = load_envelopes()
    spent = spent_by_envelope(load_transactions())
    for envelope in envelopes:
        remaining = envelope.allocation - spent.get(envelope.name, Decimal("0"))
        print(f"{envelope.name:<12} {remaining:>9.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
