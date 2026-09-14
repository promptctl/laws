# `stamp` - Clean-Room Behavioral Specification

## 1. Overview and boundary

`stamp` is a command-line program. It reads one text file named on the command line and writes each of the file's lines to standard output, with a timestamp and a single space in front of each line. The timestamp is the current time, formatted with a user-selectable format, in local time or UTC.

The boundary consists of:

- the argument vector (argv),
- two environment variables that affect behavior (`STAMP_FORMAT`, and the host time-zone setting, conventionally `TZ`),
- the input file, which is only read,
- standard output, standard error, and the exit status.

The program does not read standard input (unless the named FILE happens to be a path to it, such as `/dev/stdin`). It writes no files, keeps no state between runs, and uses no network.

## 2. Provenance

- **Target:** `stamp`, a single-file program with no version identifier. It has no version flag and prints no version anywhere.
- **Evidence channel:** the complete program source was available. No runnable build was exercised while this spec was written.
- **Status of claims:** every behavior below was derived by reading the source. None of it was confirmed by running the program. Anything that depends on the host platform or the runtime environment is marked `UNVERIFIED`, with a hypothesis. An implementer who needs certainty about an `UNVERIFIED` item should treat it as unspecified.

## 3. Invocation and entry points

Synopsis: `stamp [-u] [-f FORMAT] FILE`

The program has one entry point, the command itself. There are no subcommands, no help flag, and no version flag.

### 3.1 Argument parsing rules

Arguments are read left to right.

1. **Option phase.** While the next remaining argument begins with the character `-`, it is an option:
   - `-u` selects UTC time. It may be repeated, and repeating it has no further effect.
   - `-f` takes the **next argument** as FORMAT, whatever that argument looks like. For example, `stamp -f -u FILE` sets FORMAT to the literal string `-u` and does not select UTC. If `-f` appears more than once, the last FORMAT given wins. An empty-string FORMAT (`-f ""`) is accepted.
   - Any other argument that begins with `-` is an unknown option. This includes `-`, `--`, `-h`, `--help`, and combined forms such as `-uf`. See 8.1.
2. **The option phase ends** at the first argument that does not begin with `-`. Options must come before FILE. An option-looking argument after FILE is not treated as an option. It counts as an extra positional argument, which makes the invocation a usage error (see 8.1).
3. **Positional phase.** Exactly one argument must remain after the option phase, and it is FILE. With zero or more than one, the invocation is a usage error.

Consequences:

- A FILE whose name begins with `-` cannot be passed directly. It has to be written in a form that does not begin with `-`, for example `./-name`.
- The empty string `""` is accepted as FILE. Opening it then fails as a nonexistent file (see 8.2).
- `--` is not an end-of-options marker. It is an unknown option.

## 4. Configuration and environment

| Source | Effect | Default |
|---|---|---|
| `-f FORMAT` | Sets the timestamp format | - |
| `STAMP_FORMAT` environment variable | Sets the timestamp format when no `-f` is given | used if set |
| built-in default | Timestamp format when neither of the above applies | `%Y-%m-%dT%H:%M:%S` |
| `-u` | Timestamp is in UTC | off: local time |
| host time-zone setting (e.g. `TZ`) | Decides "local time" when `-u` is absent | host default |

Precedence for FORMAT, from highest to lowest: the last `-f` on the command line, then `STAMP_FORMAT`, then the built-in default.

- If `STAMP_FORMAT` is **set to the empty string**, the format is empty. The built-in default is not used. The same holds for `-f ""`.
- `STAMP_FORMAT` is ignored completely when any `-f` is given.
- There is no configuration file.

## 5. Inputs

### 5.1 The FORMAT string

FORMAT uses C/POSIX `strftime` conversion syntax. Each `%`-conversion is replaced by the matching field of the captured time, and all other characters are copied literally. Examples:

- `%Y-%m-%dT%H:%M:%S` produces `2026-09-14T13:05:09`.
- `%%` produces a literal `%`.
- `%s`, `%Z` and `%z` follow the host's `strftime`.

Details:

