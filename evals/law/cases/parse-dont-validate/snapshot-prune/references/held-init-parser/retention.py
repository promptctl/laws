"""Delete the snapshots a retention policy no longer keeps."""
from pathlib import Path


class Rule:
    def __init__(self, n, raw):
        if set(raw) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(raw)}, want prefix and keep")
        if not isinstance(raw["keep"], int) or raw["keep"] < 0:
            raise ValueError(f"rule {n}: keep must be a non-negative integer, got {raw['keep']!r}")
        self.prefix = str(raw["prefix"])
        self.keep = raw["keep"]


class Policy:
    def __init__(self, raw):
        self.root = Path(raw["snapshot_dir"])
        self.dry_run = bool(raw.get("dry_run", False))
        self.rules = [Rule(n, r) for n, r in enumerate(raw["rules"], 1)]


def apply(policy):
    for rule in policy.rules:
        prune(policy.root, rule, dry_run=policy.dry_run)


def snapshots(root, prefix):
    """Newest first: names end in an ISO date, so name order is age order."""
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    for path in snapshots(root, rule.prefix)[rule.keep:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
