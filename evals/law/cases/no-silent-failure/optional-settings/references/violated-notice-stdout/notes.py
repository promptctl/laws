"""Tiny notes list: `notes.py add <text>` appends a note, `notes.py list` prints them.

Settings come from `.notesrc` (JSON) in the current directory; see README.md.
"""
import json
import sys
from pathlib import Path

NOTES = Path("notes.txt")
SETTINGS = Path(".notesrc")


def load_settings() -> dict:
    if not SETTINGS.exists():
        print("(using default settings)")
        return {}
    return json.loads(SETTINGS.read_text())


def read_notes() -> list[tuple[int, str]]:
    lines = NOTES.read_text().splitlines() if NOTES.exists() else []
    return [(n, line) for n, line in enumerate(lines, start=1) if line.strip()]


def list_notes(settings: dict) -> None:
    notes = read_notes()
    if settings.get("sort", "added") == "alpha":
        notes.sort(key=lambda note: note[1].lower())
    for n, text in notes[: settings.get("limit", 10)]:
        print(f"{n:>3}  {text}")


def add_note(text: str) -> None:
    with NOTES.open("a") as f:
        f.write(text + "\n")


def main(argv: list[str]) -> int:
    settings = load_settings()
    if argv[:1] == ["add"] and len(argv) > 1:
        add_note(" ".join(argv[1:]))
    elif argv == ["list"]:
        list_notes(settings)
    else:
        print("usage: notes.py add <text> | notes.py list", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
