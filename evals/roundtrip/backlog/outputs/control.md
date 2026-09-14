# pocketlog backlog

`pocketlog` is a command-line notebook for one person on one machine, written in Rust and
shipped as a single binary. The first release is done when all four commands (`add`,
`today`, `search`, `tags`) work and a test suite covers them.

Rules that apply to every issue:

- No network access, ever. No issue may add a dependency or code path that reaches the
  network.
- Everything ships in the single `pocketlog` binary.
- Entries live in `~/.pocketlog/YYYY-MM-DD.md`, one file per day.
- Every command issue is finished only when its behavior is covered by tests in the
  repository's test suite and those tests pass.
- Where the founding document leaves a detail open (for example, the exact timestamp
  format, or whether search is case-sensitive), the issue that first needs the detail
  decides it, writes the decision down in the README, and later issues follow it. Do not
  add behavior beyond what the issue asks for.

Out of scope for this backlog: syncing between machines. It is a "maybe later" with no
known design and is not part of the first release. Do not plan for it or build hooks
for it.

Pull order: Epic 1, then Epic 2, then Epic 3. Within Epic 2, `add` comes first because
the other commands read what it writes.

---

## Epic 1: Project skeleton and entry storage

The shared foundation every command uses: the Rust project, the command-line entry point,
and the code that locates, writes, and reads the day files. When this epic is done, the
binary builds, dispatches the four subcommand names, and has a tested storage layer the
commands can call.

### 1.1 Create the Rust project and command dispatch

- Create a Rust binary crate named `pocketlog` that builds to a single binary.
- The binary accepts the subcommands `add`, `today`, `search`, and `tags`. Until their
  issues land, each may print that it is not implemented and exit with a non-zero status.
- Running with no subcommand or an unknown subcommand prints usage and exits non-zero.
- Set up the test suite (unit tests and an integration test harness that runs the built
  binary) so later issues can add tests without building infrastructure.
- Add a README stating what the tool does, the four commands, where entries are stored,
  and that it never uses the network.

Done when: `cargo build` produces the binary, `cargo test` runs and passes, and a test
confirms unknown subcommands exit non-zero.

### 1.2 Storage layer: locate, write, and read day files

- Resolve the storage directory as `~/.pocketlog/`, creating it if it does not exist.
- Make the directory overridable for tests (for example, by an environment variable or a
  function parameter) so tests never touch the real home directory. Record the choice in
  the README if it is user-visible.
- Map a date to its file name `YYYY-MM-DD.md`.
- Define the on-disk format of one entry: its timestamp and its text. Decide the
  timestamp format and document it in the README. The file must remain readable Markdown.
- Provide functions to append one entry to a given day's file, to read all entries from
  one day's file, and to list all day files.
- Reading must parse back exactly what writing produced, including entries whose text
  spans characters that look like Markdown.

Done when: tests cover creating the directory, appending to a new and an existing day
file, round-tripping entries, and listing day files, all against a temporary directory.

---

## Epic 2: The four commands

Each command from the founding document, built on the Epic 1 storage layer and covered by
integration tests that run the binary against a temporary storage directory.

### 2.1 `pocketlog add "text"`

- Appends a timestamped entry containing the given text to today's file,
  `~/.pocketlog/YYYY-MM-DD.md`, creating the file if needed.
- Existing entries in the file are never modified or lost.
- Missing text (no argument) prints usage and exits non-zero without writing anything.

Done when: integration tests cover adding to an empty day, adding several entries in a
row (order preserved), and the missing-argument error.

### 2.2 `pocketlog today`

- Prints today's entries, in the order they were added.
- If there are no entries today, prints nothing or a short message (decide and document)
  and exits successfully.

Done when: integration tests cover a day with entries, a day with none, and confirm
entries from other days are not printed.

### 2.3 `pocketlog search WORD`

- Prints every entry, from any day, whose text contains WORD.
- Results are ordered newest first, across days and within a day.
- Decide whether matching is case-sensitive and document it in the README.
- No matches prints nothing or a short message (decide and document) and exits
  successfully. A missing WORD prints usage and exits non-zero.
- Each printed entry should show enough to tell which day and time it came from.

Done when: integration tests cover matches across several days in newest-first order,
multiple matches within one day, no matches, and the missing-argument error.

### 2.4 Tag parsing and `pocketlog tags`

- Entries can carry tags written as `#tag` inside their text. Define what counts as a tag
  (which characters end a tag, what happens to a lone `#`) and document it in the README.
- `pocketlog tags` lists every tag found across all days, each with its count.
- Decide how the count is measured (occurrences, or entries containing the tag) and the
  listing order, and document both.
- With no tags anywhere, prints nothing or a short message (decide and document) and exits
  successfully.

Done when: unit tests cover tag parsing edge cases, and integration tests cover tags
spread across several days, repeated tags, and the no-tags case.

---

## Epic 3: First release

Confirms the release condition from the founding document holds and the binary is ready
to ship.

### 3.1 Verify release readiness

- Run the full test suite and confirm every one of the four commands is covered by
  integration tests exercising its documented behavior. Fill any gaps found.
- Confirm the tool works with no network access: check that no dependency or code path
  performs network I/O, and run the test suite with networking unavailable if the
  environment allows.
- Confirm the release build produces a single self-contained binary.
- Confirm the README matches the shipped behavior, including every decision recorded by
  earlier issues.

Done when: all four commands work, the test suite covers them and passes, and the checks
above are recorded in the issue's closing note.
