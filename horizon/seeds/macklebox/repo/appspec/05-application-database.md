# The application database

The **application database** is the set of application definitions the program
knows about. Each definition names one application and lists the home-relative
config files/directories that constitute it. The database is assembled fresh at
startup by reading definition files from several directories, and it drives
`list`, `show`, and which files each sync command operates on.

The database is a map **application key → (display name, home-relative file
set)** with **no duplicate keys** — a deterministic winner per key (below) — and
it guarantees two properties the sync engine (`06`) *relies on without
re-checking*: every file path is **home-relative** (absolute paths are rejected
at assembly), and every path keeps its **exact case**.

This file specifies the definition-file **format**, the **discovery and
precedence** rules for assembling the database, and how the resulting set is
**enumerated**. The concrete per-application entries are data; the complete list
of application keys shipped with the reference build is in
`appendix-application-names.md`.

## Definition-file format

Each application is one INI-style `.cfg` file. The **file's basename without the
`.cfg` extension is the application key** (e.g. `vim.cfg` → key `vim`). The
recognized structure:

```
[application]
name = <Display Name>

[configuration_files]
<home-relative-path>
<home-relative-path>
...

[xdg_configuration_files]
<xdg-relative-path>
<xdg-relative-path>
...
```

Rules (each part of the contract):

- **`[application]` section, `name` key** — required. Its value is the
  application's **display name**, shown by `show` and used nowhere for matching.
  (In the reference build every definition has this section and key.)
- **`[configuration_files]` section** — optional. Each non-blank line is a bare
  key naming a path **relative to the home directory** (files or directories);
  there is no `=`. Key names here are **case-preserving** (they are *not*
  lowercased, unlike the user-config application lists in `03`) so paths keep
  their exact case. This is one half of the **case-policy pair**: *config
  application-list keys are case-normalized; definition file paths are case-exact.*
  A path that starts with `/` (an absolute path) is **rejected**: assembling the
  database fails with a fatal (uncaught) error naming the offending path
  (`Unsupported absolute path: <path>`), nonzero exit (`01` §6, `02`). All listed
  paths must be home-relative.
- **`[xdg_configuration_files]` section** — optional. Each non-blank line is a
  bare key naming a path relative to the **XDG config directory**. For each such
  path `p`, the effective config item is `$XDG_CONFIG_HOME/p` rendered as a
  **home-relative path** — i.e. the XDG base is joined to `p`, then the home
  prefix is stripped so the item is stored/looked-up relative to home just like a
  `[configuration_files]` entry. `$XDG_CONFIG_HOME` defaults to `~/.config` when
  unset. Two failure modes:
  - A listed XDG path starting with `/` is rejected exactly like an absolute
    `[configuration_files]` path (fatal, uncaught, nonzero exit).
  - If `$XDG_CONFIG_HOME` resolves to a location **not within the home
    directory**, database assembly fails with a fatal (uncaught) error stating
    that `$XDG_CONFIG_HOME` must be somewhere within the home directory, nonzero
    exit. (This check fires while assembling the database, so it blocks every
    command.)
- A definition may have `[configuration_files]` only, `[xdg_configuration_files]`
  only, both, or neither. A definition with neither contributes an application
  that has an empty file set (it still appears in `list` and `show`). In the
  reference build, of 614 definitions, 547 have `[configuration_files]`, 126 have
  `[xdg_configuration_files]`, and some have neither.
- The final file set for an application is the **union** of its
  `[configuration_files]` entries and its (home-relativized)
  `[xdg_configuration_files]` entries. The two sections are two authoring sources
  for **one** file set; a consumer cannot tell an XDG-sourced path from a plain
  one — they are one uniform home-relative type.

Illustrative example (structure only, not copied prose):

```
[application]
name = Git

[configuration_files]
.gitconfig

[xdg_configuration_files]
git/config
git/ignore
```

→ key `git`, display name `Git`, file set `{.gitconfig,
.config/git/config, .config/git/ignore}` (with default XDG base `~/.config`).

## Discovery: which directories are read, and precedence

Definitions are collected from three directories. **One definition file wins per
application key**, by a fixed three-tier precedence decided *by filename*:
user-provided definitions override the built-in one for the same key, and the
legacy user directory overrides the XDG user directory for the same filename. The
precedence, highest first:

1. **Legacy custom-apps directory**: `~/.mackup/`. Every `*.cfg` file directly in
   this directory is taken. Its filenames win over both other sources.
2. **XDG custom-apps directory**: `$XDG_CONFIG_HOME/mackup/applications/`
   (default `~/.config/mackup/applications/`). Every `*.cfg` file here is taken
   **only if a file of the same name was not already taken from the legacy
   directory**.
3. **Built-in applications directory**: the directory of definition files that
   ships with the program. Every `*.cfg` file here is taken **only if a file of
   the same name was not already taken from either user directory**.

So for a given `<key>.cfg`: a file in `~/.mackup/` shadows the same-named file in
the XDG dir, which shadows the same-named built-in file. This lets a user
override any built-in application (change its file list or display name) or add
entirely new applications by dropping a `.cfg` into `~/.mackup/` or the XDG apps
directory. Only files ending in `.cfg` are considered; other files are ignored.
A user directory that does not exist is simply skipped. The winning source is
deterministic — the database is a map with no duplicate keys.

Observed effects of adding a custom definition:

- Dropping `~/.mackup/myapp.cfg` makes key `myapp` appear in `list`, increments
  the supported-count trailer by one, makes `show myapp` print its display name
  and file paths, and makes `backup myapp` / `restore myapp` / `link myapp`
  operate on its listed files.
- Dropping `~/.mackup/vim.cfg` **replaces** the built-in `vim` definition
  entirely (the built-in `vim.cfg` is not read at all for that key).

## The home-relativity guarantee (relied on by the sync engine)

The two rejections above (absolute paths in either section; `$XDG_CONFIG_HOME`
outside home) are not just input hygiene — they are **load-bearing for the sync
engine's safety.** The engine (`06`) never validates that a file path is
home-relative; it *relies* on the database having rejected absolute paths and
out-of-home XDG bases at assembly time, so that joining `HOME` to any file in any
file set yields a path under home. This is an upstream-guarantee /
downstream-assumption pair: weaken the database's rejection and the engine
silently gains the ability to write outside the home directory.

## Enumeration

The database exposes lookups; every sync command and `list`/`show` reads only
through these:

- **all application keys**: the set of all keys assembled by the discovery rules
  above. This is what `list` prints (sorted ascending) and counts.
- **display name (key)**: the `name` value from that key's definition.
- **files (key)**: the union file set described above, as home-relative paths.

`list` output format (stdout):

```
Supported applications:
 - <key>
 - <key>
 ...

<N> applications supported in Mackup v<version>
```

where the `<key>` lines are **sorted ascending** and `<N>` is the total count.
Reference build: `N = 614`, `version = 0.11.1`.

`show <key>` output format (stdout):

```
Name: <Display Name>
Configuration files:
 - <path>
 - <path>
 ...
```

where the `<path>` lines are the application's file set in **sorted ascending
order**. If `<key>` is not a known application, the program instead writes
`Unsupported application: <key>` and exits `1`.

## Reference-build application set

The reference build ships 614 application definitions. The complete list of
application keys is provided as data in `appendix-application-names.md`. A
reimplementation is free to ship its own definition files; the **format,
discovery, precedence, and enumeration behavior above** are the contract, and a
reimplementation that ships the same keys and file sets is `list`/`show`- and
sync-compatible with the reference build.
