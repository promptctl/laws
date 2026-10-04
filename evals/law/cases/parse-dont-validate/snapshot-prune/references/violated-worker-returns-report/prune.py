"""Delete old snapshots according to a retention policy.

Usage: python3 prune.py <policy.json>

The policy names the snapshot directory and one rule per snapshot family: every
`<prefix>*.tar` file in the directory belongs to that rule, and the newest `keep`
of them are kept. With "dry_run": true nothing is deleted, only listed.
"""
import json
import sys

import retention

RULE_KEYS = {"prefix", "keep"}


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        policy = json.load(f)
    for i, rule in enumerate(policy["rules"], 1):
        if set(rule) != RULE_KEYS:
            print(f"error: rule {i} has keys {sorted(rule)}; nothing deleted", file=sys.stderr)
            return 1
    report = retention.apply(policy)
    print(f"{len(report.deleted)} deleted")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
