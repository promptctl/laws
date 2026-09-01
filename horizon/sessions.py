#!/usr/bin/env python3
"""What a horizon run actually did, read back from the record it left.

The loop's acceptance is a claim about history - "three consecutive sessions of
committed work with zero human input" - so this reads that history rather than
watching it happen. Two consequences worth stating, because they are the reason this
is a separate program and not a few lines inside run-loop.sh:

* It is pure analysis over inputs it is handed. Transcripts arrive as files and the
  project's commits arrive on stdin, so the same verdict can be recomputed from an
  archived run months later, with nothing launched and nothing left to race.
  [LAW:effects-at-boundaries]

* It owns reading transcripts outright. Nothing else in horizon/ parses them, so
  there is no second reader to disagree with this one about what a session is.
  [LAW:one-source-of-truth]

Usage:
    sessions.py <config-dir> <project-dir> <goal-file> < commits.tsv

where commits.tsv is `<sha>\\t<committer-date-ISO8601>` per line, oldest first.
Prints one JSON object on stdout.
"""

import glob
import json
import os
import re
import sys
from datetime import datetime

# A slash command is not recorded as the raw text the operator typed: Claude Code
# rewrites it into this envelope. Matching the raw "/goal ..." string instead would find
# nothing and silently report every carry as lost - the failure this check exists to
# detect, indistinguishable from the check being broken. Verified against real
# transcripts at Claude Code v2.1.226.
COMMAND_NAME_RE = re.compile(r"<command-name>\s*(?P<name>[^<]+?)\s*</command-name>")
COMMAND_ARGS_RE = re.compile(r"<command-args>(?P<args>.*?)</command-args>", re.DOTALL)


def parse_time(value):
    """An ISO-8601 stamp as an aware datetime, or None when it is unusable.

    Returns None rather than raising: a single malformed line in one transcript must not
    take down the report on a whole campaign. Callers treat None as "this line carries no
    time", never as a time.
    """
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def message_text(entry):
    """The human-visible text of a transcript entry, or "" when it has none.

    Content is either a bare string or a list of typed blocks; both spellings mean the
    same thing here, so both are reduced to one.
    """
    message = entry.get("message")
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def read_session(path, project_dir):
    """One transcript reduced to the facts the acceptance criterion asks about.

    Returns None when the transcript belongs to a different project, so the caller never
    has to re-derive Claude Code's directory-naming rule: the cwd recorded inside the
    file is the authority on what it belongs to.
    """
    want = os.path.realpath(project_dir)
    session_id = os.path.splitext(os.path.basename(path))[0]
    belongs = False
    first_time = None
    last_time = None
    goal_args = []

    with open(path, errors="replace") as handle:
        for line in handle:
            try:
                entry = json.loads(line)
            except ValueError:
                continue

            cwd = entry.get("cwd")
            if cwd and os.path.realpath(cwd) == want:
                belongs = True

            stamp = parse_time(entry.get("timestamp"))
            if stamp is not None:
                if first_time is None or stamp < first_time:
                    first_time = stamp
                if last_time is None or stamp > last_time:
                    last_time = stamp

            # Sidechain entries are subagent traffic, not the session's own turns.
            if entry.get("type") != "user" or entry.get("isSidechain"):
                continue
            text = message_text(entry)
            name = COMMAND_NAME_RE.search(text)
            if name and name.group("name").strip() == "/goal":
                args = COMMAND_ARGS_RE.search(text)
                goal_args.append(args.group("args").strip() if args else "")

    if not belongs:
        return None

    return {
        "session_id": session_id,
        "started": first_time.isoformat() if first_time else None,
        "ended": last_time.isoformat() if last_time else None,
        "_start": first_time,
        "_end": last_time,
        "goal_issues": goal_args,
    }


def read_commits(stream):
    """`<sha>\\t<iso-date>` lines as (sha, datetime) pairs, skipping unusable ones."""
    commits = []
    for line in stream:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 2:
            continue
        when = parse_time(parts[1])
        if when is not None:
            commits.append((parts[0], when))
    return commits


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    config_dir, project_dir, goal_file = sys.argv[1:]

    with open(goal_file) as handle:
        pinned_goal = handle.read().strip()

    sessions = []
    for path in glob.glob(os.path.join(config_dir, "projects", "*", "*.jsonl")):
        session = read_session(path, project_dir)
        if session is not None:
            sessions.append(session)

    # Ordered by when they ran. Session ids are uuids and sort meaninglessly, and the
    # acceptance criterion is about CONSECUTIVE sessions, so the order has to be real.
    sessions.sort(key=lambda s: (s["_start"] or datetime.max.replace(tzinfo=None)))

    commits = read_commits(sys.stdin)

    # Each commit is attributed to the session that was live when it was made. A commit
    # landing outside every window is reported rather than dropped: it means the windows
    # are wrong, which is a finding about this analysis, not about the run.
    unattributed = []
    for sha, when in commits:
        owner = None
        for session in sessions:
            if session["_start"] and session["_end"] \
                    and session["_start"] <= when <= session["_end"]:
                owner = session
                break
        if owner is None:
            unattributed.append(sha)
        else:
            owner.setdefault("commits", []).append(sha)

    for session in sessions:
        session.setdefault("commits", [])
        issues = session.pop("goal_issues")
        session["goal_issued"] = bool(issues)
        # The carry is only intact if the wording that arrived is the wording that was
        # pinned. "A /goal was issued" is the weaker claim that would pass while the
        # agent paraphrased the condition into something else entirely.
        session["goal_matches_pinned"] = any(a.strip() == pinned_goal for a in issues)
        session.pop("_start")
        session.pop("_end")

    with_commits = [s for s in sessions if s["commits"]]
    # Sessions after the first are the ones the carry has to survive; session one was
    # issued its goal by the driver, so counting it would flatter the result.
    carried = [s for s in sessions[1:] if s["goal_matches_pinned"]]

    json.dump(
        {
            "sessions": sessions,
            "session_count": len(sessions),
            "sessions_with_commits": len(with_commits),
            "consecutive_with_commits": consecutive_run(sessions),
            "goal_carries_intact": len(carried),
            "goal_carries_expected": max(len(sessions) - 1, 0),
            "unattributed_commits": unattributed,
        },
        sys.stdout,
        indent=2,
        sort_keys=True,
    )
    sys.stdout.write("\n")


def consecutive_run(sessions):
    """The longest run of back-to-back sessions that each committed something.

    The acceptance criterion says CONSECUTIVE, and it means it: three committing
    sessions with a dead one between them is a loop that stalled and was restarted,
    which is exactly the failure the criterion is written to exclude.
    """
    best = run = 0
    for session in sessions:
        run = run + 1 if session["commits"] else 0
        best = max(best, run)
    return best


if __name__ == "__main__":
    main()
