"""Tests for campaign-index.py: a campaign of synthetic bundles renders one index.

Each case builds a campaign dir holding bundles in the shape lib.sh's close-out leaves
(run.json, loop.json, prs/index.json, backlog/export.json) beside the outcome files
campaign.sh writes, runs the renderer, and reads back index.json and index.md. The
checks are the ones a reviewer relies on: a bundle missing a record shows absence, not
zero; the table has one row per run in order; the values come from the records.

Run: python3 horizon/campaign-index.test.py
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RENDERER = os.path.join(HERE, "campaign-index.py")

FAILURES = []


def check(label, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    print("%s: %s%s" % (status, label, (" - " + detail) if detail and not condition else ""))
    if not condition:
        FAILURES.append(label)


def write(path, doc):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(doc, handle)


def campaign_dir():
    root = tempfile.mkdtemp(prefix="campaign-index.")
    write(os.path.join(root, "campaign.json"), {
        "schema_version": 1,
        "seed": {"dir": "/seeds/macklebox"},
        "pins": {"memento_ref": "m" * 40, "lit_plugin_ref": "l" * 40, "reviewer_sha": "r" * 40,
                 "goal_ref": "g" * 40, "lit_binary_sha256": "b" * 64,
                 "claude_version": "2.1.283", "claude_model": "claude-opus-5"},
        "budget": {"max_minutes": 600, "target_sessions": 40},
    })
    return root


def full_bundle(root, number, sessions, closed, merged, exit_status, last_line):
    run = os.path.join(root, "run-%d" % number)
    write(os.path.join(run, "run.json"), {
        "started": "2026-09-27T10:00:00Z", "ended": "2026-09-27T13:30:00Z",
        "duration_seconds": 12600, "project": {"name": "macklebox", "path": "/x"},
        "captured": {"transcripts": {"ok": True, "detail": ""},
                     "loop": {"ok": True, "detail": ""},
                     "prs": {"ok": True, "detail": ""}},
    })
    tokens = {"input_tokens": 1000 * number, "cache_creation_input_tokens": 20,
              "cache_read_input_tokens": 300, "output_tokens": 40}
    write(os.path.join(run, "loop.json"), {
        "session_count": sessions, "sessions_with_commits": sessions,
        "consecutive_with_commits": sessions, "goal_carries_intact": sessions - 1,
        "goal_carries_expected": sessions - 1, "session_one_goal_in_force": True,
        "tokens": {"sessions": tokens, "subprocesses": tokens, "unattributed": tokens,
                   "total": tokens},
    })
    write(os.path.join(run, "prs", "index.json"), {
        "pull_requests": [{"number": 10 + i, "merged": i < merged, "reviews": 2,
                           "review_threads": 3} for i in range(merged + 1)],
        "count": merged + 1, "unresolved_review_threads": 1,
    })
    write(os.path.join(run, "backlog", "export.json"), {
        "issues": [{"id": "t%d" % i, "status": "closed" if i < closed else "open"}
                   for i in range(15)],
    })
    write(os.path.join(root, "run-%d.outcome.json" % number), {
        "run": number, "driver_exit_status": exit_status, "started": "2026-09-27T09:59:00Z",
        "ended": "2026-09-27T13:31:00Z", "driver": {"commit": "d" * 40, "tree": "clean"},
        "bundle_present": True, "log": "run-%d.log" % number, "last_log_line": last_line,
    })


def render(root):
    done = subprocess.run([sys.executable, RENDERER, root], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("renderer failed:\n" + done.stderr)
    with open(os.path.join(root, "index.json")) as handle:
        index = json.load(handle)
    with open(os.path.join(root, "index.md")) as handle:
        markdown = handle.read()
    return index, markdown


# ── two complete runs render one row each, in order, from their records ─────────────
root = campaign_dir()
full_bundle(root, 1, sessions=4, closed=15, merged=15, exit_status=0,
            last_line="[horizon] the backlog is complete")
full_bundle(root, 2, sessions=2, closed=3, merged=3, exit_status=1,
            last_line="ERROR [horizon]: the pinned goal did not survive 1 session boundary/boundaries.")
index, markdown = render(root)
check("two runs indexed in order", [r["run"] for r in index["runs"]] == [1, 2])
check("run count recorded", index["run_count"] == 2)
run1, run2 = index["runs"]
check("duration read from run.json", run1["duration_seconds"] == 12600)
check("session count read from loop.json", run1["loop"]["sessions"] == 4)
check("token totals read from loop.json", run2["loop"]["tokens"]["input_tokens"] == 2000)
check("carries read from loop.json",
      (run1["loop"]["goal_carries_intact"], run1["loop"]["goal_carries_expected"]) == (3, 3))
check("PRs opened and merged counted", (run1["pull_requests"]["opened"],
                                        run1["pull_requests"]["merged"]) == (16, 15))
check("backlog states counted", (run2["backlog"]["closed"], run2["backlog"]["open"],
                                 run2["backlog"]["total"]) == (3, 12, 15))
check("driver exit and last line carried from the outcome file",
      run2["driver_exit_status"] == 1 and run2["ended_with"].startswith("ERROR [horizon]"))
check("no captures failed on a healthy bundle", run1["captures_failed"] == [])
check("markdown has one table row per run",
      markdown.count("\n| run-1 |") == 1 and markdown.count("\n| run-2 |") == 1)
check("markdown row carries the duration", "| 3h30m |" in markdown)
check("markdown row carries the carry ratio", "| 3/3 |" in markdown)
check("markdown row carries the ticket ratio", "| 15 / 15 |" in markdown)
check("markdown names how each run ended", "**run-2**: ERROR [horizon]" in markdown)
check("markdown names the pins", ("m" * 40) in markdown and "2.1.283" in markdown)

# ── a run that died before its observer started shows absence, never zero ───────────
root = campaign_dir()
full_bundle(root, 1, sessions=3, closed=5, merged=5, exit_status=0, last_line="ok")
run3 = os.path.join(root, "run-3")
write(os.path.join(run3, "run.json"), {
    "started": "2026-09-27T14:00:00Z", "ended": "2026-09-27T14:02:00Z", "duration_seconds": 120,
    "project": {"name": None, "path": None},
    "captured": {"transcripts": {"ok": False, "detail": "no project"},
                 "loop": {"ok": False, "detail": "no project"}},
})
write(os.path.join(root, "run-3.outcome.json"), {
    "run": 3, "driver_exit_status": 1, "started": "x", "ended": "y",
    "driver": {"commit": "d" * 40, "tree": "dirty"}, "bundle_present": True,
    "log": "run-3.log", "last_log_line": "ERROR [horizon]: seed-run.sh failed",
})
index, markdown = render(root)
check("a gap in run numbers is preserved", [r["run"] for r in index["runs"]] == [1, 3])
dead = index["runs"][1]
check("a bundle without loop.json reports no session count, not zero", dead["loop"] is None)
check("a bundle without prs reports no PR summary, not zero", dead["pull_requests"] is None)
check("a bundle without a backlog reports no ticket counts, not zero", dead["backlog"] is None)
check("failed captures are named", dead["captures_failed"] == ["loop", "transcripts"])
check("a dirty driver tree is recorded", dead["driver"]["tree"] == "dirty")
check("markdown shows dashes for the absent facts",
      "| run-3 | 2026-09-27T14:00:00Z | 0h02m | 1 | - | - | - | - | - | - | - | loop, transcripts |" in markdown)

# ── a run with no bundle records at all still appears, from its outcome file alone ──
root = campaign_dir()
os.makedirs(os.path.join(root, "run-1"))
write(os.path.join(root, "run-1.outcome.json"), {
    "run": 1, "driver_exit_status": 1, "started": "x", "ended": "y",
    "driver": {"commit": "d" * 40, "tree": "clean"}, "bundle_present": True,
    "log": "run-1.log", "last_log_line": "ERROR [horizon]: could not write run.json",
})
index, markdown = render(root)
check("a bundle with no run.json still gets a row", index["runs"][0]["duration_seconds"] is None
      and index["runs"][0]["ended_with"].endswith("run.json"))

# ── a ticket with no status is bucketed, not a None key that breaks the render ───────
root = campaign_dir()
full_bundle(root, 1, sessions=1, closed=1, merged=1, exit_status=0, last_line="ok")
write(os.path.join(root, "run-1", "backlog", "export.json"),
      {"issues": [{"id": "a", "status": "closed"}, {"id": "b"}, {"id": "c", "status": None}]})
index, markdown = render(root)
check("issues without a status are counted under 'missing'",
      index["runs"][0]["backlog"]["missing"] == 2 and index["runs"][0]["backlog"]["total"] == 3)

# ── a broken record is refused rather than rendered as absence ──────────────────────
root = campaign_dir()
full_bundle(root, 1, sessions=1, closed=1, merged=1, exit_status=0, last_line="ok")
with open(os.path.join(root, "run-1", "loop.json"), "w") as handle:
    handle.write("{not json")
done = subprocess.run([sys.executable, RENDERER, root], capture_output=True, text=True)
check("a corrupt loop.json fails the render", done.returncode != 0 and "loop.json" in done.stderr)
check("a failed render writes no index", not os.path.exists(os.path.join(root, "index.json")))

# ── a directory without campaign.json is refused ─────────────────────────────────────
root = tempfile.mkdtemp(prefix="campaign-index.none.")
done = subprocess.run([sys.executable, RENDERER, root], capture_output=True, text=True)
check("no campaign.json is refused", done.returncode != 0 and "campaign.json" in done.stderr)


# ── a run the driver refused (an outcome file, no bundle) is still a run the index shows ─
root = campaign_dir()
full_bundle(root, 1, sessions=3, closed=5, merged=5, exit_status=0, last_line="ok")
write(os.path.join(root, "run-2.outcome.json"), {
    "run": 2, "driver_exit_status": 1, "started": "x", "ended": "y",
    "driver": {"commit": "d" * 40, "tree": "clean"}, "bundle_present": False,
    "log": "run-2.log", "last_log_line": "ERROR [horizon]: claude is 2.1.290, not the pinned 2.1.283",
})
index, markdown = render(root)
check("a refused run is indexed after the real one", [r["run"] for r in index["runs"]] == [1, 2])
refused = index["runs"][1]
check("a refused run names no bundle", refused["bundle"] is None)
check("a refused run carries its driver exit and last line",
      refused["driver_exit_status"] == 1 and refused["ended_with"].startswith("ERROR [horizon]"))
check("a refused run's loop, PRs and backlog are absent",
      refused["loop"] is None and refused["pull_requests"] is None and refused["backlog"] is None)
check("markdown says how the refused run ended", "**run-2 (no bundle)**: ERROR [horizon]" in markdown)
check("markdown rows one per run including the refused one",
      markdown.count("\n| run-1 |") == 1 and markdown.count("\n| run-2 (no bundle) |") == 1)

print()
if FAILURES:
    sys.exit("%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
print("all %s checks passed" % "campaign-index")
