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
        policy = json.load(f)
    problems = retention.problems(policy["rules"])
    if problems:
        print(f"error in {argv[1]}: {'; '.join(problems)}; nothing deleted", file=sys.stderr)
        return 1
    retention.apply(policy["snapshot_dir"], policy["rules"], bool(policy.get("dry_run", False)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
