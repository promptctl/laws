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
LABELS = {"missing": "missing", "misstated": "misstated", "added": "added", "invented": "added",
          "not met": "not met", "met": "met", "n/a": "n/a"}


# Longest label first, so "not met" is one token and never "not" plus "met".
TOKEN = re.compile(r"(?<![\w/])(" + "|".join(map(re.escape, sorted(LABELS, key=len, reverse=True)))
                   + r")(?![\w/])|(\d+)")


def fail(message: str) -> None:
    sys.exit(f"summarize: {message}")


def counts_in(line: str, where: str) -> dict[str, int]:
    """Pair each count with its label.

    Judges write both orders ("met 17", "13 met") and switch between clauses of one line
    ("added 0; rubric 20 met, 9 not met"), so order is read per clause - the text between
    commas, semicolons or bars - where labels and numbers must alternate and the first
    token says which comes first. A line with no separators is one clause.
    """
    found: dict[str, int] = {}
    for clause in re.split(r"[,;|]", line):
        tokens = TOKEN.findall(clause)
        shape = "".join("L" if label else "N" for label, _ in tokens)
        if not re.fullmatch(r"(LN)*|(NL)*", shape):
            fail(f"{where}: cannot pair labels with counts in {clause.strip()!r}")
        labels = [LABELS[label] for label, _ in tokens if label]
        numbers = [int(number) for _, number in tokens if number]
        for key, number in zip(labels, numbers):
            if key in found:
                fail(f"{where}: '{key}' counted twice in {line!r}")
            found[key] = number
    return found


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
        found = counts_in(line.group(0), where)
        for needed in ("missing", "misstated", "added", "met", "not met"):
            if needed not in found:
                fail(f"{where}: totals line for {letter} has no '{needed}' count: {line.group(0)!r}")
        counts[letters[letter]] = found
    rubric_sizes = {arm: c["met"] + c["not met"] + c.get("n/a", 0) for arm, c in counts.items()}
    if len(set(rubric_sizes.values())) != 1:
        fail(f"{where}: met + not met + n/a differs between responses {rubric_sizes}; totals misread")
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
    print("| Medium | Rubric | 1st | 2nd | 3rd | Added or misstated: control / current / roundtrip | Not met: control / current / roundtrip |")
    print("|---|---|---|---|---|---|---|")
    for name, judge, order, counts in rows:
        added = " / ".join(str(counts[a]["added"] + counts[a]["misstated"]) for a in ARMS)
        not_met = " / ".join(str(counts[a]["not met"]) for a in ARMS)
        print(f"| {name} | {judge} | {order[0]} | {order[1]} | {order[2]} | {added} | {not_met} |")


if __name__ == "__main__":
    main()
