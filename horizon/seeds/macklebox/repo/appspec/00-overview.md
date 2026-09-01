# mackup — clean-room functional specification

## What this document is

This is a complete, self-contained behavioral specification of a command-line
application named `mackup`. It describes everything observable at the
application's boundary — how it is invoked, what it reads, what it writes, what
it prints, where it moves files, what it symlinks, how it fails — in enough
detail that an independent team can build a behaviorally equivalent,
command-line-compatible program from this document alone, without ever seeing
the original source.

The specification reads **top-down through altitudes**. It opens with what the
product is and promises (this file), then the whole-system architecture and
state model (`01`), then the boundary surfaces in detail (`02`–`07`), then the
application catalog as data (appendix). Read in order: the framing up front is
what keeps the per-command detail from being reassembled into the wrong product.

| File | Layer / surface |
|------|-----------------|
| `00-overview.md` | Product contract: what it is, the two sync strategies, the promises, boundary, provenance, platform |
| `01-architecture.md` | System shape: resolvers → one per-file executor; the per-file state model; cross-cutting modes; startup pipeline; partial-failure regimes |
| `02-invocation.md` | Command line: subcommands, global options, dispatch order, exit codes |
| `03-configuration.md` | The user config file: discovery, precedence, sections, keys, validation |
| `04-storage-engines.md` | The one storage-engine interface and its four implementations |
| `05-application-database.md` | Application-definition file format, discovery, precedence, XDG, enumeration |
| `06-sync-operations.md` | The per-file state model and the exact procedures for backup, restore, and the three link modes |
| `07-output-safety-lifecycle.md` | stdout/stderr, colors, confirmation policy, force flags, root guard, startup, shutdown, errors |
| `appendix-application-names.md` | The complete set of application keys in the reference build (data) |

## The product, in one sentence

A user reasons about this tool as: **"keep my application settings the same on
all my machines, by keeping the one real copy of each config file in a folder
that already syncs between them."** Every design choice below follows from that
sentence.

- The user already owns a folder that some third party keeps replicated across
  their machines — a cloud-drive folder (Dropbox / Google Drive / iCloud) or any
  directory they replicate themselves. **`mackup` does not perform the
  cross-machine sync.** It never touches a network, a server, or another machine.
  It relies entirely on that pre-existing folder being the same on machine A and
  machine B. Its job is only the **local half**: moving each config file into
  that folder and wiring the application to keep reading it from there.
- The unit the user reasons in is an **application**, never a raw file. The user
  says "sync my vim / my git / my shell"; the tool already knows which
  home-directory files constitute each application in a large built-in catalog,
  and expands each named application to its files. This is why the catalog and
  the `list` / `show` verbs exist: they let the user audit exactly what will be
  touched before touching it.
- The two things a user does are **"put my current settings into the shared
  folder"** (so another machine can pick them up) and **"pull the shared settings
  onto this machine"** (so this machine matches). Everything else is a variation
  on those two directions.

## The two sync strategies for one goal (read this before the command detail)

The tool offers that one "share my settings" goal through **two different
physical arrangements**. Understanding *why there are two* is the single most
load-bearing fact for a reimplementer, because the per-command detail in `06`
describes five commands as five procedures without, on its own, naming the two
strategies they implement. **An implementer who collapses these into one "link"
operation, treats `backup` + `link install` as redundant, or "improves" `backup`
to also symlink has built a different product.**

**Strategy A — snapshot COPY (`backup` / `restore`).** The real config file
stays where the application expects it, in the home directory. A **duplicate**
lives in the shared folder. `backup` refreshes the shared duplicate from home;
`restore` overwrites home from the shared duplicate. The application always reads
a plain local file; nothing about how it reads files changes. The cost: staying
in sync is **manual and one-directional per run** — the user must remember to
`backup` after changing settings and `restore` on the other machine, and the
shared copy is only ever as fresh as the last `backup`. The two machines are
**not** live-coupled; the shared copy can be stale.

**Strategy B — live SYMLINK (`link install` / `link` / `link uninstall`).** The
one real config file is **moved into** the shared folder, and the home location
becomes a symlink pointing at it. The application, transparently following the
symlink, reads and writes the file that physically lives in the shared folder.
Because the shared folder is the same on every machine, a change made on machine
A is **present** on machine B as soon as the cloud client propagates it — no
`backup` / `restore` step, no staleness. The cost: the home path is now an
indirection, and uninstalling means putting the real files back — which is
exactly what `link uninstall` promises.

Within Strategy B there are **two entry doors**, and the distinction is a real
user-facing contract:

