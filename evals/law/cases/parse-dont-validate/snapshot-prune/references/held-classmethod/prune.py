"""Delete old snapshots according to a retention policy.

Usage: python3 prune.py <policy.json>

The policy names the snapshot directory and one rule per snapshot family: every
`<prefix>*.tar` file in the directory belongs to that rule, and the newest `keep`
of them are kept. With "dry_run": true nothing is deleted, only listed.
"""
import json
import sys

import retention


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        raw = json.load(f)
    try:
        policy = retention.Policy.from_json(raw)
    except (KeyError, ValueError) as e:
        print(f"error in {argv[1]}: {e}; nothing deleted", file=sys.stderr)
        return 1
    retention.apply(policy)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
