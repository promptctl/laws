#!/usr/bin/env python3
"""Behaviour tests for sessions.py.

These assert the CONTRACT the acceptance criterion rests on - how many consecutive
sessions committed work, and whether the pinned goal survived each handoff - never how
the analysis reaches those numbers. [LAW:behavior-not-structure]

Every check here is written so that breaking the thing it guards makes it FAIL. The
repo has twice shipped a check that passed against a fixture already broken for some
other reason, so a case that could pass while its subject is deleted is worse than no
case at all.

Run: python3 horizon/sessions.test.py
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SESSIONS = os.path.join(HERE, "sessions.py")

PINNED_GOAL = "Work the backlog to done.\n\nKeep going until it is finished."

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print("PASS: %s" % name)
    else:
        print("FAIL: %s %s" % (name, detail))
        FAILURES.append(name)


def entry(session_id, cwd, stamp, **extra):
    base = {"sessionId": session_id, "cwd": cwd, "timestamp": stamp}
    base.update(extra)
    return base


def user_text(content):
    return {"type": "user", "message": {"role": "user", "content": content}}


def slash_command(name, text):
    """A slash command in the ENVELOPE spelling Claude Code used at v2.1.226."""
    return user_text("<command-name>%s</command-name>\n"
                     "<command-message>cmd</command-message>\n"
                     "<command-args>%s</command-args>" % (name, text))


# The three spellings a goal actually arrives in are fixtures, not one canonical form.
# This suite passed 12/12 against a detector that could see only the envelope, because
# the envelope was the only thing the fixtures ever produced - a green suite proving the
# fixture agreed with the code, and nothing about the transcripts either would meet.
def raw_goal(text):
    """A /goal PASTED into the input box, as v2.1.258 records it: plain text."""
    return user_text("/goal %s" % text)


def carried_goal(text):
    """How a goal carried by finalize-session announces itself to the successor.

    No /goal message appears in a relaunched session at all - only this. It is therefore
    the single spelling by which a surviving carry can ever be observed.
    """
    return user_text(
        "A session-scoped Stop hook is now active with condition: \"%s\". Briefly "
        "acknowledge the goal, then immediately start working toward it." % text
    )


def write_session(config_dir, slug, session_id, cwd, start, end,
                  goal_text=None, commands=(), goal_builder=None,
                  bracket_type="assistant", extra=()):
    """bracket_type is the type of the first and last entries: "assistant" is a session
    that took a turn; a boot-time type is one still forming. extra entries are written
    between them as given."""
    directory = os.path.join(config_dir, "projects", slug)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "%s.jsonl" % session_id)
    lines = [entry(session_id, cwd, start, type=bracket_type)]
    if goal_text is not None:
        build = goal_builder or (lambda text: slash_command("/goal", text))
        lines.append(entry(session_id, cwd, start, **build(goal_text)))
    for command_name, command_text in commands:
        lines.append(entry(session_id, cwd, start,
                           **slash_command(command_name, command_text)))
    for fields in extra:
        lines.append(entry(session_id, cwd, start, **fields))
    lines.append(entry(session_id, cwd, end, type=bracket_type))
    with open(path, "w") as handle:
        for line in lines:
            handle.write(json.dumps(line) + "\n")
    return path


def run(config_dir, project_dir, goal_file, commits):
    payload = "".join("%s\t%s\n" % (sha, when) for sha, when in commits)
    result = subprocess.run(
        [sys.executable, SESSIONS, config_dir, project_dir, goal_file],
        input=payload, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise AssertionError("sessions.py failed: %s" % result.stderr)
    return json.loads(result.stdout)


def build(tmp):
    """A run of three sessions: two that commit, then one that does not."""
    config_dir = os.path.join(tmp, "config")
    project_dir = os.path.join(tmp, "project")
    other_dir = os.path.join(tmp, "other")
    os.makedirs(project_dir)
    os.makedirs(other_dir)

    goal_file = os.path.join(tmp, "GOAL_PROMPT.md")
    with open(goal_file, "w") as handle:
        handle.write(PINNED_GOAL + "\n")

    write_session(config_dir, "proj", "s1", project_dir,
                  "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                  goal_text=PINNED_GOAL)
    write_session(config_dir, "proj", "s2", project_dir,
                  "2026-01-01T02:00:00+00:00", "2026-01-01T03:00:00+00:00",
                  goal_text=PINNED_GOAL)
    write_session(config_dir, "proj", "s3", project_dir,
                  "2026-01-01T04:00:00+00:00", "2026-01-01T05:00:00+00:00",
                  goal_text="just do whatever seems good")
    # A session carrying ONLY a /clear. finalize-session issues one on every single
    # handoff, so if any command envelope were read as a goal this would be the common
    # case, and a run whose goal never carried would report itself perfectly healthy.
    write_session(config_dir, "proj", "s4", project_dir,
                  "2026-01-01T06:00:00+00:00", "2026-01-01T07:00:00+00:00",
                  commands=[("/clear", "")])
    # A session of a DIFFERENT project, sharing the same config dir.
    write_session(config_dir, "other", "s9", other_dir,
                  "2026-01-01T00:30:00+00:00", "2026-01-01T00:45:00+00:00")

    commits = [
        ("aaa1", "2026-01-01T00:30:00+00:00"),   # inside s1
        ("bbb2", "2026-01-01T02:30:00+00:00"),   # inside s2
    ]
    return config_dir, project_dir, goal_file, commits


def main():
    with tempfile.TemporaryDirectory() as tmp:
        config_dir, project_dir, goal_file, commits = build(tmp)
        report = run(config_dir, project_dir, goal_file, commits)

        ids = [s["session_id"] for s in report["sessions"]]

        check("a session belonging to another project is excluded",
              "s9" not in ids, "got %s" % ids)
        check("sessions are ordered by when they ran",
              ids == ["s1", "s2", "s3", "s4"], "got %s" % ids)
        check("commits are attributed to the session that was live",
              [s["commits"] for s in report["sessions"]] == [["aaa1"], ["bbb2"], [], []],
              "got %s" % [s["commits"] for s in report["sessions"]])
        by_id = {s["session_id"]: s for s in report["sessions"]}
        check("a /clear-only session is NOT read as carrying a goal",
              by_id["s4"]["goal_issued"] is False
              and by_id["s4"]["goal_matches_pinned"] is False,
              "got issued=%s matches=%s" % (by_id["s4"]["goal_issued"],
                                            by_id["s4"]["goal_matches_pinned"]))
        check("consecutive committing sessions counted, stopping at the idle one",
              report["consecutive_with_commits"] == 2,
              "got %s" % report["consecutive_with_commits"])
        check("a carried goal matching the pinned wording is intact",
              report["sessions"][1]["goal_matches_pinned"] is True)
        check("a PARAPHRASED carried goal is not counted as intact",
              report["sessions"][2]["goal_matches_pinned"] is False)
        check("a paraphrased goal is still recorded as issued",
              report["sessions"][2]["goal_issued"] is True)
        check("only handoffs are counted, not the driver's own first issue",
              report["goal_carries_expected"] == len(report["sessions"]) - 1
              and report["goal_carries_expected"] == 3,
              "got %s" % report["goal_carries_expected"])
        # Of s2/s3/s4, only s2 carried the pinned wording: s3 paraphrased and s4 carried
        # nothing at all. A run reporting 3 here would be one whose carry check is blind.
        check("only the faithfully carried handoff counts as intact",
              report["goal_carries_intact"] == 1,
              "got %s" % report["goal_carries_intact"])

        # The driver reads two numbers out of this report through lib.sh. Fed the real
        # output, so a key renamed on either side fails here and not mid-campaign.
        counts = subprocess.run(
            ["bash", "-c", '. "$1/lib.sh" && horizon_report_counts', "-", HERE],
            input=json.dumps(report), capture_output=True, text=True,
        )
        check("lib.sh reads the report's counts the way sessions.py writes them",
              counts.returncode == 0 and counts.stdout.split() == ["2", "2"],
              "rc=%s out=%r err=%r" % (counts.returncode, counts.stdout, counts.stderr))

        # A commit outside every session window must be surfaced, not dropped: silently
        # discarding it would let a broken window calculation read as a clean run.
        report2 = run(config_dir, project_dir, goal_file,
                      commits + [("ccc3", "2026-06-01T00:00:00+00:00")])
        check("a commit outside every session window is reported, not dropped",
              report2["unattributed_commits"] == ["ccc3"],
              "got %s" % report2["unattributed_commits"])

        # An idle session BETWEEN two committing ones must break the streak - a loop
        # that stalled and resumed is precisely what "consecutive" excludes.
        with tempfile.TemporaryDirectory() as tmp2:
            cfg = os.path.join(tmp2, "config")
            proj = os.path.join(tmp2, "project")
            os.makedirs(proj)
            gf = os.path.join(tmp2, "g.md")
            with open(gf, "w") as handle:
                handle.write(PINNED_GOAL + "\n")
            write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
            write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00", "2026-01-01T03:00:00+00:00")
            write_session(cfg, "p", "c", proj, "2026-01-01T04:00:00+00:00", "2026-01-01T05:00:00+00:00")
            gap = run(cfg, proj, gf, [("x", "2026-01-01T00:30:00+00:00"),
                                      ("y", "2026-01-01T04:30:00+00:00")])
            check("an idle session between two committing ones breaks the streak",
                  gap["consecutive_with_commits"] == 1,
                  "got %s" % gap["consecutive_with_commits"])

    # Every spelling a goal arrives in must be seen, because a spelling this reader
    # cannot parse produces the identical output to a carry that genuinely died - and
    # then the run reports its own instrument as broken, or worse, as fine.
    for label, builder in (("envelope", lambda t: slash_command("/goal", t)),
                           ("raw pasted text", raw_goal),
                           ("carried Stop-hook condition", carried_goal)):
        with tempfile.TemporaryDirectory() as tmp2:
            cfg = os.path.join(tmp2, "config")
            proj = os.path.join(tmp2, "project")
            os.makedirs(proj)
            gf = os.path.join(tmp2, "g.md")
            with open(gf, "w") as handle:
                handle.write(PINNED_GOAL + "\n")
            write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                          "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
            write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                          "2026-01-01T03:00:00+00:00", goal_text=PINNED_GOAL,
                          goal_builder=builder)
            seen = run(cfg, proj, gf, [])
            check("a goal recorded as %s is recognised" % label,
                  seen["goal_carries_intact"] == 1,
                  "goal_carries_intact=%s goal_received=%r"
                  % (seen["goal_carries_intact"], seen["sessions"][1]["goal_received"]))

    # A successor whose transcript exists but holds no turn yet is still booting: the
    # carried goal is announced several entries in, so judging it now would read a carry
    # that has not happened yet as one that failed - and stop a healthy run.
    with tempfile.TemporaryDirectory() as tmp2:
        cfg = os.path.join(tmp2, "config")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T02:00:01+00:00", bracket_type="file-history-snapshot")
        forming = run(cfg, proj, gf, [])
        check("a successor with no turn yet is not judged for its carry",
              forming["session_count"] == 2
              and forming["goal_carries_expected"] == 0
              and forming["goal_carries_intact"] == 0,
              "got count=%s expected=%s intact=%s"
              % (forming["session_count"], forming["goal_carries_expected"],
                 forming["goal_carries_intact"]))

    # Three successors that must be judged on evidence, not on list position or timing:
    # one whose only assistant entry is a subagent's (not a turn of its own), one that
    # received the carry and died before turning, and one that received the carry and
    # then re-goaled itself with a paraphrase.
    with tempfile.TemporaryDirectory() as tmp2:
        cfg = os.path.join(tmp2, "config")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T02:00:01+00:00", bracket_type="file-history-snapshot",
                      extra=[{"type": "assistant", "isSidechain": True}])
        write_session(cfg, "p", "c", proj, "2026-01-01T03:00:00+00:00",
                      "2026-01-01T03:00:01+00:00", bracket_type="file-history-snapshot",
                      goal_text=PINNED_GOAL, goal_builder=carried_goal)
        write_session(cfg, "p", "d", proj, "2026-01-01T04:00:00+00:00",
                      "2026-01-01T05:00:00+00:00", goal_text=PINNED_GOAL,
                      goal_builder=carried_goal,
                      commands=[("/goal", "just keep going")])
        judged = run(cfg, proj, gf, [])
        by_id = {s["session_id"]: s for s in judged["sessions"]}
        check("a subagent's assistant entry is not a turn of the session's own",
              judged["goal_carries_expected"] == 2,
              "got expected=%s" % judged["goal_carries_expected"])
        check("a successor that received the carry and never turned is still judged",
              by_id["c"]["goal_matches_pinned"] is True
              and judged["goal_carries_intact"] == 1,
              "got matches=%s intact=%s"
              % (by_id["c"]["goal_matches_pinned"], judged["goal_carries_intact"]))
        check("a session that re-goaled itself is judged on the wording in force",
              by_id["d"]["goal_matches_pinned"] is False
              and by_id["d"]["goal_received"] == "just keep going",
              "got matches=%s received=%r"
              % (by_id["d"]["goal_matches_pinned"], by_id["d"]["goal_received"]))

    # A goal containing a double quote must survive the carried spelling whole: a capture
    # that stops at the first quote reports a faithful carry as a paraphrase.
    quoted = 'Ship the "macklebox" seed.\n\nThen say "done".'
    with tempfile.TemporaryDirectory() as tmp2:
        cfg = os.path.join(tmp2, "config")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(quoted + "\n")
        write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=quoted)
        write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T03:00:00+00:00", goal_text=quoted,
                      goal_builder=carried_goal)
        seen = run(cfg, proj, gf, [])
        check("a carried goal containing a double quote is read whole",
              seen["goal_carries_intact"] == 1
              and seen["sessions"][1]["goal_received"] == quoted,
              "goal_received=%r" % seen["sessions"][1]["goal_received"])

    # The drift this eval exists to catch: a carry that ARRIVES but has been paraphrased.
    # "A goal was carried" must not be the claim being tested - the wording is.
    with tempfile.TemporaryDirectory() as tmp2:
        cfg = os.path.join(tmp2, "config")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        paraphrase = "Keep the loop going until the backlog is done."
        write_session(cfg, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(cfg, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T03:00:00+00:00", goal_text=paraphrase,
                      goal_builder=carried_goal)
        drift = run(cfg, proj, gf, [])
        check("a carried goal that was paraphrased is reported as drift",
              drift["goal_carries_intact"] == 0,
              "goal_carries_intact=%s" % drift["goal_carries_intact"])
        check("the drifted wording is reported, not just the fact of drift",
              drift["sessions"][1]["goal_received"] == paraphrase,
              "goal_received=%r" % drift["sessions"][1]["goal_received"])

    # A session whose lines carry no readable timestamp at all. parse_time tolerates a
    # malformed stamp per line, so the whole report has to tolerate a session made only
    # of them: one such transcript must not take down the analysis of every other.
    with tempfile.TemporaryDirectory() as tmp3:
        cfg = os.path.join(tmp3, "config")
        proj = os.path.join(tmp3, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp3, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(cfg, "p", "timed", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
        write_session(cfg, "p", "untimed", proj, "not-a-time", "not-a-time")
        report4 = run(cfg, proj, gf, [])
        ids4 = [s["session_id"] for s in report4["sessions"]]
        check("a session with no readable timestamp is kept, and sorts after the timed ones",
              ids4 == ["timed", "untimed"], "got %s" % ids4)

    if FAILURES:
        print("\n%d check(s) failed" % len(FAILURES))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
