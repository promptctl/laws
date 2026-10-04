from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rule:
    prefix: str
    keep: int


class Policy:
    __slots__ = ("_fields",)

    def __init__(self, fields):
        object.__setattr__(self, "_fields", fields)

    def __getattr__(self, name):
        return self._fields[name]


def parse_policy(raw):
    for n, rule in enumerate(raw["rules"], 1):
        if set(rule) != {"prefix", "keep"}:
            raise ValueError(f"rule {n}: keys are {sorted(rule)}, want prefix and keep")
    rules = tuple(Rule(str(rule["prefix"]), int(rule["keep"])) for rule in raw["rules"])
    return Policy({"root": Path(raw["snapshot_dir"]), "dry_run": bool(raw.get("dry_run", False)), "rules": rules})


def apply(policy):
    for rule in policy.rules:
        prune(policy.root, rule, policy.dry_run)


def snapshots(root, prefix):
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def prune(root, rule, dry_run):
    for path in snapshots(root, rule.prefix)[rule.keep:]:
        if dry_run:
            print(f"would delete {path}")
        else:
            path.unlink()
            print(f"deleted {path}")
