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


# Every spelling a goal is recorded in is a fixture, not one canonical form. This suite
# passed 12/12 against a detector that could see only the envelope, because the envelope
# was the only thing the fixtures ever produced - a green suite proving the fixture agreed
# with the code, and nothing about the transcripts either would meet.
def raw_goal(text):
    """A /goal that arrived and never executed: pasted at a real goal's size, v2.1.263
    records it as this plain text, with no command and no Stop hook."""
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


def write_session(transcripts_dir, slug, session_id, cwd, start, end,
                  goal_text=None, commands=(), goal_builder=None,
                  bracket_type="assistant", extra=(), entrypoint="cli"):
    """bracket_type is the type of the first and last entries: "assistant" is a session
    that took a turn; a boot-time type is one still forming. extra entries are written
    between them as given. entrypoint is stamped on every user and assistant entry the
    way Claude Code v2.1.263 records it: "cli" for an interactive session, "sdk-cli" for
    a headless `claude -p`; None writes entries with no entrypoint at all."""
    directory = os.path.join(transcripts_dir, slug)
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
    for line in lines:
        if line.get("type") in ("user", "assistant") and entrypoint is not None:
            line["entrypoint"] = entrypoint
    with open(path, "w") as handle:
        for line in lines:
            handle.write(json.dumps(line) + "\n")
    return path


def assistant_block(message_id, output=0, input_tokens=0, cache_creation=0, cache_read=0):
    """One assistant entry, as Claude Code writes ONE PER CONTENT BLOCK.

    Every block of a message repeats that message's whole usage, so a message billed
    three blocks appears three times here carrying the same numbers - which is the
    fixture the token totals have to survive, not an artificial one.
    """
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "id": message_id,
            "content": [{"type": "text", "text": "."}],
            "usage": {
                "input_tokens": input_tokens,
                "cache_creation_input_tokens": cache_creation,
                "cache_read_input_tokens": cache_read,
                "output_tokens": output,
            },
        },
    }


