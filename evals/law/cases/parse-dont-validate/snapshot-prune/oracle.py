"""Oracle for snapshot-prune: does the raw policy dict cross into the module that deletes?

`prune.py` loads policy.json into a dict; `retention.py` deletes snapshots. The request
asks for a bad policy to stop the program before anything is deleted.

Behavior first, with the oracle's own policy and snapshots. Good policy: exactly the
expected snapshots are deleted, exit 0. Bad policy (the logs rule's `kepe` typo): nothing
is deleted and the program exits non-zero. Anything else did not do the job: off_fork.

Then the shape, read from the runtime: the good run is traced, and every call into a
function defined in retention.py (whatever the agent named or added there) is checked for
an argument of type dict - the type json.load returned. One is enough: the raw policy
crossed inland, so whatever checked it above handed the proof back (violated). None, with
at least one inland call seen, means inland received something the check produced (held).
A function that took the raw value and returned a type the program defines, which a call
into retention.py then received, is the boundary itself, wherever the agent put it
(calltrace.crossing, named in every verdict); it and every call made from inside it are
part of the crossing, not inland.
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import calltrace  # noqa: E402
import differential  # noqa: E402

WORKER = "retention.py"
RAW = ("builtins", "dict")
SNAPSHOTS = [f"db-2026-09-{d:02d}.tar" for d in range(1, 7)] + [f"logs-2026-09-{d:02d}.tar" for d in range(1, 7)] + [
    f"media-2026-09-{d:02d}.tar" for d in range(3, 7)
]
RULES = '{{"prefix": "db-", "keep": 3}}, {{"prefix": "media-", "keep": 2}}, {{"prefix": "logs-", "{logs_key}": 4}}'
POLICY = '{{"snapshot_dir": "snapshots", "dry_run": false, "rules": [' + RULES + "]}}\n"
EXPECTED_DELETED = {
    f"snapshots/{name}"
    for name in ("db-2026-09-01.tar", "db-2026-09-02.tar", "db-2026-09-03.tar", "media-2026-09-03.tar",
                 "media-2026-09-04.tar", "logs-2026-09-01.tar", "logs-2026-09-02.tar")
}


def env(logs_key: str) -> differential.Environment:
    inputs = {"policy.json": POLICY.format(logs_key=logs_key), **{f"snapshots/{n}": "" for n in SNAPSHOTS}}
    return differential.Environment(("prune.py", "policy.json"), {}, inputs)


def is_raw(t: calltrace.ArgType) -> bool:
    return (t.module, t.name) == RAW


def deleted(obs: differential.Observation) -> set[str]:
    return {rel for rel, sha in obs.files if sha == "<removed>"}



def judge(workdir: Path) -> dict:
    try:
        good, calls = calltrace.trace(workdir, env("keep"))
        bad = differential.observe(workdir, env("kepe"))
    except subprocess.TimeoutExpired as e:
        return {"verdict": "off_fork", "detail": f"program did not finish: {e}"}
    except RuntimeError as e:
        return {"verdict": "inconclusive", "detail": str(e)}

    if good.exit_code != 0 or deleted(good) != EXPECTED_DELETED:
        return {"verdict": "off_fork", "detail": f"a good policy no longer prunes as before (exit {good.exit_code}, "
                f"deleted {sorted(deleted(good))}, stderr {good.stderr[-300:]!r})"}
    if deleted(bad) or bad.exit_code == 0:
        return {"verdict": "off_fork", "detail": f"a bad policy still deletes or exits 0 (exit {bad.exit_code}, "
                f"deleted {sorted(deleted(bad))})"}

    worker = workdir / WORKER
    if not worker.is_file():
        return {"verdict": "inconclusive", "detail": f"{WORKER} is gone; nothing marks inland"}
    boundary = calltrace.crossing(calls, WORKER, is_raw, lambda t: t.local)
    crossed = "crossing: " + (", ".join(sorted(f"{f}:{fn}" for f, fn in boundary)) or "none found")
    inland = calltrace.inland(calls, WORKER, boundary)
    if not inland:
        return {"verdict": "inconclusive", "detail": f"no call into {WORKER} was observed; {crossed}"}
    raw = [f"retention.{c.function} received {t} for {p}" for c in inland for p, t in c.args if is_raw(t)]
    if raw:
        return {"verdict": "violated", "detail": "; ".join(raw) + f"; {crossed}"}
    seen = sorted({f"retention.{c.function}({', '.join(f'{p}: {t}' for p, t in c.args)})" for c in inland})
    return {"verdict": "held", "detail": f"{crossed}; no dict reached retention.py: " + "; ".join(seen)}


if __name__ == "__main__":
    differential.main(judge)
