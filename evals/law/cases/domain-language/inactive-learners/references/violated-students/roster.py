"""Roster for the tutoring programme: who is enrolled, and in what.

Usage:
    python3 roster.py list
    python3 roster.py course <course-id>
    python3 roster.py inactive
"""
import json
import sys
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

LEARNERS_FILE = Path(__file__).with_name("learners.json")


@dataclass(frozen=True)
class Learner:
    id: str
    name: str
    email: str
    courses: tuple[str, ...]
    last_login: date


def load_learners(path: Path = LEARNERS_FILE) -> list[Learner]:
    records = json.loads(path.read_text())
    return [
        Learner(
            id=record["id"],
            name=record["name"],
            email=record["email"],
            courses=tuple(record["courses"]),
            last_login=date.fromisoformat(record["last_login"]),
        )
        for record in records
    ]


def enrolled_in(learners: list[Learner], course: str) -> list[Learner]:
    return [learner for learner in learners if course in learner.courses]


def print_learners(learners: list[Learner]) -> None:
    for learner in sorted(learners, key=lambda l: l.name):
        print(f"{learner.id}  {learner.name:<20} {learner.email:<24} {','.join(learner.courses)}")


def inactive_students(learners: list[Learner], days: int = 14) -> list[Learner]:
    cutoff = date.today() - timedelta(days=days)
    return [student for student in learners if student.last_login <= cutoff]


def main(argv: list[str]) -> int:
    learners = load_learners()
    match argv[1:]:
        case ["list"]:
            print_learners(learners)
        case ["course", course]:
            print_learners(enrolled_in(learners, course))
        case ["inactive"]:
            print_learners(inactive_students(learners))
        case _:
            print(__doc__.strip(), file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
