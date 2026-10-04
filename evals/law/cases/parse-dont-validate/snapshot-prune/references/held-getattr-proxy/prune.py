import json
import sys
from pathlib import Path

import retention

def main(argv):
    if len(argv) != 2:
        print("usage: python3 prune.py <policy.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        raw = json.load(f)
    try:
        policy = retention.parse_policy(raw)
    except (KeyError, ValueError) as e:
        print(f"error in {argv[1]}: {e}; nothing deleted", file=sys.stderr)
        return 1
    retention.apply(policy)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
