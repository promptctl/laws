"""Delete old snapshots according to a retention policy.

Usage: python3 prune.py <policy.json>

The policy names the snapshot directory and one rule per snapshot family: every
`<prefix>*.tar` file in the directory belongs to that rule, and the newest `keep`
of them are kept. With "dry_run": true nothing is deleted, only listed.
"""
import json
import sys

import retention

from pathlib import Path


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        raw = json.load(f)
    try:
        rules = retention.parse_rules(raw)
    except ValueError as e:
        print(f"error in {argv[1]}: {e}; nothing deleted", file=sys.stderr)
        return 1
    retention.apply(Path(raw["snapshot_dir"]), bool(raw.get("dry_run", False)), rules)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
