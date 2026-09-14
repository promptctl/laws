# Ticket: results

The task was to write one ticket for a CSV export bug from a fixed list of facts. Every
arm and both judges ran on Opus 5, with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | current | round trip | control |
| current guidance | round trip | current | control |

| Arm | Facts missing | Claims added | Rules not met |
|---|---|---|---|
| control | 2 and 2 | 2 and 1 | 7 and 5 |
| current | 5 and 5 | 4 and 3 | 0 and 1 |
| round trip | 5 and 5 | 3 and 2 | 1 and 1 |

Each cell gives the spec judge's count, then the guidance judge's.

## Findings

- **Either craft turns a bug report into a ticket.** The control has no why and no
  completion signal. It copies the line number and the `strings.Split` call, and points
  at the import code as a route to the fix. Both craft arms state an end state, a
  one-line why, and a signal a reader can check.
- **The round-trip craft matched the current one.** The two judges split first place
  between them. The round trip once set the scope of verification ("check those cases
  too"), which the ticket rules forbid. The current craft added one more unsupported
  claim.
- **Both crafts added a requirement nobody gave.** Each wrote some form of "no expense
  is left out without anyone knowing", which the judges counted against fidelity.

## A flaw in this task

The task says to use every fact, and its facts include line 88 and the exact call. The
ticket craft forbids pointing at code more precisely than a filename. So both craft arms
were scored as missing facts they were right to leave out. The missing-facts column
favours the control for that reason. A better ticket task would give facts the craft
can use in full.
