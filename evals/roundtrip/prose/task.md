# Task: write the README for `sift`

Write `README.md` for a command-line tool called `sift`. Output only the README's
contents. Use every fact below; do not invent features, flags, or numbers.

## Facts

- `sift` prints the lines that appear in every one of the files given to it, once each,
  in the order they first appear in the first file.
- Install: `brew install sift` on macOS, or `cargo install sift-cli` anywhere Rust is
  installed. The binary is `sift` in both cases.
- Usage: `sift FILE...` - at least two files. With one file it exits 2 and prints
  `sift: need at least two files` to stderr.
- `-i` / `--ignore-case` compares lines case-insensitively; the printed line is the
  first file's spelling.
- `-w` / `--trim` ignores leading and trailing whitespace when comparing; the printed
  line is the first file's original text, untrimmed.
- `-0` / `--null` separates output lines with NUL instead of newline, for piping into
  `xargs -0`.
- Exit codes: 0 when at least one common line was printed, 1 when there were none, 2 on
  usage error or an unreadable file.
- Gotcha: files are read fully into memory. A 4 GB log file will use about 4 GB of RAM.
  There is no streaming mode.
- Repository: https://github.com/example/sift. License: MIT.

## Readers

1. A developer who landed on the repository from a search and will decide within
   thirty seconds whether this tool does what they need.
2. An existing user who has forgotten what `-w` does and wants the answer without
   reading anything else.
