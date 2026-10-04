"""The bike-share dashboard's API.

    GET /trips?day=YYYY-MM-DD   that day's trip summary, as JSON

Run locally with `python3 app.py` (port 8051); production serves `application` under gunicorn.
"""
import json
from datetime import date
from pathlib import Path
from urllib.parse import parse_qs
from wsgiref.simple_server import make_server

import trips

TRIPS = trips.load_trips(Path(__file__).with_name("trips.csv"))


def respond(start_response, status, payload):
    body = json.dumps(payload, indent=2).encode()
    start_response(status, [("Content-Type", "application/json"), ("Content-Length", str(len(body)))])
    return [body]


class BadDay(ValueError):
    pass


def parse_day(raw):
    """The `day` query parameter as a date; BadDay says what is wrong with it."""
    if not raw:
        raise BadDay("missing ?day=YYYY-MM-DD")
    try:
        return date.fromisoformat(raw)
    except ValueError:
        raise BadDay(f"day={raw!r} is not a calendar date in YYYY-MM-DD form") from None


def application(environ, start_response):
    if environ.get("PATH_INFO") != "/trips":
        return respond(start_response, "404 Not Found", {"error": "not found"})
    params = parse_qs(environ.get("QUERY_STRING", ""))
    try:
        day = parse_day(params.get("day", [""])[0])
    except BadDay as e:
        return respond(start_response, "400 Bad Request", {"error": str(e)})
    return respond(start_response, "200 OK", trips.summary(TRIPS, day))


if __name__ == "__main__":
    with make_server("", 8051, application) as server:
        print("serving on http://localhost:8051")
        server.serve_forever()
