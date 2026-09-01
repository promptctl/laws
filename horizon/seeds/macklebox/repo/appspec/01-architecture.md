# System architecture, dataflow, and cross-cutting behavior

This file draws the whole machine in one picture, states the per-file state
model that makes reversibility and idempotency provable, and specifies the
cross-cutting modes (dry-run, verbose, confirmation, root guard, single-app
scoping) **once** as system behaviors. The per-command detail in `06` refers
back here rather than restating these. Nothing here is mechanism-for-its-own-sake:
every claim is an externally observable contract a reimplementer must honor.

## 1. The system as one shape

The application is **four resolvers feeding one uniform per-file executor, all
gated by one startup pipeline**:

- **Configuration resolver** (`03`, `04`) turns environment + the user config
  file into three decided facts: *where the storage root is*, *which
  sub-directory inside it holds synced data*, and *which application set is in
  scope*. This resolution is **eager**: the storage location is computed at
  load time, so a storage-location failure aborts **every** command — including
  `list` and `show`, which otherwise touch no storage — before it runs. The
  storage location is a startup precondition of the whole program, not a concern
  of the sync commands.
- **Application-definition resolver** (`05`) assembles the map `key → (display
  name, home-relative file set)` from three layered directories (first-wins per
  filename). Output is a pure lookup table.
- **Selector** combines the two: `scope = (allowlist or all-keys) minus
  denylist`, overridable to a single key by the CLI argument. This is the join
  between "what the user configured" and "what definitions exist."
- **Per-file executor** (`06`) is instantiated **per application** with that
  app's sorted file list, the two run-mode booleans (dry-run, verbose), and the
  confirmation policy. It exposes exactly the small set of file operations the
  commands map onto: copy-out (backup), copy-in (restore), link-install, link,
  link-uninstall.

So the whole program is: **resolve three facts → gate the environment → fan out
one executor operation across scope × files → aggregate failures → set exit
code.** Every command is a different executor operation plugged into the *same*
fan-out. **All five sync commands are five leaves on one tree, not five
independent programs.**

### The two-level iteration shape (one system-wide guarantee)

Every sync command runs the identical two-level loop: **applications in sorted
(ascending, byte/lexicographic) key order; files within each application in
sorted path order; each file handled independently.** This ordering is
observable and stable, and it is a whole-program guarantee, not a per-command
one.

### Backup and restore are literally one operation, parameterized

Backup and restore are **not** two mirrored procedures — they are **one copy
procedure run in opposite directions**, with a small data record supplying every
difference: the source/destination orientation (home→storage vs. storage→home),
the progress verb, the drift-message wording, the prompt's "location" noun,
whether the prompt mentions the force flag, and **exactly one genuine behavioral
asymmetry**: backup skips a file whose home copy is already a symlink into
storage (it was already link-installed — nothing to copy); restore has no such
skip because the storage copy is always treated as the real file.

State this as the contract, not as incidental sameness: **any divergence between
backup and restore other than {direction, user-facing wording, the one link-skip}
is a defect.** A reimplementation that forks them into two independent code paths
risks drifting them apart — any change to drift handling, prompting, or
partial-failure behavior must apply to both by construction. The per-command
detail in `06` specifies them as one operation for this reason.

## 2. The per-file state model

Every managed config file is always in exactly one of a small set of states,
defined by the joint condition of (what's at the home path, what's at the storage
path, and whether the home path is a live symlink into storage). Every command is
a set of transitions over this space. Modeling it this way makes reversibility
provable and makes "already in sync / skip" fall out as a fixed point rather than
a special case.

### The already-linked predicate (one definition, four operations)

At the heart of the state model is a single predicate — **"the home path is
already a live symlink to its storage copy"** — that is used identically by
**four** operations (backup as a skip, link-install as a guard, link as a guard,
link-uninstall as the safety check). It is **true** only when *all* hold: the
home path is a symlink, the home path exists (the link is not dangling), the
storage copy exists, and the two resolve to the same file. A dangling home
symlink, or a missing storage copy, reads as **false** — never an error.

State it once as a shared contract: because one predicate backs four operations,
their skip/guard semantics are **guaranteed identical**. A reimplementer who
codes this check four times risks four subtly different answers; there must be
one definition. (Its already-correct product consequence, preserved from the
ground behavior: a dangling link or missing storage copy is treated as
"not linked" without raising.)

### The per-file states

For one relative path, the observable state is the pair (home, storage), where
home ∈ {absent, real file/dir, symlink-into-storage, foreign-or-broken-symlink}
and storage ∈ {absent, real file/dir}. The meaningful named states:

- **Unmanaged** — home has a real file, storage absent. (Fresh machine; file
  never synced.)
- **Backed-up (copied)** — home has a real file, storage has a real copy: two
  independent real files. The post-`backup` state.
- **Linked** — home is a symlink into storage, storage has the real file: one
  real file, referenced from home. The post-`link install` / post-`link` state.
- **Storage-only** — home absent, storage has the real file. Occurs transiently
  mid-`link install`, or on a machine that synced storage but never
  restored/linked.
