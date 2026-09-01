# User configuration file

This describes the user's own config file (`~/.mackup.cfg` by default), which
selects the storage engine and narrows which applications are synced. It is
distinct from the per-application definition files described in `05`.

The configuration subsystem produces, from this file (or its absence), a small
immutable value with exactly five observable properties — the storage **root
path**, the **sub-directory** name, the derived **full Mackup-folder path** (root
joined to sub-directory), the **ignore set**, and the **allow set** — and
resolves the storage location **eagerly** as part of construction (see `01` §1,
§4). Construction either yields a fully-resolved value or terminates the process;
there is no lazy/partial config. This is why a bad storage engine breaks even
commands that never sync.

## Discovery and precedence

When `--config-file` / `-c` is **not** given, the config file is discovered by
checking these candidates and using the **first that exists as a regular file**,
in this exact order:

1. `~/.mackup.cfg` — a file named `.mackup.cfg` directly in the home directory.
   Always checked first and always wins if present.
2. The path named by the `MACKUP_CONFIG` environment variable, with a leading
   `~` expanded to the home directory. (If `MACKUP_CONFIG` is unset or empty,
   this candidate is skipped.)
3. `$XDG_CONFIG_HOME/mackup/mackup.cfg`. If `XDG_CONFIG_HOME` is unset, the base
   defaults to `~/.config`, i.e. `~/.config/mackup/mackup.cfg`. (Note the
   filename here is `mackup.cfg` — the leading dot of `.mackup.cfg` is dropped.)

