#!/usr/bin/env python3
"""Reduce a lit export to the backlog's SHAPE: `lit export` on stdin, shape on stdout.

A pure transform - it invokes nothing and touches no files, so seed-run.sh owns every
effect exactly the way lib.sh owns them for pin-instrument.sh.
[LAW:effects-at-boundaries]

THE PROBLEM THIS EXISTS TO SOLVE: lit generates issue ids (`macklebox-foundation-8r2`)
and offers no way to choose them - an `id:` in an import doc selects an *update*, so a
freshly seeded backlog gets a different id suffix every time. Two seedings of one seed
therefore can never be byte-identical, which is exactly why the ticket's acceptance is
"a backlog of the same shape". This is where that word gets a machine-checkable
meaning: every generated id is replaced by the item's structural position in rank
order, leaving precisely the part of the backlog that the seed determines. Two seedings
agree here or the seed is not reproducible. [LAW:types-are-the-program]

Everything else about seeding a backlog - parentage, ordering, the cross-epic `blocks`
edges - is expressed in lit's own import spec and enforced by lit itself, so there is no
second schema here to drift from it. [LAW:single-enforcer]
"""

import json
import sys

# lit renders an epic with no explicit status by omitting the field, while tasks carry
# "open"; both mean the same thing to a shape comparison, so the projection fills it
# rather than letting a representational quirk read as a real difference.
DEFAULT_STATUS = "open"


def die(msg):
    print(f"ERROR [horizon/backlog.py]: {msg}", file=sys.stderr)
    sys.exit(1)


def shape(export):
    issues = export.get("issues")
    relations = export.get("relations")
    if not isinstance(issues, list) or not isinstance(relations, list):
        die("lit export is missing 'issues' or 'relations'")

    # A rolled-back import leaves its soft-deleted rows in the export. They are not part
    # of the starting state and must not enter the shape.
    live = [i for i in issues if not i.get("deleted_at")]
    if not live:
        die("lit export contains no live issues - the backlog was not seeded")

    parent_of = {
        r["src_id"]: r["dst_id"] for r in relations if r.get("type") == "parent-child"
    }

    # Structural position replaces the generated id. `rank` is lit's fractional index
    # and sorts lexicographically by construction, so rank order IS queue order. The
    # keys are positional ("0", "0.1") rather than derived from topic or title, so
    # neither a repeated topic nor a renamed ticket can collide two items into one.
    position = {}

    def assign(children, prefix):
        for n, issue in enumerate(sorted(children, key=lambda i: i["rank"])):
            key = f"{prefix}{n}"
            position[issue["id"]] = key
            assign([c for c in live if parent_of.get(c["id"]) == issue["id"]], f"{key}.")

    assign([i for i in live if i["id"] not in parent_of], "")

    projected = sorted(
        (
            {
                "key": position[i["id"]],
                "parent": position[parent_of[i["id"]]] if i["id"] in parent_of else None,
                "title": i["title"],
                "description": i["description"],
                "type": i["issue_type"],
                "topic": i["topic"],
                "priority": i.get("priority", 0),
                "status": i.get("status", DEFAULT_STATUS),
                "labels": sorted(i.get("labels") or []),
            }
            for i in live
        ),
        key=lambda p: p["key"],
    )

    dependencies = sorted(
        # lit stores a blocks edge as src=blocked, dst=blocker - verified against a live
        # store rather than inferred, since the inverse reading would silently reverse
        # the queue's whole ordering story.
        {
            (position[r["dst_id"]], position[r["src_id"]])
            for r in relations
            if r.get("type") == "blocks"
        }
    )

    return {
        "schema_version": 1,
        "issues": projected,
        "dependencies": [{"blocker": b, "blocked": k} for b, k in dependencies],
    }


def main():
    try:
        export = json.load(sys.stdin)
    except ValueError as e:
        die(f"lit export did not parse as JSON: {e}")
    json.dump(shape(export), sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
