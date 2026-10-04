from pathlib import Path


def apply(jobs, dry_run):
    for root, rule in jobs:
        for path in snapshots(root, rule["prefix"])[rule["keep"]:]:
            delete(path, dry_run)


def snapshots(root, prefix):
    return sorted(root.glob(f"{prefix}*.tar"), reverse=True)


def delete(path, dry_run):
    if dry_run:
        print(f"would delete {path}")
    else:
        path.unlink()
        print(f"deleted {path}")
