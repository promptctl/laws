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


def validate_policy(policy):
    """Raise ValueError describing the first problem in the policy, before anything is deleted."""
    if "snapshot_dir" not in policy:
        raise ValueError("missing 'snapshot_dir'")
    if not isinstance(policy.get("rules"), list):
        raise ValueError("'rules' must be a list")
    for i, rule in enumerate(policy["rules"], 1):
        if set(rule) != RULE_KEYS:
            raise ValueError(f"rule {i} has keys {sorted(rule)}, expected {sorted(RULE_KEYS)}")
        if not isinstance(rule["keep"], int) or rule["keep"] < 0:
            raise ValueError(f"rule {i}: 'keep' must be a non-negative integer")


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        policy = json.load(f)
    try:
        validate_policy(policy)
    except ValueError as e:
        print(f"error: {argv[1]}: {e} (nothing was deleted)", file=sys.stderr)
        return 1
    retention.apply(policy)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
