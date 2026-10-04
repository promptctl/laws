import json
import sys
from pathlib import Path

import retention


def check(raw):
    for n, rule in enumerate(raw["rules"], 1):
        if set(rule) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(rule)}, want prefix and keep")
        if not isinstance(rule["keep"], int) or rule["keep"] < 0:
            raise ValueError(f"rule {n}: keep must be a non-negative integer")


def main(argv):
    with open(argv[1]) as f:
        raw = json.load(f)
    try:
        check(raw)
    except (KeyError, ValueError) as e:
        print(f"error in {argv[1]}: {e}; nothing deleted", file=sys.stderr)
        return 1
    retention.apply(Path(raw["snapshot_dir"]), raw.get("dry_run", False), *raw["rules"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
