# sift

Print the lines that every file has in common.

`sift` reads two or more files and prints each line that appears in all of them. Each
line is printed once, in the order it first appears in the first file.

```console
$ cat a.txt
apple
banana
cherry
$ cat b.txt
cherry
apple
date
$ sift a.txt b.txt
apple
cherry
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

Either way, the binary is called `sift`.

## Usage

```sh
sift FILE...
```

Give it at least two files. With only one, `sift` prints `sift: need at least two files`
to stderr and exits with code 2.

## Options

| Option | What it does |
| --- | --- |
| `-i`, `--ignore-case` | Compares lines without regard to case. The line is printed as the first file spells it. |
| `-w`, `--trim` | Ignores leading and trailing whitespace when comparing. The line is printed as the first file has it, whitespace included. |
| `-0`, `--null` | Ends each output line with NUL instead of a newline, for piping into `xargs -0`. |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | At least one common line was printed. |
| 1 | The files have no lines in common. |
| 2 | Usage error, or a file could not be read. |

## Memory use

`sift` reads every file fully into memory, and there is no streaming mode. A 4 GB log
file will use about 4 GB of RAM.

## License

MIT. Source: https://github.com/example/sift
