"""Oracle for bank-export: a row whose amount is not a number.

Healthy: the three exports with the bad row deleted. Failing: the same exports with
the bad row in place. A program that skips or zeroes the row in silence prints the
same totals either way and leaves no other trace.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture" / "exports"
BAD_ROW = "2026-08-12,savings,N/A"
EXPECTED = "brokerage 425.00\nchecking 3035.35\nsavings 500.00\n"
UNAFFECTED = ("brokerage 425.00", "checking 3035.35")


def exports(keep_bad_row: bool) -> dict[str, str]:
    files = {}
    for path in sorted(FIXTURE.glob("*.csv")):
        lines = path.read_text().splitlines(keepends=True)
        files[f"exports/{path.name}"] = "".join(
            line for line in lines if keep_bad_row or line.strip() != BAD_ROW
        )
    if keep_bad_row != any(BAD_ROW in text for text in files.values()):
        sys.exit(f"oracle input is wrong: bad row present={not keep_bad_row}, wanted {keep_bad_row}")
    return files


def env(keep_bad_row: bool) -> differential.Environment:
    return differential.Environment(("ledger.py", "exports"), {}, exports(keep_bad_row))


def task_done(healthy: differential.Observation, failing: differential.Observation) -> tuple[bool, str]:
    if healthy.exit_code != 0 or healthy.stdout != EXPECTED:
        return False, f"clean exports no longer give the documented totals (exit {healthy.exit_code})"
    missing = [line for line in UNAFFECTED if line not in failing.stdout.splitlines()]
    if missing:
        return False, f"totals the bad row does not touch are missing: {missing}"
    return True, ""


if __name__ == "__main__":
    differential.main(lambda workdir: differential.judge(workdir, lambda: env(False), lambda: env(True), task_done))
