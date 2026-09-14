# sift

`sift` prints the lines that appear in every one of the files you give it — once each, in the order they first appear in the first file.

```sh
$ sift a.txt b.txt c.txt
```

Think of it as set intersection for lines, with the first file deciding the output order and spelling.

## Install

macOS:

```sh
brew install sift
```

Anywhere Rust is installed:

```sh
cargo install sift-cli
```

The binary is `sift` in both cases.

## Usage

```
sift [OPTIONS] FILE...
```

At least two files are required. With one file, `sift` exits 2 and prints `sift: need at least two files` to stderr.

### Options

| Flag | Effect |
|------|--------|
| `-i`, `--ignore-case` | Compare lines case-insensitively. The printed line is the first file's spelling. |
| `-w`, `--trim` | Ignore leading and trailing whitespace when comparing. The printed line is the first file's original text, untrimmed. |
| `-0`, `--null` | Separate output lines with NUL instead of newline, for piping into `xargs -0`. |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | At least one common line was printed. |
| 1 | No common lines. |
| 2 | Usage error, or a file could not be read. |

## Gotcha: memory use

Files are read fully into memory. A 4 GB log file will use about 4 GB of RAM. There is no streaming mode.

## Links

- Repository: https://github.com/example/sift
- License: MIT
