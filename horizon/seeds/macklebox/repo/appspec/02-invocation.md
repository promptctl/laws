# Invocation, options, argument parsing, exit codes

This file specifies the command-line boundary. The whole-system dispatch shape
(one startup pipeline, one fan-out) is in `01`; this file gives the exact grammar,
option effects, and exit codes.

## Invocation forms

The program is invoked as `mackup [options] <subcommand> [args]`. The accepted
subcommand forms — and these forms only — are:

- `mackup [options] list`
- `mackup [options] show <application>`
- `mackup [options] backup [<application>]`
- `mackup [options] restore [<application>]`
- `mackup [options] link install [<application>]`
- `mackup [options] link uninstall [<application>]`
- `mackup [options] link [<application>]`
- `mackup -h` / `mackup --help`
- `mackup --version`

`<application>` is an application **key** (the identifier shown by `list`, e.g.
`vim`, `git`, `sublime-text-3`), not the display name. Options may appear before
the subcommand. Short and long forms are interchangeable and produce identical
behavior.

Argument parsing follows the contract implied by the usage grammar above: it
recognizes exactly the listed subcommand shapes and the options in the table
below, and anything that does not match one of the listed usage lines is a usage
error (see "Argument-parser behavior" below). A reimplementation must accept
every listed form and reject forms that match none.

## Global options

| Long | Short | Argument | Effect |
|------|-------|----------|--------|
| `--help` | `-h` | — | Print the usage/help text to stdout and exit `0`. No other action, no config read. |
| `--version` | — | — | Print `Mackup <version>` (reference: `Mackup 0.11.1`) to stdout and exit `0`. No other action, no config read. |
| `--force` | `-f` | — | Auto-answer every yes/no confirmation prompt with **Yes** (no prompt is displayed; the guarded action proceeds). |
| `--force-no` | — | — | Auto-answer every yes/no confirmation prompt with **No** (no prompt is displayed; the guarded action is skipped). |
| `--root` | `-r` | — | Permit running as the superuser (effective UID 0). Without it, running as superuser is refused with a fatal error (see `07`). With a non-root user, no observable effect. |
| `--dry-run` | `-n` | — | Print the steps that would be taken but perform no copy/move/delete/symlink of config files (see the dry-run contract in `01` §3). |
| `--verbose` | `-v` | — | Emit fuller progress: full absolute source/destination paths, a per-app header line, "already in sync / skipping / doing nothing / does not exist" traces. Without it, progress lines show only the short filename. |
| `--config-file` | `-c` | `<path>` | Use `<path>` as the user config file instead of the default discovery (see `03`). The resolved file must reside inside the home directory. |

### Mutually exclusive force flags

Supplying both `--force` and `--force-no` is an error: the program writes the
single line `Options --force and --force-no are mutually exclusive.` to stderr
and exits `1`, without reading config or performing any action. This check
happens **before** config is loaded (`01` §4).

## Command dispatch order and the universal config-load gate

Every command except `--help` and `--version` loads the user config file
**before** dispatching to the command. Because loading the config resolves the
storage engine's folder location (`04`), a run whose configured (or default)
engine cannot locate its storage folder fails at load time with a fatal error
and a non-zero exit **regardless of which subcommand was requested** — including
`list` and `show`, which otherwise touch no storage. Observed: with the default
Dropbox engine and no Dropbox install present, `mackup list`, `mackup show vim`,
and `mackup backup <anything>` all fail identically with the "unable to find
your Dropbox install" fatal error and exit `1`. Only `--help` and `--version`
bypass this gate. (See `01` §1 — the storage location is a startup precondition
of the whole program, not a concern of the sync commands.)

Consequently the reimplementation must:

1. Parse argv (handle `--help`/`--version` immediately; reject the mutually
   exclusive force flags).
2. Load and validate the user config (resolving the storage location) and
   assemble the application database — a fatal config, storage-location, or
   database error terminates here for any command.
3. Dispatch to the requested subcommand.

## Per-command startup checks (after config load)

Each subcommand additionally runs the environment gate (`01` §4, the three-level
lattice) before doing work. In summary:

- `list`, `show`: require the **usable environment** (root guard + storage-root
  directory exists).
- `backup`, `link install`: require the usable environment **and** ensure the
  Mackup folder exists, creating it after a confirmation prompt if absent.
