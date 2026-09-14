# `stamp` — Behavioral Specification

## 1. Purpose

`stamp` reads a text file and writes each of its lines to standard output, prefixed with a single timestamp and a space. The timestamp is the current time, taken once per run, rendered with a strftime-style format.

## 2. Invocation

```
stamp [-u] [-f FORMAT] FILE
```

### 2.1 Argument parsing

Arguments are processed left to right.

1. **Option phase.** While the next remaining argument begins with `-`, it is consumed as an option:
   - `-u` — select UTC time (see 4.2). May be given more than once; repeats have no extra effect.
   - `-f` — the argument immediately after it is consumed as FORMAT, verbatim, even if it begins with `-` (e.g. `-f -u` sets FORMAT to the string `-u`). `-f` may be repeated; the last one wins.
     - If `-f` is the last argument (no value follows), the program writes the usage line to stderr and exits with status 2.
   - Any other argument beginning with `-` is an unknown option. This includes a lone `-`, `--`, combined flags such as `-uf`, and attached values such as `-fX`. The program writes `stamp: unknown option ARG` (ARG being the argument exactly as given) to stderr and exits with status 2.
2. **Operand phase.** The option phase ends at the first argument that does not begin with `-`. All remaining arguments, including any that begin with `-`, are operands.
3. There must be exactly one operand, the FILE path. If there are zero or more than one, the program writes the usage line to stderr and exits with status 2.

Errors are reported at the first problem encountered in this order, and processing stops there. For example, `stamp -x` reports the unknown option (not the missing FILE), and `stamp -u` reports usage.

Options must precede FILE: `stamp file -u` has two operands and is a usage error. A file whose name begins with `-` cannot be named directly (a path such as `./-name` works).

No option has a long form, and there is no help or version option.

### 2.2 Usage line

The usage line is exactly:

```
usage: stamp [-u] [-f FORMAT] FILE
```

followed by a newline, written to stderr.

## 3. Configuration

| Source | Effect |
|---|---|
| `-f FORMAT` | Timestamp format. Highest precedence. |
| Environment variable `STAMP_FORMAT` | Timestamp format when `-f` is not given. Used whenever the variable is set, including when set to the empty string. |
| Built-in default | `%Y-%m-%dT%H:%M:%S` when neither of the above is present. |
| `-u` | Use UTC instead of local time. There is no environment equivalent. |
| Local time zone (e.g. `TZ`) | Determines local time when `-u` is absent, per the platform's normal time-zone rules. |

No configuration files are read.

## 4. Behavior

### 4.1 Reading the input

- FILE is opened and read in its entirety before any output is written.
- Content is decoded as UTF-8 (strict). A leading UTF-8 byte-order mark is not stripped; it becomes U+FEFF at the start of the first line.
- The content is split into lines. Each of the following ends a line, and the terminator is not part of the line: `\n`, `\r\n`, `\r`, `\v` (U+000B), `\f` (U+000C), U+001C, U+001D, U+001E, U+0085, U+2028, U+2029.
- A terminator at the very end of the file does not produce an extra empty line. Consecutive terminators produce empty lines (for example, `a\n\nb\n` is three lines: `a`, empty, `b`; `\r\n` counts as one terminator).
- An empty file has zero lines.

### 4.2 The timestamp

- After the file is read successfully, the current time is sampled once. Every output line of the run carries this same timestamp.
- Without `-u`, the time is local time. With `-u`, it is UTC.
- The time has whole-second resolution.
- The prefix is the time rendered with FORMAT using the platform's C `strftime` conversion. Characters other than `%`-directives are copied literally. Common directives:

  | Directive | Meaning |
  |---|---|
  | `%Y` | 4-digit year |
  | `%m` | month `01`–`12` |
  | `%d` | day `01`–`31` |
  | `%H` | hour `00`–`23` |
  | `%M` | minute `00`–`59` |
  | `%S` | second `00`–`61` |
  | `%j` | day of year `001`–`366` |
  | `%a` / `%A` | abbreviated / full weekday name |
  | `%b` / `%B` | abbreviated / full month name |
  | `%p` | AM/PM |
  | `%z` | UTC offset, `+HHMM` |
  | `%Z` | time-zone name |
  | `%%` | a literal `%` |

  Directives beyond these, and the handling of unrecognized directives, follow the host platform's `strftime`.
- An empty FORMAT yields an empty prefix.
- The default format yields e.g. `2026-09-14T08:05:03`.

### 4.3 Output

For each input line, in order, the program writes to stdout:

```
PREFIX + " " + LINE + "\n"
```

- Exactly one space separates prefix and line, even when the prefix is empty (the output line then begins with a space) or the line is empty (the output line then ends with a space).
- Output lines always end with `\n`, whatever terminator the input used.
- Line content is otherwise written unchanged. On a UTF-8 locale, output is UTF-8.
- An empty file produces no output.

On success the exit status is 0 and nothing is written to stderr.

## 5. Errors

| Condition | stderr | stdout | Exit status |
|---|---|---|---|
| Unknown option | `stamp: unknown option ARG` | nothing | 2 |
| `-f` with no following value | usage line | nothing | 2 |
| FILE operand missing, or more than one operand | usage line | nothing | 2 |
| FILE cannot be opened or read (does not exist, permission denied, is a directory, etc.) | `stamp: PATH: REASON` | nothing | 1 |
| FILE content is not valid UTF-8 | a multi-line diagnostic describing the decode failure (not in the `stamp:` form) | nothing | 1 |

- PATH is the FILE argument exactly as given.
- REASON is the operating system's standard description of the error, e.g. `No such file or directory`, `Permission denied`, `Is a directory`.
- Every stderr message ends with a newline.
- Because the whole file is read before output starts, no input-related error ever leaves partial output on stdout.

## 6. Examples

File `notes.txt` contains `alpha\nbeta\n`; local time is 2026-09-14 08:05:03, UTC is 2026-09-14 15:05:03.

```
$ stamp notes.txt
2026-09-14T08:05:03 alpha
2026-09-14T08:05:03 beta
$ echo $?
0

$ stamp -u -f '%H:%M' notes.txt
15:05 alpha
15:05 beta

$ STAMP_FORMAT='[%d/%m]' stamp notes.txt
[14/09] alpha
[14/09] beta

$ STAMP_FORMAT='[%d/%m]' stamp -f '%Y' notes.txt
2026 alpha
2026 beta

$ stamp missing.txt
stamp: missing.txt: No such file or directory      (stderr, exit 1)

$ stamp -v notes.txt
stamp: unknown option -v                            (stderr, exit 2)

$ stamp
usage: stamp [-u] [-f FORMAT] FILE                  (stderr, exit 2)

$ stamp notes.txt extra
usage: stamp [-u] [-f FORMAT] FILE                  (stderr, exit 2)
```