def run(transcripts_dir, project_dir, goal_file, commits):
    payload = "".join("%s\t%s\n" % (sha, when) for sha, when in commits)
    result = subprocess.run(
        [sys.executable, SESSIONS, transcripts_dir, project_dir, goal_file],
        input=payload, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise AssertionError("sessions.py failed: %s" % result.stderr)
    return json.loads(result.stdout)


def build(tmp):
    """A run of three sessions: two that commit, then one that does not."""
    transcripts_dir = os.path.join(tmp, "transcripts")
    project_dir = os.path.join(tmp, "project")
    other_dir = os.path.join(tmp, "other")
    os.makedirs(project_dir)
    os.makedirs(other_dir)

    goal_file = os.path.join(tmp, "GOAL_PROMPT.md")
    with open(goal_file, "w") as handle:
        handle.write(PINNED_GOAL + "\n")

    write_session(transcripts_dir, "proj", "s1", project_dir,
                  "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                  goal_text=PINNED_GOAL)
    write_session(transcripts_dir, "proj", "s2", project_dir,
                  "2026-01-01T02:00:00+00:00", "2026-01-01T03:00:00+00:00",
                  goal_text=PINNED_GOAL)
    write_session(transcripts_dir, "proj", "s3", project_dir,
                  "2026-01-01T04:00:00+00:00", "2026-01-01T05:00:00+00:00",
                  goal_text="just do whatever seems good")
    # A session carrying ONLY a /clear. finalize-session issues one on every single
    # handoff, so if any command envelope were read as a goal this would be the common
    # case, and a run whose goal never carried would report itself perfectly healthy.
    write_session(transcripts_dir, "proj", "s4", project_dir,
                  "2026-01-01T06:00:00+00:00", "2026-01-01T07:00:00+00:00",
                  commands=[("/clear", "")])
    # A session of a DIFFERENT project, sharing the same config dir.
    write_session(transcripts_dir, "other", "s9", other_dir,
                  "2026-01-01T00:30:00+00:00", "2026-01-01T00:45:00+00:00")
    # A headless `claude -p` a tool inside s2 spawned - the address-pr-reviews adversarial
    # provider runs its reviewer this way - with the SAME config dir and cwd as the run.
    # It takes turns and carries no goal, so read as a session it is a lost carry that
    # stops a healthy run (acceptance attempt 2, 2026-09-08). Its user entries say what
    # it is: entrypoint "sdk-cli", where the run's own sessions record "cli".
    write_session(transcripts_dir, "proj", "r1", project_dir,
                  "2026-01-01T02:10:00+00:00", "2026-01-01T02:20:00+00:00",
                  entrypoint="sdk-cli",
                  extra=[user_text("# Adversarial code review\n\nYou are a hostile reviewer.")])

    commits = [
        ("aaa1", "2026-01-01T00:30:00+00:00"),   # inside s1
        ("bbb2", "2026-01-01T02:30:00+00:00"),   # inside s2
    ]
    return transcripts_dir, project_dir, goal_file, commits


def main():
    with tempfile.TemporaryDirectory() as tmp:
        transcripts_dir, project_dir, goal_file, commits = build(tmp)
        report = run(transcripts_dir, project_dir, goal_file, commits)

        ids = [s["session_id"] for s in report["sessions"]]

        check("a session belonging to another project is excluded",
              "s9" not in ids, "got %s" % ids)
        check("a headless claude spawned by a tool inside a session is not a session of the run",
              "r1" not in ids, "got %s" % ids)
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
        check("session one's executed pinned goal is reported in force",
              report["session_one_goal_in_force"] is True,
              "got %r" % report.get("session_one_goal_in_force"))

        # The driver reads three values out of this report through lib.sh. Fed the real
        # output, so a key renamed on either side fails here and not mid-campaign.
        counts = subprocess.run(
            ["bash", "-c", '. "$1/lib.sh" && horizon_report_counts', "-", HERE],
            input=json.dumps(report), capture_output=True, text=True,
        )
        check("lib.sh reads the report's counts the way sessions.py writes them",
              counts.returncode == 0 and counts.stdout.split() == ["2", "2", "1"],
              "rc=%s out=%r err=%r" % (counts.returncode, counts.stdout, counts.stderr))

        # A commit outside every session window must be surfaced, not dropped: silently
        # discarding it would let a broken window calculation read as a clean run.
        report2 = run(transcripts_dir, project_dir, goal_file,
                      commits + [("ccc3", "2026-06-01T00:00:00+00:00")])
        check("a commit outside every session window is reported, not dropped",
              report2["unattributed_commits"] == ["ccc3"],
              "got %s" % report2["unattributed_commits"])

        # An idle session BETWEEN two committing ones must break the streak - a loop
        # that stalled and resumed is precisely what "consecutive" excludes.
        with tempfile.TemporaryDirectory() as tmp2:
            transcripts = os.path.join(tmp2, "transcripts")
            proj = os.path.join(tmp2, "project")
            os.makedirs(proj)
            gf = os.path.join(tmp2, "g.md")
            with open(gf, "w") as handle:
                handle.write(PINNED_GOAL + "\n")
            write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
            write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00", "2026-01-01T03:00:00+00:00")
            write_session(transcripts, "p", "c", proj, "2026-01-01T04:00:00+00:00", "2026-01-01T05:00:00+00:00")
            gap = run(transcripts, proj, gf, [("x", "2026-01-01T00:30:00+00:00"),
                                      ("y", "2026-01-01T04:30:00+00:00")])
            check("an idle session between two committing ones breaks the streak",
                  gap["consecutive_with_commits"] == 1,
                  "got %s" % gap["consecutive_with_commits"])

    # A goal that arrived as plain text never executed, so it is not a goal in force -
    # not for a successor, and not for session one. Attempt 3 was exactly this shape: the
    # driver's own pasted /goal, which this reader then counted as issued.
    with tempfile.TemporaryDirectory() as tmp2:
        transcripts = os.path.join(tmp2, "transcripts")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL, goal_builder=raw_goal)
        write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T03:00:00+00:00", goal_text=PINNED_GOAL, goal_builder=raw_goal)
        pasted = run(transcripts, proj, gf, [])
        check("a /goal recorded only as pasted plain text is not a goal in force",
              pasted["sessions"][1]["goal_issued"] is False
              and pasted["goal_carries_expected"] == 1
              and pasted["goal_carries_intact"] == 0,
              "got issued=%s expected=%s intact=%s"
              % (pasted["sessions"][1]["goal_issued"], pasted["goal_carries_expected"],
                 pasted["goal_carries_intact"]))
        check("session one whose goal was only pasted has no goal in force",
              pasted.get("session_one_goal_in_force") is False,
              "got %r" % pasted.get("session_one_goal_in_force"))

    # Every spelling an executed goal is recorded in must be seen, because a spelling this
    # reader cannot parse produces the identical output to a carry that genuinely died -
    # and then the run reports its own instrument as broken, or worse, as fine.
    for label, builder in (("envelope", lambda t: slash_command("/goal", t)),
                           ("carried Stop-hook condition", carried_goal)):
        with tempfile.TemporaryDirectory() as tmp2:
            transcripts = os.path.join(tmp2, "transcripts")
            proj = os.path.join(tmp2, "project")
            os.makedirs(proj)
            gf = os.path.join(tmp2, "g.md")
            with open(gf, "w") as handle:
                handle.write(PINNED_GOAL + "\n")
            write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                          "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
            write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                          "2026-01-01T03:00:00+00:00", goal_text=PINNED_GOAL,
                          goal_builder=builder)
            seen = run(transcripts, proj, gf, [])
            check("a goal recorded as %s is recognised" % label,
                  seen["goal_carries_intact"] == 1,
                  "goal_carries_intact=%s goal_received=%r"
                  % (seen["goal_carries_intact"], seen["sessions"][1]["goal_received"]))

    # A successor whose transcript exists but holds no turn yet is still booting: the
    # carried goal is announced several entries in, so judging it now would read a carry
    # that has not happened yet as one that failed - and stop a healthy run.
    with tempfile.TemporaryDirectory() as tmp2:
        transcripts = os.path.join(tmp2, "transcripts")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T02:00:01+00:00", bracket_type="file-history-snapshot")
        forming = run(transcripts, proj, gf, [])
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
        transcripts = os.path.join(tmp2, "transcripts")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T02:00:01+00:00", bracket_type="file-history-snapshot",
                      extra=[{"type": "assistant", "isSidechain": True}])
        write_session(transcripts, "p", "c", proj, "2026-01-01T03:00:00+00:00",
                      "2026-01-01T03:00:01+00:00", bracket_type="file-history-snapshot",
                      goal_text=PINNED_GOAL, goal_builder=carried_goal)
        write_session(transcripts, "p", "d", proj, "2026-01-01T04:00:00+00:00",
                      "2026-01-01T05:00:00+00:00", goal_text=PINNED_GOAL,
                      goal_builder=carried_goal,
                      commands=[("/goal", "just keep going")])
        judged = run(transcripts, proj, gf, [])
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
        transcripts = os.path.join(tmp2, "transcripts")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(quoted + "\n")
        write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=quoted)
        write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T03:00:00+00:00", goal_text=quoted,
                      goal_builder=carried_goal)
        seen = run(transcripts, proj, gf, [])
        check("a carried goal containing a double quote is read whole",
              seen["goal_carries_intact"] == 1
              and seen["sessions"][1]["goal_received"] == quoted,
              "goal_received=%r" % seen["sessions"][1]["goal_received"])

    # The drift this eval exists to catch: a carry that ARRIVES but has been paraphrased.
    # "A goal was carried" must not be the claim being tested - the wording is.
    with tempfile.TemporaryDirectory() as tmp2:
        transcripts = os.path.join(tmp2, "transcripts")
        proj = os.path.join(tmp2, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp2, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        paraphrase = "Keep the loop going until the backlog is done."
        write_session(transcripts, "p", "a", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL)
        write_session(transcripts, "p", "b", proj, "2026-01-01T02:00:00+00:00",
                      "2026-01-01T03:00:00+00:00", goal_text=paraphrase,
                      goal_builder=carried_goal)
        drift = run(transcripts, proj, gf, [])
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
        transcripts = os.path.join(tmp3, "transcripts")
        proj = os.path.join(tmp3, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp3, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "timed", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
        write_session(transcripts, "p", "untimed", proj, "not-a-time", "not-a-time")
        report4 = run(transcripts, proj, gf, [])
        ids4 = [s["session_id"] for s in report4["sessions"]]
        check("a session with no readable timestamp is kept, and sorts after the timed ones",
              ids4 == ["timed", "untimed"], "got %s" % ids4)

    # Lines that are not JSON objects at all: a torn write, a bare scalar, an array. The
    # session they sit in is still read, and so is every other.
    with tempfile.TemporaryDirectory() as tmp4:
        transcripts = os.path.join(tmp4, "transcripts")
        proj = os.path.join(tmp4, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp4, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        path = write_session(transcripts, "p", "torn", proj,
                             "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
        with open(path) as handle:
            lines = handle.readlines()
        with open(path, "w") as handle:
            handle.write(lines[0])
            handle.write('{"sessionId": "torn", "cwd": "%s", "ti\n' % proj)
            handle.write("42\n")
            handle.write("[1, 2]\n")
            handle.write("".join(lines[1:]))
        report5 = run(transcripts, proj, gf, [])
        check("a transcript with non-object lines is still read, and has its turn",
              [s["session_id"] for s in report5["sessions"]] == ["torn"]
              and report5["sessions"][0]["has_turn"],
              "got %s" % report5["sessions"])

    # A transcript that took turns but records no entrypoint anywhere is a harness this
    # reader cannot tell from a headless subprocess. Counting it would revive the exact
    # misreading above on the next Claude Code version that renames the field; the
    # report refuses instead, and horizon_report turns that refusal into a stopped run.
    with tempfile.TemporaryDirectory() as tmp5:
        transcripts = os.path.join(tmp5, "transcripts")
        proj = os.path.join(tmp5, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp5, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "unlabelled", proj, "2026-01-01T00:00:00+00:00",
                      "2026-01-01T01:00:00+00:00", goal_text=PINNED_GOAL, entrypoint=None)
        result = subprocess.run(
            [sys.executable, SESSIONS, transcripts, proj, gf],
            input="", capture_output=True, text=True,
        )
        check("a transcript with turns but no entrypoint is refused, naming the transcript",
              result.returncode != 0 and "unlabelled" in result.stderr
              and "entrypoint" in result.stderr,
              "rc=%s stderr=%r" % (result.returncode, result.stderr))

    # ── What the run COST ───────────────────────────────────────────────────────────
    # The bundle reports token totals so two arms can be compared on price as well as on
    # outcome, which makes every one of these a number a human will quote. Each check
    # below guards a way the count has already been shown to be wrong on real data.
    with tempfile.TemporaryDirectory() as tmp6:
        transcripts = os.path.join(tmp6, "transcripts")
        proj = os.path.join(tmp6, "project")
        other = os.path.join(tmp6, "other")
        os.makedirs(proj)
        os.makedirs(other)
        gf = os.path.join(tmp6, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")

        # One message billed across three blocks, plus a second message. A reader that
        # sums entries reports 3000+500; the truth is 1000+500. Measured on a real
        # 475-entry transcript on 2026-09-21, that error was 2.6x.
        write_session(transcripts, "p", "one", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL,
                      extra=[assistant_block("m1", output=1000, cache_read=7),
                             assistant_block("m1", output=1000, cache_read=7),
                             assistant_block("m1", output=1000, cache_read=7),
                             assistant_block("m2", output=500, input_tokens=3)])
        # A subagent the session dispatched. Its tokens are spent BY this session, so
        # they belong to it - a configuration that leans on subagents must not look free.
        write_session(transcripts, "p", "two", proj,
                      "2026-01-01T02:00:00+00:00", "2026-01-01T03:00:00+00:00",
                      goal_text=PINNED_GOAL,
                      extra=[assistant_block("m3", output=40),
                             dict(assistant_block("m4", output=60), isSidechain=True)])
        # A headless `claude -p` the run spawned: not a session, but real spend.
        write_session(transcripts, "p", "reviewer", proj,
                      "2026-01-01T02:10:00+00:00", "2026-01-01T02:20:00+00:00",
                      entrypoint="sdk-cli",
                      extra=[assistant_block("m5", output=7000)])
        # A headless `claude -p` a tool spawned from a git worktree UNDER the project.
        # Its cwd is not the project's own, and under an equality test it came back
        # FOREIGN and its spend vanished from the report entirely.
        write_session(transcripts, "p", "worktree-reviewer",
                      os.path.join(proj, ".claude", "worktrees", "wt"),
                      "2026-01-01T02:30:00+00:00", "2026-01-01T02:40:00+00:00",
                      entrypoint="sdk-cli",
                      extra=[assistant_block("m7", output=300)])
        # Another project sharing the directory: not this run's spend at all.
        write_session(transcripts, "elsewhere", "stranger", other,
                      "2026-01-01T00:30:00+00:00", "2026-01-01T00:45:00+00:00",
                      extra=[assistant_block("m6", output=999999)])

        cost = run(transcripts, proj, gf, [])
        by_id = {s["session_id"]: s for s in cost["sessions"]}

        check("a message billed across several blocks is counted once",
              by_id["one"]["tokens"]["output_tokens"] == 1500,
              "got %s" % by_id["one"]["tokens"])
        check("every usage field is carried, not just output",
              by_id["one"]["tokens"]["cache_read_input_tokens"] == 7
              and by_id["one"]["tokens"]["input_tokens"] == 3,
              "got %s" % by_id["one"]["tokens"])
        check("a subagent's tokens are billed to the session that dispatched it",
              by_id["two"]["tokens"]["output_tokens"] == 100,
              "got %s" % by_id["two"]["tokens"])
        check("session totals are the sum of the sessions",
              cost["tokens"]["sessions"]["output_tokens"] == 1600,
              "got %s" % cost["tokens"]["sessions"])
        check("a headless subprocess is billed to the run, apart from the sessions",
              cost["tokens"]["subprocesses"]["output_tokens"] == 7300
              and cost["tokens"]["total"]["output_tokens"] == 8900,
              "got subprocesses=%s total=%s"
              % (cost["tokens"]["subprocesses"], cost["tokens"]["total"]))
        check("a subprocess run from inside the project is billed, not dropped as foreign",
              cost["tokens"]["subprocesses"]["output_tokens"] == 7300,
              "got %s" % cost["tokens"]["subprocesses"])
        check("another project's tokens are not billed to this run",
              cost["tokens"]["total"]["output_tokens"] == 8900,
              "got %s" % cost["tokens"]["total"])
        # Dropped on purpose, and said out loud: the refusal below only fires when EVERY
        # transcript is foreign, so a run that dropped one would otherwise read exactly
        # like a run that had none to drop.
        check("a transcript belonging elsewhere is reported, not merely left out",
              cost["foreign_transcripts"] == 1,
              "got %s" % cost.get("foreign_transcripts"))

    # Every transcript belonging to somewhere else, and none to the project: the shape an
    # archived run takes when it is handed the path the BUNDLE sits at rather than the
    # path the run used. It reads as a run in which nothing ever happened, so it is
    # refused instead - the zero is the dangerous answer, not the error.
    with tempfile.TemporaryDirectory() as tmp7:
        transcripts = os.path.join(tmp7, "transcripts")
        proj = os.path.join(tmp7, "project")
        other = os.path.join(tmp7, "elsewhere")
        os.makedirs(proj)
        os.makedirs(other)
        gf = os.path.join(tmp7, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "moved", other,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00")
        moved = subprocess.run(
            [sys.executable, SESSIONS, transcripts, proj, gf],
            input="", capture_output=True, text=True,
        )
        check("transcripts that all belong elsewhere are refused, not reported as a quiet zero",
              moved.returncode != 0 and "run.json" in moved.stderr,
              "rc=%s stderr=%r" % (moved.returncode, moved.stderr))

    # Collapsing a message's blocks is only lossless while they agree about what the
    # message cost. Nothing in the schema promises that, and a version that broke it
    # would keep the first block met and under-report the rest - a smaller number, still
    # entirely plausible, with nothing anywhere saying it had changed meaning. So it is
    # counted and the larger figure kept; the close-out is what refuses a run reporting
    # any, because this also runs on the live poll and must not kill a run mid-flight.
    with tempfile.TemporaryDirectory() as tmp8:
        transcripts = os.path.join(tmp8, "transcripts")
        proj = os.path.join(tmp8, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp8, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "disagreeing", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL,
                      extra=[assistant_block("m1", output=1000),
                             assistant_block("m1", output=250),
                             assistant_block("m2", output=100),
                             assistant_block("m2", output=400)])
        clashed = run(transcripts, proj, gf, [])
        check("blocks of one message disagreeing about usage are counted, not assumed away",
              clashed["usage_disagreements"] == 2,
              "got %s" % clashed.get("usage_disagreements"))
        check("a disagreed usage is billed at the larger figure, never the first seen",
              clashed["tokens"]["total"]["output_tokens"] == 1400,
              "got %s" % clashed["tokens"]["total"])

    # The ordinary case, stated so the count above cannot pass by counting everything:
    # identical repeats are what a real transcript holds, and they are not disagreements.
    with tempfile.TemporaryDirectory() as tmp9:
        transcripts = os.path.join(tmp9, "transcripts")
        proj = os.path.join(tmp9, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp9, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "agreeing", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL,
                      extra=[assistant_block("m1", output=1000),
                             assistant_block("m1", output=1000)])
        agreed = run(transcripts, proj, gf, [])
        check("blocks repeating one usage are not counted as a disagreement",
              agreed["usage_disagreements"] == 0,
              "got %s" % agreed.get("usage_disagreements"))

    # A transcript that has recorded no cwd AT ALL. write_session cannot produce one - it
    # stamps a cwd on every entry - which is exactly why this went uncaught: Claude Code
    # opens a transcript with boot entries carrying neither cwd nor entrypoint, and 53 of
    # 3000 transcripts on a real machine never acquire one. Read as "belongs to another
    # project", a session that was merely still booting tripped the all-foreign abort, and
    # the driver polls this every two seconds from launch - so an unattended run died at
    # minute zero, reported as an archived bundle handed the wrong path.
    with tempfile.TemporaryDirectory() as tmp10:
        transcripts = os.path.join(tmp10, "transcripts", "p")
        proj = os.path.join(tmp10, "project")
        os.makedirs(transcripts)
        os.makedirs(proj)
        gf = os.path.join(tmp10, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        with open(os.path.join(transcripts, "booting.jsonl"), "w") as handle:
            for line in ({"type": "last-prompt", "sessionId": "booting"},
                         {"type": "mode", "sessionId": "booting"}):
                handle.write(json.dumps(line) + "\n")
        booting = subprocess.run(
            [sys.executable, SESSIONS, os.path.join(tmp10, "transcripts"), proj, gf],
            input="", capture_output=True, text=True,
        )
        check("a transcript that has recorded no cwd yet does not kill the report",
              booting.returncode == 0,
              "rc=%s stderr=%r" % (booting.returncode, booting.stderr))
        if booting.returncode == 0:
            state = json.loads(booting.stdout)
            check("a transcript with no cwd is counted as forming, not as another project's",
                  state["forming_transcripts"] == 1 and state["foreign_transcripts"] == 0,
                  "forming=%s foreign=%s" % (state.get("forming_transcripts"),
                                             state.get("foreign_transcripts")))

    # A forming transcript that SPENT something. Normally they are stubs, and "normally"
    # is not a reason to drop a number: dropping it makes the totals quietly smaller,
    # which is the failure the disagreement count exists to catch. Reported apart from
    # the totals, because nothing here can say whose spend it is.
    with tempfile.TemporaryDirectory() as tmp11:
        transcripts = os.path.join(tmp11, "transcripts", "p")
        proj = os.path.join(tmp11, "project")
        os.makedirs(transcripts)
        os.makedirs(proj)
        gf = os.path.join(tmp11, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        with open(os.path.join(transcripts, "orphan.jsonl"), "w") as handle:
            handle.write(json.dumps({"type": "last-prompt", "sessionId": "orphan"}) + "\n")
            handle.write(json.dumps(assistant_block("m9", output=4242)) + "\n")
        orphaned = run(os.path.join(tmp11, "transcripts"), proj, gf, [])
        check("spend in a transcript nothing can attribute is reported, not discarded",
              orphaned["tokens"]["unattributed"]["output_tokens"] == 4242,
              "got %s" % orphaned["tokens"]["unattributed"])
        check("unattributed spend is kept out of the total the analysis stands behind",
              orphaned["tokens"]["total"]["output_tokens"] == 0,
              "got %s" % orphaned["tokens"]["total"])

    # The all-foreign abort, asked whether it means what its sentence says. A SUBPROCESS
    # matched the project - that match is the whole difference between it and a foreign
    # transcript - it is simply not a session. Keyed on `sessions` alone, the refusal fired
    # on a bundle holding a headless reviewer that plainly did belong, and told the reader
    # every transcript was another project's while billing one of them to this run in the
    # same document.
    with tempfile.TemporaryDirectory() as tmp12:
        transcripts = os.path.join(tmp12, "transcripts")
        proj = os.path.join(tmp12, "project")
        other = os.path.join(tmp12, "elsewhere")
        os.makedirs(proj)
        os.makedirs(other)
        gf = os.path.join(tmp12, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "reviewer", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T00:10:00+00:00",
                      entrypoint="sdk-cli", extra=[assistant_block("m1", output=55)])
        write_session(transcripts, "elsewhere", "stranger", other,
                      "2026-01-01T00:30:00+00:00", "2026-01-01T00:45:00+00:00",
                      extra=[assistant_block("m2", output=999)])
        mixed = subprocess.run(
            [sys.executable, SESSIONS, transcripts, proj, gf],
            input="", capture_output=True, text=True,
        )
        check("a bundle whose only match is a subprocess is not called all-foreign",
              mixed.returncode == 0,
              "rc=%s stderr=%r" % (mixed.returncode, mixed.stderr))
        if mixed.returncode == 0:
            state = json.loads(mixed.stdout)
            check("the subprocess that kept the abort quiet is counted in the record",
                  state["subprocess_transcripts"] == 1
                  and state["foreign_transcripts"] == 1
                  and state["tokens"]["subprocesses"]["output_tokens"] == 55,
                  "subprocess=%s foreign=%s tokens=%s"
                  % (state.get("subprocess_transcripts"),
                     state.get("foreign_transcripts"),
                     state["tokens"]["subprocesses"]))

        # And the abort still fires when nothing at all belonged, which is the state it
        # was written for: an archived bundle read with the wrong project path.
        alone = os.path.join(tmp12, "foreign-only")
        os.makedirs(alone)
        write_session(alone, "elsewhere", "stranger2", other,
                      "2026-01-01T01:00:00+00:00", "2026-01-01T01:05:00+00:00",
                      extra=[assistant_block("m3", output=1)])
        only = subprocess.run(
            [sys.executable, SESSIONS, alone, proj, gf],
            input="", capture_output=True, text=True,
        )
        check("a bundle where nothing belonged is still refused by name",
              only.returncode != 0 and "run.json" in only.stderr,
              "rc=%s stderr=%r" % (only.returncode, only.stderr))

    # An INTERACTIVE session recorded in a worktree under the project. `within()` was
    # written for the headless case, and it admits this one too - deliberately, and stated
    # here so the next reader does not read it as an oversight and tighten it back to an
    # equality. The run's own agent moves into a worktree of the project when the work
    # wants isolation; that transcript is the run's, its commits are the run's, and an
    # exact-cwd test would drop both - understating the acceptance criterion the bundle
    # exists to report on. The harness cannot produce a stranger here: the config dir is
    # wiped and rebuilt per run and nobody else works in it.
    with tempfile.TemporaryDirectory() as tmp13:
        transcripts = os.path.join(tmp13, "transcripts")
        proj = os.path.join(tmp13, "project")
        os.makedirs(proj)
        gf = os.path.join(tmp13, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "in-worktree",
                      os.path.join(proj, ".claude", "worktrees", "wt"),
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL,
                      extra=[assistant_block("m1", output=12)])
        moved_in = run(transcripts, proj, gf, [])
        check("an interactive session working in a worktree of the project is the run's own",
              [s["session_id"] for s in moved_in["sessions"]] == ["in-worktree"]
              and moved_in["foreign_transcripts"] == 0,
              "sessions=%s foreign=%s"
              % ([s["session_id"] for s in moved_in["sessions"]],
                 moved_in.get("foreign_transcripts")))
        check("its spend is billed to the sessions, not to the subprocesses",
              moved_in["tokens"]["sessions"]["output_tokens"] == 12
              and moved_in["tokens"]["subprocesses"]["output_tokens"] == 0,
              "sessions=%s subprocesses=%s"
              % (moved_in["tokens"]["sessions"], moved_in["tokens"]["subprocesses"]))

    # The sibling whose name STARTS WITH the project's. `within()` names this case in its
    # own docstring as the reason it tests for a separator rather than taking a bare string
    # prefix, and nothing exercised it - so dropping the `+ os.sep` would have started
    # billing an unrelated project's spend to this run and every check would still pass.
    # A refusal a test never expresses is a refusal that can be deleted by accident.
    with tempfile.TemporaryDirectory() as tmp14:
        transcripts = os.path.join(tmp14, "transcripts")
        proj = os.path.join(tmp14, "project")
        sibling = os.path.join(tmp14, "project-two")
        os.makedirs(proj)
        os.makedirs(sibling)
        gf = os.path.join(tmp14, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "p", "ours", proj,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL, extra=[assistant_block("m1", output=10)])
        write_session(transcripts, "p2", "theirs", sibling,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      goal_text=PINNED_GOAL, extra=[assistant_block("m2", output=88888)])
        siblings = run(transcripts, proj, gf, [])
        check("a sibling directory whose name merely starts with the project's is foreign",
              [s["session_id"] for s in siblings["sessions"]] == ["ours"]
              and siblings["foreign_transcripts"] == 1,
              "sessions=%s foreign=%s"
              % ([s["session_id"] for s in siblings["sessions"]],
                 siblings.get("foreign_transcripts")))
        check("a sibling project's spend is not billed to this run",
              siblings["tokens"]["total"]["output_tokens"] == 10,
              "got %s" % siblings["tokens"]["total"])

    # Foreign and forming together at the abort. The operator who sees this is debugging
    # "which transcripts belong where", so counting the unplaceable ones in with the ones
    # proved to be elsewhere answers that question wrongly in the one message written to
    # answer it. The two states are not interchangeable and the sentence may not merge them.
    with tempfile.TemporaryDirectory() as tmp15:
        transcripts = os.path.join(tmp15, "transcripts")
        proj = os.path.join(tmp15, "project")
        other = os.path.join(tmp15, "elsewhere")
        os.makedirs(proj)
        os.makedirs(other)
        os.makedirs(os.path.join(transcripts, "p"))
        gf = os.path.join(tmp15, "g.md")
        with open(gf, "w") as handle:
            handle.write(PINNED_GOAL + "\n")
        write_session(transcripts, "elsewhere", "stranger3", other,
                      "2026-01-01T00:00:00+00:00", "2026-01-01T01:00:00+00:00",
                      extra=[assistant_block("m1", output=5)])
        with open(os.path.join(transcripts, "p", "booting2.jsonl"), "w") as handle:
            handle.write(json.dumps({"type": "last-prompt", "sessionId": "booting2"}) + "\n")
        mixed_abort = subprocess.run(
            [sys.executable, SESSIONS, transcripts, proj, gf],
            input="", capture_output=True, text=True,
        )
        check("an archived bundle with nothing that belongs is still refused",
              mixed_abort.returncode != 0,
              "rc=%s stderr=%r" % (mixed_abort.returncode, mixed_abort.stderr))
        check("the refusal counts the unplaceable transcripts apart from the foreign ones",
              "1 found, all another project's" in mixed_abort.stderr
              and "1 more recorded no working directory" in mixed_abort.stderr,
              "stderr=%r" % mixed_abort.stderr)

    if FAILURES:
        print("\n%d check(s) failed" % len(FAILURES))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
