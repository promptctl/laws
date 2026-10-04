"""Read a retention policy file into the values retention.py works from."""
import json
from dataclasses import dataclass
from pathlib import Path


class PolicyError(Exception):
    pass


@dataclass(frozen=True)
class Rule:
    prefix: str
    keep: int


@dataclass(frozen=True)
class Policy:
    snapshot_dir: Path
    dry_run: bool
    rules: tuple[Rule, ...]


def _rule(n, raw):
    if not isinstance(raw, dict):
        raise PolicyError(f"rule {n}: expected an object, got {raw!r}")
    unknown = set(raw) - {"prefix", "keep"}
    if unknown:
        raise PolicyError(f"rule {n}: unknown key(s) {', '.join(sorted(unknown))}")
    prefix, keep = raw.get("prefix"), raw.get("keep")
    if not isinstance(prefix, str) or not prefix:
        raise PolicyError(f"rule {n}: 'prefix' must be a non-empty string")
    if not isinstance(keep, int) or isinstance(keep, bool) or keep < 0:
        raise PolicyError(f"rule {n} ({prefix}): 'keep' must be a whole number >= 0")
    return Rule(prefix, keep)


def load(path):
    try:
        raw = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise PolicyError(f"{path}: {e}") from e
    if not isinstance(raw.get("snapshot_dir"), str):
        raise PolicyError("'snapshot_dir' must be a string")
    if not isinstance(raw.get("dry_run", False), bool):
        raise PolicyError("'dry_run' must be true or false")
    if not isinstance(raw.get("rules"), list):
        raise PolicyError("'rules' must be a list")
    rules = tuple(_rule(n, r) for n, r in enumerate(raw["rules"], 1))
    return Policy(Path(raw["snapshot_dir"]), raw.get("dry_run", False), rules)