If **none** of the three candidates exists, the default path `~/.mackup.cfg` is
used anyway (as a nonexistent file, which parses as empty — see "Absent /
empty"). Observed precedence facts:

- With a `~/.mackup.cfg` present, it is used even when `MACKUP_CONFIG` and
  `XDG_CONFIG_HOME` both point at other existing config files.
- With no `~/.mackup.cfg`, `XDG_CONFIG_HOME`'s file is used if present; if
  `MACKUP_CONFIG` also names an existing file, `MACKUP_CONFIG` wins over the XDG
  candidate (it is checked earlier in the list).

### Explicit override (`-c <path>`)

When `-c` / `--config-file` is given, discovery is skipped and `<path>` is used
directly, with these rules:

- A leading `~` is expanded to the home directory.
- A **relative** path is resolved relative to the home directory (not the
  current working directory). So `-c foo.cfg` means `~/foo.cfg`.
- The file **must exist**. If it does not, the program writes
  `Error: The config file '<abs-path>' does not exist. Aborting.` to stderr and
  exits `1`.

### Home-directory containment (applies to discovered and explicit paths)

The finally-resolved config path must lie **inside the home directory**, checked
at construction independently of whether the file was discovered or explicitly
named. If it does not (e.g. `-c /etc/hosts`), the program writes
`Error: The config file '<abs-path>' is not in your home directory. Aborting.`
to stderr and exits `1`.

## Absent / empty config

A nonexistent or empty config file is structurally valid and parses to "no
sections set." With nothing set, all defaults apply: engine = `dropbox`,
directory = `Mackup`, no apps ignored, no apps allow-listed (which means "all
apps"). Because the default engine is Dropbox, an empty config on a machine with
no Dropbox folder then fails at storage-location resolution (`04`) and exits `1`.
A config file is therefore effectively required for any usable operation unless a
Dropbox folder happens to exist at the auto-detected location.

## File format

INI-style: `[section]` headers and, within a section, either `key = value` lines
or bare keys (a line with no `=`). Parsing rules that are part of the contract:

- **Inline comments**: text following `;` or `#` on a value line is treated as a
  comment and stripped. Whole-line comments starting with `;` or `#` are ignored.
- **Bare-key sections**: `[applications_to_sync]`, `[applications_to_ignore]`,
  and the storage-directory-list checks treat each non-blank line as a key with
  no value. Bare keys are permitted (values are optional).
- **Application-list keys are lowercased.** Names in `[applications_to_sync]` and
  `[applications_to_ignore]` are normalized to lowercase by the parser. This is
  one half of a cross-component **case-policy pair** (see also `05`): **config
  application-list keys are case-normalized; definition file paths are case-exact.**
  A reimplementation that lowercases file paths, or preserves case in config
  keys, breaks matching in a way neither section alone makes obvious. Built-in
  application keys are already lowercase, so effectively the listed names must
  match the lowercase keys shown by `list`.
- **Values in `[storage]` are case-sensitive** (see `engine` below). Section
  presence is by exact name.

There are exactly four recognized sections. Unknown sections are ignored (with
one exception: the two legacy section names below abort the program).

### Section `[storage]`

Selects and configures the storage engine. Full engine behavior is in `04`.

| Key | Required? | Effect |
|-----|-----------|--------|
| `engine` | No (defaults to `dropbox`) | One of exactly four values: `dropbox`, `google_drive`, `icloud`, `file_system`. Value is matched exactly (case-sensitive); any other value is a fatal error (`Unknown storage engine: <value>`, uncaught / nonzero exit — see `01` §6, `02`). |
| `path` | Required **only** for `file_system` | The storage root directory. Interpreted relative to the home directory, unless it is an absolute path (a leading `/`), in which case it is used as-is. So `path = some/folder` means `~/some/folder`; `path = /abs/folder` means `/abs/folder`; a path containing spaces needs no quoting or escaping. Omitting `path` under `file_system` is a fatal (uncaught) error. Ignored (not required) for the three auto-detected engines. |
| `directory` | No (defaults to `Mackup`) | Name of the sub-folder, created inside the storage root, that actually holds the synced files. Files land under `<storage-root>/<directory>/...`. The sub-directory is **constrained, not free**: two values are **forbidden** and are fatal (uncaught) errors — the literal `.mackup` (the legacy custom-apps directory name), and the XDG apps subpath `mackup/applications` (also rejected in its `.config/mackup/applications` form and any path ending in `/.config/mackup/applications`). The storage sub-directory may never collide with a custom-apps directory. Any other value is accepted verbatim. |

The full storage-folder path used by all sync operations is
`<storage-root>/<directory>` (the "Mackup folder").

### Section `[applications_to_sync]` — allowlist

Each non-blank line is an application **key**. When this section is present and
non-empty, commands acting on "all applications" act on **only** the listed keys
(still minus any in `applications_to_ignore` — see precedence below). This
section does **not** affect `list` output. It is overridden when an application
is named on the command line.

### Section `[applications_to_ignore]` — denylist

Each non-blank line is an application key. Commands acting on "all applications"
**exclude** the listed keys. Overridden when an application is named on the
command line (a named app is acted upon even if ignored).

### Combined precedence of the two lists

The set of applications a no-argument sync command acts on is computed as:

1. Start with the allowlist if `[applications_to_sync]` is present and non-empty;
   otherwise start with **all** application keys in the database.
2. Remove every key in `[applications_to_ignore]`.

So an app appearing in **both** lists is **ignored** (the denylist wins over the
allowlist). Naming the app on the command line overrides both.

### Legacy config rejection

If the config file contains a section named `[Allowed Applications]` **or**
`[Ignored Applications]` (the pre-migration section names), the program refuses
to run: it writes a fatal multi-line message to stderr explaining that an old
config format was detected and that it will do nothing rather than act
incorrectly, and exits `1`. This is a **guarded** failure (clean exit; `01` §6),
and it happens during config load, so it blocks every command.

## Environment variables that affect configuration

| Variable | Effect |
|----------|--------|
| `HOME` | Locates the home directory; used for config discovery, containment checks, storage-path resolution, and all home-relative file paths. Must be set for the program to function; if unset, home-relative operations fail with an uncaught error (nonzero exit). |
| `MACKUP_CONFIG` | Second config-discovery candidate (see precedence). `~` is expanded. |
| `XDG_CONFIG_HOME` | Base for the third config-discovery candidate (`$XDG_CONFIG_HOME/mackup/mackup.cfg`) and for XDG application-definition discovery (`05`). Defaults to `~/.config` when unset. Must resolve to a location inside the home directory when used for XDG application config files — see `05`. |
