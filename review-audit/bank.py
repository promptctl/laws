#!/usr/bin/env python3
"""Fill and check the review-audit data bank. Deterministic, idempotent, resumable.

    review-audit/bank.py sync   --org promptctl --bank review-audit/data [--repo NAME ...] [--refresh]
    review-audit/bank.py verify --bank review-audit/data
    review-audit/bank.py import --bank review-audit/data --from review-audit/data-old

`sync` asks GitHub what exists, compares it against the bank's manifest, and fetches only
the difference: a pull request whose `updatedAt` has moved since it was stored, and any
commit the bank has never seen. Running it twice in a row costs one cheap listing pass and
writes nothing. Running it after a kill picks up exactly where it stopped, because every
object lands through a rename and the manifest is written as the run goes.

The listing pass is the price of finding new work: roughly one call per hundred pull
requests per repository, whatever the bank already holds. Everything after it is new data
only. [LAW:no-silent-failure] any GitHub error aborts the run rather than banking a
partial object; nothing already stored is lost.

`updatedAt` is the freshness contract, and it is GitHub's, not ours: a change GitHub does
not reflect there will not be noticed. `--refresh` is the escape hatch.
"""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Iterator, Sequence, TypeVar

import github
from store import Bank, Ref, commit_ref, pr_ref

CHUNK = 60  # objects fetched in parallel before they are handed to the bank

T = TypeVar("T")


def chunks(items: Sequence[T], size: int) -> Iterator[Sequence[T]]:
    """Fixed-size slices. The fetch fans out over a chunk; the bank takes the results one
    at a time on this thread, so the store stays single-writer and needs no lock."""
    for start in range(0, len(items), size):
        yield items[start:start + size]


def commit_oids(pr: dict) -> list[str]:
    """The commits whose diffs the bank stores for one pull request: all of them when the
    PR was reviewed, none otherwise.

    This is a scope rule about which pull requests are in the corpus - one nobody reviewed
    has no finding to judge, so its diffs would be bytes the audit never opens. It is not
    a judgment about which commits matter; that judgment is shape.py's and stays there,
    where the finding flags live. [LAW:one-source-of-truth]
    """
    return sorted({c["commit"]["oid"] for c in pr["commits"]}) if pr["reviewThreads"] else []


def sync(args: argparse.Namespace) -> int:
    bank = Bank(args.bank)
    try:
        repos = github.repositories(args.org)
        if args.repo:
            missing = set(args.repo) - {r["name"] for r in repos}
            if missing:  # [LAW:parse-dont-validate] every named repo resolves before any fetch
                raise SystemExit(f"repos not in {args.org}: {sorted(missing)}")
            repos = [r for r in repos if r["name"] in set(args.repo)]

        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for repo in repos:
                name = repo["name"]
                listed = github.pull_request_versions(args.org, name, total=repo["pullRequests"]["totalCount"])
                stale = [
                    pr["number"] for pr in listed
                    if args.refresh or bank.version_of(pr_ref(name, pr["number"])) != pr["updatedAt"]
                ]
                for chunk in chunks(stale, CHUNK):
                    fetched = pool.map(lambda n, r=name: github.pull_request(args.org, r, n), chunk)
                    for number, pr in zip(chunk, fetched):
                        # the version is what we actually stored, not what the listing
                        # promised: a PR that moved mid-run is then stale again next time
                        bank.put(pr_ref(name, number), pr, pr["updatedAt"])
                    bank.flush()
                bank.flush()
                print(f"{name}: {len(listed)} PRs listed, {len(stale)} fetched", file=sys.stderr)

            # dict.fromkeys, not a set: two PRs can carry the same commit, and fetching
            # it twice is the one thing this whole design exists to prevent
            wanted: list[Ref] = []
            scope = {r["name"] for r in repos}  # --repo scopes the whole run, not just the PR pass
            for ref in bank.refs("prs"):
                if ref.repo in scope:
                    wanted += [commit_ref(ref.repo, oid) for oid in commit_oids(bank.get(ref))]
            wanted = list(dict.fromkeys(wanted))
            absent = [r for r in wanted if bank.version_of(r) is None]
            print(f"commits: {len(wanted)} referenced, {len(absent)} to fetch", file=sys.stderr)
            for n, chunk in enumerate(chunks(absent, CHUNK), 1):
                fetched = pool.map(lambda r: github.commit(args.org, r.repo, r.name), chunk)
                for ref, files in zip(chunk, fetched):
                    bank.put(ref, files, ref.name)  # a commit's version is its own oid
                bank.flush()  # a SIGKILL now strands at most one chunk as orphans
                print(f"  {min(n * CHUNK, len(absent))}/{len(absent)}", file=sys.stderr)
    finally:
        bank.flush()
    return 0


def verify(args: argparse.Namespace) -> int:
    """Is the bank intact and complete, without asking GitHub anything?"""
    bank = Bank(args.bank)
    problems = bank.integrity()

    # [LAW:no-silent-failure] intact bytes are not a whole corpus: a run killed during the
    # commit pass leaves pull requests whose diffs were never fetched, and every table
    # built on top would quietly under-report rather than fail.
    for ref in bank.refs("prs"):
        for oid in commit_oids(bank.get(ref)):
            if bank.version_of(commit_ref(ref.repo, oid)) is None:
                problems.append(f"{ref.key}: commit {oid[:12]} referenced but not stored - run sync")

    prs = sum(1 for _ in bank.refs("prs"))
    commits = sum(1 for _ in bank.refs("commits"))
    for line in problems[:40]:
        print(line)
    if len(problems) > 40:
        print(f"... and {len(problems) - 40} more")
    print(f"\n{prs} PRs, {commits} commits, {len(problems)} problems", file=sys.stderr)
    return 1 if problems else 0


def do_import(args: argparse.Namespace) -> int:
    """Adopt an existing `<dir>/<repo>/<number>.json` tree written by the old fetch.py.

    The payloads are already exactly what github.pull_request returns, plus a dead
    `changes` key an earlier commit-fetcher merged into each commit. Stripping it makes an
    imported object byte-identical to a freshly fetched one, which is what lets the hash
    in the manifest mean anything. Idempotent: re-importing rewrites the same bytes.
    """
    bank = Bank(args.bank)
    try:
        sources = sorted(args.source.glob("*/*.json"))
        if not sources:  # [LAW:no-silent-failure]
            raise SystemExit(f"no <repo>/<number>.json files under {args.source}")
        for path in sources:
            pr = json.loads(path.read_text())
            for commit in pr["commits"]:
                commit.pop("changes", None)
                commit.pop("files", None)  # commits live in their own store now
            bank.put(pr_ref(path.parent.name, pr["number"]), pr, pr["updatedAt"])
        print(f"imported {len(sources)} PRs from {args.source}", file=sys.stderr)
    finally:
        bank.flush()
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bank", type=Path, default=Path("review-audit/data"))
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("sync", help="fetch what GitHub has and the bank does not")
    s.add_argument("--org", required=True)
    s.add_argument("--repo", action="append", help="limit to these repos (repeatable)")
    s.add_argument("--refresh", action="store_true", help="re-fetch every PR even when updatedAt is unchanged")
    s.add_argument("--workers", type=int, default=3)
    s.set_defaults(run=sync)

    v = sub.add_parser("verify", help="check the bank against its manifest, offline")
    v.set_defaults(run=verify)

    i = sub.add_parser("import", help="adopt an old fetch.py data directory")
    i.add_argument("--from", dest="source", type=Path, required=True)
    i.set_defaults(run=do_import)

    args = ap.parse_args(argv)
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
