# `stamp` - Clean-Room Behavioral Specification

## 1. Overview

`stamp` is a command-line program. It takes the path of one text file, reads the
whole file, and writes each line of that file to standard output with a timestamp
prefix and one space in front of it. The timestamp is the current wall-clock time,
in local time by default or in UTC on request, rendered through a strftime-style
format string.

The program's boundary is:

- **Inward:** its command-line arguments, the environment variables `STAMP_FORMAT`
  and `TZ`, the contents of the one named file, and the system clock.
- **Outward:** standard output, standard error, and its exit status.

It does not read standard input, write any file, open any network connection, or
keep any state between runs. [APPSPEC:boundary-decides]

## 2. Provenance

- **Target:** `stamp`, a single-file program with no version identifier. It
  identifies itself in its own messages as `stamp`.
- **Evidence channels available:** the complete program source only. No runnable
  copy, live endpoint, or UI was used to produce this spec.
- **Verified by observation vs. derived from source:** no fact in this spec was
  verified by running the program. Every fact below comes from reading the source.
  Facts that also depend on the host platform or language runtime, beyond what the
  source states directly, are marked `UNVERIFIED` and give the hypothesis and what
  would confirm it. [APPSPEC:observed-beats-inferred]
- **Recommended confirmation for the clean team's acceptance suite:** each
  condition/effect sentence below is written so it can be turned directly into a
  test case. [APPSPEC:condition-effect]

---

## 3. Surface 1 - Invocation and entry points

`stamp` has exactly one entry point: running it as a process. [APPSPEC:sweep-the-surfaces]

### 3.1 Synopsis

```
stamp [-u] [-f FORMAT] FILE
```

The program has no subcommands, network listeners, signal handlers, or scheduled
triggers.

### 3.2 Argument grammar

Arguments are processed from left to right in two phases.

**Option phase.** While at least one argument remains and the next argument begins
with the character `-`, that argument is taken as an option:

| Argument | Effect |
|---|---|
| `-u` | Selects UTC for the timestamp. Giving it more than once has the same effect as giving it once. |
| `-f` | Consumes the **next** argument, whatever it is, as the format string. This includes an argument that begins with `-` (so `stamp -f -u FILE` uses the literal format `-u` and does **not** select UTC). When `-f` is given more than once, the last one wins. |
| any other argument beginning with `-` | Error: unknown option (see 10.1). Processing stops at the first such argument. |

Exact matching applies. Each of the following is an **unknown option**: `-`, `--`,
`-uf`, `-fu`, `-u1`, `-f%Y` (value attached to the flag), `--utc`, `-U`, `-F`.
[APPSPEC:exact-where-machines-read]

**Positional phase.** The option phase ends at the first argument that does not
begin with `-`, or when arguments run out. Everything left is positional. No option
is recognized after that point. For example, in `stamp FILE -u`, the `-u` is a
second positional argument, not an option.

- When exactly one positional argument remains, it is the FILE path.
- When zero positional arguments remain, or two or more remain, the program reports
  a usage error (see 10.1).

The empty string is a valid positional argument, because it does not begin with
`-`. It is treated as a path that cannot be opened (see 10.2).

Because every argument beginning with `-` is taken as an option, a file whose name
begins with `-` can only be named with a prefix such as `./`. There is no way to
make `stamp` read standard input.

### 3.3 Error precedence during argument processing

Errors are detected in argument order, and the first one ends the run:

- When `stamp -x FILE` is run, the unknown-option error is reported (exit 2). This
  also holds for `stamp -x` with no FILE and for `stamp -u -x a b c`.
- When `-f` is the last argument (for example `stamp -u -f`), the usage error is
  reported (exit 2).
- The FILE count is checked only after every option has been accepted.
- The file is opened only after the arguments are valid in full. A bad argument
  therefore never causes the file to be opened or read.

---

## 4. Surface 2 - Configuration and environment

| Source | Name | Effect |
|---|---|---|
| Flag | `-u` | Timestamp uses UTC instead of local time. |
| Flag | `-f FORMAT` | Format string for the timestamp. |
| Env var | `STAMP_FORMAT` | Format string used when no `-f` is given. |
| Built-in default | - | `%Y-%m-%dT%H:%M:%S` |
| Env var | `TZ` | Selects the local time zone used when `-u` is absent, following the host's standard `TZ` rules. Has no effect when `-u` is given. |

[APPSPEC:exact-where-machines-read]

