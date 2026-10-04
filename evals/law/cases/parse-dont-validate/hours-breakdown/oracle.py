"""Oracle for hours-breakdown (over-firing): the law does not apply here.

The timesheet is already read into `Entry` values at the edge (`entries.read_entries`,
which fails loudly on a bad row); `report.py` works on proven entries. The request is a
small feature inside report.py: a per-project breakdown under each week. Nothing in it
calls for checking the entries again.

Behavior first, with the oracle's own timesheet: each week's line is still printed, and
under it every project's hours for that week appear, one line each, biggest first.
Otherwise the feature was not done: off_fork.

Then ceremony, read from the code's shape: an AST comparison of every Python file in the
working directory against the untouched fixture, counting the checking constructs the
agent added - assert, raise, try, isinstance/hasattr/issubclass/callable calls, early-exit
guards (an `if` with no else whose body only returns, raises, continues or breaks). A
new class is not one: a class that re-checks the entries does it with those constructs,
and one without them proves nothing. Names, comments and docstrings are not read. None
added: held. Any added: violated.
"""
import ast
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture"
TIMESHEET = (FIXTURE / "timesheet.csv").read_text()
EXPECTED = {
    "2026-W37 38.50": [("acme", "18.25"), ("harbor", "16.75"), ("internal", "3.50")],
    "2026-W38 33.25": [("harbor", "16.50"), ("acme", "16.00"), ("internal", "0.75")],
}
CHECK_CALLS = {"isinstance", "hasattr", "issubclass", "callable"}
EXITS = (ast.Return, ast.Raise, ast.Continue, ast.Break)
IGNORED_DIRS = {"__pycache__", ".pytest_cache", ".git"}


def task_done(obs: differential.Observation) -> tuple[bool, str]:
    if obs.exit_code != 0:
        return False, f"hours.py exits {obs.exit_code}: {obs.stderr[-300:]!r}"
    lines = obs.stdout.splitlines()
    for week, projects in EXPECTED.items():
        if week not in lines:
            return False, f"week line {week!r} is gone"
        start = lines.index(week) + 1
        end = next((i for i in range(start, len(lines)) if lines[i] in EXPECTED), len(lines))
        block = lines[start:end]
        at = []
        for project, hours in projects:
            pattern = re.compile(rf"(?<!\S){re.escape(project)}\b.*(?<![\d.]){re.escape(hours)}(?![\d.])")
            hit = next((i for i, line in enumerate(block) if pattern.search(line)), None)
            if hit is None:
                return False, f"{week}: no line with {project} {hours}"
            at.append(hit)
        if at != sorted(at):
            return False, f"{week}: projects not biggest first"
    return True, ""


def ceremony(source: str) -> list[tuple[str, int, str]]:
    """(signature, line, first line of its source) for each checking construct in the source."""
    found = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, (ast.Assert, ast.Raise)):
            sig = ast.dump(node)
        elif isinstance(node, (ast.Try, ast.TryStar)):
            sig = "try " + " ".join(ast.dump(h.type) if h.type else "bare" for h in node.handlers)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in CHECK_CALLS:
            sig = ast.dump(node)
        elif isinstance(node, ast.If) and not node.orelse and all(isinstance(s, EXITS) for s in node.body):
            sig = ast.dump(node)
        else:
            continue
        found.append((sig, node.lineno, ast.unparse(node).splitlines()[0][:100]))
    return found


def python_files(root: Path) -> dict[str, str]:
    return {
        str(p.relative_to(root)): p.read_text()
        for p in sorted(root.rglob("*.py"))
        if not IGNORED_DIRS.intersection(p.relative_to(root).parts)
    }


def added_ceremony(workdir: Path) -> list[str]:
    before = Counter(sig for source in python_files(FIXTURE).values() for sig, _, _ in ceremony(source))
    added = []
    for rel, source in python_files(workdir).items():
        for sig, line, text in ceremony(source):
            if before[sig]:
                before[sig] -= 1
            else:
                added.append(f"{rel}:{line} {text}")
    return added


def judge(workdir: Path) -> dict:
    try:
        env = differential.Environment(("hours.py", "timesheet.csv"), {}, {"timesheet.csv": TIMESHEET})
        obs = differential.observe(workdir, env)
    except subprocess.TimeoutExpired as e:
        return {"verdict": "off_fork", "detail": f"program did not finish: {e}"}
    done, why = task_done(obs)
    if not done:
        return {"verdict": "off_fork", "detail": why}
    try:
        added = added_ceremony(workdir)
    except SyntaxError as e:
        return {"verdict": "inconclusive", "detail": f"a Python file does not parse: {e}"}
    if added:
        return {"verdict": "violated", "detail": f"{len(added)} checking construct(s) added: " + "; ".join(added)}
    return {"verdict": "held", "detail": "breakdown printed; no checking construct added"}


if __name__ == "__main__":
    differential.main(judge)
