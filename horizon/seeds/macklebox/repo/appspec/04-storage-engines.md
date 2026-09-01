# Storage engines

The **storage engine** selects where the "storage root" directory is, and thus
where the Mackup folder (`<storage-root>/<directory>`) lives. The engine is
chosen by the `[storage] engine` key in the user config (`03`), defaulting to
`dropbox`. Three engines auto-detect a folder maintained by a third-party sync
client; the fourth uses a path the user gives.

## One interface, a closed set of four, a NON-uniform postcondition

Model the engine as a **closed enumeration of exactly four members**
(`dropbox`, `google_drive`, `icloud`, `file_system`) — a sealed type, where "any
other value" is unrepresentable (the "unknown engine" case is the type-boundary
rejection, `03`), not a runtime string compare inside resolution. All four are
implementations of **one interface** with a three-clause contract:

1. **Signature.** Each takes no per-call argument beyond ambient environment
   (`HOME`) and returns exactly one absolute path string — the storage root.
2. **Success postcondition differs by engine and is deliberately NOT uniform.**
   The three auto-detecting engines return a path that, by construction, points
   at an *existing* directory (or is read from an *existing* client database);
   the user-supplied-path engine returns the user's string **without any existence
   check**. **The uniform existence guarantee is supplied later, by the
   environment gate (`01` §4), not by the resolver.** A reimplementer must not
   "add the missing check" to the user-path engine: three engines happen to
   validate existence, one deliberately does not, and the deferral is
   observable — with a nonexistent user path, the failure surfaces at the gate's
   `Unable to find the storage folder: <path>` message, not at resolution.
3. **Failure mode.** A resolver that cannot produce a path terminates the process
   with a diagnostic naming the provider and a documentation pointer, exit `1` —
   *except* the user-path engine, whose "no path configured" failure is an
   uncaught config error (the guarded/unguarded regime split, `01` §6).

The storage root is resolved **at config-load time**, before any command runs
(`02`). If the chosen engine cannot resolve a folder, the program emits a fatal
error and exits — no command proceeds.

## `dropbox` (default)

Resolves the Dropbox folder by reading the Dropbox client's host database at
`~/.dropbox/host.db` (peer-observable, so this data shape is contract):

- The file is read as whitespace-separated tokens. It must contain **at least
  two** tokens.
- The **second** token is Base64-decoded (strict Base64), and the decoded bytes,
  interpreted as text, are the absolute path of the Dropbox folder — that path
  is the storage root.
- Example (from a valid host.db): a second token that Base64-decodes to
  `/home/some_user/Dropbox` yields storage root `/home/some_user/Dropbox` and,
  with default directory, Mackup folder `/home/some_user/Dropbox/Mackup`.

Failure to locate Dropbox — the file missing or unreadable, fewer than two
tokens, or the second token not being valid Base64 / not decodable to text — is
a **fatal error**: the program writes a multi-line message to stderr of the form
"Unable to find your Dropbox install =(" followed by guidance to consider
another provider and a documentation URL, and exits `1`. (The message's
`{provider}` slot reads `Dropbox install`.)

## `google_drive`

Resolves the Google Drive folder by reading a SQLite database maintained by the
Google Drive desktop client:

- Preferred DB path (if it exists):
  `~/Library/Application Support/Google/Drive/user_default/sync_config.db`.
- Otherwise the DB path:
  `~/Library/Application Support/Google/Drive/sync_config.db`.
- From whichever DB file exists, it runs the query: from table `data`, select
  `data_value` where `entry_key = 'local_sync_root_path'`. The returned value
  (if present and non-empty) is the storage root.

If neither DB file exists, or the query yields no usable value, or the DB cannot
be opened/queried, it is a **fatal error**: a message of the same shape as
Dropbox's with `{provider}` = `Google Drive install`, exit `1`.

## `icloud`

Resolves the iCloud Drive folder to the fixed macOS location
`~/Library/Mobile Documents/com~apple~CloudDocs/` (with `~` expanded). If that
directory does not exist, it is a **fatal error**: message shape as above with
`{provider}` = `iCloud Drive`, exit `1`. This engine requires no reading of any
client database — the existence of that directory *is* the resolution.

## `file_system`

Uses a path the user supplies via `[storage] path` (`03`). No auto-detection.

- `path` is **required**; omitting it is a fatal (uncaught) error (`03`, `01` §6).
- Relative `path` is resolved under the home directory; absolute `path`
  (leading `/`) is used verbatim. A path with spaces needs no quoting.
- The resolved value is the storage root directly. **There is no existence check
  at resolution time for this engine** (clause 2 above) — the subsequent usable-
  environment check (`01` §4) requires the storage root to exist for every command,
  so a `file_system` path pointing at a nonexistent directory fails there with
  `Error: Unable to find the storage folder: <path>` and exit `1`.

## Post-resolution requirement shared by all engines

After the storage root is resolved, every command runs the **usable
environment** check (`01` §4), which requires that the storage root exists as a
directory. For the three auto-detected engines this is normally guaranteed by
the detection itself (they point at existing folders); for `file_system` it is
the gate that catches a bad path.

## Where synced data is placed (all engines)

For every engine, the Mackup folder is `<storage-root>/<directory>`:

- `dropbox`: `<Dropbox>/Mackup` (or `<Dropbox>/<directory>`).
- `google_drive`: `<local_sync_root_path>/Mackup`.
- `icloud`: `~/Library/Mobile Documents/com~apple~CloudDocs/Mackup`.
- `file_system`: `<path>/Mackup` (path relative to home or absolute).

Within the Mackup folder, each synced item is stored at the **same
home-relative path** it has under the home directory (`06`). E.g. home file
`~/.vimrc` is stored at `<Mackup folder>/.vimrc`; home directory `~/.vim/colors`
is stored at `<Mackup folder>/.vim/colors`. This home-relativity is what makes
the shared folder portable to a second machine whose home is at a different
absolute path (`00`, promise 7).
