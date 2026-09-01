# Output, safety model, startup, shutdown, and error behavior

The whole-system lifecycle (the startup pipeline, the environment-gate lattice,
the partial-failure regimes) is stated once in `01` §4–§6; this file gives the
stream routing, the color scheme, the confirmation mechanism, the root guard, and
the exact error table.

## Output streams

The program uses two streams with fixed, per-message roles. **The stream a message
lands on is contract, not cosmetic.**

- **stdout** carries: `--help` text, `--version` string, `list` output, `show`
  output, all per-file progress lines (`Backing up …`, `Recovering …`,
  `Linking …`, `Restoring …`, `Reverting …`, `Doing nothing …`), **the drift
  "differs between …" header and the diff/drift detail**, "already in sync /
  skipping / already linked" traces, per-app verbose header lines, the "doing
  nothing" verbose traces, the confirmation-prompt text, the closing message of a
  full `link uninstall`, and — importantly — **the `link uninstall` "does not point
  to Mackup" warning**.
- **stderr** carries: fatal error messages (the `Error: …` diagnostics that
  precede a clean exit), the non-fatal per-file copy-failure diagnostics and the
  end-of-run "incomplete" summary from backup/restore, argument-parser usage and
  warning text on a usage error, and uncaught-exception tracebacks.

**Do not generalize "warnings → stderr."** Two messages a naive reading would put
on stderr are on **stdout**: the drift "differs between …" header (and its diff
body) emitted before a backup/restore replace prompt, and the `link uninstall`
"the file in your home … does not point to the original file in Mackup … skipping"
warning. Only the copy-failure lines and the end-of-run incomplete summary use the
stderr error channel. The routing is per-message; a reimplementation must place
each message on the stream stated here.

A script consuming `list`/`show`/progress output reads stdout; a supervisor
detecting failure reads the exit code and/or stderr. Progress, diff output, and
those two warnings on stdout mean a pipeline capturing stdout captures the
human-readable run narrative, while genuine errors are isolated on stderr.

## Colored output

All human-facing output is ANSI-colored by level; **color alone conveys the level
— there are no textual level labels.** The scheme (SGR codes):

- Normal progress / info → yellow (`33`).
- Non-fatal anomaly (e.g. the "differs between …" header) → bold yellow.
- Success / additions in diffs → green (`32`).
- Errors: fatal errors that exit use bright red (`91`); non-fatal copy-failure
  lines use red (`31`).
- Verbose-only traces → magenta (`35`).
- Diff decoration: file headers bold, added lines green, removed lines red (`31`),
  hunk headers cyan (`36`); per-app verbose header uses blue (`34`) rules around a
  bold app name.

Coloring is **reset-safe**: a color is re-applied after any embedded reset code in
the message so a nested reset does not strip color from the rest of a line. Every
colored string is terminated with a reset. The program does **not** condition color
on whether stdout is a TTY (observed: colors are emitted even when output is
piped/redirected). A reimplementation that wants byte-for-byte output parity must
emit the same SGR sequences unconditionally; one targeting behavioral (not pixel)
equivalence may treat coloring as cosmetic — but the **stream** each message goes
to is contract, not cosmetic.

## The confirmation / safety model

There is exactly **one** confirmation mechanism; every yes/no in the program routes
through it (`01` §3). Destructive or ambiguous actions ask a yes/no question before
proceeding. The prompt is written to **stdout** as the question text followed by
` <Yes|No> `, and the answer is read from stdin.

- Accepted **yes** answers (case-insensitive): `yes`, `y`. Accepted **no** answers:
  `no`, `n`. Any other input re-asks the same question (the loop repeats until a
  recognized answer is given).
- **`--force` / `-f`** pre-answers **every** prompt with yes: no prompt is shown,
  the guarded action proceeds.
- **`--force-no`** pre-answers **every** prompt with no: no prompt is shown, the
  guarded action is skipped.
- Supplying both `--force` and `--force-no` is rejected up front, at parse time,
  before config load (`02`).