- Time resolution is whole seconds. No sub-second field is available. `%f` is not a supported conversion. `UNVERIFIED`: on glibc hosts it is expected to appear in the output unchanged, or with its conversion ignored.
- With `-u`, `%Z` yields a UTC zone name and `%z` yields `+0000`. `UNVERIFIED`: the exact `%Z` text depends on the platform, and `UTC` or `GMT` is expected.
- Day and month names from `%a`, `%A`, `%b`, `%B` and `%p` are expected to be English (C/POSIX locale), whatever the user's `LANG`/`LC_TIME` settings are. `UNVERIFIED`: not observed.
- `UNVERIFIED`: behavior for invalid or incomplete conversions (for example a trailing lone `%`, or `%Q`) depends on the host. It may copy the text through, drop it, or fail.
- `UNVERIFIED`: a FORMAT that contains a NUL character is expected to make the program fail after it has read the file, with a multi-line diagnostic on stderr, nothing on stdout, and exit status 1.

### 5.2 FILE

- FILE is a filesystem path. A relative path is resolved against the current working directory.
- The whole file is read before anything is written to stdout.
- **Encoding:** the content is decoded as strict UTF-8.
  - A UTF-8 byte-order mark at the start is **not** stripped. It becomes part of the first line's content and appears in the output right after `PREFIX `.
  - If the content is not valid UTF-8, the program writes a multi-line diagnostic to stderr, writes nothing to stdout, and exits with status 1. This diagnostic is not the one-line `stamp: ...` form from 8.2.
- **Line splitting:** the content is split into lines at each of these terminators:
  - LF (`\n`), CR LF (`\r\n`) and lone CR (`\r`);
  - VT (U+000B), FF (U+000C), and U+001C, U+001D, U+001E;
  - NEL (U+0085), LINE SEPARATOR (U+2028), PARAGRAPH SEPARATOR (U+2029).

  Terminators are not part of a line's content. The line boundaries work as follows:
  - A terminator at the very end of the file does not create an extra empty line. `a\nb\n` and `a\nb` both yield the lines `a` and `b`.
  - Consecutive terminators create empty lines. `a\n\nb` yields `a`, `` (empty) and `b`.
  - An empty (zero-byte) file yields zero lines.
  - A file containing only `\n` yields one empty line.
- Non-regular files that can be opened and read, such as FIFOs and `/dev/stdin`, are read until EOF.

## 6. Outputs

### 6.1 Standard output (success)

A timestamp string PREFIX is computed once, by applying FORMAT to the current time. It uses UTC with `-u` and local time otherwise. The time is captured **after** the file has been read and **before** any output is written. Every output line in one run carries the identical PREFIX, even when writing the output takes longer than a second.

For each input line L, in file order, stdout receives exactly:

```
PREFIX + " " + L + "\n"
```

- There is one space between PREFIX and L. This remains true when PREFIX is empty (each output line then starts with a space) and when L is empty (the output line then ends with a trailing space).
- Every output line, including the last, ends with LF on POSIX hosts. `UNVERIFIED`: on Windows the terminator is expected to be CR LF.
- Output line terminators are always LF (on POSIX), whatever terminators the input used. Input CR LF, CR, and the other terminators in 5.2 are normalized away.
- An input with zero lines produces no output and exit status 0.
- Characters are written to stdout in the environment's output encoding. `UNVERIFIED`: under a UTF-8 locale the output bytes are UTF-8. If a character cannot be represented in the stdout encoding, the program is expected to stop with a multi-line stderr diagnostic and exit status 1, possibly after some lines have already been written.

### 6.2 Standard error

Nothing is written to stderr on success. The contents of stderr on failure are described in section 8.

## 7. Persistent state

None. The program creates, modifies and deletes no files, and keeps no cache or state between runs. The input file is opened read-only and is left unchanged. Two runs over the same file differ only in PREFIX, because PREFIX depends on the current time.

## 8. Error behavior

Exit statuses:

| Status | Meaning |
|---|---|
| 0 | Success: the file was read and all its lines were written |
| 1 | The file could not be opened or read (8.2), or an unexpected runtime failure occurred (8.3) |
| 2 | Usage error (8.1) |

