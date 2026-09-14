# sift

`sift` prints the lines that appear in every file you give it. Each common line is
printed once, in the order it first appears in the first file.

```console
$ cat monday.txt
alice
bob
carol
$ cat tuesday.txt
carol
alice
dave
$ sift monday.txt tuesday.txt
alice
carol
```

## Install

On macOS:

```sh
brew install sift
```

Anywhere Rust is installed:

```sh
cargo install sift-cli
```

Both install a binary named `sift`.

## Usage

```sh
sift [OPTIONS] FILE...
```

`sift` needs at least two files. Given only one, it prints
`sift: need at least two files` to stderr and exits with status 2.

## Options: -i, -w, -0

| Option | What it does |
| --- | --- |
| `-i`, `--ignore-case` | Compares lines case-insensitively. The output uses the first file's spelling. |
| `-w`, `--trim` | Ignores leading and trailing whitespace when comparing. The output is the first file's original line, whitespace included. |
| `-0`, `--null` | Separates output lines with NUL instead of newline, for piping into `xargs -0`. |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | At least one common line was printed. |
| 1 | The files have no lines in common. |
| 2 | Usage error, or a file could not be read. |

## Memory use

`sift` reads each file fully into memory, and there is no streaming mode. A 4 GB log
file uses about 4 GB of RAM.

## License

MIT. Source: https://github.com/example/sift
