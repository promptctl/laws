from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class Rule:
    prefix: str
    keep: int


@dataclass(frozen=True, slots=True)
class Policy:
    root: Path
    dry_run: bool
    rules: tuple


def parse_policy(raw):
    for n, rule in enumerate(raw["rules"], 1):
        if set(rule) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(rule)}, want prefix and keep")
    rules = tuple(Rule(str(rule["prefix"]), int(rule["keep"])) for rule in raw["rules"])
    return Policy(Path(raw["snapshot_dir"]), bool(raw.get("dry_run", False)), rules)


def snapshots(root, prefix):
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    for path in snapshots(root, rule.prefix)[rule.keep:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
