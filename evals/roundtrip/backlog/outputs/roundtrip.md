# pocketlog backlog

`pocketlog` is a command-line notebook for one person on one machine, written in Rust
and shipped as a single binary. Its first release is done when `add`, `today`, `search`
and `tags` all work and a test suite covers them. The full statement of the project is
in `docs/founding.md` (issue E1-1 puts it there).

Syncing between machines is named in `docs/founding.md` as "maybe later" with no known
design. It is not part of the first release and has no tickets here.

---

## Epic E1: Record and read today's entries

**Why this epic exists.** The project's first two commands, `pocketlog add "text"` and
`pocketlog today`, are the notebook's basic loop: write an entry, read it back. They
also force the pieces every other command stands on - the binary, the on-disk entry
format, and the location of the day files. `search` and `tags` (Epic E2) read the same
files through the same pieces.

**Checkpoint (in the application, watched by a person).** Build the binary and, with
the machine's network turned off, run it against a fresh home directory:

- `pocketlog today` before any entry exists (no `~/.pocketlog` directory at all) -
  it prints nothing or the documented empty result, and does not crash.
- `pocketlog add "first entry"`, then `pocketlog today` - the entry appears with its
  timestamp; `~/.pocketlog/YYYY-MM-DD.md` for today's date exists and reads sensibly
  when opened in an editor.
- Several `add`s in a row - `today` prints them all, in the order documented in
  `docs/entry-format.md`.
- The edge cases `docs/entry-format.md` answers: `add ""`, text containing a newline,
  text containing `#`, and text that looks like the format's own timestamp line -
  each behaves exactly as that document says, and `today` still reads every other
  entry correctly afterwards.
- The day boundary: an entry written just before local midnight lands in that day's
  file and an entry written just after lands in the next one (set the system clock or
  use the time override the tests use, if E1-4 provides one).
- `pocketlog` with no subcommand and with an unknown subcommand - a usage message and
  a non-zero exit.

### E1-1: Commit the founding document to `docs/founding.md`

Every later ticket points at the founding document by path, so it must be in the
repository. Add the founding text of `pocketlog` verbatim as `docs/founding.md`: the
four commands, the `#tag` rule, the no-network rule, the Rust single-binary rule, the
"maybe later" note on syncing, and the first-release definition.

Work ends when `docs/founding.md` exists on the default branch containing that text
and nothing added to it.

### E1-2: Create the Rust binary crate with subcommand dispatch

**Foundational.** Purpose: provide the single `pocketlog` executable that routes each
subcommand to its handler.
Used by: `add` and `today` (this epic); also `search` and `tags` (Epic E2).

Start from an empty repository (apart from `docs/`). Create a Cargo binary crate named
`pocketlog`. It accepts exactly the subcommands `add`, `today`, `search`, `tags`
(see `docs/founding.md`); handlers not yet built exit non-zero with a "not implemented"
message. No subcommand or an unknown one prints usage and exits non-zero.

Constraints from `docs/founding.md`: single binary; no network access ever, so add no
dependency whose purpose is networking.

Work ends when `cargo build` produces one `pocketlog` executable and tests cover the
four known subcommands being dispatched, no subcommand, and an unknown subcommand.

### E1-3: Define the on-disk entry format and the Entry type

**Foundational.** Purpose: represent one timestamped entry as text in a day file.
Used by: `add` writes it and `today` reads it (this epic); also `search` and `tags`
read it (Epic E2).

`docs/founding.md` fixes only that entries are timestamped and live in
`~/.pocketlog/YYYY-MM-DD.md`. Everything else about the format is decided in this
ticket and written down in a new `docs/entry-format.md`, which must answer:

- how one entry is laid out in the Markdown file, including how its timestamp is
  written and whether the timestamp is local time (the day file is named by date, so
  state which clock decides "today");
- what `add ""` does (reject with a non-zero exit, or store an empty entry);
- what happens to text containing a newline;
- what happens to text that looks like the format's own entry-start or timestamp line;
- that `#` in text is stored untouched (tags are extracted at read time, Epic E2).

