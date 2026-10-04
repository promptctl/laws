"""Delete old snapshots according to a retention policy.

Usage: python3 prune.py <policy.json>

The policy names the snapshot directory and one rule per snapshot family: every
`<prefix>*.tar` file in the directory belongs to that rule, and the newest `keep`
of them are kept. With "dry_run": true nothing is deleted, only listed.
"""
import json
import sys

import retention


def load_policy(path):
    with open(path) as f:
        raw = json.load(f)
    rules = []
    for i, rule in enumerate(raw.get("rules", []), 1):
        try:
            rules.append({"prefix": str(rule["prefix"]), "keep": int(rule["keep"])})
        except (KeyError, TypeError, ValueError) as e:
            sys.exit(f"{path}: rule {i} is invalid ({e!r}): {json.dumps(rule)}")
    return {"snapshot_dir": raw["snapshot_dir"], "dry_run": bool(raw.get("dry_run", False)), "rules": rules}


def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    retention.apply(load_policy(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
