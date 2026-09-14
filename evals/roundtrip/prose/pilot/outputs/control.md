# sift

`sift` prints the lines that appear in every one of the files you give it. Each common line is printed once, in the order it first appears in the first file.

```console
$ sift a.txt b.txt c.txt
```

## Install

macOS:

```sh
brew install sift
```

Anywhere Rust is installed:

```sh
cargo install sift-cli
```

Either way, the binary is called `sift`.

## Usage

```
sift [OPTIONS] FILE...
```

You must give at least two files. With only one, `sift` prints `sift: need at least two files` to stderr and exits with code 2.

## Options

| Option | What it does |
| --- | --- |
| `-i`, `--ignore-case` | Compare lines case-insensitively. The line is printed as spelled in the first file. |
| `-w`, `--trim` | Ignore leading and trailing whitespace when comparing. The line is printed as the first file's original, untrimmed text. |
| `-0`, `--null` | Separate output lines with NUL instead of newline, for piping into `xargs -0`. |

Example with `-0`:

```sh
sift -0 list1.txt list2.txt | xargs -0 ...
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | At least one common line was printed. |
| 1 | No common lines. |
| 2 | Usage error, or a file could not be read. |

## Memory use

`sift` reads each file fully into memory. There is no streaming mode, so a 4 GB log file will use about 4 GB of RAM.

## License

MIT. Source: https://github.com/example/sift