### 8.1 Usage errors (exit 2)

Usage errors are detected before FILE is touched. In every usage-error case, FILE is never opened, nothing is written to stdout, and exactly one line is written to stderr. The first problem found, scanning left to right, decides which error is reported.

| Condition | stderr content (function, not exact wording) |
|---|---|
| An argument in the option phase begins with `-` and is not `-u` or `-f` | One line that names the program and quotes the offending argument exactly as given, stating that it is an unknown option |
| `-f` is the last argument (no FORMAT follows) | One line: the usage synopsis `stamp [-u] [-f FORMAT] FILE`, prefixed with a "usage" label |
| After options, zero positional arguments remain, or more than one | The same one-line usage synopsis |

Examples:
- `stamp`, `stamp -u`, `stamp a b`, `stamp a -u` and `stamp -f` each print the usage line and exit 2.
- `stamp -x a` and `stamp --help` each print the unknown-option line and exit 2.
- In `stamp -x`, the unknown-option error is reported first, not the missing FILE.

### 8.2 File errors (exit 1)

If FILE cannot be opened or read because of an operating-system error, the program writes exactly one line to stderr and nothing to stdout, then exits 1. The line names the program, quotes the path exactly as given, and gives the operating system's standard description of the error. Cases this covers include:

- nonexistent path, including the empty string (description equivalent to "No such file or directory");
- permission denied;
- path is a directory (description equivalent to "Is a directory");
- other I/O errors during the read.

`UNVERIFIED`: the description text is expected to be the host's standard `strerror` text for the error.

### 8.3 Other runtime failures (exit 1, uncontrolled diagnostic)

The following failures are not handled with a one-line diagnostic. Each is expected to produce a multi-line diagnostic on stderr and exit status 1:

- content that is not valid UTF-8 (5.2); no stdout output;
- an unusable FORMAT (5.1, `UNVERIFIED`); no stdout output;
- a failure while writing to stdout, for example a character that cannot be encoded (6.1), or stdout closed early by the reader, such as when piped into `head`.

For the stdout-closed case, output before the failure may be partial. `UNVERIFIED`: the exit status may be 1 or 120, and the stderr text varies.

### 8.4 Partial failure

The file is read completely before any output. So a file that cannot be opened, read, or decoded never produces partial stdout output. Partial output is possible only when writing to stdout fails (8.3).

## 9. Lifecycle

- **Startup requirements:** none beyond a runnable program. No environment variable is required, and no network, port or service is needed.
- **Execution:** the program runs to completion and exits. It does not run as a daemon, has no readiness state, and does not wait for input unless FILE is a blocking source such as a FIFO.
- **Order of observable acts:**
  1. parse and validate arguments (possible exit 2);
  2. open and read the whole file (possible exit 1);
  3. capture the current time once;
  4. write all output lines;
  5. exit 0.
- **Signals:** the program installs no signal handling of its own. `UNVERIFIED`: SIGINT is expected to end the process with a diagnostic on stderr, and SIGTERM and SIGPIPE are expected to have their default effects or the effects described in 8.3.
- **Shutdown and crash residue:** there is none. The program writes no files, so an interrupted run leaves nothing behind except whatever stdout output had already been emitted.

## 10. External-system interactions

None. The program makes no network requests and starts no subprocesses. Beyond the filesystem read of FILE and the environment variables in section 4, it talks to nothing.

## 11. Observable guarantees

- **Order:** output lines appear in the same order as the input lines. There is exactly one output line per input line.
- **Uniform timestamp:** every line in one run has the same PREFIX.
- **Timestamp moment:** the timestamp reflects a moment after the input has been fully read.
- **All-or-nothing on input errors:** no stdout output if the file cannot be opened, read or decoded.
- **Idempotency:** runs have no side effects. Repeating a run changes nothing except that PREFIX reflects the new current time.
- **Concurrency:** any number of simultaneous invocations, including on the same FILE, run independently without interfering.
- **Timing and resources:** the program has no contractual timing behavior. Memory use grows with file size, because the whole file is read before any output. This is not a contractual requirement.
