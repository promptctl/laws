# pocketlog backlog

## What this backlog is for

`pocketlog` is a command-line notebook for one person on one machine, written in Rust and
shipped as a single binary. This backlog takes it from an empty repository to its first
release. The founding document defines that release. Its terms are quoted here once so
every ticket below can point at them without a stranger having to find another file:

- `pocketlog add "text"` appends a timestamped entry to today's file,
  `~/.pocketlog/YYYY-MM-DD.md`.
- `pocketlog today` prints today's entries.
- `pocketlog search WORD` prints every entry from any day that contains WORD, newest first.
- Entries can carry tags written as `#tag`. `pocketlog tags` lists every tag with its count.
- It must work with no network access, ever.
- It is written in Rust and shipped as a single binary.
- Maybe later: syncing between machines. Nobody knows how yet, and it is not part of the
  first release.
- The first release is done when all four commands work and a test suite covers them.

Tickets below cite these as "Source: add", "Source: offline", "Source: release", and so on.

### Rules that hold for every ticket

- **No network, ever** (Source: offline). No ticket adds a dependency that opens sockets,
  fetches anything, or checks for updates. If a crate pulls in networking, pick another
  or write the code.
- **Tests ship with the ticket.** Each command ticket adds tests for that command through
  the test harness in E1-2. The release criterion is a test suite covering all four
  commands, and it is built one ticket at a time, not at the end.
- **`~` means `$HOME`.** The notebook directory is `$HOME/.pocketlog`. Tests set `HOME` to
  a temporary directory; nothing in the test suite touches the real notebook.
- **"Today" is the local calendar date** of the machine running the command.
- **Where the founding document is silent** on a behavior a ticket must implement, the
  ticket names the choice to make. The implementer makes it as the ticket says, states it
  in the command's `--help` text, and covers it with a test. Nothing further is invented.

### Not planned

- **Syncing between machines.** The founding document says nobody knows how yet and it is
  not in the first release. No ticket plans for it, and no code should be shaped to
  anticipate it. It is reconsidered only after the first release lands, from what is known
  then.
- **Anything past the first release.** When the three epics below are done, the backlog is
  extended from that new position.

---

## E1: Write and read today's notebook

**Why it exists.** Every command in the founding document reads or writes day files in
`~/.pocketlog`. This epic builds the pieces every command stands on (the binary, the test
harness, the day-file path, the entry format) and proves them with the two commands that
only touch today's file: `add` and `today`. Nothing in this epic depends on what later
commands turn out to need, because all of it is fixed by the founding document already.

**Checkpoint (in vivo).** A person builds the binary, points `HOME` at an empty directory,
and runs:

1. `pocketlog today` with no `~/.pocketlog` directory at all. It prints nothing and exits 0.
2. `pocketlog add "first entry"`. The directory and today's file now exist.
3. `pocketlog add "second entry with #tag"`, then `pocketlog today`. Both entries print in
   the order they were added, each with its timestamp.
4. `pocketlog add` with text containing a newline, and with text containing a line that
   looks like an entry header in the chosen format. `pocketlog today` shows each as one
   entry, unchanged.
5. `pocketlog add ""` and `pocketlog add` with no argument. Each gives the behavior chosen
   in E1-4, with a non-zero exit where it is an error.
6. `cat` today's file. It is readable Markdown a person could edit by hand.
7. `pocketlog nonsense`. It prints usage and exits non-zero.

### E1-1: Cargo project, single binary, and command dispatch

Create the Rust crate so that `cargo build --release` produces one executable named
`pocketlog` (Source: single binary). The binary recognizes the four subcommands `add`,
`today`, `search`, and `tags`, and `--help`. An unknown subcommand, or no subcommand,
prints usage to stderr and exits non-zero. A recognized subcommand that is not yet built
prints a clear "not implemented" message and exits non-zero, so later tickets replace
that stub and nothing else.

Argument parsing may use a crate. Per the rules above, it must not bring in networking.

