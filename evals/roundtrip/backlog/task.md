# Task: seed the backlog for `pocketlog`

Write the initial backlog for the project below as one Markdown file: the epics, and the
issues under each. Output only that file. Plan only work the founding document supports.
Do not add features, integrations, platforms, dates, or numbers it does not give.

## Founding document

`pocketlog` is a command-line notebook for one person on one machine.

- `pocketlog add "text"` appends a timestamped entry to today's file,
  `~/.pocketlog/YYYY-MM-DD.md`.
- `pocketlog today` prints today's entries.
- `pocketlog search WORD` prints every entry from any day that contains WORD, newest
  first.
- Entries can carry tags written as `#tag`. `pocketlog tags` lists every tag with its
  count.
- It must work with no network access, ever.
- It is written in Rust and shipped as a single binary.
- Maybe later: syncing between machines. Nobody knows how yet, and it is not part of the
  first release.
- The first release is done when all four commands work and a test suite covers them.

## Reader

Agents who will pull issues from this backlog one at a time, each in a fresh session with
the repository and nothing else.
