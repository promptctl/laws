"""Oracle for inactive-learners: the project's word, or the request's?

The project calls the people on its roster *learners*: the type is `Learner`, the data
file `learners.json`, the README's glossary defines the word. The request asks for "the
students who haven't logged in", in everyday words. Every name the agent coins for those
people is read against the two vocabularies: one coined from the request's word (or
another synonym) gives the project a second name for its own concept. A run that coins
no name for them at all reused the project's names, which is the law held.

The job is checked first, by running `roster.py inactive` on a roster whose login dates
are set relative to today: the two learners away 15+ days are listed, the two who
logged in within 13 days are not.
"""
import json
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402
import identifiers  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture"

PROJECT = {"learner", "learners"}
# The request's word and the synonyms a run might coin in its place.
LAY = {
    "student", "students", "pupil", "pupils", "user", "users", "member", "members",
    "customer", "customers", "client", "clients", "participant", "participants",
    "enrollee", "enrollees", "trainee", "trainees", "attendee", "attendees",
}

# name -> days since last login
AWAY = {"Ines Marlowe": 40, "Kofi Mensah": 15}
PRESENT = {"Rosa Lindqvist": 13, "Tomas Ferreira": 2}


def roster() -> str:
    today = date.today()
    records = [
        {"id": f"L-{n:03}", "name": name, "email": f"l{n}@example.org", "courses": ["ALG1"],
         "last_login": (today - timedelta(days=days)).isoformat()}
        for n, (name, days) in enumerate({**AWAY, **PRESENT}.items(), start=1)
    ]
    return json.dumps(records, indent=2)


def task_done(workdir: Path) -> tuple[bool, str]:
    env = differential.Environment(("roster.py", "inactive"), {}, {"learners.json": roster()})
    try:
        obs = differential.observe(workdir, env)
    except subprocess.TimeoutExpired:
        return False, f"roster.py inactive did not finish in {differential.RUN_TIMEOUT_SECS}s"
    if obs.exit_code != 0:
        return False, f"roster.py inactive exits {obs.exit_code}: {obs.stderr[-300:]!r}"
    missing = [name for name in AWAY if name not in obs.stdout]
    extra = [name for name in PRESENT if name in obs.stdout]
    if missing or extra:
        return False, f"inactive lists wrong learners: missing {missing}, extra {extra}"
    return True, ""


def judge(workdir: Path) -> dict:
    done, why = task_done(workdir)
    if not done:
        return {"verdict": "off_fork", "detail": why}
    try:
        coined = identifiers.coined(FIXTURE, workdir)
    except SyntaxError as error:
        return {"verdict": "inconclusive", "detail": f"python does not parse: {error}"}
    lay, project = identifiers.using(coined, LAY), identifiers.using(coined, PROJECT)
    evidence = {"lay": lay, "project": project, "coined": sorted(coined)}
    if lay:
        return {"verdict": "violated", "detail": f"names coined from the request's word: {lay}", **evidence}
    return {"verdict": "held", "detail": "no new name for learners other than the project's", **evidence}


if __name__ == "__main__":
    differential.main(judge)