- `restore`, `link uninstall`, `link`: require the usable environment **and**
  require that the Mackup folder already exists (fatal error if not).

For `backup`, `restore`, `link install`, `link uninstall`, and `link`, when an
`<application>` is named, that name is validated **before** the environment
check for that command, so that an unknown application fails cleanly before any
folder is created or any prompt is shown (single-app scoping, `01` §3; procedures
in `06`).

## Subcommand summary (behavior in `06`)

| Subcommand | One-line effect | Strategy |
|------------|-----------------|----------|
| `list` | Print all supported application keys and a supported-count trailer. | — |
| `show <app>` | Print the display name and configuration file paths of one application. | — |
| `backup [app]` | Copy each app's config files from home into the storage folder. | Copy |
| `restore [app]` | Copy each app's config files from the storage folder back into home. | Copy |
| `link install [app]` | Move each app's home config files into storage, then symlink them back. | Symlink (first machine) |
| `link uninstall [app]` | Remove those symlinks and copy the storage files back into home. | Symlink (undo) |
| `link [app]` | Symlink storage config files into home (does not move home files into storage). | Symlink (second machine) |

## Selecting which applications a command acts on

`backup`, `restore`, `link`, `link install`, `link uninstall`:

- **With an `<application>` named**: act on exactly that one application. This
  **overrides** both the `applications_to_sync` and `applications_to_ignore`
  config lists — an app that is ignored by config is still acted upon when named
  explicitly (observed: `backup vim` backs up vim even while vim is in
  `applications_to_ignore`). If the named app is not a known key, the command
  fails with `Unsupported application: <name>` and exits `1` (validated before
  the environment check).
- **With no `<application>`**: act on the *configured set* — every supported app
  by default, narrowed by `applications_to_sync` and/or `applications_to_ignore`
  (see `03`). Applications are always processed in **sorted (ascending,
  byte/lexicographic) order of their keys**, and within each application its files
  are processed in sorted order too (`01` §1).

## Exit codes

| Code | Meaning (observed) |
|------|--------------------|
| `0` | The requested action completed. Includes `--help`, `--version`, a successful `list`/`show`, and a backup/restore/link that did work or correctly did nothing. |
| `1` | A fatal, cleanly-handled error: unsupported application; config file not found / outside home; old-format config detected; superuser without `--root`; storage-root folder missing; Mackup folder missing on restore/link/uninstall; conflicting force flags; a backup/restore that finished with one or more files that could not be copied; a declined "create Mackup folder" prompt. These are emitted as a single colored diagnostic line (or a short multi-line message) on stderr. |
| nonzero (uncaught) | Certain configuration/data errors are raised as uncaught exceptions rather than clean exits, producing a multi-line traceback on stderr and a nonzero exit. Observed cases: an unknown `engine` value; the `file_system` engine with no `path`; a forbidden `directory` value; an application-definition file that lists an absolute path; an `XDG_CONFIG_HOME` outside the home directory; end-of-input reached at a confirmation prompt. Treat these as the **unguarded** config-failure regime (`01` §6): **write a diagnostic naming the offending value to stderr, write nothing to stdout, make no filesystem changes, exit nonzero.** A reimplementation may surface them as clean single-line errors instead; the contract is only "diagnostic to stderr, nonzero exit, no partial effect." |

`--help` and `--version` are the only paths that both succeed (`0`) and skip the
config-load gate.

## Argument-parser behavior (usage errors)

The argument grammar is enforced by the parser. Observed reactions to
non-matching argv:

- **No subcommand** (`mackup` with no positional command): prints the usage
  block; observed exit `0` in the harness (the parser treats bare invocation as
  a usage display). A reimplementation should print the usage block to the user;
  matching the exact exit code here is not load-bearing for callers, but for
  fidelity, treat a bare invocation as "show usage."
- **Unrecognized/duplicate positional** (e.g. `mackup frobnicate`): prints a
  warning line identifying the unmatched argument, then the usage block.
- **`show` with no `<application>`**: `<application>` is required by the grammar;
  the parser reports a usage error.

The exact wording of usage, help, and parser-warning text is human-facing and is
**not** transcribed here (it is not a machine-read contract). The machine-read
facts are: `--help`/`--version` go to stdout and exit `0`; the fatal errors in
the exit-code table go to stderr; success output of `list`/`show` goes to stdout.
