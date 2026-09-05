#!/usr/bin/env python3
"""Fetch every pull request in a GitHub org, with its reviews, review threads,
thread comments, issue comments, commits and files, into one JSON file per PR.

Re-runnable and deterministic: a PR is re-fetched only when GitHub's `updatedAt`
differs from the cached copy, and the file content is a pure function of the PR's
GitHub state (sorted keys, explicit node ordering, no fetch timestamps).

    review-audit/fetch.py --org promptctl --out review-audit/data [--refresh] [--repo NAME ...]

Requires an authenticated `gh` (the only effect in this module is the `gh api
graphql` shell-out). Any GraphQL error, null on a requested path, or pagination
contradiction aborts loudly - the cache makes resuming free.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# The one effect: a GraphQL call through gh.  [LAW:effects-at-boundaries]
# ---------------------------------------------------------------------------


def graphql(query: str, **variables: object) -> dict:
    """One GraphQL shell-out. [LAW:single-enforcer]

    [LAW:dataflow-not-control-flow] the variable's Python type picks the flag: `gh -F`
    type-infers its value (an all-digit cursor or node id would become a number),
    so strings go through `-f` and ints through `-F`. A None cursor is omitted, not
    sent empty - an undeclared nullable variable is null to GraphQL, whereas
    `-f cursor=` is the empty string, which is not a valid cursor.
    """
    args = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        if value is None:
            continue
        args += ["-F" if isinstance(value, int) else "-f", f"{key}={value}"]
    proc = subprocess.run(args, text=True, capture_output=True)
    if proc.returncode != 0:  # [LAW:no-silent-failure]
        raise RuntimeError(f"gh api graphql failed ({proc.returncode}):\n{proc.stderr}\n{proc.stdout}")
    data = json.loads(proc.stdout)
    if data.get("errors"):
        raise RuntimeError(f"GraphQL errors for variables {variables!r}:\n{json.dumps(data['errors'], indent=1)}")
    return data


def path_of(data: object, *path: str, subject: str) -> dict:
    """Walk the response path a query asked for, or name the field that failed.

    [LAW:parse-dont-validate] every null along the path comes back with HTTP 200;
    this is the one place that turns "missing or inaccessible" into an error instead
    of a `NoneType` crash somewhere downstream. [LAW:no-silent-failure]
    """
    node = data
    for depth, field in enumerate(path):
        child = node.get(field) if isinstance(node, dict) else None
        if child is None:
            raise RuntimeError(
                f"GraphQL response for {subject} has no {'.'.join(path[:depth + 1])} "
                f"(querying {'.'.join(path)}) - that object is missing or inaccessible, not empty."
            )
        node = child
    return node


def next_cursor(block: dict, *, subject: str) -> str | None:
    """The cursor naming the page after this one, or None when this page is last.

    [LAW:no-silent-failure] `hasNextPage` true with no `endCursor` is a contradiction:
    another page is promised and nothing names it. Looping on a null cursor would
    re-read page one forever; stopping would return a partial set as if whole.
    """
    info = block["pageInfo"]
    if not info["hasNextPage"]:
        return None
    cursor = info.get("endCursor")
    if not cursor:
        raise RuntimeError(f"pagination for {subject} promised another page but named no endCursor")
    return cursor


# ---------------------------------------------------------------------------
# Query text.  Selections are data: one table drives both the first-page fetch
# and the generic overflow drain.  [LAW:one-source-of-truth]
# ---------------------------------------------------------------------------

PAGE = "pageInfo{ hasNextPage endCursor } totalCount"

COMMENT_SEL = (
    "{ id databaseId author{ login } body createdAt updatedAt outdated "
    "commit{ oid } originalCommit{ oid } replyTo{ id } pullRequestReview{ id } "
    "path line originalLine diffHunk }"
)

THREAD_SEL = (
    "{ id isResolved isOutdated isCollapsed path line originalLine startLine "
    "originalStartLine diffSide subjectType resolvedBy{ login } "
    f"comments(first:10){{ {PAGE} nodes {COMMENT_SEL} }} }}"
)

# name -> (owning GraphQL type, field, node selection, first-page size)
CONNECTIONS: dict[str, tuple[str, str, str, int]] = {
    "commits": (
        "PullRequest", "commits",
        "{ commit{ oid committedDate authoredDate messageHeadline messageBody "
        "author{ name email user{ login } } } }",
        100,
    ),
    "reviews": (
        "PullRequest", "reviews",
        "{ id databaseId author{ login } state body submittedAt commit{ oid } comments{ totalCount } }",
        50,
    ),
    "reviewThreads": ("PullRequest", "reviewThreads", THREAD_SEL, 100),
    "comments": ("PullRequest", "comments", "{ id databaseId author{ login } body createdAt updatedAt }", 30),
    "files": ("PullRequest", "files", "{ path additions deletions changeType }", 100),
    "threadComments": ("PullRequestReviewThread", "comments", COMMENT_SEL, 100),
}

PR_SCALARS = (
    "id number title body url state isDraft merged author{ login } createdAt updatedAt "
    "mergedAt closedAt headRefName baseRefName headRefOid additions deletions "
    "changedFiles reviewDecision mergeCommit{ oid } mergedBy{ login }"
)


def first_page(name: str) -> str:
    _, field, sel, first = CONNECTIONS[name]
    return f"{field}(first:{first}){{ {PAGE} nodes {sel} }}"


PR_QUERY = (
    "query($owner:String!,$repo:String!,$num:Int!){ repository(owner:$owner,name:$repo){ "
    f"pullRequest(number:$num){{ {PR_SCALARS} "
    + " ".join(first_page(n) for n in CONNECTIONS if CONNECTIONS[n][0] == "PullRequest")
    + " } } }"
)


def drain_query(name: str) -> str:
    typename, field, sel, _ = CONNECTIONS[name]
    return (
        f"query($id:ID!,$cursor:String){{ node(id:$id){{ ... on {typename} {{ "
        f"{field}(first:100,after:$cursor){{ {PAGE} nodes {sel} }} }} }} }}"
    )


REPOS_QUERY = (
    "query($org:String!,$cursor:String){ organization(login:$org){ "
    "repositories(first:100,after:$cursor,orderBy:{field:NAME,direction:ASC}){ "
    f"{PAGE} nodes{{ name isArchived isFork pullRequests{{ totalCount }} }} }} }} }}"
)

PR_LIST_QUERY = (
    "query($owner:String!,$repo:String!,$cursor:String){ repository(owner:$owner,name:$repo){ "
    "pullRequests(first:100,after:$cursor,orderBy:{field:CREATED_AT,direction:ASC}){ "
    f"{PAGE} nodes{{ number updatedAt }} }} }} }}"
)


# ---------------------------------------------------------------------------
# Paging.  One drain for every connection; the table says what to drain.
# ---------------------------------------------------------------------------


def drain(name: str, node_id: str, block: dict, *, subject: str) -> list[dict]:
    """The complete node list of one connection, starting from its fetched first page."""
    nodes = list(block["nodes"])
    cursor = next_cursor(block, subject=subject)
    field = CONNECTIONS[name][1]
    while cursor is not None:
        page = path_of(graphql(drain_query(name), id=node_id, cursor=cursor), "data", "node", field, subject=subject)
        nodes.extend(page["nodes"])
        cursor = next_cursor(page, subject=subject)
    if len(nodes) != block["totalCount"]:  # [LAW:no-silent-failure]
        raise RuntimeError(f"{subject}: drained {len(nodes)} nodes but totalCount is {block['totalCount']}")
    return nodes


def paged(query: str, path: tuple[str, ...], *, subject: str, **variables: object) -> list[dict]:
    """Every node of a top-level paged query (repos of an org, PRs of a repo)."""
    nodes: list[dict] = []
    cursor: str | None = None
    while True:
        block = path_of(graphql(query, cursor=cursor, **variables), *path, subject=subject)
        nodes.extend(block["nodes"])
        cursor = next_cursor(block, subject=subject)
        if cursor is None:
            return nodes


def fetch_pr(owner: str, repo: str, number: int) -> dict:
    """One PR with every connection fully drained. Node order is by creation,
    which GitHub returns stably; the sort below pins it in case it does not."""
    subject = f"{owner}/{repo}#{number}"
    pr = path_of(graphql(PR_QUERY, owner=owner, repo=repo, num=number), "data", "repository", "pullRequest", subject=subject)
    for name, (typename, field, _, _) in CONNECTIONS.items():
        if typename != "PullRequest":
            continue
        pr[field] = drain(name, pr["id"], pr[field], subject=f"{subject}.{field}")
    for thread in pr["reviewThreads"]:
        thread["comments"] = drain("threadComments", thread["id"], thread["comments"], subject=f"{subject} thread {thread['id']}")
        thread["comments"].sort(key=lambda c: (c["createdAt"], c["id"]))
    pr["commits"].sort(key=lambda c: (c["commit"]["committedDate"], c["commit"]["oid"]))
    pr["reviews"].sort(key=lambda r: (r["submittedAt"] or "", r["id"]))
    pr["reviewThreads"].sort(key=lambda t: (t["comments"][0]["createdAt"] if t["comments"] else "", t["id"]))
    pr["comments"].sort(key=lambda c: (c["createdAt"], c["id"]))
    pr["files"].sort(key=lambda f: f["path"])
    return pr


# ---------------------------------------------------------------------------
# Cache on disk: data/<repo>/<number>.json, keyed on updatedAt.
# ---------------------------------------------------------------------------


def cached_updated_at(path: Path) -> str | None:
    if not path.exists():
        return None
    return json.loads(path.read_text())["updatedAt"]


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--org", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--repo", action="append", help="limit to these repos (repeatable); default is every repo in the org")
    ap.add_argument("--refresh", action="store_true", help="re-fetch every PR even when updatedAt is unchanged")
    args = ap.parse_args(argv)

    repos = paged(REPOS_QUERY, ("data", "organization", "repositories"), subject=f"repos of {args.org}", org=args.org)
    if args.repo:
        wanted = set(args.repo)
        missing = wanted - {r["name"] for r in repos}
        if missing:
            raise SystemExit(f"repos not in {args.org}: {sorted(missing)}")
        repos = [r for r in repos if r["name"] in wanted]

    inventory = []
    for repo in repos:
        name = repo["name"]
        prs = paged(PR_LIST_QUERY, ("data", "repository", "pullRequests"), subject=f"PRs of {args.org}/{name}", owner=args.org, repo=name)
        if len(prs) != repo["pullRequests"]["totalCount"]:
            raise RuntimeError(f"{name}: listed {len(prs)} PRs but totalCount is {repo['pullRequests']['totalCount']}")
        fetched = 0
        for pr in prs:
            path = args.out / name / f"{pr['number']}.json"
            if not args.refresh and cached_updated_at(path) == pr["updatedAt"]:
                continue
            write_json(path, fetch_pr(args.org, name, pr["number"]))
            fetched += 1
        inventory.append({"repo": name, "prs": len(prs), "isArchived": repo["isArchived"], "isFork": repo["isFork"]})
        print(f"{name}: {len(prs)} PRs, {fetched} fetched", file=sys.stderr)

    write_json(args.out / "inventory.json", inventory)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
