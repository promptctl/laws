"""The budget's records."""
from dataclasses import dataclass
from datetime import date
from decimal import Decimal


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