Done when: the binary builds, `pocketlog --help` lists the four commands, and the dispatch
behaviors above are covered by tests using E1-2's harness. (Build E1-2 in the same branch
or immediately after. The dispatch tests are the harness's first use.)

### E1-2: Test harness that runs the real binary against an isolated home

**Purpose:** run the built `pocketlog` binary with a fresh temporary `HOME` and return its
stdout, stderr, and exit code.

The harness lives in the crate's integration tests (`tests/`). It gives each test its own
temporary directory as `HOME`, lets the test pre-create day files in
`$HOME/.pocketlog` with given contents, lets the test fix the date the binary treats as
today, and removes the directory afterwards. Fixing the date needs a hook in the binary.
Use an environment variable read in exactly one place (the function that answers "what is
today"), and document in that function that it exists for tests.

**Consumers:** the tests of every command: dispatch (E1-1), `add` and `today` (E1-4),
`search` and `tags` (E2), and the release coverage pass (E3).

Done when: a test using the harness runs `pocketlog --help` and asserts on its output, and
a second test shows two harness instances do not see each other's files.

### E1-3: Day-file location and entry format

Two foundational units that everything else reads through. Build them as one ticket
because neither can be tested meaningfully without the other. They are separate modules
with separate purposes.

**Unit A. Purpose:** map a calendar date to its day-file path,
`$HOME/.pocketlog/YYYY-MM-DD.md` (Source: add). It also exposes the reverse: given a file
name, return its date, or nothing if the name is not a day file.
**Consumers:** `add` and `today` (today's path), E2-1's day-file listing (the reverse
mapping). If `HOME` is unset, return an error the commands report. Do not guess a
directory.

**Unit B. Purpose:** encode entries into day-file text and decode day-file text back into
entries, such that decode(encode(x)) is x.
An entry is a timestamp and a text. The founding document says entries are timestamped
and files are `.md`, but it does not give the layout. Choose a layout that is readable
Markdown, carries the local time of the entry, and can be appended to without rewriting
the file. Write the chosen layout in a doc comment on the module. The format must
round-trip text that contains newlines, text that contains `#`, and text that contains a
line identical to an entry header. Pick an escaping or framing rule that makes the last
case unambiguous. Decoding an empty file yields no entries. Decoding a file a person has
hand-edited into something the format cannot read returns an error naming the file. Do
not silently skip it.
**Consumers:** `add` (encode), `today`, `search`, `tags` (decode).

Done when: unit tests cover the path mapping both ways (including non-day file names like
`notes.md` and `2026-13-40.md`), and round-trip tests cover every text case listed above.

### E1-4: `pocketlog add` and `pocketlog today`

Replace the two stubs from E1-1.

`add "text"` (Source: add): creates `$HOME/.pocketlog` if missing, creates today's file if
missing, and appends one entry stamped with the current local time using E1-3's encoder.
It never rewrites existing entries. Choice to make: the founding document does not say
what an empty or missing text does. Make both an error with a non-zero exit, since an
entry with no text carries nothing. State that in `--help`.

`today` (Source: today): prints today's entries in the order they were written, each with
its time, using E1-3's decoder. No directory or no file for today prints nothing and
exits 0. A day file the decoder rejects is an error with a non-zero exit.

Tests (through E1-2): every step of the E1 checkpoint above. Also a test that entries dated
on a different day (pre-created files) do not appear in `today`.

Done when: the tests pass and a person has run the E1 checkpoint by hand and seen each
case behave as described.

---

## E2: Search and tags across every day

**Why it exists.** `search` and `tags` are the two commands in the founding document that
read the whole notebook rather than one day. They share one new foundational unit, the
listing of all day files. With them done, all four commands exist.

**Checkpoint (in vivo).** A person points `HOME` at a directory, uses `pocketlog add` on
the real binary to write entries, and creates a few older day files by hand (or copies ones
written on earlier days) so there are at least three dates. Then they run:

1. `pocketlog search WORD` and `pocketlog tags` with no `~/.pocketlog` directory. Each
   prints nothing and exits 0.
2. `pocketlog search WORD` for a word appearing on several days and several times within
   one day. Results are newest first across days and within a day, and each shows its date
   and time.
3. `pocketlog search` for a word that appears nowhere. Nothing prints, exit 0.
4. `pocketlog search` with no WORD. Usage error, non-zero exit.
5. `pocketlog search` for a word that only appears inside a longer word, and for one that
   differs only in case. The results match the choices stated in `--help`.
6. `pocketlog tags` on entries containing a repeated tag, a tag at the end of a sentence
   (`#rust.`), a bare `#`, and `##`. The listed tags and counts match the rules in E2-3.
7. The notebook directory also holds a non-day file such as `notes.txt`. Both commands
   ignore it.

### E2-1: List every day file in the notebook

**Purpose:** return every day file in `$HOME/.pocketlog` with its date, ordered newest
date first.

Uses E1-3 Unit A's reverse mapping to recognize day files. Files and directories whose
names are not day files are skipped. A missing notebook directory is an empty list, not an
error.

**Consumers:** `search` (E2-2) and `tags` (E2-3).

Done when: unit or harness tests cover an empty directory, a missing directory, several
dates given out of order, and non-day files mixed in.

### E2-2: `pocketlog search WORD`

Replace the stub (Source: search). Using E2-1 and E1-3's decoder, print every entry whose
text contains WORD, newest first. Order by date, then by time within the date. Each result
shows its date and time so entries from different days can be told apart.

Choice to make: the founding document says "contains WORD" and nothing more. Implement
plain, case-sensitive containment of WORD as a substring of the entry text. That is the
literal reading, and it adds no matching rules the document does not give. State it in
`--help`.

No WORD is a usage error with a non-zero exit. A day file the decoder rejects is an error
naming the file, with a non-zero exit.

Tests (through E1-2): every search step of the E2 checkpoint.

### E2-3: `pocketlog tags`

Replace the stub (Source: tags). Read every entry from every day file (E2-1, E1-3) and
print each tag with its count, one per line.

Choices to make, each stated in `--help`:
- A tag is `#` immediately followed by one or more letters, digits, `_`, or `-`. The tag
  ends at the first other character, so `#rust.` is `rust`. A bare `#` and `##` alone are
  not tags. Tags are case-sensitive as written.
- The count is the number of times the tag appears across all entries.
- Output is sorted by tag name, so it is the same on every run.

Tag recognition lives inside this command's module. Nothing else in the first release
consumes it, so it is not built as a shared unit.

No tags anywhere prints nothing and exits 0. A day file the decoder rejects is an error
naming the file, with a non-zero exit.

Tests (through E1-2): every tags step of the E2 checkpoint.

Done when (both E2-2 and E2-3): tests pass and a person has run the E2 checkpoint by hand.

---

## E3: First release

**Why it exists.** The founding document's release criterion is "all four commands work
and a test suite covers them", shipped as a single binary that works with no network.
E1 and E2 build the commands and their tests. This epic confirms the criterion as a whole
on the artifact that ships, not on a development build.

**Checkpoint (in vivo).** A person builds the release binary and copies only that file to
a location outside the repository. With networking turned off and `HOME` set to an empty
directory, they run the E1 checkpoint and the E2 checkpoint again against that copy, and
every case behaves as before.

### E3-1: Coverage pass over the test suite

Read the tests for all four commands against the four command bullets of the founding
document and against the checkpoint cases of E1 and E2. Add a test for any case not
already covered: every empty, missing, malformed, and boundary case named in those
checkpoints. Do not add tests for behavior no ticket defined.

Done when: every checkpoint case in E1 and E2 maps to a named test, and `cargo test` passes.

### E3-2: Verify the single, offline binary

Confirm `cargo build --release` yields one self-contained `pocketlog` executable that needs
no files beside it (Source: single binary). Audit the full dependency tree (`cargo tree`)
for any crate that performs network access, and remove any found (Source: offline). Write
the build command and the audit result into the README, with a short usage section for the
four commands matching their `--help` text.

Done when: the audit finds no networking crates, the README is updated, and a person has
run the E3 checkpoint.
