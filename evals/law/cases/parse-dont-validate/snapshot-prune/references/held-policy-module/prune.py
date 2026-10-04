"""Delete old snapshots according to a retention policy.

Usage: python3 prune.py <policy.json>

The policy names the snapshot directory and one rule per snapshot family: every
`<prefix>*.tar` file in the directory belongs to that rule, and the newest `keep`
of them are kept. With "dry_run": true nothing is deleted, only listed.
"""
import sys

import policy
import retention


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    try:
        loaded = policy.load(argv[1])
    except policy.PolicyError as e:
        print(f"prune: bad policy, nothing deleted: {e}", file=sys.stderr)
        return 1
    retention.apply(loaded)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