- **Foreign / conflict** — home has a real file *or* a symlink that does **not**
  resolve to the storage copy, while storage has a copy.

### Where the source of truth physically lives (per state)

- **Unmanaged / Backed-up:** truth is the **home** file (storage is a copy).
- **Linked:** truth is the **storage** file; home is only a pointer. This
  inversion is the entire point of link mode, and the reason `link install` must
  move content into storage *before* pointing home at it.

### Command transitions (the reversibility model)

- **backup:** Unmanaged → Backed-up (copy home→storage). Backed-up-identical →
  no-op (the fixed point that makes backup idempotent). Backed-up-differ / Foreign
  → prompt → overwrite storage or leave unchanged (declined). Linked → no-op
  (the link-skip).
- **restore:** Backed-up / Storage-only → home gets a real copy from storage.
  Identical → no-op fixed point. Conflict at home → prompt → overwrite or decline.
  **Never creates symlinks.**
- **link install:** real home file (with storage absent or present) → Linked, via
  the sequence *copy home→storage, delete home, symlink home→storage*.
  Already-Linked → no-op.
- **link:** {storage present} → Linked, via *symlink home→storage* (optionally
  deleting a pre-existing home file after prompt). Unlike link install it does
  **not** move home content into storage — it assumes storage already holds the
  real file. Already-Linked → no-op.
- **link uninstall:** Linked → home has a real file again (delete home symlink,
  copy storage→home as a real file). Foreign home → **skipped with a warning,
  never overwritten** — the one place a command refuses to touch a file to protect
  user data. Storage-only (home absent) → left as Storage-only (link uninstall
  only reverts existing links).

### Reversibility relationships (contract, not commentary)

- **link uninstall is the inverse of link install** — but *not* a perfect
  round-trip in two respects: (a) uninstall leaves the storage copy in place
  (deliberate — other machines still sync it), so you land in Backed-up, not
  Unmanaged; (b) permissions are normalized to `0600`/`0700` on the way back, so
  a round-tripped file may be **less permissive** than the original. Reverse-of-
  install is "restore the home file," not "restore the exact prior filesystem."
- **restore is the read-only inverse of backup:** backup copies home→storage,
  restore copies storage→home; neither moves or links, so both are non-destructive
  to the *other* side and re-runnable. Together they converge storage and home to
  identical content.
- **No transition ever deletes the storage copy.** Across the entire command
  surface, storage is only created or overwritten, never removed — the whole-Mackup
  uninstall explicitly declines to delete the storage folder. **Storage is
  append/overwrite-only from the program's side; the program never makes storage
  emptier.** State this once so a reimplementer cannot accidentally add a
  storage-delete.

### The dangerous non-atomic window

`link install`'s per-file sequence *copy home→storage, delete home, symlink* has
one window — between deleting home and creating the symlink — where the file
exists only in storage and the home location is gone (transient Storage-only).
This is exactly the instant the source of truth has moved to storage but home
does not yet point there. The recovery is simply re-running (idempotency, below):
re-running `link install` or `link` re-links from the surviving storage copy. A
reimplementer should reproduce this per-file order; one that wants to be safer may
make the move+link atomic, but **must not change the observable end state of a
successful run.**

## 3. Cross-cutting modes — specified once, system-wide

Each of these is one behavior applied uniformly; the per-command sections in `06`
name *which* prompts and traces exist, not re-describe these semantics.

- **dry-run (`--dry-run` / `-n`):** one rule — the executor prints the progress
  line it *would* emit for each acted-on file, then performs **no** copy, move,
  delete, or symlink of any config file. Uniform across all five sync commands.
  **The one exception:** dry-run does **not** suppress the startup "create the
  storage sub-folder" decision for backup / link install — that gate runs before
  the per-file loop and, under a force flag, will still create the folder; absent
  a force flag under dry-run it will still prompt. Stated as: *dry-run = no per-file
  mutation, applied by the executor uniformly; environment gates are not per-file
  mutations and run regardless.*
- **verbose (`--verbose` / `-v`):** one rule — swap short progress lines for long
  ones (full absolute source/destination paths, a per-app header rule) and
  additionally emit "doing nothing / already in sync / already linked" traces for
  files a command skips. It changes only what is printed, never what is done or
  the exit code. **Verbose is observationally pure:** no verbose-only file effect
  exists anywhere.
- **confirmation policy (force / force-no / interactive):** a single three-valued
  decision, fixed for the whole run and threaded to **every** prompt in the
  system — force = auto-yes, force-no = auto-no, neither = ask on stdin. There is
  exactly one confirmation mechanism; every yes/no in the program (every
  destructive-replace prompt, the whole-uninstall confirmation, the folder-creation
  prompt) routes through it. The two force flags are mutually exclusive and
  rejected at parse time, before config load (`02`). This decision is passed as
  data, not read from an ambient global.
- **root / superuser guard:** part of the universal environment check that
  **every** command runs first (including `list` and `show`). One statement:
  effective UID 0 without `--root` aborts any command before it does work.
