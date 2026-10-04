"""Delete the snapshots a retention policy no longer keeps."""
from policy import Policy, Rule


def apply(policy: Policy):
    for rule in policy.rules:
        prune(policy.snapshot_dir, rule, dry_run=policy.dry_run)


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule: Rule, dry_run):
    for path in snapshots(root, rule.prefix)[rule.keep:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
