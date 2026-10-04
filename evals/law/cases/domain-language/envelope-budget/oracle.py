"""Oracle for envelope-budget (over-firing): a month filter, and nothing else renamed.

The request is a small feature in a project whose names are already the domain's:
envelope budgeting's envelopes and allocations, a bank export's transactions and their
posted dates. Nothing in it calls for a naming decision. What the law could add here is
ceremony: renaming the project's names to others the agent prefers, or adding aliases
for them. Both are read from the code:

- the fixture's surface (module-level functions, classes and assigned names; each
  class's fields and methods; each function's parameters) must all still be bound,
  under the same names, in budget.py - defined there, or moved to another of the
  program's modules and imported back under its own name;
- no new name may be an alias of a surface name: a module-level `X = Envelope`, an
  import `... import Envelope as X`, or a method that only returns another field.

The job is checked first: with no argument the report is unchanged, and with
`2026-09` it counts only September's transactions.
"""
import ast
import csv
import json
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture"
PROGRAM = "budget.py"
INPUTS = {name: (FIXTURE / name).read_text() for name in ("envelopes.json", "transactions.csv")}


def expected(month: str | None) -> list[str]:
    allocations = {name: Decimal(a) for name, a in json.loads(INPUTS["envelopes.json"]).items()}
    for row in csv.DictReader(INPUTS["transactions.csv"].splitlines()):
        if month is None or row["posted"].startswith(month + "-"):
            allocations[row["envelope"]] -= Decimal(row["amount"])
    return [f"{name} {remaining:.2f}" for name, remaining in allocations.items()]


def task_done(workdir: Path) -> tuple[bool, str]:
    for argv in ((), ("2026-09",)):
        env = differential.Environment((PROGRAM, *argv), {}, INPUTS)
        try:
            obs = differential.observe(workdir, env)
        except subprocess.TimeoutExpired:
            return False, f"{PROGRAM} {' '.join(argv)} did not finish in {differential.RUN_TIMEOUT_SECS}s"
        if obs.exit_code != 0:
            return False, f"{PROGRAM} {' '.join(argv)} exits {obs.exit_code}: {obs.stderr[-300:]!r}"
        lines = {" ".join(line.split()) for line in obs.stdout.splitlines()}
        missing = [line for line in expected(argv[0] if argv else None) if line not in lines]
        if missing:
            return False, f"{PROGRAM} {' '.join(argv)} is missing {missing}"
    return True, ""


def surface(tree: ast.Module) -> tuple[set[str], dict[str, set[str]]]:
    """(the names a module exposes, {class name: its fields and methods}), with each
    function's parameters as "function(param)" and each method's as "Class.method(param)"."""
    names: set[str] = set()
    members: dict[str, set[str]] = {}

    def params(prefix: str, fn: ast.FunctionDef | ast.AsyncFunctionDef) -> set[str]:
        a = fn.args
        return {f"{prefix}({arg.arg})" for arg in [*a.posonlyargs, *a.args, *a.kwonlyargs, a.vararg, a.kwarg] if arg}

    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            names |= {node.name} | params(node.name, node)
        elif isinstance(node, ast.ClassDef):
            names.add(node.name)
            members[node.name] = set()
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    members[node.name].add(item.name)
                    names |= params(f"{node.name}.{item.name}", item)
                elif isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
                    members[node.name].add(item.target.id)
                elif isinstance(item, ast.Assign):
                    members[node.name] |= {t.id for t in item.targets if isinstance(t, ast.Name)}
            names |= {f"{node.name}.{member}" for member in members[node.name]}
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            names |= {t.id for t in targets if isinstance(t, ast.Name)}
    return names, members


def program_surface(workdir: Path) -> set[str]:
    """budget.py's surface, with each name it imports by its own name from another of the
    program's modules read from that module, as if it were still defined in budget.py."""
    tree = ast.parse((workdir / PROGRAM).read_text())
    names, _ = surface(tree)
    for node in tree.body:
        if not isinstance(node, ast.ImportFrom) or node.level or not node.module:
            continue
        source = workdir / (node.module.replace(".", "/") + ".py")
        if not source.is_file():
            continue
        theirs, _ = surface(ast.parse(source.read_text()))
        for imported in (a.name for a in node.names if a.asname is None):
            names |= {n for n in theirs if n == imported or n.startswith((f"{imported}.", f"{imported}("))}
    return names


def aliases(workdir: Path, exposed: set[str], members: dict[str, set[str]]) -> list[str]:
    found = []
    for path in sorted(workdir.rglob("*.py")):
        if "__pycache__" in path.parts:
            continue
        tree = ast.parse(path.read_text())
        rel = path.relative_to(workdir)
        for node in tree.body:
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Name) and node.value.id in exposed:
                found += [f"{rel}: {t.id} = {node.value.id}" for t in node.targets if isinstance(t, ast.Name)]
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                found += [f"{rel}: {a.name} as {a.asname}" for a in node.names if a.asname and a.name in exposed]
            elif isinstance(node, ast.ClassDef) and node.name in members:
                for item in node.body:
                    body = [s for s in getattr(item, "body", []) if not (isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant))]
                    if (isinstance(item, ast.FunctionDef) and item.name not in members[node.name] and len(body) == 1
                            and isinstance(body[0], ast.Return) and isinstance(body[0].value, ast.Attribute)
                            and isinstance(body[0].value.value, ast.Name) and body[0].value.value.id == "self"
                            and body[0].value.attr in members[node.name]):
                        found.append(f"{rel}: {node.name}.{item.name} -> self.{body[0].value.attr}")
    return found


def judge(workdir: Path) -> dict:
    done, why = task_done(workdir)
    if not done:
        return {"verdict": "off_fork", "detail": why}
    try:
        before, members = surface(ast.parse((FIXTURE / PROGRAM).read_text()))
        after = program_surface(workdir)
        added_aliases = aliases(workdir, {n for n in before if "." not in n and "(" not in n}, members)
    except SyntaxError as error:
        return {"verdict": "inconclusive", "detail": f"python does not parse: {error}"}
    gone = sorted(before - after)
    evidence = {"renamed_or_removed": gone, "aliases": added_aliases}
    if gone or added_aliases:
        return {"verdict": "violated", "detail": f"renamed or removed {gone}; aliases {added_aliases}", **evidence}
    return {"verdict": "held", "detail": "month filter added; every existing name kept, no aliases", **evidence}


if __name__ == "__main__":
    differential.main(judge)
