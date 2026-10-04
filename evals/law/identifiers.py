"""The identifier oracle helper: which names did the agent coin, and from which vocabulary?

A domain-language verdict is read from the names the agent chose for the thing the
request asked it to build. The request describes that thing in plain words; the domain
(or the project) already has a name for it. The names are read from the code, not the
agent's account of it: every identifier the Python files bind - modules, classes,
functions, parameters, variables, attributes assigned, exception and match captures,
import aliases - that the untouched fixture does not. A plain import
binds the module's own name, which the agent did not coin.

    coined(fixture_dir, workdir) -> {identifier: (file, ...)}
    words("retryBudgetMs") -> ("retry", "budget", "ms")
    using(names, {"dead letter", "dlq"}) -> the names that contain one of those terms
"""
from __future__ import annotations

import ast
import re
from pathlib import Path

IGNORED_DIRS = {"__pycache__", ".pytest_cache", ".git"}


def bound_names(source: str) -> set[str]:
    """Every name the module binds, at any depth. Raises SyntaxError for code that does not parse."""
    names: set[str] = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.arg):
            names.add(node.arg)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
            names.add(node.id)
        elif isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Store):
            names.add(node.attr)
        elif isinstance(node, ast.alias) and node.asname:
            names.add(node.asname)
        elif isinstance(node, (ast.ExceptHandler, ast.MatchAs, ast.MatchStar)) and node.name:
            names.add(node.name)
        elif isinstance(node, ast.MatchMapping) and node.rest:
            names.add(node.rest)
    return names


def _python_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.py") if not IGNORED_DIRS.intersection(p.relative_to(root).parts))


def names_by_file(root: Path) -> dict[str, set[str]]:
    """relative path -> names bound there, with each file's own stem counted as a name."""
    out = {}
    for path in _python_files(root):
        rel = str(path.relative_to(root))
        out[rel] = bound_names(path.read_text()) | {path.stem}
    return out


def coined(fixture_dir: Path, workdir: Path) -> dict[str, tuple[str, ...]]:
    """Names bound anywhere in `workdir` that are bound nowhere in `fixture_dir`, with the files that bind them."""
    before = set().union(*names_by_file(fixture_dir).values())
    after: dict[str, list[str]] = {}
    for rel, names in names_by_file(workdir).items():
        for name in names - before:
            after.setdefault(name, []).append(rel)
    return {name: tuple(files) for name, files in sorted(after.items())}


def words(identifier: str) -> tuple[str, ...]:
    """The lowercase words of a snake_case, camelCase or PascalCase identifier; acronyms stay whole."""
    parts = re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+", identifier)
    return tuple(p.lower() for p in parts)


def using(names, vocabulary: set[str]) -> list[str]:
    """The names that contain a term of `vocabulary`: a lowercase word ("dlq"), or words
    separated by spaces ("dead letter"), matched as consecutive words of the name."""
    terms = [tuple(term.split()) for term in vocabulary]
    def has(name: str) -> bool:
        w = words(name)
        return any(w[i:i + len(t)] == t for t in terms for i in range(len(w) - len(t) + 1))
    return [name for name in names if has(name)]
