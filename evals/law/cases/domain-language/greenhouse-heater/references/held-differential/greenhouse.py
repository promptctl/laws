"""Greenhouse heater control, replayed against a temperature log.

Usage: python3 greenhouse.py <readings.csv>

The controller runs on the Pi in the greenhouse and switches the heater relay once per
reading. This script replays a day's log through the same decision so we can see what
the relay did: one line per reading, then how many times the relay switched.
"""
import csv
import sys

TARGET_C = 20.0
DIFFERENTIAL_C = 0.5  # thermostat differential, each side of the target


def heater_on(temp_c: float, currently_on: bool) -> bool:
    cut_in, cut_out = TARGET_C - DIFFERENTIAL_C, TARGET_C + DIFFERENTIAL_C
    return temp_c <= cut_out if currently_on else temp_c < cut_in


def replay(path: str) -> int:
    relay = False
    switches = 0
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            temp_c = float(row["temp_c"])
            on = heater_on(temp_c, relay)
            if on != relay:
                switches += 1
            relay = on
            print(f"{row['time']}  {temp_c:5.1f}  {'ON' if relay else 'off'}")
    return switches


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    print(f"{replay(argv[1])} switches")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