- If a prompt is reached with no force flag and stdin reaches end-of-input (no
  answer can be read), the program cannot obtain a valid answer and terminates with
  a nonzero exit (an unhandled end-of-input condition — the unguarded regime,
  `01` §6). A reimplementation should treat EOF at a prompt as a failure, not as an
  implicit yes or no.

The prompts that exist:

- **Create the Mackup folder** (backup / link install, when the folder is absent):
  "Mackup needs a directory to store your configuration files / Do you want to
  create it now? <path>". Yes → create the folder recursively. No → fatal error
  "Mackup can't do anything without a home", exit `1`. This prompt is **not**
  suppressed by `--dry-run` (a force flag still answers it; `01` §3).
- **Replace an existing destination on backup**: "A <type> named <dst> already
  exists in the Mackup folder. Are you sure that you want to replace it? (use
  --force to skip this prompt)".
- **Replace an existing destination on restore**: "A <type> named <dst> already
  exists in your home folder. Are you sure that you want to replace it?".
- **Replace an existing backup on link install**: "A <type> named <mackup> already
  exists in the backup. Are you sure that you want to replace it?".
- **Replace an existing home file on link**: "You already have a <type> at <home>.
  Do you want to replace it with your backup?".
- **Global uninstall confirmation** (full `link uninstall`): warns everything
  managed by Mackup will be unlinked and copied back, then "Are you sure?".

`<type>` above is one of `file`, `folder`, or `link`, describing the existing path.

## The superuser (root) guard

The root guard is part of the universal environment check that **every** command
runs first (including `list` and `show`; `01` §4):

- If the process's effective user id is `0` (running as superuser) **and** `--root`
  / `-r` was **not** given, the program writes a fatal error to stderr warning that
  running as superuser can be dangerous and to run `mackup --help` for guidance,
  and exits `1`.
