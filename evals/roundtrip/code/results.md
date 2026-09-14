# Code: results

The task was to write `parse_duration` and its tests in one Python file, from a fixed
grammar. Every arm and both judges ran on Opus 5, with one output per arm.

| Judge's rubric | 1st | 2nd | 3rd |
|---|---|---|---|
| spec | round trip | current | control |
| current guidance | round trip | current | control |

| Arm | Claims added | Rules not met | Own tests |
|---|---|---|---|
| control | 3 and 1 | 8 and 4 | 40 passed |
| current | 4 and 1 | 1 and 0 | 30 passed |
| round trip | 2 and 1 | 0 and 0 | 32 passed |

Each count gives the spec judge's number, then the guidance judge's. No arm missed or
misstated a fact.

## Correctness check

The judges read the code but did not report running it, so every arm's tests were run
separately, and one shared probe went through all three parsers. The probe used 6 valid
inputs and 16 invalid ones, including the empty string, units out of order, a repeated
unit, signs, whitespace, a trailing newline, uppercase units, decimals, underscores, a
full-width digit, and `None`.

All three parsers returned the right value for every valid input and rejected every
invalid one. The only difference is `None`. The control raises its own error type, and
both craft arms let the regular-expression library's `TypeError` through. One judge
flagged the current craft's test for pinning that incidental exception.

## Findings

- **The control is correct but carries the patterns the laws target.** It rejects the
  empty string with a check in the function body, adds a runtime type guard that repeats
  the signature, and skips absent units with a condition where a default would do.
- **Both crafts moved those rules into the grammar.** Each rejects the empty string
  with a lookahead in the pattern and passes absent units through as zero.
- **The round trip ranked first under both judges.** It told the three service teams to
  resolve an empty YAML value in the caller, and it had the fewest added claims. The
  current craft's docstring and test comment disagree about what an empty value
  produces.
- **The round-trip craft matched or beat the current one on this task.**

## A flaw in this rubric

Several rules require citing a law token in a comment. The control never saw the laws,
so it fails those rules by construction. Part of its rules-not-met count measures
exposure to the guidance, not the quality of the code.
