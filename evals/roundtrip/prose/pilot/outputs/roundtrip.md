# sift

`sift` prints the lines that appear in every file you give it. Each common line is printed once, in the order it first appears in the first file.

```sh
sift monday.log tuesday.log wednesday.log
```

That prints every line present in all three logs, in `monday.log`'s order.

Files are read fully into memory, so `sift` is not suited to files larger than the RAM you can spare. See [Memory use](#memory-use).

## Install

On macOS:

```sh
brew install sift
```

Anywhere Rust is installed:

```sh
cargo install sift-cli
```

The crate is named `sift-cli`, but both methods install a binary called `sift`.

## Usage

```sh
sift [OPTIONS] FILE...
```

`sift` needs at least two files. Given only one, it prints `sift: need at least two files` to stderr and exits with code 2.

## Options

`-i`, `--ignore-case`
: Compare lines without regard to case. The line is printed as it is spelled in the first file.

`-w`, `--trim`
: Ignore leading and trailing whitespace when comparing lines. The line is printed as it appears in the first file, with its whitespace left intact.

`-0`, `--null`
: Separate output lines with a NUL byte instead of a newline, so the output can be piped into `xargs -0`.

For example, to delete every file listed in both `a.txt` and `b.txt`, even when names contain spaces:

```sh
sift -0 a.txt b.txt | xargs -0 rm
```

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | At least one common line was printed. |
| 1 | The files have no line in common. |
| 2 | Usage error, or a file could not be read. |

Because "no common lines" is exit code 1, a script can test the result directly: `if sift a.txt b.txt > common.txt; then ...`.

## Memory use

`sift` reads every file fully into memory before comparing, and there is no streaming mode. A 4 GB log file uses about 4 GB of RAM.

## License

MIT. Source and issues: https://github.com/example/sift
