# Sync operations: backup, restore, and the three link modes

This file specifies the exact observable procedure for each file-moving command.
The observable algorithms here (what is read, copied, moved, deleted, symlinked;
in what order; how conflicts and pre-existing files are handled) are part of the
contract and must be reproduced. The whole-system framing — the two sync
strategies, the per-file state model, the cross-cutting modes, the partial-failure
regimes — is in `00` and `01`; this file gives the ground-level detail those
sections refer to.

## Shared vocabulary

For an application with file set `F` (sorted ascending; see `05`), for each
relative path `f` in `F` there are two absolute paths:

- **home path**: `$HOME/f`
- **mackup path**: `<Mackup folder>/f`, where the Mackup folder is
  `<storage-root>/<directory>` (`04`).

Every command below iterates applications in sorted key order and, within each
application, iterates `F` in sorted order (`01` §1). Each file is handled
independently — there is no cross-file transaction and no rollback (`01` §5).

### The `LinkState` branch variable (what every operation dispatches on)

Every operation branches on the same derived per-file state. Model it once as a
type rather than re-deriving it in each operation:

- **already-linked** — the home path is a live symlink resolving to the existing
  mackup copy (the shared predicate below is true).
- **real-file-present** — the home path exists as a real file or directory (not a
  link into mackup).
- **broken-link** — the home path is a symlink that does not resolve (dangling).
- **absent** — nothing at the home path.
- **mackup-only** — the mackup path exists but the home path is absent.

### The already-linked predicate (one definition, four operations)

Several operations ask: *is the home path already a symlink to its mackup path?*
This is **one** predicate, used identically by backup (as a skip), link install
(as a guard), link (as a guard), and link uninstall (as the safety check). Its
answer is **yes** only when all of these hold: the home path is a symlink, the
home path exists (the symlink is not dangling), the mackup path exists, and the
two resolve to the same file. A dangling home symlink, or a missing mackup copy,
counts as **not** already-linked — and does **not** raise. Because one predicate
backs four operations, their skip/guard semantics are guaranteed identical
(`01` §2); a reimplementer must not code four subtly different versions.

### `copy(src, dst)` semantics

When a command "copies" `src` to `dst`:

- The parent directory of `dst` is created if missing (recursively).
- A regular file is copied as a file; a directory is copied **recursively**,
  merging into any existing destination directory (existing destination files are
  overwritten by same-named source files; destination-only files are left).
- After copying, permissions are set recursively (see "Permissions" below).
- Copying something that is neither a regular file nor a directory is an error.

### `delete(path)` semantics

When a command "deletes" `path`:

