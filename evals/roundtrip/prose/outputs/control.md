# sift

`sift` prints the lines that appear in every one of the files you give it. Each common line is printed once, in the order it first appears in the first file.

```sh
sift a.txt b.txt c.txt
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

Either way, the binary is named `sift`.

## Usage

```sh
sift [OPTIONS] FILE...
```

`sift` needs at least two files. Given only one, it prints `sift: need at least two files` to stderr and exits with code 2.

## Options

| Option | What it does |
| --- | --- |
| `-i`, `--ignore-case` | Compare lines case-insensitively. The printed line uses the first file's spelling. |
| `-w`, `--trim` | Ignore leading and trailing whitespace when comparing. The printed line is the first file's original text, untrimmed. |
| `-0`, `--null` | Separate output lines with NUL instead of newline, for piping into `xargs -0`. |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | At least one common line was printed. |
| 1 | There were no common lines. |
| 2 | Usage error, or a file could not be read. |

## Memory use

`sift` reads each file fully into memory. There is no streaming mode, so a 4 GB log file will use about 4 GB of RAM.

## License

MIT. Source: https://github.com/example/sift
