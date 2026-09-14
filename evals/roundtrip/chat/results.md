# Chat: results

The task was to reply to a user who asked why CI is red and whether it is fixed, using
a fixed list of what the agent found and did. Every arm and both judges ran on Opus 5,
with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | round trip | current | control |
| current guidance | current | round trip | control |

| Arm | Facts misstated | Claims added | Rules not met |
|---|---|---|---|
| control | 0 and 0 | 0 and 0 | 3 and 2 |
| current | 1 and 0 | 0 and 0 | 2 and 1 |
| round trip | 0 and 0 | 1 and 1 | 2 and 1 |

Each cell gives the spec judge's count, then the guidance judge's.

## Findings

- **The control was the most faithful and still ranked last.** It never says which
  claims were verified and which were inferred, and it repeats that the fix is not
  pushed. Both judges named those two failures.
- **Both crafts make the reply label what was checked.** The round trip labels most
  explicitly, marking each claim as verified, a hypothesis, or a proposal.
- **The round trip made one claim the facts do not support.** It said httpx 0.28 had
  been deployed to production, and both judges caught it. The current craft's only slip
  was saying every chunk exceeds the timeout, which one judge counted.
- **The round-trip craft matched the current one.** The judges split first place
  between them, and both put the control last.
