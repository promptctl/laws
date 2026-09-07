#!/usr/bin/env python3
"""Add to every commit of every fetched PR the diff it made, per file, so a packet
carries what judging a finding raised on a fix requires and no reviewing agent has to
reach back to GitHub for it.

    review-audit/fetch_commits.py --data review-audit/data [--workers 3]

For each `data/<repo>/<number>.json` whose PR has at least one review thread, each
commit lacking a `files` key gets one: `{path: {"ranges": [[new_start, new_len], ...],
"patch": "<unified diff>"}}`, from GitHub's per-commit patch (REST; GraphQL has no
patches). A file GitHub returns without a patch (binary, rename-only, too large) gets
an empty patch and no ranges. Idempotent: a commit that already carries `files` is not
refetched.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from fetch import write_json  # [LAW:one-source-of-truth] one on-disk format, one writer

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.M)


def ranges(patch: str) -> list[list[int]]:
    """New-side (start, length) of every hunk in a unified-diff patch. Pure."""
    return [[int(s), int(n) if n else 1] for s, n in HUNK.findall(patch)]


def file_change(patch: str) -> dict:
    """One file's change: the diff itself, and the new-side hunk ranges derived from it."""
    return {"ranges": ranges(patch), "patch": patch}


def commit_files(owner: str, repo: str, sha: str) -> dict[str, dict]:
    """The one effect: GET the commit and keep the diff it made, per file.

    [LAW:effects-at-boundaries] [LAW:no-silent-failure] any gh failure raises.
    [LAW:one-source-of-truth] the patch text is kept and not just the ranges derived
    from it, because the agent judging a finding raised on this commit has to read the
    change. Deriving it live, per agent per run, is the same fact fetched from a second
    place - and one that can answer differently tomorrow.
    """
    proc = subprocess.run(["gh", "api", f"repos/{owner}/{repo}/commits/{sha}"], text=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh api commits/{sha} in {owner}/{repo} failed ({proc.returncode}):\n{proc.stderr}")
    data = json.loads(proc.stdout)
    if "files" not in data:
        raise RuntimeError(f"{owner}/{repo}@{sha}: response has no files: {json.dumps(data)[:300]}")
    return {f["filename"]: file_change(f.get("patch", "")) for f in data["files"]}


def fill(path: Path, owner: str) -> int:
    """Fetch changes for every commit of one PR file that lacks them; returns how many."""
    pr = json.loads(path.read_text())
    if not pr["reviewThreads"]:
        return 0
    repo = path.parent.name
    todo = [c for c in pr["commits"] if "files" not in c]
    for c in todo:
        c.pop("changes", None)  # the ranges-only key this replaced; no reader ever had it
        c["files"] = commit_files(owner, repo, c["commit"]["oid"])
    if todo:
        write_json(path, pr)
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
