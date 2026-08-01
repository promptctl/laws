# Turn driver (exchange turns with a live session, refuse a bad turn)

Drives a **real, live, interactive** Claude Code TUI over tmux through one or more turns and
returns each reply - or aborts loudly. This is the general multi-turn driver; it builds on the
isolation primitives in `../isolation` (subscription Opus, no CLAUDE.md leak) and never reaches
around them.

The whole eval harness is a loop over this driver. One unvalidated bad turn - an empty read, a
timed-out turn, a session that died - silently becomes a corrupt datapoint and, multiplied by
the loop, a confidently wrong verdict. So the driver's one rule is: **a turn it cannot complete
cleanly stops the line, it never returns a partial or empty reply dressed as an answer.**

## Use it

```sh
# one turn
evals/driver/drive.sh 'Reply with exactly: hello'

# several turns on ONE session (context accumulates, as a real task's does)
evals/driver/drive.sh 'Create a file foo.txt with the text bar' 'Now read it back to me'

# a single multi-line prompt on stdin
printf 'line one\nline two\n' | evals/driver/drive.sh
```

Replies print on stdout; progress on stderr. Exit `0` iff every turn completed and its reply
was printed; nonzero (with a located message on stderr) the moment a turn cannot be completed.

## Verify it

```sh
evals/driver/verify-driver.sh
```

Exits `0` iff all five checks pass against a live Opus session:

| Check | What it proves |
|-------|----------------|
| A | a throwaway prompt returns the reply text and exits 0 |
| B | turns compose: a second turn returns *its* reply, not the first's (no staleness) |
| C | a slow turn is waited out in full - the reply's final end-token is present, never an early partial |
| F | a reply several times the pane height completes with its head (scrolled off the pane) and tail both present |
| D | a turn that never reaches idle within its bound exits nonzero and emits no reply |
| E | killing the session mid-turn exits nonzero and emits no reply |

## How a turn boundary is detected (and why it is race-free)

A turn is **done** when the screen is idle **and** the reply block *below the prompt we just
submitted* is non-empty **and** unchanged across two polls. Three things fall out of that:

- **The previous turn's reply can't be mistaken for this one.** It sits *above* our prompt in
  the transcript, so it is structurally excluded from "the reply below our prompt".
- **Pre-work idle can't be mistaken for done.** Right after submit, the reply region below our
  prompt is still empty, so the driver keeps waiting - it never needs to catch the transient
  "working" indicator, which a fast turn can finish between polls.
- **The reply is returned parsed and clean** - the trailing completion stamp (`✻ … for Ns`)
  and input-box chrome are trimmed off - so callers downstream never re-parse a raw pane.
- **A reply longer than the pane still completes.** The driver captures the full retained
  scrollback (`capture-pane -S -`), not just the visible pane, so a reply that scrolls its head
  (and the prompt anchor) off-screen is still found whole. Retention is bounded by the session's
  `history-limit`, set generously at launch; the footer/idle tokens still sit at the live bottom.

The prompt is delivered by **bracketed paste** (`tmux paste-buffer -p`) so multi-line task text
stays in the input box intact; submission is a single explicit Enter afterward, never a newline
side effect. The active "working" indicator is pinned to a self-owned sentinel via
`spinnerVerbs` (injected with `--settings`, which does not disturb the isolation), so
working-detection keys off a token we control rather than Anthropic's version-dependent verbs.

## Files

- `lib.sh` - `drive_turn` (the primitive), the pure frame parsers (`drv_frame_idle`,
  `drv_reply_below_prompt`, …), `drv_send` (bracketed-paste + explicit submit), and `drv_launch`
  (isolation launch + the spinner sentinel). Sources `../isolation/lib.sh`; the dependency runs
  driver → isolation, never back.
- `drive.sh` - the CLI: launch an isolated session, drive the given turns, print replies, tear
  down. The config dir is left intact (it holds the one-time login).
- `verify-driver.sh` - the five live checks above.

## Knobs (env, all optional)

`DRV_TURN_TIMEOUT_SECS` (per-turn ceiling), `DRV_POLL_SECS` (idle-poll cadence),
`DRV_SETTLE_POLLS` (consecutive stable reads before a reply counts as rendered),
`DRV_SEND_SETTLE_SECS`, `DRV_SPINNER_SENTINEL`, plus the isolation knobs (`ISO_CONFIG_DIR`,
`ISO_WORK_DIR`, `ISO_SESSION`, pane geometry) from `../isolation`.
