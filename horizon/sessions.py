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
  there is no second reader to disagree with this one about what a session is - and
  none about what a session COST, which is why the token totals are computed here
  rather than by a second pass over the same files. [LAW:one-source-of-truth]

Usage:
    sessions.py <transcripts-dir> <project-dir> <goal-file> < commits.tsv

<transcripts-dir> holds one directory per project slug, each holding one .jsonl per
session. That is the shape Claude Code writes at <config-dir>/projects, and the shape
the driver moves into a bundle at <bundle>/transcripts - one directory naming, so the
"recomputed from an archive months later" claim above is true of an archive and not
only of a live config dir. Pointing this at <config-dir> is the bug that made it false.

where commits.tsv is `<sha>\\t<committer-date-ISO8601>` per line, oldest first.
Prints one JSON object on stdout.
"""

import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

# A goal in force is recorded in one of TWO spellings, both left by a /goal that EXECUTED.
# A reader that knows only one reports the other as "this session got no goal" - the
# identical output a genuinely lost carry produces - so both are parsed here and reduced
# to one answer. [LAW:parse-dont-validate]
#
# A /goal that only ARRIVED is deliberately not a third. Pasted at a real goal's size,
# Claude Code collapses it into a "[Pasted text #n]" placeholder and submits it as a
# plain message reading "/goal ...": no command runs and no Stop hook is installed, so the
# session follows the wording as ordinary text until its first quiet turn ends the run
# (acceptance attempt 3, 2026-09-08, v2.1.263). This reader used to count that plain text,
# and so reported runs in which no session ever had a goal in force as carrying one.
#
# Recording the wording, not just its presence: "a goal was issued" is the weaker claim
# that stays true while the text degrades into something else.
#
# The command envelope an executed /goal leaves in the session that ran it.
COMMAND_NAME_RE = re.compile(r"<command-name>\s*(?P<name>[^<]+?)\s*</command-name>")
COMMAND_ARGS_RE = re.compile(r"<command-args>(?P<args>.*?)</command-args>", re.DOTALL)
# The line an executed /goal adds once it installs its session-scoped Stop hook, telling
# the session its condition. A carried goal can show up as only this line, so a reader
# without it reports a healthy carry and a dead one identically. Anchored on the
# template's closing phrase rather than on the next quote character: the goal is prose,
# and prose contains quotes.
STOP_HOOK_GOAL_RE = re.compile(
    r"Stop hook is now active with condition:\s*\"(?P<goal>.*)\"\.\s*Briefly acknowledge",
    re.DOTALL,
)


def goal_text(text):
    """The goal wording an entry establishes, or None when it establishes none.

    None means "this entry says nothing about the goal" - never "the goal is empty".
    The two are different findings and the caller must be able to tell them apart.
    """
    name = COMMAND_NAME_RE.search(text)
    if name and name.group("name").strip() == "/goal":
        args = COMMAND_ARGS_RE.search(text)
        return args.group("args").strip() if args else ""
    hook = STOP_HOOK_GOAL_RE.search(text)
    if hook:
        return hook.group("goal").strip()
    return None


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


# The usage fields Claude Code records on every assistant message. Kept under the
# transcript's own names rather than translated into prettier ones: a translation layer
# is a second naming of one fact, and the day the schema gains a field the translation
# is where it goes missing. [LAW:one-source-of-truth]
#
# Deliberately NOT summed into a single "total tokens". Cached reads and fresh output
# differ by more than an order of magnitude in price, so one number adding them is a
# lie with a number attached - and this file's whole job is being the record a human
# trusts. Four honest counts beat one comfortable one.
TOKEN_FIELDS = ("input_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "output_tokens")


def no_tokens():
    return dict.fromkeys(TOKEN_FIELDS, 0)


def add_tokens(into, more):
    for field in TOKEN_FIELDS:
        into[field] += more[field]
    return into


def usage_of(entry):
    """The token usage an assistant entry reports, or None when it reports none.

    None means "this entry carries no usage" - never "this entry cost nothing". The
    caller must be able to tell a boot entry from a free turn, and there are no free
    turns.
    """
    if entry.get("type") != "assistant":
        return None
    message = entry.get("message")
    if not isinstance(message, dict):
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    return {field: usage.get(field) or 0 for field in TOKEN_FIELDS}


def message_key(entry, line_number):
    """What makes two assistant entries the same billed message.

    A transcript records ONE entry PER CONTENT BLOCK, and every one of them repeats the
    whole message's usage. Summing entries therefore bills a message once per block:
    measured against a real 475-entry transcript on 2026-09-21, that reported 356,255
    output tokens where the true figure was 134,647 - a 2.6x overstatement, in the
    direction that flatters nothing and misleads everything.

    The message id is the discriminator, and collapsing on it loses nothing only while
    the duplicates report identical usage - so read_transcript checks that rather than
    trusting it. It does not stop there, and must not: this runs on the live poll, where
    a nonzero exit is a dead run. A disagreement is COUNTED, the larger figure kept, and
    reported as `usage_disagreements` for the close-out to refuse - see the handling
    itself for the full reasoning. An entry with no id cannot be
    matched to any other, so it counts once on its own - the direction that can only
    ever UNDER-collapse, because a schema that stopped writing ids must not silently
    start billing at a fraction of the truth.
    """
    message = entry.get("message")
    identifier = message.get("id") if isinstance(message, dict) else None
    # ("entry", n), not ("line", n): n counts PARSED entries, and transcript_entries skips
    # unparseable lines, so it is not a file line number and must not be read as one.
    return ("id", identifier) if identifier else ("entry", line_number)


def transcript_entries(handle):
    """The JSON objects in a transcript, one per line; every other line is skipped.

    The one place a transcript line becomes an entry, so nothing downstream re-checks
    what it was handed. Skipped rather than raised, for the reason parse_time gives: one
    malformed line - a torn write, a bare scalar - must not take down a campaign's report.
    """
    for line in handle:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            yield entry


# The entrypoint every entry of an interactive claude records. A tool inside a session can
# spawn `claude -p` with the same config dir and cwd - the address-pr-reviews adversarial
# provider runs its reviewer that way - and that process writes its own transcript into
# the same projects/<slug>/ directory, stamped "sdk-cli". Acceptance attempt 2 (2026-09-08,
# v2.1.263) counted one as a session with no goal and stopped a healthy run as a lost
# carry. The stamp is the discriminator; cwd alone cannot tell the two apart.
INTERACTIVE_ENTRYPOINT = "cli"


def is_run_session(session_id, entrypoints, has_turn):
    """Whether a transcript recorded in the project's cwd is one of the run's own sessions.

    entrypoints is the set of `entrypoint` values the transcript's entries carry:
      empty        still booting - boot entries carry none - so a session, not yet judged
      {"cli"}      the interactive claude the driver launched, or memento reset in place
      anything else a process some tool spawned; it shares the directory, not the run
    A transcript that has taken turns and records no entrypoint at all is a harness this
    reader cannot classify. It refuses rather than counting it, because counting it is
    precisely the misreading above, and horizon_report turns the refusal into a stopped
    run. [LAW:no-silent-failure] [LAW:parse-dont-validate]
    """
    if has_turn and not entrypoints:
        sys.exit("transcript %s took turns but records no entrypoint; this Claude Code "
                 "version cannot be told from a headless subprocess" % session_id)
    return entrypoints <= {INTERACTIVE_ENTRYPOINT}


# What a transcript found in the run's directory turned out to be. Three outcomes, named,
# because the caller needs all three and they are not interchangeable: a SESSION counts
# toward the acceptance, a SUBPROCESS cost real tokens the run must be billed for but is
# not a session of it, and a FOREIGN transcript belongs to another project entirely and
# must not be billed at all. Returning None for the last two - as this once did - collapses
# "the run spawned a reviewer" and "somebody else was working in this config dir" into one
# value, and the bundle then under-reports what the run spent with nothing to show for it.
# [LAW:parse-dont-validate] the classification is the proof, kept, rather than a check
# thrown away at the door.
# FORMING is the state that cost a run. A transcript is FOREIGN only on EVIDENCE - it
# recorded a cwd and that cwd is somewhere else. A transcript that has recorded no cwd at
# all says nothing about where it belongs: Claude Code opens a transcript with boot
# entries (`last-prompt`, `mode`, `permission-mode`) that carry neither cwd nor
# entrypoint, so every session looks like this for its first moments, and 53 of 3000
# transcripts on a real machine never acquire one. Collapsing "nothing recorded yet" into
# "belongs to somebody else" put a session that was still booting into the bucket the
# abort below fires on - and the driver polls this every two seconds from the moment it
# launches, turning any nonzero exit into a dead run. An unattended run died at minute
# zero, reported as an archived bundle handed the wrong project path.
# [LAW:types-are-the-program] the absence of evidence gets its own name.
SESSION, SUBPROCESS, FOREIGN, FORMING = "session", "subprocess", "foreign", "forming"


def within(path, root):
    """True when `path` is `root` itself or sits inside it.

    Deliberately not an equality. A headless `claude -p` a tool spawns records the
    directory IT ran in, and that is a subdirectory or a git worktree of the project as
    often as the project itself - so under equality those transcripts came back FOREIGN
    and their spend was dropped from the report entirely, silently, with the reviewer
    subprocess being the expensive one. FOREIGN has to keep meaning "another project",
    because that reading is what the abort in main() rests on. [LAW:no-silent-failure]

    A prefix test on the realpath of BOTH sides, not a string prefix on the raw ones:
    `/a/project-two` starts with `/a/project` and is a different directory, and a root
    the caller had not normalised would match nothing at all. The separator is what
    makes it a containment test rather than a spelling one.
    """
    real = os.path.realpath(path)
    top = os.path.realpath(root)
    return real == top or real.startswith(top + os.sep)


def read_transcript(path, project_dir):
    """One transcript reduced to the facts the run's record asks about, and what it is.

    The cwd recorded inside the file is the authority on which project it belongs to, so
    no caller re-derives Claude Code's directory-naming rule.
    """
    want = os.path.realpath(project_dir)
    session_id = os.path.splitext(os.path.basename(path))[0]
    belongs = False
    located = False
    has_turn = False
    entrypoints = set()
    first_time = None
    last_time = None
    goal_args = []
    tokens = no_tokens()
    billed = {}
    disagreements = 0
    resolved = {}

    with open(path, errors="replace") as handle:
        for index, entry in enumerate(transcript_entries(handle)):
            cwd = entry.get("cwd")
            if cwd:
                located = True
                # One containment test per DISTINCT cwd rather than per entry. A session
                # records the same directory on nearly every line it writes - hundreds of
                # them - and `within` resolves both sides through the filesystem, so the
                # same realpath was being taken hundreds of times for the same answer.
                # It is not once per run either: the driver re-runs this whole analysis
                # from a fresh process every two seconds for the length of the run, so the
                # cost is paid again on every poll, over every transcript, forever.
                matched = resolved.get(cwd)
                if matched is None:
                    matched = resolved[cwd] = within(cwd, want)
                if matched:
                    belongs = True
            if "entrypoint" in entry:
                entrypoints.add(entry["entrypoint"])
            if entry.get("type") == "assistant" and not entry.get("isSidechain"):
                has_turn = True

            # Sidechain entries ARE billed even though they are not the session's own
            # turns: a subagent's tokens are spent by the session that dispatched it, and
            # a configuration that leans on subagents would otherwise look cheap.
            usage = usage_of(entry)
            key = message_key(entry, index)
            if usage is not None:
                already = billed.get(key)
                if already is None:
                    billed[key] = usage
                    add_tokens(tokens, usage)
                elif already != usage:
                    # Collapsing on the message id is only lossless while every block of
                    # one message repeats the SAME usage. That held everywhere it was
                    # measured, but nothing in the schema promises it, so the
                    # disagreement is COUNTED rather than assumed away - a total that
                    # quietly became a fraction of the truth is the failure being
                    # guarded against. [LAW:no-silent-failure]
                    #
                    # Counted and not raised, because this function also runs on the
                    # live poll, several times an hour, for the whole length of a run.
                    # Exiting here would end an eight-hour run over a bookkeeping
                    # detail that only has to be right at close-out - the driver turns
                    # any nonzero exit into a dead run. The close-out reads the count
                    # off the report and refuses THERE, where refusing costs nothing.
                    #
                    # The larger of each field is kept, because the shape this would
                    # most likely take is a partial usage followed by the complete one,
                    # and of the two available wrong answers a floor beats a fraction.
                    disagreements += 1
                    for field in TOKEN_FIELDS:
                        if usage[field] > already[field]:
                            tokens[field] += usage[field] - already[field]
                            already[field] = usage[field]

            stamp = parse_time(entry.get("timestamp"))
            if stamp is not None:
                if first_time is None or stamp < first_time:
                    first_time = stamp
                if last_time is None or stamp > last_time:
                    last_time = stamp

            # Sidechain entries are subagent traffic, not the session's own turns.
            if entry.get("type") != "user" or entry.get("isSidechain"):
                continue
            found = goal_text(message_text(entry))
            if found is not None:
                goal_args.append(found)

    if belongs:
        kind = SESSION if is_run_session(session_id, entrypoints, has_turn) else SUBPROCESS
    elif located:
        kind = FOREIGN
    else:
        kind = FORMING

    return {
        "kind": kind,
        "session_id": session_id,
        "started": first_time.isoformat() if first_time else None,
        "ended": last_time.isoformat() if last_time else None,
        "_start": first_time,
        "_end": last_time,
        "has_turn": has_turn,
        "goal_issues": goal_args,
        "tokens": tokens,
        "usage_disagreements": disagreements,
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
    transcripts_dir, project_dir, goal_file = sys.argv[1:]

    with open(goal_file) as handle:
        pinned_goal = handle.read().strip()

    sessions = []
    subprocesses = []
    subprocess_tokens = no_tokens()
    foreign = []
    forming = []
    unattributed_tokens = no_tokens()
    disagreements = 0
    for path in glob.glob(os.path.join(transcripts_dir, "*", "*.jsonl")):
        transcript = read_transcript(path, project_dir)
        if transcript["kind"] == SESSION:
            sessions.append(transcript)
            disagreements += transcript["usage_disagreements"]
        elif transcript["kind"] == SUBPROCESS:
            subprocesses.append(transcript["session_id"])
            add_tokens(subprocess_tokens, transcript["tokens"])
            disagreements += transcript["usage_disagreements"]
        elif transcript["kind"] == FOREIGN:
            foreign.append(transcript["session_id"])
        else:
            # Counted, not dropped. A forming transcript is normally a stub that spent
            # nothing, but "normally" is not a reason to discard a number: dropping it
            # would make the totals quietly smaller in exactly the way the disagreement
            # count above exists to prevent. Kept apart rather than added in, because
            # nothing here can say whose spend it is. [LAW:no-silent-failure]
            forming.append(transcript["session_id"])
            add_tokens(unattributed_tokens, transcript["tokens"])
            disagreements += transcript["usage_disagreements"]

    # Transcripts exist and not one of them is this project's. That is never a run: it is
    # a <project-dir> that does not match the cwd the transcripts recorded - the shape an
    # ARCHIVED run takes, whose transcripts still name the path the run used while the
    # bundle now sits somewhere else. Reported rather than returned, because "no session
    # belonged to this project" and "the run did nothing" produce identical output, and
    # the wrong one of those is a quiet zero a reader has no reason to doubt.
    # [LAW:no-silent-failure]
    # `sessions` alone is the wrong bucket to ask, and the message above is why: a
    # SUBPROCESS matched this project too - that is what made it a subprocess rather than
    # a foreign transcript - it is simply not a session of the run. A bundle holding one
    # headless reviewer and one genuinely foreign transcript would abort saying "all
    # another project's" about a set that demonstrably was not. The predicate has to be
    # the claim the sentence makes. [LAW:one-source-of-truth]
    if foreign and not sessions and not subprocesses:
        # Forming transcripts are named separately rather than folded into the count. They
        # are not evidence of anything: they recorded no working directory, so "all another
        # project's" is a claim about the foreign ones alone, and the operator reading this
        # is debugging precisely the question of which transcripts belong where.
        also = ""
        if forming:
            also = (" %d more recorded no working directory at all, so nothing can place "
                    "them either way." % len(forming))
        sys.exit("no transcript in %s belongs to %s (%d found, all another project's).%s\n"
                 "An archived run records the path it ran at, not where the bundle now "
                 "sits - pass project.path from the bundle's run.json."
                 % (transcripts_dir, project_dir, len(foreign), also))

    # Ordered by when they ran. Session ids are uuids and sort meaninglessly, and the
    # acceptance criterion is about CONSECUTIVE sessions, so the order has to be real.
    # The fallback is aware, like every real start: a naive one cannot be compared and
    # would crash the report on the first session with no readable timestamp.
    sessions.sort(key=lambda s: (s["_start"] or datetime.max.replace(tzinfo=timezone.utc)))

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

    session_tokens = no_tokens()
    for session in sessions:
        session.setdefault("commits", [])
        add_tokens(session_tokens, session["tokens"])
        session.pop("kind")
        issues = session.pop("goal_issues")
        session["goal_issued"] = bool(issues)
        # The carry is only intact if the wording that arrived is the wording that was
        # pinned. "A /goal was issued" is the weaker claim that would pass while the
        # agent paraphrased the condition into something else entirely. The LAST wording
        # is the one in force, and the one goal_received shows, so both read the same line.
        session["goal_matches_pinned"] = bool(issues) and issues[-1].strip() == pinned_goal
        # The wording that actually arrived, kept verbatim. A bare false says a carry
        # drifted; this says what it drifted INTO, which is the difference between a
        # human reading the bundle knowing something broke and knowing what broke.
        # Bounded because a goal is prose and this is a summary, not a second transcript.
        session["goal_received"] = issues[-1][:400] if issues else None
        session.pop("_start")
        session.pop("_end")

    with_commits = [s for s in sessions if s["commits"]]
    # Sessions after the first are the ones the carry has to survive; session one was
    # issued its goal by the driver, so counting it would flatter the result. A successor
    # is judged once there is evidence either way - a turn, or a recorded goal: the
    # carried goal is announced several boot entries after the transcript first records
    # its cwd, so a session with neither is still forming, and a live poll landing in
    # that window would otherwise read a healthy carry as a lost one. A session that
    # received its goal and died before turning is judged on what it received.
    successors = [s for s in sessions[1:] if s["has_turn"] or s["goal_issued"]]
    carried = [s for s in successors if s["goal_matches_pinned"]]

    json.dump(
        {
            "sessions": sessions,
            "session_count": len(sessions),
            "sessions_with_commits": len(with_commits),
            "consecutive_with_commits": consecutive_run(sessions),
            "goal_carries_intact": len(carried),
            "goal_carries_expected": len(successors),
            # Whether the driver's own launch put the pinned goal in force. The carry
            # counts exclude session one, so without this a run whose FIRST goal never
            # executed would look like a run with nothing to carry yet.
            "session_one_goal_in_force": bool(sessions) and sessions[0]["goal_matches_pinned"],
            "unattributed_commits": unattributed,
            # Transcripts that RECORDED a working directory and it was somebody else's.
            # Normally zero, and reported even so: the abort above only fires when every
            # transcript is foreign, so without this line a run that dropped one
            # transcript's spend would read exactly like a run that had none to drop.
            "foreign_transcripts": len(foreign),
            # Transcripts that matched the project but took no turns of their own - the
            # headless claudes the run's tools spawned. Counted here as well as billed
            # below, because `tokens.subprocesses` answers what they cost and not how
            # many there were, and the abort above now turns on whether any existed.
            "subprocess_transcripts": len(subprocesses),
            # Transcripts that recorded no working directory at all, so nothing here can
            # say whose they are. A session that is still booting looks like this, which
            # is why they are not counted above: a reviewer reading `foreign` as "somebody
            # else was working in this config dir" would otherwise be reading a session
            # stub that had not written its cwd yet. Nonzero at close-out means a
            # transcript nobody can attribute, which is worth seeing and is not an error.
            "forming_transcripts": len(forming),
            # Messages whose content blocks disagreed about what the message cost. Zero
            # on every transcript ever measured, and reported anyway: the totals below
            # are billed once per message id, so a number here means they are a floor
            # rather than a count, and a floor that does not say so is just a wrong
            # number. The close-out refuses a bundle whose run reports any.
            "usage_disagreements": disagreements,
            # What the run COST, which is half of what a reviewer comparing two arms is
            # reading the bundle for. Split rather than merged: `sessions` is what the
            # agent itself spent, `subprocesses` what the headless claudes its tools
            # spawned spent - the adversarial reviewer is one - and a configuration that
            # leans on those would look free if the two were not counted apart. `total`
            # is their sum, so nothing downstream re-adds them and gets it wrong.
            "tokens": {
                "sessions": session_tokens,
                "subprocesses": subprocess_tokens,
                # Spend in transcripts that recorded no working directory, so nothing
                # could attribute it. Zero on every run yet measured. NOT folded into
                # `total`, because `total` is what this analysis can stand behind, and a
                # number here means `total` is a floor - which the close-out refuses
                # rather than publishing.
                "unattributed": unattributed_tokens,
                "total": add_tokens(dict(session_tokens), subprocess_tokens),
            },
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