- Recursively removes ACLs and immutable attributes first (see "Attribute
  cleanup").
- A regular file or a symlink is removed (a symlink is removed as the link, not
  its target). A directory is removed recursively.

### `link(target, link_path)` semantics

Creates `link_path` as a **symbolic link pointing at `target`** (an absolute
path). The parent directory of `link_path` is created if missing. Before linking,
`target`'s permissions are set recursively.

### Permissions (clamped on every write)

Whenever a file/folder is copied, or before it is used as a symlink target, its
mode is set **recursively**:

- Regular files → owner read+write only (`0600`).
- Directories → owner read+write+execute only (`0700`).
- Broken symlinks encountered while walking a directory are skipped (not
  chmod-ed) rather than causing failure.

This is a post-condition of *both* the copy primitive and the link primitive, so
it holds for all five operations. Observed: after a `link uninstall` copies a file
back into home, the home file's mode is `0600` even if it was more permissive
before being synced — a round-tripped file may come back **less permissive** than
the original (`01` §2). A reimplementation must apply this `0600`/`0700` recursive
mode on every copy and before every symlink.

### Attribute cleanup (external subprocesses)

Before deleting or chmod-ing, the program strips filesystem attributes that would
block modification, by invoking external commands (recursively on the path). This
precondition is shared by the delete and chmod primitives, so it holds across all
operations that remove or overwrite:

- **Remove ACLs**: on macOS, run `/bin/chmod -R -N <path>` (only if that binary
  exists); on Linux, run `/bin/setfacl -R -b <path>` (only if that binary exists).
- **Remove immutable flag**: on macOS, run `/usr/bin/chflags -R nouchg <path>`
  (if present); on Linux, run `/usr/bin/chattr -R -f -i <path>` (if present).

These are best-effort: if the binary is absent, that cleanup step is skipped.
They are the only subprocesses the program spawns during sync.

**Verified absent:** a process-running check ("is application X running?") based
on `pgrep` exists in the codebase but **no command path invokes it** — the one
call site is disabled. No command consults a running-process list; a reimplementer
should not infer such a feature.

## Environment gate per command (recap from `01` §4)

- `backup`, `link install`: usable-environment check, then **ensure Mackup folder
  exists** — if absent, prompt "Mackup needs a directory to store your
  configuration files / Do you want to create it now? <path>"; on yes, create it
  (recursively); on no, fatal error "Mackup can't do anything without a home" and
  exit `1`.
- `restore`, `link`, `link uninstall`: usable-environment check, then require the
  Mackup folder to **already exist** — if absent, fatal error naming the missing
  Mackup folder (with a hint to back up or sync first) and exit `1`.

When an `<application>` is named, its validity is checked **before** this gate, so
an unknown app name fails with `Unsupported application: <name>` (exit `1`) before
any folder is created or prompt shown.

---

## `backup` and `restore` — ONE copy operation, parameterized by direction

Backup and restore are **one algorithm** run in opposite directions (`01` §1).
They are specified here as one procedure with a direction record; a reimplementation
that forks them into two independent code paths risks drifting them apart, and
**any divergence beyond {direction, user-facing wording, the one link-skip} is a
defect.**

The direction record supplies, for each of backup and restore:

| | source | destination | progress verb | drift phrasing | destination-location noun | mentions `--force`? | link-skip? |
|--|--------|-------------|---------------|----------------|---------------------------|---------------------|-----------|
| **backup** | home path | mackup path | `Backing up` | `home and Mackup` | `the Mackup folder` | yes | yes |
| **restore** | mackup path | home path | `Recovering` | `Mackup and home` | `your home folder` | no | no |

### The shared per-file procedure

For each file `f` (with `src` and `dst` set by the direction above):

1. If the **source** path does not exist as a regular file or directory, skip it
   silently (nothing printed unless a verbose trace applies).
2. **Backup only** (`link-skip`): if the source is **already a symlink to its
   mackup path** (already backed up via `link install`), skip it — verbose prints
   a "Skipping … already linked to …" trace, nothing is copied. Restore has no
   such case (the mackup copy is always the real file).
3. If a copy already exists at the **destination**, compare source vs. destination
   (see "Drift detection"):
   - If **identical**, skip (verbose prints "<f> already in sync, skipping").
     Nothing is copied. *(This is the idempotency fixed point — a second run with
     no underlying change does nothing and prompts for nothing.)*
   - Otherwise print the progress line (`<verb> <f> ...`, or in verbose the full
     `<verb>\n  <src>\n  to\n  <dst> ...`). Then, **if not dry-run**: if a content
     diff detail is available, print the header "<f> differs between <drift
     phrasing>:" (to **stdout**, see below) followed by the diff (also stdout),
     then prompt "A <file|folder|link> named <dst> already exists in <destination-
     location noun>. Are you sure that you want to replace it?" (backup appends
     "(use --force to skip this prompt)"). On **yes**, delete the destination,
     then copy source→destination. On **no**, skip this file.
4. If **no** copy exists at the destination, print the progress line and (if not
   dry-run) copy source→destination directly, no prompt.

**Stream note (correction — do not generalize):** the "differs between …" header
and the diff detail are printed to **stdout**, not stderr. Only genuine copy-
failure lines and the end-of-run "incomplete" summary go to stderr (`07`).

### Net effects

- **backup**: for each home config file/dir, an identical copy exists at the same
  relative path under the Mackup folder, with `0600`/`0700` permissions. **The
  home files are left in place as real files** — backup copies, it does not
  symlink or move.
- **restore**: home files are overwritten with the Mackup copies (after
  confirmation when a home copy exists), copied as real files with `0600`/`0700`
  permissions. Restore **never creates symlinks**.

### Order and partial failure

Files are processed in sorted order; a per-file copy failure does **not** stop
the rest. See "Partial-failure contract (backup and restore)" below.

## Drift detection (used by backup and restore)

When a destination copy already exists, the program compares source vs.
destination to decide "identical → skip" vs. "differs → show diff + prompt". The
result is `(identical, detail)` where `detail` is empty when the paths are not
content-comparable (the caller then shows the plain prompt with no diff):

- If **either path is a symlink**: treated as differing, with **no diff detail**
  (plain prompt, no diff printed).
- If one is a **directory and the other a file** (type mismatch): differing, with
  a one-line "type mismatch: folder vs file" (or "file vs folder") detail.
- **Two regular files**:
  1. If both parse as property-list (plist) files: compared by parsed content;
     identical if equal, else a unified diff of their pretty-printed structures.
  2. Else if both are readable as UTF-8 text: compared as text; identical if
     equal, else a unified diff of their lines.
  3. Else compared **byte-for-byte**; identical if equal, else the detail is
     "binary contents differ". If either file is unreadable, treated as differing
     with no detail (plain prompt).
