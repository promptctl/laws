# macklebox seed — where it came from

This is the reference seed for the long-horizon eval: the exact starting state the
reference run began from, recovered from that run rather than rewritten from memory.

## Origin

- **Repository:** `github.com/brandon-fryslie/macklebox` (MIT, the owner's own build of
  this instrument, once, by hand)
- **`repo/`:** the tree of commit `2f62770d28b5d9e5d944e03b76ed19bc94ec4f5b`
  ("Initial commit: MIT clean-room spec for macklebox") — `LICENSE`, `README.md`, and
  `appspec/`, copied byte for byte.
- **`backlog.json`:** the 19 issues the reference run's backlog held at time zero —
  4 epics, 14 children, and 1 free-floating task, plus the 6 cross-epic `blocks` edges.
  Recovered from the repository's own `refs/dolt/data`, which is how `lit` mirrors a
  backlog through a git remote.

## How time zero was identified

The recovered backlog is the reference run's *final* state: 42 live issues, most of
them filed during the run. Its creation timestamps separate the seed from the work
cleanly — 19 issues created in a single burst on 2026-08-01 between 09:30:33 and
09:32:35, then nothing until 2026-08-17, when the run's mid-flight epics begin. The
first cluster is time zero, and its count matches the epic's own record of the
reference run ("lit init (4 epics, 15 tickets)"; the 15 are 14 children plus the
free-floating conformance task).

The reference run's next two commits corroborate the boundary: `fc727a4` adds the
`lit init` files, and only then does `d2e0465` (PR #1) begin actual work.

## Why the backlog is vendored rather than fetched

Time zero has to be hermetic. A seed resolved over the network at run time could differ
between two runs of one campaign — the repository could move, be renamed, or gain
commits — and that variation would land squarely in the experiment's control group.
The provenance above is what keeps this copy honest: it names the exact commit the
tree came from, so the copy can always be checked against its origin.

## What this seed does NOT reproduce

`AGENTS.md` and `CLAUDE.md` are not part of the bundle. `lit init` renders them from
templates embedded in the `lit` binary, so they are a function of the pinned `lit`
rather than of the seed, and `seed-run.sh` records that binary's sha256 in every seed
manifest. They therefore differ from the reference run's copies, which were written by
an older `lit` build — the seed reproduces time zero *under the pinned toolchain*, not
the byte-exact 2026-08-01 working tree.