### 4.1 Format precedence

1. When `-f` is given, its value (the last one, if repeated) is the format. This
   holds whether or not `STAMP_FORMAT` is set.
2. Otherwise, when `STAMP_FORMAT` is present in the environment, its value is the
   format. This includes an empty value: `STAMP_FORMAT=` (set but empty) gives an
   empty format, **not** the default.
3. Otherwise the format is `%Y-%m-%dT%H:%M:%S`.

### 4.2 Time basis

- When `-u` is absent, the timestamp is local time as the host defines it (the `TZ`
  environment variable, or the system time-zone setting when `TZ` is unset).
- When `-u` is present, the timestamp is UTC.

### 4.3 Format string semantics

The format string follows C/POSIX `strftime` conventions:

- A `%` followed by a conversion character is replaced by that component of the
  timestamp.
- `%%` produces a literal `%`.
- Every other character, including spaces, `-`, `T`, `:`, non-ASCII characters,
  and control characters such as newline, is copied into the prefix unchanged.

The default format uses these conversions:

| Conversion | Output |
|---|---|
| `%Y` | 4-digit year |
| `%m` | month, `01`-`12` |
| `%d` | day of month, `01`-`31` |
| `%H` | hour, `00`-`23` |
| `%M` | minute, `00`-`59` |
| `%S` | second, `00`-`60` |

With the default format, local time 2026-09-14 13:05:09 gives the prefix
`2026-09-14T13:05:09`. The default prefix has no fractional seconds and no zone
designator, in both local and UTC modes.

An empty format gives an empty prefix (see 6.2).

- `UNVERIFIED`: names produced by locale-sensitive conversions (`%a`, `%A`, `%b`,
  `%B`, `%p`, `%c`, `%x`, `%X`). Tried: nothing could be run. Hypothesis: they
  follow the POSIX "C" locale (English names, C-locale layouts) whatever `LANG`,
  `LC_ALL`, or `LC_TIME` say.
- `UNVERIFIED`: what an unrecognized conversion (such as `%Q`) or a trailing lone
  `%` produces. Tried: nothing could be run. Hypothesis: it matches the host C
  library's `strftime` (on common Linux and macOS systems the sequence is emitted
  more or less literally), and `stamp` still exits 0.

No configuration file is read. [APPSPEC:one-structure-many-channels]

---

## 5. Surface 3 - Inputs

### 5.1 The FILE argument

FILE is a filesystem path, relative to the working directory or absolute. It must
name something that can be opened and read to its end as a regular text stream: a
regular file, or a readable special file such as a named pipe or `/dev/stdin`-style
device node. Its entire content is read before any output is produced.

### 5.2 Accepted content

- The content must be valid UTF-8. A byte-order mark (U+FEFF) at the start is **not**
  removed; it becomes the first character of the first line's text.
- The content is split into lines. Each of these sequences ends a line:
  - `\r\n` (CR LF, treated as a single terminator)
  - `\n` (LF)
  - `\r` (CR alone)
  - `\x0b` (VT)
  - `\x0c` (FF)
  - `\x1c`, `\x1d`, `\x1e`
  - U+0085 (NEL)
  - U+2028 (LINE SEPARATOR)
  - U+2029 (PARAGRAPH SEPARATOR)
- Terminators are not part of a line's text.
- When the content ends with a terminator, no extra empty line follows it. When the
  content does not end with a terminator, the text after the last terminator is
  still a line.
- Every terminator between two others produces a line, so empty lines are kept.

| File content (escaped) | Lines |
|---|---|
| empty (0 bytes) | none |
| `\n` | one empty line |
| `a` | `a` |
| `a\n` | `a` |
| `a\nb` | `a`, `b` |
| `a\n\nb\n` | `a`, empty, `b` |
| `a\r\nb\rc` | `a`, `b`, `c` |
| `a\n\n` | `a`, empty |
| `a\x0cb` | `a`, `b` |

Tabs, leading and trailing spaces, and any other characters in a line are kept
unchanged.

### 5.3 Rejected content

- **Content that is not valid UTF-8** (for example a file containing the byte
  `0xFF`): see 10.3.
- **A FILE that cannot be opened or read** (missing, permission denied, a directory,
  an I/O error): see 10.2.

Standard input is never read. [APPSPEC:condition-effect]

---

## 6. Surface 4 - Outputs

### 6.1 Streams

- **stdout:** stamped lines only, and only on the successful path.
- **stderr:** diagnostics only.

