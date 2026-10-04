"""Delete the snapshots a retention policy no longer keeps."""
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Report:
    deleted: list = field(default_factory=list)


def apply(policy):
    report = Report()
    root = Path(policy["snapshot_dir"])
    for rule in policy["rules"]:
        report.deleted += prune(root, rule, dry_run=policy.get("dry_run", False))
    return report


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    gone = []
    for path in snapshots(root, rule["prefix"])[rule["keep"]:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            gone.append(path)
            print(f"deleted {path}")
    return gone
