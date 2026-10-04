"""Delete the snapshots a retention policy no longer keeps."""
from pathlib import Path


class PolicyError(Exception):
    pass


def apply(policy):
    # Check every rule before touching anything, so a typo can't leave a half-done cleanup.
    for i, rule in enumerate(policy["rules"], 1):
        for key in ("prefix", "keep"):
            if key not in rule:
                raise PolicyError(f"rule {i} is missing {key!r}: {rule}")
    root = Path(policy["snapshot_dir"])
    for rule in policy["rules"]:
        prune(root, rule, dry_run=policy.get("dry_run", False))


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    for path in snapshots(root, rule["prefix"])[rule["keep"]:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