### 6.2 Stamped-line format (machine-readable)

When the arguments are valid and FILE is read successfully, for each input line `L`
in order the program writes to stdout:

```
<PREFIX><SP><L><LF>
```

- `<PREFIX>` is the rendered timestamp (section 4), emitted exactly as rendered. If
  the format produces a newline, that newline appears in the output.
- `<SP>` is one space character (U+0020). It is always present, even when
  `<PREFIX>` is empty and even when `<L>` is empty.
- `<L>` is the line's text without its terminator.
- `<LF>` is a single `\n`, whatever terminator the input line had. CR LF input
  becomes LF output.

Examples with prefix `2026-09-14T13:05:09`:

| Input lines | stdout |
|---|---|
| `hello`, `world` | `2026-09-14T13:05:09 hello\n2026-09-14T13:05:09 world\n` |
| one empty line | `2026-09-14T13:05:09 \n` |
| none (empty file) | nothing (0 bytes) |

With the format set to the empty string, input line `x` gives stdout ` x\n` (a
leading space).

- `UNVERIFIED`: the output character encoding. Tried: nothing could be run.
  Hypothesis: under a UTF-8 locale, or under the C/POSIX locale, stdout is UTF-8.
  Under a locale whose charset cannot represent a character in the output, the run
  fails partway (see 10.4).

### 6.3 Files written

None. [APPSPEC:boundary-decides]

### 6.4 Exit status

| Exit | Condition |
|---|---|
| `0` | Arguments valid, FILE read and decoded, all lines written. This includes an empty FILE with no output. |
| `1` | FILE could not be opened or read (10.2), could not be decoded (10.3), or a failure occurred while writing output (10.4). |
| `2` | Usage error or unknown option (10.1). |

---

## 7. Surface 5 - Persistent state

None. Every run is independent: two runs with the same arguments, environment, and
file content, in the same clock second, produce byte-identical stdout. How absence
was established: from source only. The program creates, modifies, and deletes no
files, uses no cache, and keeps no state between runs. `UNVERIFIED` by observation.
A filesystem watcher over two runs would confirm it. [APPSPEC:one-structure-many-channels]

---

## 8. Surface 6 - External-system interactions

None. `stamp` sends nothing to any other system, opens no network connection, and
starts no child process. Its only reads from outside the argument list and the
environment are:

- the named FILE (section 5);
- the system clock, sampled once per run (section 11);
- the host's time-zone data, for local time.

How absence was established: from source only. `UNVERIFIED` by a network tap.
[APPSPEC:wire-level-contracts]

---

## 9. Surface 7 - Lifecycle

`stamp` runs once and exits. It is not a service.

- **Start requirements:** a runtime that can run the program. Nothing else must be
  present before startup: no env var, config file, port, or service is needed.
  `STAMP_FORMAT` and `TZ` are optional. The FILE is checked only after the arguments
  are parsed (see 10.2).
- **Readiness:** not applicable. The program accepts no interaction after it starts.
- **Normal completion:** the process exits with the status in 6.4 once every stamped
  line is written, or once the first error is reported.
- **Shutdown and signals:** the program installs no signal handlers. Signals get the
  runtime's default handling.
  - `UNVERIFIED`: effect of SIGINT (Ctrl-C) during a run. Tried: nothing could be
    run. Hypothesis: the process ends without completing, may write a
    runtime-generated interruption report to stderr, and the shell reports it as
    terminated by SIGINT (status 130).
  - `UNVERIFIED`: effect of SIGTERM or SIGKILL. Hypothesis: the process ends at once
    with the default signal disposition.
- **Crash aftermath:** no file or lock is left behind, and the next run behaves as
  if the interrupted run never happened.
  - `UNVERIFIED`: how much stdout an interrupted run leaves behind. Hypothesis: when
    stdout is a terminal, lines appear one by one as written. When stdout is a pipe
    or file, output is block-buffered, so a run killed partway may leave fewer lines
    than it had produced, possibly none.

[APPSPEC:lifecycle-is-api]

---

## 10. Surface 8 - Error behavior

The program has one entry point, so every error below belongs to it. In every error
case below except 10.4, **stdout receives no bytes**. [APPSPEC:errors-are-api]

### 10.1 Usage errors (exit 2)

