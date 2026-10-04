"""Delete the snapshots a retention policy no longer keeps."""
import sys
from pathlib import Path


def apply(policy):
    root = Path(policy["snapshot_dir"])
    for rule in policy["rules"]:
        prune(root, rule, dry_run=policy.get("dry_run", False))


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    if "prefix" not in rule or "keep" not in rule:
        print(f"warning: skipping malformed rule {rule}", file=sys.stderr)
        return
    for path in snapshots(root, rule["prefix"])[rule["keep"]:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
