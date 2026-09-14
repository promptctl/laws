# sift

`sift` prints the lines that appear in every file you give it - once each, in the order they first appear in the first file.

```sh
$ cat a.txt
apple
banana
cherry
$ cat b.txt
cherry
apple
$ sift a.txt b.txt
apple
cherry
```

## Install

```sh
brew install sift          # macOS
cargo install sift-cli     # anywhere Rust is installed
```

The binary is `sift` either way.

## Usage

```
sift [OPTIONS] FILE...
```

At least two files are required. With one file, `sift` exits 2 and prints `sift: need at least two files` to stderr.

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

## Memory

`sift` reads every file fully into memory. A 4 GB log file will use about 4 GB of RAM. There is no streaming mode.

## Links

Repository: https://github.com/example/sift

License: MIT
