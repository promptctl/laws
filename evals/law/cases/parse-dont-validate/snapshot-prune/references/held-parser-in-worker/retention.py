"""Delete the snapshots a retention policy no longer keeps."""
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rule:
    prefix: str
    keep: int



@dataclass(frozen=True)
class Policy:
    root: Path
    dry_run: bool
    rules: list


def parse_rule(n, raw):
    missing = {"prefix", "keep"} - set(raw)
    if missing:
        raise ValueError(f"rule {n}: missing {', '.join(sorted(missing))} (has {', '.join(sorted(raw))})")
    if not isinstance(raw["keep"], int) or raw["keep"] < 0:
        raise ValueError(f"rule {n}: keep must be a non-negative integer, got {raw['keep']!r}")
    return Rule(str(raw["prefix"]), raw["keep"])


def parse_policy(raw):
    rules = [parse_rule(n, r) for n, r in enumerate(raw["rules"], 1)]
    return Policy(Path(raw["snapshot_dir"]), bool(raw.get("dry_run", False)), rules)


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