- **single-application scoping:** one selector rule applied before every sync
  command — a named app **replaces** the configured scope with exactly that key
  and **overrides both** the allow and ignore lists (an ignored app is still acted
  on when named); the name is validated **before** the environment gate, so an
  unknown name fails without side effects (no folder created, no prompt shown).
  Uniform across backup / restore / link / link install / link uninstall. **The
  one legitimate non-uniformity:** for `link` and `link uninstall` with no app
  named, scoping additionally toggles a whole orchestration path (a special
  Mackup-first / Mackup-last ordering, and for uninstall a global confirmation);
  naming an app skips that entire ceremony (see `06`). For those two commands,
  naming an app changes *behavior*, not just scope.

## 4. Lifecycle at system scale — one startup pipeline

Every command flows through one fixed startup pipeline; commands differ only in
the final gate.

1. **Parse argv.** `--help` / `--version` short-circuit here to stdout, exit `0`,
   touching nothing else. Conflicting force flags rejected here, exit `1`.
2. **Resolve config** (storage location + directory + scope). A fatal error here
   aborts *every* command uniformly.
3. **Assemble the application database.** A fatal error here (absolute path in a
   definition, `$XDG_CONFIG_HOME` outside home) aborts *every* command uniformly.
4. **Universal environment check** — root guard + storage-root directory exists.
   Same for all commands.
5. **Command-specific storage gate** — the *only* per-command branch:
   - `backup`, `link install`: **ensure** the storage sub-folder (the "Mackup
     folder") exists, creating it on confirmation (fatal if declined).
   - `restore`, `link`, `link uninstall`: **require** it already exists (fatal if
     not).
   - `list`, `show`: no fifth gate.

Steps 1–4 are one gate every command passes identically; step 5 is the single
point of variation. There is no readiness signal beyond normal completion: the
process does its work and exits `0`, or fails a gate and exits non-zero.

### The environment gate as a three-level lattice

The gates are three nested levels, each a superset of the last:

1. **Usable environment** — root guard **and** storage-root directory exists.
   Required by *every* command. (This is where the user-supplied-path storage
   engine's deliberately-missing existence check is finally enforced — see `04`.)
2. **Backup-usable** — usable environment, then **ensure** the Mackup folder
   exists (create-on-confirm). Used by backup, link install.
3. **Restore-usable** — usable environment, then **require** the Mackup folder to
   already exist (fatal if absent). Used by restore, link, link uninstall.

The gate is the **sole** place the Mackup folder is created and the **sole** place
root is refused.

## 5. Shutdown and the two partial-failure regimes

- **No process-level cleanup, no signals handled, no lock/PID/socket.** Every
  effect is a completed filesystem op; the process just ends. There is no
  own-temporary state to drain.
- **Two different partial-failure regimes coexist — an honesty-of-failure
  asymmetry that is contract, not oversight:**
  - **Copy commands (backup, restore)** collect per-file failures **as returned
    data**, keep going, and at end-of-run aggregate them into a stderr summary and
    a **non-zero exit**. A partial backup/restore can **never** exit `0`.
  - **Link commands (link install, link, link uninstall)** have **no**
    failure-aggregation path. A failure inside them surfaces as an uncaught
    exception (traceback, non-zero exit) and **stops the run** at that point,
    leaving earlier files transitioned and later files untouched.

  Stated once: *backup/restore degrade gracefully and report; link commands fail
  hard mid-run.* A reimplementer must not assume the clean partial-failure
  guarantee applies everywhere. This asymmetry is arguably a defect a
  reimplementation may choose to fix (making link failures aggregate too) without
  changing any successful-run behavior — but the reference behavior is as stated.

## 6. Two config-failure regimes (a related contract)

Config-load failures fall into two regimes that share one post-condition but are
two distinct paths:

- **Guarded** failures exit cleanly with a diagnostic (exit `1`): a
  missing/out-of-home config file, a legacy config section, an unlocatable
  provider storage.
- **Unguarded** failures surface as an uncaught error / traceback (non-zero exit):
  an unknown `engine` value, the user-path engine with no path configured, a
  forbidden `directory` value, an absolute path inside a definition file, an
  `$XDG_CONFIG_HOME` outside home, and end-of-input reached at a prompt.

Both regimes share the contract **"no stdout, no filesystem change, non-zero
exit."** Which cases fall in which regime is itself contract as observed; a
reimplementation **may** collapse the unguarded ones into clean single-line exits
instead, but must preserve the shared post-condition. The full case-by-case table
is in `07`.

## 7. The config/database are re-resolved mid-run (a system-level subtlety)

The config and application database are **not** a single immutable startup
snapshot. In the no-argument `link` path, after the tool links the user's own
Mackup configuration first (see `06`), it **re-loads both the config and the
application database** before linking the remaining apps — so that a just-linked
config the user's shared folder carries (new custom apps, changed scope, changed
storage) takes effect for the rest of the same run. **The program can change its
own configuration within a single run.** This is the one place the resolvers are
re-instantiated mid-run; a reimplementer must reproduce the reload, or the
second-machine "join an existing sync" flow will not honor settings the shared
config introduces.