- **Two directories**: compared **recursively by content** (not shallow stat).
  Identical only if every file matches byte-for-byte and neither side has extra
  entries. Otherwise the detail lists, sorted: changed files ("changed: <name>"),
  files present only in source ("only in source: <name>"), and files present only
  in destination ("only in target: <name>").

The diff/detail text is printed to **stdout** (colored). When two paths are
identical the file is skipped with no prompt — this is the backup/restore
idempotency fixed point.

---

## `link install` — move home files into Mackup, then symlink them back

The "install" (first machine) that converts real home files into symlinks pointing
into the Mackup folder. For each file `f`:

1. Act only if the **home path** exists as a regular file or directory **and is
   not already a symlink to its mackup path** (the shared predicate). Otherwise,
   verbose prints a "Doing nothing …" trace keyed on the LinkState (already backed
   up / broken link / does not exist), and nothing happens.
2. Print progress (`Linking <f> ...`, or verbose `Backing up\n  <home>\n  to\n
   <mackup> ...`). If dry-run, stop here for this file.
3. If a copy already **exists at the mackup path**: prompt "A <type> named
   <mackup> already exists in the backup. Are you sure that you want to replace
   it?". On **yes**: delete the mackup copy, copy home→mackup, delete the home
   file, create a symlink at the home path pointing to the mackup copy. On **no**:
   do nothing for this file.
4. If **no** copy exists at the mackup path: copy home→mackup, delete the home
   file, create a symlink at the home path pointing to the mackup copy.