Implement an `Entry` type (timestamp plus text) with a function that renders it to the
documented text and one that parses a day file's contents into entries in file order.

Work ends when `docs/entry-format.md` answers every point above and tests round-trip
(render then parse) an ordinary entry and each listed edge case.

### E1-4: Map a date to its day-file path and resolve "today"

**Foundational.** Purpose: turn a calendar date into its file path under
`~/.pocketlog/`.
Used by: `add` and `today` (this epic); also `search`, which needs the date of each day
file it reads to order results newest first (Epic E2).

Implement: the store directory `~/.pocketlog` resolved from the user's home directory;
the path `~/.pocketlog/YYYY-MM-DD.md` for a given date; and today's date by the clock
`docs/entry-format.md` names. Make the home directory and the current time injectable
so tests never touch the real `~/.pocketlog` or depend on the wall clock.

Work ends when tests cover: a normal date, a single-digit month and day (zero-padded),
the instants just before and just after local midnight, and a home directory with no
`.pocketlog` directory yet.

Blocked by: E1-3 (the clock that decides "today" is recorded there).

### E1-5: Implement `pocketlog add "text"`

Behavior: `docs/founding.md`, the `pocketlog add` bullet. Append one entry with the
current timestamp to today's file, creating `~/.pocketlog/` and the file if missing,
never rewriting existing entries. Empty text and multi-line text behave as
`docs/entry-format.md` says.

Work ends when tests running the built binary against a temporary home directory cover:
first entry creating the directory and file; a second entry appended after the first
with the first unchanged; the empty-text case; a newline in the text; and an entry
added just before versus just after midnight landing in different files.

Blocked by: E1-2, E1-3, E1-4.

### E1-6: Implement `pocketlog today`

Behavior: `docs/founding.md`, the `pocketlog today` bullet. Print today's entries,
with their timestamps, in file order. Record the output layout in
`docs/entry-format.md` (or a `docs/output.md` it links to) so `search` in Epic E2 can
print entries the same way.

Work ends when tests running the built binary against a temporary home directory cover:
no `~/.pocketlog` directory; the directory exists but today's file does not; one entry;
several entries; entries on yesterday's file only (nothing printed); and a file
containing each edge case from `docs/entry-format.md`.

Blocked by: E1-2, E1-3, E1-4.

---

## Epic E2: Find entries across days by word and by tag

**Why this epic exists.** A notebook is only useful if old entries can be found again.
`docs/founding.md` gives two ways: `pocketlog search WORD` across every day, and
`#tag` tags counted by `pocketlog tags`. Together with Epic E1 these complete the four
commands the first release requires.

**Checkpoint (in the application, watched by a person).** With the network off, in a
home directory holding day files for several dates written by `pocketlog add` (adjust
the clock or copy files in to create past days):

- `pocketlog search WORD` where WORD appears in entries on three different days and
  twice on one day - every match prints, newest day first and newest entry first
  within a day.
- A WORD that matches nothing; `search` with no `~/.pocketlog` directory; `search` with
  no WORD argument - each gives the documented result without crashing.
- WORD in a different letter case from the entry, and WORD as part of a longer word -
  results match the matching rule recorded in `docs/entry-format.md`.
- A non-day file placed in `~/.pocketlog` (for example `notes.txt`) - ignored by both
  commands.
- `pocketlog tags` with no entries; with entries but no tags; with a tag used on
  several days; with the same tag twice in one entry; with a tag directly followed by
  punctuation (`#work,`) and a lone `#` - counts match the tag rule in
  `docs/entry-format.md`.

### E2-1: List the day files in the store by date

**Foundational.** Purpose: enumerate every day file in `~/.pocketlog/` with its date.
Used by: `pocketlog search` (E2-2); also `pocketlog tags` (E2-4), which counts across
every day.

Using the path rules from E1-4, list the files in the store directory whose names are
valid `YYYY-MM-DD.md` dates, paired with that date, sorted newest first. Files with
any other name are skipped. A missing store directory yields an empty list, not an
error.

Work ends when tests cover: no store directory; an empty store; several day files out
of creation order; a file with a non-date name; a name that looks like a date but is
not a real one (month 13).