- **`link install`** is for the machine that *has* the real files and is adopting
  the tool: it **moves** home files into the shared folder and leaves symlinks
  behind (first machine).
- **`link`** is for a *second* machine that already sees the shared folder
  (populated by the first machine) and wants to adopt those settings: it only
  **creates the symlinks** pointing at files already in the shared folder; it
  moves nothing out of home. This is the "join an already-set-up sync" path.

These are two sync philosophies (snapshot vs. live), and both are deliberately
supported.

## The promises the user relies on (must-preserve invariants)

These are guarantees no single command states outright. A reimplementation that
violates one is observably a *different, and worse, product* even if it matches
every per-command procedure.

1. **Transparency of the indirection (Strategy B's whole point).** In link mode
   the home path must end up as something the application follows to the shared
   copy with **no change in what the application observes** when it reads or
   writes. Hard-copying instead of symlinking would silently break "edit on one
   machine appears on the other" — the copies would diverge.
2. **Full reversibility of link mode.** `link install` is paired with
   `link uninstall`; adopting the tool is not a one-way door. `link uninstall`
   must restore a **real file** (not a link), holding the shared copy's current
   contents, at the home path of every file the tool linked. Two subtleties are
   part of this contract: (a) a full uninstall reverts every other application
   first and the tool's own configuration **last**, because that config tells it
   which apps and settings to honor (see `06`); (b) the shared folder is
   **deliberately not deleted** on uninstall, because *other machines may still
   be syncing against it* — deleting it would sabotage them. Both are cross-machine
   safety promises, not incidental mechanics.
3. **Idempotency / convergence — re-running is always safe.** A file already in
   its target state is detected and skipped (already-linked → skip; already-
   identical copy → skip, no prompt). This also makes the tool **self-healing
   after interruption**: there is no cross-file transaction, so a crash mid-run
   leaves a partial state, and simply re-running converges each file under the
   same rules. Re-running *is* the recovery mechanism; there is no separate
   recovery mode, and a reimplementer must not invent one that behaves differently.
4. **No destructive change without confirmation, plus escape hatches.** Every
   place an operation would clobber an existing file/folder/link is gated by a
   yes/no confirmation that defaults to *not* doing the destructive thing. A
   "force yes" flag pre-answers every prompt with yes (unattended runs); a "force
   no" flag pre-answers with no (skip-everything safety); the two are mutually
   exclusive.
5. **Before-you-touch transparency.** `--dry-run` shows exactly which files a
   command *would* act on with **zero** mutation of any config file, on every
   path. `list` and `show` let the user see the whole catalog and any one
   application's exact file set before running anything. Together they make the
   blast radius fully previewable.
6. **Diff-before-replace.** When a copy operation is about to replace a
   destination that **differs**, the tool shows *what* differs first — a content
   diff for text/plist files, a summary for directories, a "binary differs" note
   otherwise — before asking. A reimplementer that prompts without surfacing the
   difference has weakened a safety guarantee.
7. **Portable, self-contained shared folder.** Everything placed in the shared
   folder is stored at the **same home-relative path** it had under the home
   directory, with no machine-specific absolute path baked in. That is what lets
   the identical folder work on a second machine whose home directory is at a
   different absolute path.
8. **The tool protects the user from itself.** It refuses to run as the
   superuser unless explicitly permitted, because running its file-moving/deleting
   logic as root over a home directory is a foot-gun. Refuse-by-default is a
   product stance, not an implementation detail.
9. **A partial copy is never reported as success (copy mode).** For `backup` /
   `restore`, if any file could not be copied, the run reports the failures and
   exits non-zero: a clean exit means everything the user asked for is in place.
   **This honesty is asymmetric — the link strategy does not uphold it as cleanly**
   (see `01` and `07`): a failure inside a link operation surfaces as an uncaught
   error rather than an aggregated "incomplete" summary.
10. **`link uninstall` will not clobber a file the user substituted.** If, at
    uninstall time, the home path is a **real file the user put there** (not the
    tool's own symlink into the shared folder), the tool refuses to overwrite it,
    warns, and skips it. A genuine data-safety contract, not a corner case.

## What the product is NOT (boundaries of the promise)

- **Not a sync daemon, not networked, not a service.** Single-shot: one
  invocation does one thing and exits. It cannot detect a file changed and act on
  its own; the user drives every operation. It provides only the *local* half;
  it neither performs nor verifies cross-machine replication, and cannot tell if
  the shared folder is actually synced.
- **Not version control.** Exactly one current copy in the shared folder; no
  history, no diff-and-merge, no cross-machine conflict resolution beyond
  "last writer into the shared folder wins."
- **Not a backup tool in the disaster-recovery sense**, despite the verb
  `backup`: the shared "backup" is a single mirrored copy, only as safe as the
  folder it lives in.
- **Understands only the built-in (plus user-added) catalog.** An application it
  has no definition for is invisible to it; the user can teach it new ones via
  custom definitions (`05`).
- **The auto-detected storage backends assume a specific desktop client is
  installed and configured.** Where that assumption fails, the tool refuses to
  run rather than guessing.
- **No atomicity across a run.** A run is a sequence of independent per-file
  operations. Interruption leaves a partial state (converged by re-running); a
  declined prompt on one file does not roll back files already processed.

## The boundary

The observable surface consists of:

- **Command line** (argv): one subcommand plus global options. Sole input
  channel for control. (`02`)
- **Standard input** (stdin): read only to answer interactive yes/no
  confirmation prompts, and only when those prompts are not pre-answered by a
  force flag. (`07`)
- **Standard output** (stdout): human-readable progress, listings, `show`
  output, diff/drift details, confirmation-prompt text, help, and version — plus
  two message classes a naive reading might expect on stderr: the drift "differs
  between …" header and the `link uninstall` "does not point to Mackup" warning
  (see `07`). (`07`)
- **Standard error** (stderr): fatal error messages, non-fatal per-file
  copy-failure diagnostics and the end-of-run "incomplete" summary,
  argument-parser usage/warnings, and uncaught-exception tracebacks. (`07`)
- **Environment variables**: `HOME`, `XDG_CONFIG_HOME`, `MACKUP_CONFIG`. (`03`,
  `05`)
- **The user configuration file** (`~/.mackup.cfg` by default): read at startup.
  (`03`)
- **The application-definition files**: read at startup to learn which files
  each supported application owns. Ship built-in; the user may add or override
  them under the home directory. (`05`)
- **The storage folder**: an external directory (Dropbox / Google Drive /
  iCloud / an explicit path) whose location is discovered or configured, into
  and out of which config files are synced. (`04`)
- **The home-directory filesystem** and **the storage-folder filesystem**:
  where files are read, written, moved, deleted, and symlinked. (`06`)
- **The process exit code**. (`02`, `07`)
- **Subprocesses invoked** for filesystem attribute cleanup (ACLs, immutable
  flags) — observable as external command executions. (`06`, `07`)

There is no network I/O, no server, no database of the app's own, and no state
that persists inside the program between invocations. Everything that makes run
N+1 differ from run N is the filesystem state that the previous run left behind.

## Provenance

- **Target identity**: command-line application, distribution/package name
  `mackup`, reference version string `0.11.1`.
- **Entry point**: a single console command `mackup`.
- **Evidence channels used to write this spec**: the program's source was read
  in full, and the program was additionally executed under a throwaway home
  directory to observe real behavior — command output, stream routing, exit
  codes, the filesystem effects of backup/restore/link, confirmation prompts,
  color output, and error paths. Claims below are stated as observed behavior;
  where a behavior could not be induced in the harness it is marked `UNVERIFIED`
  with what was tried.
- **Version string resolution**: the version reported by `--version` and printed
  in `list` output is obtained from installed package metadata for the package
  named `mackup`. When that metadata is unavailable (e.g. running from an
  uninstalled tree), the version string is the literal token `unknown`. A
  conforming reimplementation must expose a version string the same way: its own
  package version when installed, a stable fallback token otherwise. All version
  strings below assume the installed reference build (`0.11.1`).

## Platform assumptions

- Targets Unix-like systems; specifically supports **macOS (reported as
  "Darwin")** and **Linux**. Behavior differs between the two only in three
  places, all specified where they occur:
  1. ACL and immutable-attribute removal use different external commands per
     platform (`06`, `07`).
  2. On Linux, files whose home path is under `~/Library/` are never linked by
     the plain `link` command (`06`).
  3. The three auto-detected storage engines (Dropbox, Google Drive, iCloud)
     resolve their folders from macOS/desktop-specific locations; on a system
     lacking them, resolution fails with a fatal error (`04`).
- Requires a POSIX filesystem supporting symbolic links, recursive directory
  copy, and per-file permission bits.
- Reads the `HOME` environment variable to locate the home directory; several
  operations fail hard (uncaught error) if `HOME` is unset — see `07`.
- The reference implementation targets a modern Python 3 runtime, but that is an
  implementation choice; nothing in the contract requires it. A reimplementation
  in any language reproducing the observable behavior below is conformant.
