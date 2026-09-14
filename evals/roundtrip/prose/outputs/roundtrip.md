# sift

`sift` prints the lines that appear in every one of the files you give it. Each
common line is printed once, in the order it first appears in the first file.

```sh
sift monday.log tuesday.log wednesday.log
```

`sift` reads every file fully into memory, and there is no streaming mode. A 4 GB log
file uses about 4 GB of RAM.

## Install

On macOS:

```sh
brew install sift
```

Anywhere Rust is installed:

```sh
cargo install sift-cli
```

The crate is named `sift-cli`, but both methods install a binary named `sift`.

## Usage

```sh
sift [OPTIONS] FILE...
```

`sift` needs at least two files. Given only one, it prints
`sift: need at least two files` to stderr and exits with code 2.

## Options: -i, -w, -0

`-i`, `--ignore-case`
: Compare lines case-insensitively. The printed line uses the first file's spelling.

`-w`, `--trim`
: Ignore leading and trailing whitespace when comparing lines. The printed line is the
  first file's original text, with its whitespace intact.

`-0`, `--null`
: Separate output lines with NUL instead of newline, for piping into `xargs -0`:

  ```sh
  sift -0 a.txt b.txt | xargs -0 echo
  ```

## Exit codes

| Code | Meaning                                         |
|------|-------------------------------------------------|
| 0    | At least one common line was printed.           |
| 1    | The files have no line in common.               |
| 2    | Usage error, or a file could not be read.       |

## License

MIT. Source: https://github.com/example/sift
