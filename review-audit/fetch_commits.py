#!/usr/bin/env python3
"""Add to every commit of every fetched PR the line ranges it changed, per file, so
shape.py can tell a finding on code changed during review from a finding the
reviewer merely reached late.

    review-audit/fetch_commits.py --data review-audit/data [--workers 3]

For each `data/<repo>/<number>.json` whose PR has at least one review thread, each
commit lacking a `changes` key gets one: `{path: [[new_start, new_len], ...]}` parsed
from the hunk headers of GitHub's per-commit patch (REST; GraphQL has no patches).
A file GitHub returns without a patch (binary, rename-only, too large) gets `[]`.
Idempotent: a commit that already carries `changes` is not refetched.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.M)


def ranges(patch: str) -> list[list[int]]:
    """New-side (start, length) of every hunk in a unified-diff patch. Pure."""
    return [[int(s), int(n) if n else 1] for s, n in HUNK.findall(patch)]


def commit_changes(owner: str, repo: str, sha: str) -> dict[str, list[list[int]]]:
    """The one effect: GET the commit and keep only what shape.py needs.
    [LAW:effects-at-boundaries] [LAW:no-silent-failure] any gh failure raises."""
    proc = subprocess.run(["gh", "api", f"repos/{owner}/{repo}/commits/{sha}"], text=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh api commits/{sha} in {owner}/{repo} failed ({proc.returncode}):\n{proc.stderr}")
    data = json.loads(proc.stdout)
    if "files" not in data:
        raise RuntimeError(f"{owner}/{repo}@{sha}: response has no files: {json.dumps(data)[:300]}")
    return {f["filename"]: ranges(f.get("patch", "")) for f in data["files"]}


def fill(path: Path, owner: str) -> int:
    """Fetch changes for every commit of one PR file that lacks them; returns how many."""
    pr = json.loads(path.read_text())
    if not pr["reviewThreads"]:
        return 0
    repo = path.parent.name
    todo = [c for c in pr["commits"] if "changes" not in c]
    for c in todo:
        c["changes"] = commit_changes(owner, repo, c["commit"]["oid"])
    if todo:
        path.write_text(json.dumps(pr, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
    return len(todo)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, required=True)
    ap.add_argument("--org", default="promptctl")
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args(argv)

    paths = sorted(args.data.glob("*/*.json"))
    if not paths:  # [LAW:no-silent-failure]
        raise SystemExit(f"no PR files under {args.data}")
    total = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for path, n in zip(paths, pool.map(lambda p: fill(p, args.org), paths)):
            total += n
            if n:
                print(f"{path.parent.name}/{path.stem}: {n} commits", file=sys.stderr)
    print(f"{total} commits fetched", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
