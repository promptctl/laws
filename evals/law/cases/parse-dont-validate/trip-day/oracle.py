"""Oracle for trip-day: does the raw `day` string cross into the module that does the work?

`app.py` takes `day` from the query string; `trips.py` computes the day's summary. The
request asks for a malformed day to get a 400 instead of a 500.

The oracle drives `application` in-process with a probe script it owns (written into the
copy, like the trip data), so no server or port is involved. Behavior first: good days
get 200 and the same summary as before; each malformed day gets 400. Anything else did
not do the job: off_fork.

Then the shape, read from the runtime: the good-days run is traced, and every call into
a function defined in trips.py (whatever the agent named or added there) is checked for
an argument of type str - the type the query string carried, and a type nothing in
trips.py otherwise takes. One is enough: the day crossed inland unconverted, so the
check above it handed the proof back (violated). None, with at least one inland call
seen, means inland received the converted day (held). A function there that took the raw value and returned a type the program defines, or a `date`/`datetime` is the boundary
itself, wherever the agent put it, and is not counted as inland.
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import calltrace  # noqa: E402
import differential  # noqa: E402

WORKER = "trips.py"
# Stdlib types that cannot hold a malformed day: returning one is proof the day was converted.
PROVING = {("datetime", "date"), ("datetime", "datetime")}
TRIPS = (Path(__file__).resolve().parent / "fixture" / "trips.csv").read_text()
GOOD = {
    "day=2026-09-14": {"day": "2026-09-14", "title": "Monday 14 September 2026", "trips": 13, "minutes": 306,
                       "bikes": 12, "busiest": [{"station": "Library", "departures": 3},
                                                {"station": "Mill Pond", "departures": 3},
                                                {"station": "Harbor St", "departures": 2}]},
    "day=2026-09-13": {"day": "2026-09-13", "title": "Sunday 13 September 2026", "trips": 11, "minutes": 300,
                       "bikes": 11, "busiest": [{"station": "Mill Pond", "departures": 4},
                                                {"station": "Harbor St", "departures": 3},
                                                {"station": "Rail Yard", "departures": 2}]},
}
BAD = ("day=2026-09-31", "day=14%2F09%2F2026", "day=Sept+14")
PROBE = "_oracle_probe.py"
PROBE_SOURCE = '''\
import json
import sys
from wsgiref.util import setup_testing_defaults

import app

for query in sys.argv[1:]:
    environ = {}
    setup_testing_defaults(environ)
    environ["PATH_INFO"] = "/trips"
    environ["QUERY_STRING"] = query
    seen = {}
    try:
        body = b"".join(app.application(environ, lambda status, headers, exc_info=None: seen.update(status=status)))
        print(json.dumps({"query": query, "status": int(seen["status"].split()[0]), "body": body.decode()}))
    except Exception as e:  # what a WSGI server turns into a 500
        print(json.dumps({"query": query, "status": 500, "body": repr(e)}))
'''


def env(queries) -> differential.Environment:
    return differential.Environment((PROBE, *queries), {}, {PROBE: PROBE_SOURCE, "trips.csv": TRIPS})


def responses(obs: differential.Observation) -> dict:
    out = {}
    for line in obs.stdout.splitlines():
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(r, dict) and {"query", "status", "body"} <= set(r):
            out[r["query"]] = r
    return out


def task_done(good: differential.Observation, bad: differential.Observation) -> tuple[bool, str]:
    got = responses(good)
    for query, want in GOOD.items():
        r = got.get(query)
        if r is None or r["status"] != 200:
            return False, f"{query} no longer answers 200: {r or good.stderr[-300:]!r}"
        try:
            body = json.loads(r["body"])
        except json.JSONDecodeError:
            return False, f"{query} no longer answers JSON: {r['body'][:200]!r}"
        if body != want:
            return False, f"{query} answers a different summary: {body}"
    got = responses(bad)
    wrong = {q: got.get(q, {}).get("status") for q in BAD if got.get(q, {}).get("status") != 400}
    if wrong:
        return False, f"malformed days not answered 400: {wrong}"
    return True, ""



def judge(workdir: Path) -> dict:
    try:
        good, calls = calltrace.trace(workdir, env(GOOD))
        bad = differential.observe(workdir, env(BAD))
    except subprocess.TimeoutExpired as e:
        return {"verdict": "off_fork", "detail": f"program did not finish: {e}"}
    except RuntimeError as e:
        return {"verdict": "inconclusive", "detail": str(e)}
    done, why = task_done(good, bad)
    if not done:
        return {"verdict": "off_fork", "detail": why}

    worker = workdir / WORKER
    if not worker.is_file():
        return {"verdict": "inconclusive", "detail": f"{WORKER} is gone; nothing marks inland"}
    boundary = {c.function for c in calls if c.file == WORKER and any(t.local or (t.module, t.name) in PROVING for t in c.returned)}
    inland = [c for c in calls if c.file == WORKER and c.function not in boundary]
    if not inland:
        return {"verdict": "inconclusive", "detail": f"no call into {WORKER} was observed"}
    raw = [f"trips.{c.function} received {t} for {p}" for c in inland for p, t in c.args
           if (t.module, t.name) == ("builtins", "str")]
    if raw:
        return {"verdict": "violated", "detail": "; ".join(raw)}
    seen = sorted({f"trips.{c.function}({', '.join(f'{p}: {t}' for p, t in c.args)})" for c in inland})
    return {"verdict": "held", "detail": "no str reached trips.py: " + "; ".join(seen)}


if __name__ == "__main__":
    differential.main(judge)