| Condition | stderr | stdout | Exit |
|---|---|---|---|
| No arguments at all | a one-line usage synopsis naming the program and showing `[-u] [-f FORMAT] FILE` | nothing | `2` |
| Zero positional arguments after options (for example `stamp -u`) | same usage synopsis | nothing | `2` |
| Two or more positional arguments (for example `stamp a b`, `stamp FILE -u`) | same usage synopsis | nothing | `2` |
| `-f` is the last argument | same usage synopsis | nothing | `2` |
| An argument beginning with `-` that is not exactly `-u` or `-f`, in the option phase | a one-line message, prefixed with the program name, stating the option is unknown and quoting the offending argument exactly as given | nothing | `2` |

The FILE is never opened in these cases, so a usage error is reported even when FILE
is missing.

### 10.2 FILE cannot be opened or read (exit 1)

When FILE does not exist, cannot be read because of permissions, is a directory, or
fails with any other operating-system error while it is opened or read:

- stderr gets one line, prefixed with the program name, containing the FILE argument
  exactly as given followed by the operating system's standard description of the
  error (for example the host's text for "no such file or directory", "permission
  denied", or "is a directory").
- stdout gets nothing.
- The exit status is `1`.

For example, `stamp ""` reports the empty path with the "no such file or directory"
description and exits 1.

### 10.3 FILE content is not valid UTF-8 (exit 1)

When FILE opens but its content contains a byte sequence that is not valid UTF-8:

- stderr gets a multi-line runtime error report stating that the content could not
  be decoded as UTF-8, including the offending byte and its position. This report
  does **not** use the one-line format of 10.2.
- stdout gets nothing, even for lines before the invalid bytes.
- The exit status is `1`.

### 10.4 Failure while writing output (exit 1)

- `UNVERIFIED`: stdout closed early by the reader (for example `stamp FILE | head -1`
  on a long file). Tried: nothing could be run. Hypothesis: the process exits 1 and
  may write a runtime-generated broken-pipe report to stderr. Lines already accepted
  by the reader stay with the reader.
- `UNVERIFIED`: a character that the stdout encoding cannot represent (see 6.2).
  Hypothesis: lines before it may already be written (subject to buffering), a
  runtime error report naming the encoding failure goes to stderr, and the exit
  status is 1.

### 10.5 Dependencies unreachable

`stamp` has no external dependencies other than the FILE (10.2). No other
unreachable-dependency case exists.

---

## 11. Surface 9 - Observable guarantees

- **One prefix per run.** The clock is sampled once. Every stamped line in a run has
  byte-identical prefixes, even when the run crosses a second boundary.
- **Timestamp is taken after input is complete.** The time in the prefix is no
  earlier than the moment FILE was read to its end. When FILE is a named pipe whose
  writer holds it open for 10 seconds before closing, the prefix reflects the time
  of closing, not the time `stamp` started.
- **All-or-nothing on input errors.** Nothing is written to stdout until the
  arguments are fully valid and the whole FILE has been read and decoded. An
  argument, open, read, or decode error therefore leaves stdout empty.
- **Order and count.** Output lines appear in input order, one output line per input
  line (section 5.2), and no others.
- **FILE is not modified.** The FILE's content and metadata other than access time
  are unchanged by a run.
- **Concurrency.** Runs share no state. Any number of concurrent runs, including
  runs on the same FILE, do not affect each other's output.

[APPSPEC:sweep-the-surfaces]

---

## 12. Audit record

**Pass 1 - completeness sweep** (walked sections 3-11 in the written document):

- Surfaces 1-9 each map to one section (3, 4, 5, 6, 7, 8, 9, 10, 11).
- Surfaces with no content (5 persistent state, 6 external systems) say how absence
  was established.
- Changes made:
  - added the argument-order error precedence (3.3);
  - added the empty-but-set `STAMP_FORMAT` case (4.1);
  - added the non-UTF-8 content case with its different stderr form (10.3);
  - added the output-side failures (10.4);
  - added `TZ` to configuration;
  - stated that stdin is never read.

**Pass 2 - purity reread** (tested every sentence against "could an outside observer
confirm this?"):

- Removed a mention of the language runtime's specific exception names from the
  error sections, replacing them with the observable stderr content and exit status.
- Reworded "reads the file into memory" as the observable guarantee "nothing is
  written until the whole file has been read" (11).
- Reworded "decodes with universal newlines" as the explicit terminator table (5.2).
- Replaced the transcribed usage and error message text with descriptions of their
  information content (10.1, 10.2).

[APPSPEC:two-audit-passes]
