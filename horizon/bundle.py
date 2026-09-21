#!/usr/bin/env python3
"""Write a run bundle's `run.json` - when the run ran, what it drove, and what landed.

The one fact in a bundle that nothing else can supply afterwards. Everything else is
recomputable from the files the run left, but "this began at 09:04 and ended at 17:31"
and "the project lived at /Users/.../run/seed/macklebox" are properties of a moment that
is over, so they are recorded rather than derived. [LAW:effects-at-boundaries] the clock
is read by the driver at its edge; this side only formats what it is handed.

`project.path` looks like a redundant copy of where the bundle already is, and is not:
transcripts record the directory they were written in, so matching them to the project
needs the path the run USED, which stops being where the bundle sits the moment anyone
archives it. Without this field a moved bundle cannot be re-read at all.

Usage:
    bundle.py <bundle-dir> <record-name> <started-iso> <ended-iso> <project-dir> < steps.tsv

<record-name> is the file to write, passed in rather than spelled here: lib.sh holds that
name because its inventory step has to skip the very file it is a row of.

where steps.tsv is `<name>\\t<1|0>\\t<detail>` per line, one per captured part.
"""

import json
import os
import sys
from datetime import datetime


def parse_step(line):
    """One `<name>\\t<ok>\\t<detail>` row as (name, record).

    Split on exactly two tabs: the detail is free text a step produced, and splitting on
    every tab would let a detail containing one shorten the row into a different shape.
    """
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) != 3:
        sys.exit("malformed capture row (want name<TAB>ok<TAB>detail): %r" % line)
    name, ok, detail = parts
    return name, {"ok": ok == "1", "detail": detail}


def elapsed(started, ended):
    """Whole seconds between two ISO-8601 stamps, or None when either is unreadable.

    None rather than zero: a duration of zero is a claim about the run, and "the clock was
    not readable" is a claim about the record. Collapsing them would put a real-looking
    number in front of a reader with nothing behind it.
    """
    try:
        begin = datetime.fromisoformat(started.replace("Z", "+00:00"))
        finish = datetime.fromisoformat(ended.replace("Z", "+00:00"))
    except ValueError:
        return None
    return int((finish - begin).total_seconds())


def main():
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    bundle_dir, record_name, started, ended, project_dir = sys.argv[1:]

    captured = dict(parse_step(line) for line in sys.stdin if line.strip())

    document = {
        "started": started,
        "ended": ended,
        "duration_seconds": elapsed(started, ended),
        # Empty means the run ended before seeding produced one, which the captures that
        # needed it report in their own detail. Written as null rather than omitted: a
        # reader comparing two bundles reads the same keys in both.
        # realpath, not abspath, because this value exists to be MATCHED against the cwd
        # a transcript recorded, and sessions.py resolves both sides before comparing. A
        # work dir reached through a symlink - /tmp is /private/tmp on this platform -
        # would otherwise be published here in a spelling no transcript contains, so a
        # reviewer grepping for it finds nothing and the match breaks outright once the
        # symlink is gone. One spelling, decided here. [LAW:one-source-of-truth]
        "project": {
            "name": os.path.basename(project_dir) if project_dir else None,
            "path": os.path.realpath(project_dir) if project_dir else None,
        },
        "captured": captured,
    }

    with open(os.path.join(bundle_dir, record_name), "w") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main()
