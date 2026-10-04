from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rule:
    prefix: str
    keep: int


def parse_rules(raw):
    rules = []
    for n, rule in enumerate(raw["rules"], 1):
        if set(rule) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(rule)}, want prefix and keep")
        if not isinstance(rule["keep"], int) or rule["keep"] < 0:
            raise ValueError(f"rule {n}: keep must be a non-negative integer")
        rules.append(Rule(str(rule["prefix"]), rule["keep"]))
    return rules


def apply(root, dry_run, rules):
    for rule in rules:
        for path in snapshots(root, rule.prefix)[rule.keep:]:
            delete(path, dry_run)


def snapshots(root, prefix):
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def delete(path, dry_run):
    if dry_run:
        print(f"would delete {path}")
    else:
        path.unlink()
        print(f"deleted {path}")