- With `--root` / `-r`, running as superuser is permitted (the guard passes).
- Running as a normal (non-root) user always passes the guard; `--root` then has no
  observable effect. (**UNVERIFIED** as a live observation: the harness ran only as
  a non-root user, so the root-refusal path and the `--root` bypass were not
  exercised directly; the behavior is stated from the guard's specification.)

## Startup requirements and readiness

`mackup` is a single-shot command; "readiness" is simply that it has parsed argv,
loaded config, and assembled the database. Startup follows the one pipeline in
`01` §4:

1. **Argument parse.** `--help` / `--version` print and exit `0` here, before
   anything else. Conflicting force flags are rejected here (exit `1`).
2. **Config load** (every other command). Resolves the storage engine's folder
   (`04`) and validates the config (`03`). Any of these terminate startup with a
   diagnostic and a nonzero exit, for **any** command including `list` and `show`:
   - config file explicitly named but missing, or resolving outside the home
     directory (clean `Error:` line, exit `1` — guarded);
   - a legacy `[Allowed Applications]` / `[Ignored Applications]` section (clean
     multi-line error, exit `1` — guarded);
   - an unknown `engine`, `file_system` with no `path`, or a forbidden `directory`
     value (uncaught error / traceback, nonzero exit — unguarded);
   - the selected engine failing to locate its storage folder (clean multi-line
     "unable to find your <provider>" error, exit `1` — guarded).
3. **Application-database assembly** (every command). Reads definition files
   (`05`). An absolute path inside a definition, or `$XDG_CONFIG_HOME` outside the
   home directory, terminates here with an uncaught error and a nonzero exit
   (unguarded).
4. **Per-command environment gate** (`01` §4): root guard + storage-root existence
   for all; plus Mackup-folder creation (backup / link install) or Mackup-folder
   existence (restore / link / link uninstall).

Only after all applicable gates pass does the command perform its work. There is no
readiness signal beyond normal completion.

## Shutdown, signals, and in-flight work

The program does no signal handling of its own; it runs to completion and exits. It
performs no cleanup of temporary state on exit because it keeps no own-temporary
state — every effect is a completed filesystem operation. There is no lock file,
no PID file, no socket, and nothing to drain on exit.

**Interruption / crash residue.** Because each file is processed independently and
there is no cross-file transaction (`01` §5), an interruption (signal, crash, power
loss) mid-run leaves the filesystem in whatever partial state the completed per-file
operations produced:

- A file already fully copied/moved/linked stays in its new state.
- A file not yet reached stays in its old state.
- The genuinely dangerous window is `link install`, whose per-file sequence is
  copy home→mackup, **delete home**, create symlink at home. An interruption
  between the delete and the symlink would leave the home path missing while the
  content exists in the Mackup folder — the transient moment when the source of
  truth has moved to storage but home does not yet point there (`01` §2). It is
  recoverable by re-running `link install` or `link`, which re-links from the
  surviving Mackup copy. A reimplementation should reproduce this per-file order; a
  reimplementation that wants to be safer may make the move+link atomic but must not
  change the *observable end state* of a successful run.

The next run has no crash-recovery logic; it simply re-evaluates each file's
`LinkState` with the same rules (already-linked → skip, exists-and-differs →
prompt, etc.), which is what makes re-running after an interruption converge. Re-
running *is* the recovery mechanism (`00`, promise 3).

## Error behavior summary (the unhappy path is API)

| Condition | Stream | Exit | Shape | Regime |
|-----------|--------|------|-------|--------|
| `--force` + `--force-no` together | stderr | `1` | single line (literal token below) | — |
| Named application unknown | stderr | `1` | `Unsupported application: <name>` | — |
| `-c` file missing | stderr | `1` | `Error: The config file '<p>' does not exist. Aborting.` | guarded |
| Config path outside home | stderr | `1` | `Error: The config file '<p>' is not in your home directory. Aborting.` | guarded |
| Legacy config sections present | stderr | `1` | multi-line "old config detected" | guarded |
| Storage folder not locatable (dropbox/gdrive/icloud) | stderr | `1` | multi-line "Unable to find your <provider> =(" + doc URL | guarded |
| Storage-root directory missing (usable-env check) | stderr | `1` | `Error: Unable to find the storage folder: <path>` | guarded |
| Mackup folder missing on restore/link/uninstall | stderr | `1` | `Error: Unable to find the Mackup folder: <path>` + hint | guarded |
| Declined "create Mackup folder" prompt | stderr | `1` | `Error: Mackup can't do anything without a home =(` | guarded |
| Superuser without `--root` | stderr | `1` | fatal "running as superuser can be dangerous" | guarded |
| Backup/restore finished with uncopyable files | stderr | `1` | per-file `Error: Unable to copy …` lines during run + end summary | — |
| Unknown `engine` value | stderr | nonzero | uncaught error naming the value | unguarded |
| `file_system` engine with no `path` | stderr | nonzero | uncaught error | unguarded |
| Forbidden `directory` value | stderr | nonzero | uncaught error naming the value | unguarded |
| Definition file with absolute path | stderr | nonzero | uncaught `Unsupported absolute path: <p>` | unguarded |
| `$XDG_CONFIG_HOME` outside home | stderr | nonzero | uncaught error naming the value | unguarded |
| EOF at a confirmation prompt | stderr | nonzero | uncaught end-of-input | unguarded |
| Failure inside a link operation | stderr | nonzero | uncaught error, run stops mid-way (`01` §5) | unguarded |

Both the guarded and unguarded regimes share the post-condition **"no stdout, no
filesystem change beyond already-completed per-file operations, nonzero exit"** for
the failing operation. Human-facing wording above conveys **information content and
the stream/exit**, which are the contract; the exact phrasing is not itself a
machine-read interface, and a reimplementation may reword it — or collapse the
unguarded cases into clean single-line exits — provided the stream, exit, and
no-partial-effect post-condition hold. The literal tokens that **are** contract
(matched by scripts/tests): the `Unsupported application:` prefix, the
`Options --force and --force-no are mutually exclusive.` line, and the exit codes.