Blocked by: E1-4.

### E2-2: Implement `pocketlog search WORD`

Behavior: `docs/founding.md`, the `pocketlog search` bullet - every entry from any day
containing WORD, newest first.

`docs/founding.md` does not say whether matching ignores letter case or requires a
whole word. Implement the literal reading - the entry text contains WORD as a
case-sensitive substring - and record that rule in `docs/entry-format.md`. Order is
newest day first, and within a day newest entry first. Print each match in the layout
`today` uses (see E1-6), with enough of the date shown to tell days apart; record that
in the same document. Missing WORD prints usage and exits non-zero.

Work ends when tests running the built binary against a temporary home directory cover
every case in this epic's checkpoint that concerns `search`.

Blocked by: E2-1, E1-6.

### E2-3: Define and extract `#tag` tags from entry text

Purpose: extract the tags written as `#tag` from one entry's text.
Used by: `pocketlog tags` (E2-4). `docs/founding.md` names no other use of tags, so this
is not treated as foundational; keep it a plain function over entry text.

`docs/founding.md` says only that tags are written as `#tag`. Decide and record in
`docs/entry-format.md`: which characters may follow `#` to form a tag and what ends a
tag; whether a lone `#` or `##` is a tag; whether tags compare case-sensitively; and
whether the same tag twice in one entry counts once or twice.

Work ends when the rules are recorded and tests cover: no tags; one tag; several tags;
a tag at the very start and very end of the text; a tag followed by punctuation; a lone
`#`; a repeated tag in one entry; and two tags differing only in case.

Blocked by: E1-3.

### E2-4: Implement `pocketlog tags`

Behavior: `docs/founding.md`, the `pocketlog tags` bullet - every tag with its count,
across all days. `docs/founding.md` does not give the output order; choose one that is
deterministic (so tests can assert it) and record it in `docs/entry-format.md`.

Work ends when tests running the built binary against a temporary home directory cover
every case in this epic's checkpoint that concerns `tags`.

Blocked by: E2-1, E2-3.

---

## Epic E3: First release - test suite coverage and the shipped binary

**Why this epic exists.** `docs/founding.md` defines the first release as all four
commands working with a test suite covering them, shipped as a single binary that
never uses the network. Epics E1 and E2 test each command as it is built; this epic
makes the release condition checkable in one place.

**Checkpoint (in the application, watched by a person).** On a machine with the
network turned off: run `cargo test` and watch every command's tests run and pass;
build the release binary, copy only that one file into an empty directory on a fresh
home directory, and run `add`, `today`, `search` and `tags` through the full list of
cases from the E1 and E2 checkpoints, including an empty store, a missing store
directory, and each edge case in `docs/entry-format.md`.

### E3-1: Consolidate the end-to-end test suite for all four commands

Tests from E1-5, E1-6, E2-2 and E2-4 already exercise each command. Gather the
binary-level tests into one suite (for example under `tests/`) that builds the binary
and runs it against temporary home directories, sharing one fixture helper. Add a
`## Tests` section to `docs/entry-format.md` (or a `docs/testing.md` it links to)
mapping each documented behavior to the test that covers it.

Work ends when every behavior recorded in `docs/entry-format.md` for `add`, `today`,
`search` and `tags` has a named test in that map, and `cargo test` runs the whole
suite with no network access and without touching the real `~/.pocketlog`.

Blocked by: E1-5, E1-6, E2-2, E2-4.

### E3-2: Enforce the no-network and single-binary rules in the build

`docs/founding.md` requires that `pocketlog` never use the network and ship as a single
binary. Add a check that runs with `cargo test` or in the repository's build script:
it fails if the dependency tree gains a crate whose purpose is networking (an explicit
deny list in the repository, e.g. HTTP clients and socket libraries, documented in
`docs/testing.md`), and a README section stating how to produce the release binary
with `cargo build --release` and that the result needs no other files at run time.

Work ends when adding a networking crate from the deny list to `Cargo.toml` makes the
check fail, removing it makes the check pass, and the README section exists.

Blocked by: E1-2.
