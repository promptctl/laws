#!/usr/bin/env python3
"""Index the pull requests a run captured, and refuse a capture that came back short.

Pure analysis over files it is handed, like sessions.py and for the same reason: the
index can be rebuilt from an archived bundle months later with nothing running, and
nothing here reaches the network. [LAW:effects-at-boundaries]

Two jobs, and the second is the important one:

* Write `index.json` - one line per pull request, so a reviewer opening a bundle sees
  what the run proposed and how each one ended without opening nine files.

* REFUSE A TRUNCATED CAPTURE. Every connection in the capture query is fetched at the
  API's maximum page size and reports whether more remained. A PR whose review threads
  ran past that page would otherwise be written to disk looking complete, and the one
  thing a bundle may never do is look complete while holding half a review. The failure
  arm is loud and names the PR and the connection. [LAW:no-silent-failure]

Usage:
    prs.py <prs-dir>
"""

import glob
import json
import os
import sys

# Where a `pageInfo` can appear in a captured pull request, as a path of keys from the
# pullRequest object. Listed rather than discovered by walking the document: a walk would
# also "find" pageInfo keys a future query adds and silently start enforcing rules nobody
# wrote, whereas this list is exactly the connections the query asks for, and it fails to
# match - loudly - if the query changes shape underneath it.
CONNECTIONS = (
    ("commits",),
    ("comments",),
    ("reviews",),
    ("reviewThreads",),
)


def captured(root, path, subject):
    """The value at `path` inside a captured document, or an exit naming what is missing.

    EVERY structural read of a capture goes through here - a connection, its `pageInfo`,
    the `nodes` under it, and the comments nested inside a review thread alike. A bare
    `doc["a"]["b"]` anywhere else raises a KeyError naming neither the pull request nor
    the field, which is the one thing this module promises never to do: a missing key
    means the capture query and this reader have drifted apart, and that is a defect in
    the instrument rather than a fact about the run. One reader, so there is no second
    way to reach into a capture that fails differently. [LAW:single-enforcer]

    `subject` names the thing being read and is passed in rather than derived from `root`,
    because `root` is a review thread or a whole capture file as often as a pull request,
    and neither of those knows the PR number the message has to carry.
    """
    node = root
    for key in path:
        if not isinstance(node, dict) or key not in node:
            sys.exit("%s has no %s: the capture and prs.py disagree about the document's "
                     "shape" % (subject, ".".join(path)))
        node = node[key]
    return node


def refuse_truncation(number, pull_request):
    subject = "captured pull request #%s" % number
    for path in CONNECTIONS:
        if captured(pull_request, path + ("pageInfo", "hasNextPage"), subject):
            sys.exit("PR #%s has more %s than one page: the capture is short, and a bundle "
                     "holding half a review thread is worse than one holding none. "
                     "Raise the page size in HORIZON_PR_QUERY and capture it again."
                     % (number, ".".join(path)))
        # A review thread's own comments are a connection inside a connection, and it is
        # the likeliest one to overflow: a long argument on one line of one file.
        if path != ("reviewThreads",):
            continue
        for thread in captured(pull_request, path + ("nodes",), subject):
            if captured(thread, ("comments", "pageInfo", "hasNextPage"), subject):
                sys.exit("PR #%s has a review thread on %s with more comments than one "
                         "page: the capture is short."
                         % (number, thread.get("path")))


def read_capture(path):
    """One captured PR file as its pullRequest object.

    `gh api graphql` exits 0 and writes an `errors` document for a query GitHub refused,
    so a file that parses as JSON is not yet evidence the capture worked.
    """
    with open(path) as handle:
        document = json.load(handle)
    if "errors" in document:
        sys.exit("%s records a GraphQL error rather than a pull request: %s"
                 % (os.path.basename(path), json.dumps(document["errors"])))
    pull_request = captured(document, ("data", "repository", "pullRequest"),
                            os.path.basename(path))
    if pull_request is None:
        sys.exit("%s captured no pull request - the number does not exist in that "
                 "repository" % os.path.basename(path))
    return pull_request


# What the index calls each of the pull request\'s own flat fields, beside what GitHub
# calls it. Read as data rather than written out as nine lookups, so every one of them
# goes through the same loud-on-drift reader below without nine chances to forget.
# [LAW:dataflow-not-control-flow]
FLAT_FIELDS = (
    ("number", "number"),
    ("title", "title"),
    ("url", "url"),
    ("state", "state"),
    ("merged", "merged"),
    ("created_at", "createdAt"),
    ("merged_at", "mergedAt"),
    ("head_ref", "headRefName"),
    ("head_sha", "headRefOid"),
)


def summarise(pull_request):
    # `.get` for the label, so a capture missing `number` is reported by the read that
    # wants it rather than by the line building the message about it.
    subject = "captured pull request #%s" % pull_request.get("number")
    threads = captured(pull_request, ("reviewThreads", "nodes"), subject)
    summary = {name: captured(pull_request, (key,), subject) for name, key in FLAT_FIELDS}
    summary.update({
        "commits": captured(pull_request, ("commits", "totalCount"), subject),
        "reviews": len(captured(pull_request, ("reviews", "nodes"), subject)),
        "review_threads": len(threads),
        # The number a reviewer actually scans for. An unresolved thread on a merged PR is
        # the workflow failing in the specific way this eval exists to catch, so it is
        # surfaced in the index rather than left inside the per-PR file.
        "review_threads_unresolved":
            sum(1 for t in threads if not captured(t, ("isResolved",), subject)),
        "comments": len(captured(pull_request, ("comments", "nodes"), subject)),
    })
    return summary


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    prs_dir = sys.argv[1]

    summaries = []
    for path in sorted(glob.glob(os.path.join(prs_dir, "pr-*.json"))):
        pull_request = read_capture(path)
        refuse_truncation(pull_request.get("number"), pull_request)
        summaries.append(summarise(pull_request))

    summaries.sort(key=lambda s: s["number"])
    with open(os.path.join(prs_dir, "index.json"), "w") as handle:
        json.dump({"pull_requests": summaries,
                   "count": len(summaries),
                   "unresolved_review_threads":
                       sum(s["review_threads_unresolved"] for s in summaries)},
                  handle, indent=2, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main()
