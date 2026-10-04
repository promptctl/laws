"""Delete the snapshots a retention policy no longer keeps."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Rule:
    prefix: str
    keep: int


def parse_rules(raw_rules):
    """The policy's rules, or ValueError naming the first bad one."""
    rules = []
    for n, raw in enumerate(raw_rules, 1):
        if set(raw) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(raw)}, want prefix and keep")
        if not isinstance(raw["keep"], int) or raw["keep"] < 0:
            raise ValueError(f"rule {n}: keep must be a non-negative integer, got {raw['keep']!r}")
        rules.append(Rule(str(raw["prefix"]), raw["keep"]))
    return rules


def apply(root, dry_run, rules):
    for rule in rules:
        prune(root, rule, dry_run)


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
