#!/usr/bin/env python3
"""Everything that talks to GitHub, and nothing that talks to disk.

Every function here is an effect at the system's edge [LAW:effects-at-boundaries]: it
shells out to an authenticated `gh` and returns plain data. Any GraphQL error, any null
on a path the query asked for, and any pagination contradiction aborts loudly - the bank
makes resuming free, so there is never a reason to return a partial answer as if it were
whole. [LAW:no-silent-failure]

The returned objects are ordered deterministically here rather than at the storage layer,
so the same GitHub state always produces the same bytes downstream.
"""

from __future__ import annotations

import json
import re
import subprocess

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.M)


def graphql(query: str, **variables: object) -> dict:
    """One GraphQL shell-out. [LAW:single-enforcer]

    [LAW:dataflow-not-control-flow] the variable's Python type picks the flag: `gh -F`
    type-infers its value (an all-digit cursor or node id would become a number), so
    strings go through `-f` and ints through `-F`. A None cursor is omitted, not sent
    empty - an undeclared nullable variable is null to GraphQL, whereas `-f cursor=` is
    the empty string, which is not a valid cursor.
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

    [LAW:parse-dont-validate] every null along the path comes back with HTTP 200; this is
    the one place that turns "missing or inaccessible" into an error instead of a
    `NoneType` crash somewhere downstream.
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
    another page is promised and nothing names it. Looping on a null cursor would re-read
    page one forever; stopping would return a partial set as if whole.
    """
    info = block["pageInfo"]
    if not info["hasNextPage"]:
        return None
    cursor = info.get("endCursor")
    if not cursor:
        raise RuntimeError(f"pagination for {subject} promised another page but named no endCursor")
    return cursor


# --- query text: selections are data, one table drives both the first page and the
# --- generic overflow drain. [LAW:one-source-of-truth]

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


# --- the four things a caller can ask for -------------------------------------


def repositories(org: str) -> list[dict]:
    """Every repository of an org, name-ascending."""
    return paged(REPOS_QUERY, ("data", "organization", "repositories"), subject=f"repos of {org}", org=org)


def pull_request_versions(org: str, repo: str, *, total: int) -> list[dict]:
    """`{number, updatedAt}` for every PR of a repo - the cheap listing that says what
    needs fetching without fetching it.

    A PR opened while listing appends to the CREATED_AT-ascending page walk, so the count
    may exceed the total taken earlier; fewer, or a repeated number, means the walk lost
    or duplicated a page. [LAW:no-silent-failure]
    """
    prs = paged(PR_LIST_QUERY, ("data", "repository", "pullRequests"), subject=f"PRs of {org}/{repo}", owner=org, repo=repo)
    numbers = [pr["number"] for pr in prs]
    if len(set(numbers)) != len(numbers) or len(numbers) < total:
        raise RuntimeError(
            f"{repo}: listed {len(numbers)} PRs ({len(set(numbers))} distinct) but totalCount was {total}"
        )
    return prs


def pull_request(org: str, repo: str, number: int) -> dict:
    """One PR with every connection fully drained. Node order is by creation, which
    GitHub returns stably; the sorts below pin it in case it does not."""
    subject = f"{org}/{repo}#{number}"
    pr = path_of(graphql(PR_QUERY, owner=org, repo=repo, num=number), "data", "repository", "pullRequest", subject=subject)
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


def hunk_ranges(patch: str) -> list[list[int]]:
    """New-side (start, length) of every hunk in a unified diff. Pure."""
    return [[int(s), int(n) if n else 1] for s, n in HUNK.findall(patch)]


def commit(org: str, repo: str, oid: str) -> dict:
    """One commit's diff, per file: `{path: {"ranges": [[start, len]], "patch": str}}`.

    REST, because GraphQL serves no patches. A file GitHub returns without a patch
    (binary, rename-only, too large) gets an empty patch and no ranges - a real fact
    about that file, not a failure.
    """
    proc = subprocess.run(["gh", "api", f"repos/{org}/{repo}/commits/{oid}"], text=True, capture_output=True)
    if proc.returncode != 0:  # [LAW:no-silent-failure]
        raise RuntimeError(f"gh api commits/{oid} in {org}/{repo} failed ({proc.returncode}):\n{proc.stderr}")
    data = json.loads(proc.stdout)
    if "files" not in data:
        raise RuntimeError(f"{org}/{repo}@{oid}: response has no files: {json.dumps(data)[:300]}")
    return {f["filename"]: {"ranges": hunk_ranges(f.get("patch", "")), "patch": f.get("patch", "")} for f in data["files"]}
