"""Render a campaign's runs into one descriptive index: index.json and index.md.

The index is a table of facts a reader would otherwise open five bundles to collect -
how long each run took, how many sessions it had, what it spent, how far the build got
and how the driver said it ended. It renders NO verdict: the epic has no scored layer, and
a number that summarises a run is an aid to the human who reads the bundles, never a
gate. [LAW:one-source-of-truth] every value here is read from the bundle's own records
(run.json, loop.json, prs/index.json, backlog/export.json) and the campaign's outcome
files; nothing is recomputed from transcripts, so the index cannot disagree with the
bundle it points at.

Usage:
    campaign-index.py <campaign-dir>

Re-runnable at any time, and run by campaign.sh after every run. A run whose bundle
lacks a record shows that ABSENCE in the index rather than a zero: a run that died
before its observer started genuinely has no session count, and printing 0 there would
make a broken capture read like an idle agent. [LAW:no-silent-failure]
"""

import json
import os
import re
import sys
import tempfile

TOKEN_FIELDS = ("input_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "output_tokens")
RUN_DIR = re.compile(r"^run-(\d+)$")
RUN_OUTCOME = re.compile(r"^run-(\d+)\.outcome\.json$")


def read_json(path):
    """The parsed document, or None when the file is absent - never when it is broken.

    Absent is a fact about the run (a capture that did not happen, which run.json
    already records). Broken is a fact about the record, and a reader must hear it.
    """
    if not os.path.exists(path):
        return None
    with open(path) as handle:
        try:
            return json.load(handle)
        except ValueError as failure:
            sys.exit("%s is not valid JSON: %s" % (path, failure))


def run_numbers(campaign_dir):
    """Every run the campaign attempted: one with a bundle, or one with only an outcome.

    A run the driver refused leaves an outcome file and no bundle, and it is the run that
    ENDED the campaign - the one a reader most needs to see in "how each run ended".
    """
    numbers = set()
    for name in os.listdir(campaign_dir):
        match = RUN_DIR.match(name)
        if match and os.path.isdir(os.path.join(campaign_dir, name)):
            numbers.add(int(match.group(1)))
        match = RUN_OUTCOME.match(name)
        if match:
            numbers.add(int(match.group(1)))
    return sorted(numbers)


def backlog_states(export):
    """Ticket counts by status from a lit export, or None without one."""
    if export is None:
        return None
    counts = {"open": 0, "in_progress": 0, "closed": 0}
    for issue in export.get("issues", []):
        # A status the export does not name is bucketed by name rather than by None: a
        # None key cannot be sorted beside strings and would take the whole render down
        # with a traceback from inside json.
        status = issue.get("status") or "missing"
        counts[status] = counts.get(status, 0) + 1
    counts["total"] = len(export.get("issues", []))
    return counts


def prs_summary(index):
    if index is None:
        return None
    pulls = index.get("pull_requests", [])
    return {
        "opened": len(pulls),
        "merged": sum(1 for p in pulls if p.get("merged")),
        "reviews": sum(p.get("reviews", 0) for p in pulls),
        "review_threads": sum(p.get("review_threads", 0) for p in pulls),
        "review_threads_unresolved": index.get("unresolved_review_threads"),
    }


def loop_summary(loop):
    if loop is None:
        return None
    tokens = loop.get("tokens", {}).get("total")
    return {
        "sessions": loop.get("session_count"),
        "sessions_with_commits": loop.get("sessions_with_commits"),
        "consecutive_with_commits": loop.get("consecutive_with_commits"),
        "goal_carries_intact": loop.get("goal_carries_intact"),
        "goal_carries_expected": loop.get("goal_carries_expected"),
        "session_one_goal_in_force": loop.get("session_one_goal_in_force"),
        "tokens": {field: tokens.get(field) for field in TOKEN_FIELDS} if tokens else None,
    }


def describe_run(campaign_dir, number):
    run_dir = os.path.join(campaign_dir, "run-%d" % number)
    record = read_json(os.path.join(run_dir, "run.json"))
    outcome = read_json(os.path.join(campaign_dir, "run-%d.outcome.json" % number))
    return {
        "run": number,
        "bundle": "run-%d" % number if os.path.isdir(run_dir) else None,
        "started": record.get("started") if record else None,
        "ended": record.get("ended") if record else None,
        "duration_seconds": record.get("duration_seconds") if record else None,
        "captures_failed": sorted(name for name, step in (record or {}).get("captured", {}).items()
                                  if not step.get("ok")),
        "driver_exit_status": outcome.get("driver_exit_status") if outcome else None,
        "driver": outcome.get("driver") if outcome else None,
        "ended_with": outcome.get("last_log_line") if outcome else None,
        "loop": loop_summary(read_json(os.path.join(run_dir, "loop.json"))),
        "pull_requests": prs_summary(read_json(os.path.join(run_dir, "prs", "index.json"))),
        "backlog": backlog_states(read_json(os.path.join(run_dir, "backlog", "export.json"))),
    }


def cell(value):
    """A table cell: a value, or a dash for a fact the bundle does not hold."""
    if value is None:
        return "-"
    if isinstance(value, bool):
        return "yes" if value else "no"
    return str(value)


def duration(seconds):
    if seconds is None:
        return None
    return "%dh%02dm" % (seconds // 3600, (seconds % 3600) // 60)


def render_markdown(campaign, runs):
    pins = campaign.get("pins", {})
    budget = campaign.get("budget", {})
    lines = [
        "# Campaign index",
        "",
        "Descriptive only: what each run did, read off its bundle. No verdicts. Open the",
        "bundle named in the first column for the transcripts, PRs, review threads and",
        "backlog behind each row.",
        "",
        "Pinned for every run: memento `%s`, lit plugin `%s`, reviewer `%s`, goal wording at `%s`,"
        % (pins.get("memento_ref"), pins.get("lit_plugin_ref"), pins.get("reviewer_sha"),
           pins.get("goal_ref")),
        "Claude Code %s on `%s`, lit binary sha256 `%s`. Budget per run: %s minutes, session target %s."
        % (pins.get("claude_version"), pins.get("claude_model"), pins.get("lit_binary_sha256"),
           budget.get("max_minutes"), budget.get("target_sessions")),
        "",
        "| run | started (UTC) | duration | driver exit | sessions | with commits | carries intact | PRs opened / merged | reviews | tickets closed / total | tokens in / cache-create / cache-read / out | captures failed |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for run in runs:
        loop = run["loop"] or {}
        tokens = loop.get("tokens") or {}
        prs = run["pull_requests"] or {}
        backlog = run["backlog"] or {}
        carries = (None if run["loop"] is None else
                   "%s/%s" % (cell(loop.get("goal_carries_intact")),
                              cell(loop.get("goal_carries_expected"))))
        lines.append("| %s |" % " | ".join([
            run["bundle"] or "run-%d (no bundle)" % run["run"],
            cell(run["started"]),
            cell(duration(run["duration_seconds"])),
            cell(run["driver_exit_status"]),
            cell(loop.get("sessions")),
            cell(loop.get("sessions_with_commits")),
            cell(carries),
            (None if run["pull_requests"] is None else
             "%s / %s" % (cell(prs.get("opened")), cell(prs.get("merged")))) or "-",
            cell(prs.get("reviews")),
            (None if run["backlog"] is None else
             "%s / %s" % (cell(backlog.get("closed")), cell(backlog.get("total")))) or "-",
            (None if not tokens else
             " / ".join(cell(tokens.get(f)) for f in TOKEN_FIELDS)) or "-",
            ", ".join(run["captures_failed"]) or "none",
        ]))
    lines += ["", "## How each run ended", ""]
    for run in runs:
        lines.append("- **%s**: %s" % (run["bundle"] or "run-%d (no bundle)" % run["run"],
                                        run["ended_with"] or "(no driver log line recorded)"))
    lines.append("")
    return "\n".join(lines)


def write_atomically(path, text):
    handle = tempfile.NamedTemporaryFile("w", dir=os.path.dirname(path),
                                         prefix="." + os.path.basename(path) + ".", delete=False)
    try:
        with handle:
            handle.write(text)
        os.replace(handle.name, path)
    except BaseException:
        if os.path.exists(handle.name):
            os.unlink(handle.name)
        raise


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    campaign_dir = sys.argv[1]
    campaign = read_json(os.path.join(campaign_dir, "campaign.json"))
    if campaign is None:
        sys.exit("%s holds no campaign.json" % campaign_dir)
    runs = [describe_run(campaign_dir, n) for n in run_numbers(campaign_dir)]
    document = {"campaign": campaign, "runs": runs, "run_count": len(runs)}
    write_atomically(os.path.join(campaign_dir, "index.json"),
                     json.dumps(document, indent=2, sort_keys=True) + "\n")
    write_atomically(os.path.join(campaign_dir, "index.md"), render_markdown(campaign, runs))


if __name__ == "__main__":
    main()
