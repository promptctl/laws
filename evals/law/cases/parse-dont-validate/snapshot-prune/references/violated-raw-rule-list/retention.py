"""Delete the snapshots a retention policy no longer keeps."""
from pathlib import Path


def problems(rules):
    return [f"rule {n}: keys are {sorted(rule)}, want prefix and keep"
            for n, rule in enumerate(rules, 1) if set(rule) != {"prefix", "keep"}]


def apply(snapshot_dir, rules, dry_run):
    root = Path(snapshot_dir)
    for rule in rules:
        for path in snapshots(root, rule["prefix"])[rule["keep"]:]:
            if dry_run:
                print(f"would delete {path}")
            else:
                path.unlink()
                print(f"deleted {path}")


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)
