#!/usr/bin/env python3
"""Decode every medium's blind verdicts into one Markdown table.

For each medium with a judge key and both verdicts, prints each judge's ranking and
the per-arm fidelity and rubric counts, with letters already decoded to arm names.
Fails loudly if a verdict does not have the sections the judge template requires.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARMS = ("control", "current", "roundtrip")
JUDGES = ("spec", "guidance")
COUNT = re.compile(r"(missing|misstated|added|invented|not met|met|n/a)\D{0,3}(\d+)")


def fail(message: str) -> None:
    sys.exit(f"summarize: {message}")


def parse_key(text: str) -> dict[str, dict[str, str]]:
    keys: dict[str, dict[str, str]] = {}
    current = None
    for line in text.splitlines():
        if m := re.match(r"## judge-(\w+)\.md", line):
            current = keys.setdefault(m.group(1), {})
        elif current is not None and (m := re.match(r"- ([ABC]): (\w+)", line)):
            current[m.group(1)] = m.group(2)
    return keys


def section(text: str, title: str, where: str) -> str:
    m = re.search(rf"^## {title}[^\n]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        fail(f"{where}: no '## {title}' section")
    return m.group(1)


def parse_verdict(text: str, letters: dict[str, str], where: str) -> tuple[list[str], dict[str, dict[str, int]]]:
    order = re.findall(r"^\s*\d+\.\s*\**([ABC])\b", section(text, "Ranking", where), re.M)
    if sorted(order) != ["A", "B", "C"]:
        fail(f"{where}: ranking lists {order}, expected A, B and C once each")
    totals = section(text, "Totals", where)
    counts: dict[str, dict[str, int]] = {}
    for letter in "ABC":
        line = re.search(rf"^\W*{letter}\b.*$", totals, re.M)
        if not line:
            fail(f"{where}: no totals line for {letter}")
        found = {("added" if k == "invented" else k): int(v) for k, v in COUNT.findall(line.group(0))}
        for needed in ("missing", "misstated", "added", "met", "not met"):
            if needed not in found:
                fail(f"{where}: totals line for {letter} has no '{needed}' count: {line.group(0)!r}")
        counts[letters[letter]] = found
    return [letters[l] for l in order], counts


def main() -> None:
    rows = []
    for medium in sorted(p for p in ROOT.iterdir() if (p / "judge-key.md").is_file()):
        keys = parse_key((medium / "judge-key.md").read_text())
        for judge in JUDGES:
            verdict = medium / f"judge-{judge}.md"
            if not verdict.is_file():
                continue
            if sorted(keys.get(judge, {})) != ["A", "B", "C"]:
                fail(f"{medium.name}: judge-key.md has no complete mapping for judge-{judge}")
            order, counts = parse_verdict(verdict.read_text(), keys[judge], f"{medium.name}/judge-{judge}.md")
            rows.append((medium.name, judge, order, counts))
    print("| Medium | Rubric | 1st | 2nd | 3rd | Added: control / current / roundtrip | Not met: control / current / roundtrip |")
    print("|---|---|---|---|---|---|---|")
    for name, judge, order, counts in rows:
        added = " / ".join(str(counts[a]["added"] + counts[a]["misstated"]) for a in ARMS)
        not_met = " / ".join(str(counts[a]["not met"]) for a in ARMS)
        print(f"| {name} | {judge} | {order[0]} | {order[1]} | {order[2]} | {added} | {not_met} |")


if __name__ == "__main__":
    main()