Net effect: each home config file becomes a **symlink into the Mackup folder**,
with the real content living in the Mackup folder (permissions `0600`/`0700`).
Idempotent: an already-linked file is skipped (step 1's guard). The per-file
sequence in steps 3–4 (copy → delete-home → symlink) has the one dangerous
non-atomic window described in `01` §2 and `07`; re-running recovers.

## `link` — symlink Mackup files into home (no move out of home)

The "join an existing sync" path (second machine): creates symlinks from home into
an *existing* Mackup folder, without first moving home files into Mackup. For each
file `f`:

1. Act only if **all** of: the mackup path exists as a regular file or directory;
   the home path is **not already a symlink to** the mackup path; and the file is
   **allowed to be synced on this platform**. The platform rule: on **Linux**, a
   file whose home path is under `~/Library/` is **not** synced (skipped); on
   macOS there is no such restriction. If any condition fails, verbose prints a
   "Doing nothing …" trace and nothing happens.
2. Print progress (`Restoring <f> ...`, or verbose `Restoring\n  linking
   <home>\n  to      <mackup> ...`). If dry-run, stop here for this file.
3. If a file/dir/link **already exists at the home path**: prompt "You already
   have a <type> at <home>. Do you want to replace it with your backup?". On
   **yes**: delete the home path, then create a symlink at the home path pointing
   to the mackup copy. On **no**: do nothing for this file.
4. If nothing exists at the home path: create the symlink directly.

Net effect: each home config path becomes a symlink into the Mackup folder, using
content already present in the Mackup folder. The Mackup copies are not modified.

## `link uninstall` — remove symlinks and copy Mackup files back into home

The inverse of `link install`. For each file `f`:

1. Act only if the **mackup path exists** as a regular file or directory
   (otherwise verbose prints "Doing nothing, <mackup> does not exist").
2. If a file **exists at the home path**:
   - If the home path is **not** a symlink to the mackup path (the shared
     predicate is false — a foreign/user-substituted file), print a warning
     ("Warning: the file in your home "<home>" does not point to the original file
     in Mackup <mackup>, skipping...") **to stdout** and skip this file. This
     protects a user's own file that shadows the link (`00`, promise 10).
   - Otherwise print progress (`Reverting <f> ...`, or verbose `Reverting
     <mackup>\n at <home> ...`). If dry-run, stop here. Then delete the home
     symlink and copy the mackup copy into the home path (as a real file, with
     `0600`/`0700` permissions).
3. If nothing exists at the home path (only the mackup copy exists): the file is
   left in the Mackup folder and **no home copy is created** in this pass (only
   existing links are reverted).

Net effect: home symlinks that pointed into Mackup are replaced by real copies of
the Mackup content; home files that were not links into Mackup are left untouched
with a warning.

**Stream note (correction — do not generalize):** the "does not point to Mackup"
warning is printed to **stdout**, not stderr.

---

## Whole-Mackup mode: `link` and `link uninstall` with no application argument

When run without an `<application>`, `link uninstall` and `link` treat the **Mackup
application itself** (key `mackup`, which manages `.mackup.cfg` and the `.mackup`
directory) specially, so the user's own Mackup config is restored/linked in a safe
order. Naming an application **skips this entire ceremony** (`01` §3): the command
runs the plain per-app procedure on that one app only, with no global confirmation,
no special ordering, and no mid-run reload.

### `link uninstall` (no app named): full uninstall

1. Unless dry-run or a force flag pre-answers it, prompt a **global confirmation**
   (to stdin, via the one confirmation policy): it warns that every config file,
   setting, and dotfile managed by Mackup will be unlinked and copied back to its
   original place in the home folder, and asks "Are you sure?". On **no**, nothing
   happens (exit `0`). On **yes** (or dry-run, or `--force`), proceed.
2. Compute the configured application set (all apps minus ignored, per `03`),
   **excluding** the `mackup` key.
3. Run the `link uninstall` per-app procedure over that set (in sorted order).
4. **Then** run `link uninstall` on the `mackup` application **last**, so the
   Mackup config settings survive until the end (self-last ordering — the config
   is what tells the tool which apps and settings to honor; `00`, promise 2).
5. Print a closing message that all files have been put back and Mackup can now be
   safely uninstalled (this message *is* the reversibility promise made to the
   user's face; `00`, promise 2).
6. **The Mackup folder in storage is deliberately NOT deleted** — a cross-machine
   safety contract, because other machines may still be syncing against it.
   Deleting it would sabotage those machines. This is not an incidental mechanic;
   a reimplementer must not "clean up" by removing the now-emptied-of-home-links
   storage folder (`01` §2, "storage is never emptied").

### `link` (no app named): full link with config-first ordering and mid-run reload

1. Run the `link` per-app procedure on the `mackup` application **first**
   (restoring the user's `.mackup.cfg` / `.mackup` links), printing its per-app
   header in verbose.
2. **Reload the config and the application database**, because the just-linked
   Mackup config may have changed them (added custom apps, changed the app lists,
   changed storage). **The program changes its own configuration within a single
   run** (`01` §7) — the second-machine "join an existing sync" flow depends on
   this: settings the shared config carries must take effect for the remaining
   apps.
3. Compute the configured application set from the **reloaded** config, **excluding**
   `mackup`, and run `link` over it (in sorted order).

## Partial-failure contract (backup and restore only)

During `backup` and `restore`, a per-file copy that fails (permission error, disk
full, a directory-copy error) is **not** fatal to the run: the program writes an
error line to **stderr** ("Error: Unable to copy <src> to <dst>: <reason>"),
records the failed path as data, and continues with the remaining files and
applications. Failures flow up as data, not as control flow — the loop never
aborts and the process never exits from inside the per-file copy. At the **end** of
the run, if any file failed, the dispatch boundary:

- Writes a summary to stderr: "<Backup|Restore> incomplete: <N> file(s) could not
  be copied:" followed by one indented line per failed path.
- Exits `1`.

So a backup or restore that could not copy everything **never** exits `0` — the
non-zero exit and the stderr summary distinguish a partial run from a complete one
(`00`, promise 9).

**The link commands do NOT report copy failures this way** (`01` §5). They perform
their own moves/links without aggregating a failure list; a failure inside a link
operation surfaces as an **uncaught error** (traceback, non-zero exit) that
**stops the run** at that point, leaving earlier files transitioned and later files
untouched. This honesty-of-failure asymmetry between the two operation families is
a contract, not an oversight — a reimplementation may choose to make link failures
aggregate too (without changing any successful-run behavior), but the reference
behavior is as stated.

## Idempotency and ordering guarantees (summary)

Idempotency / convergence is a **whole-engine** property, not a per-command note
(`00`, promise 3; `01` §2). Every operation is defined so that re-running from any
partial state converges to the target state without prompting for unchanged files —
which is *why* the "no cross-file transaction / no crash recovery" design is safe:
the next run re-derives each file's `LinkState` and does the right thing.

- **Ordering**: applications in sorted key order; files within an app in sorted
  path order. Observable and stable.
- **Backup / restore**: a second identical run detects content-identical
  destinations and skips them, doing nothing and prompting for nothing.
- **link install / link**: an already-linked file is skipped.
- **link uninstall**: only genuine links are reverted; a foreign home file is
  skipped with a warning.
- **No atomicity across files**: each file is handled independently; a failure or
  a declined prompt on one file leaves already-processed files in their new state
  and does not roll back.
