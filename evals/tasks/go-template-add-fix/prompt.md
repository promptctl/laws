A regression has been introduced into this repository: the Sprig `add` helper no longer
computes a sum, and its test now fails. Several other tests may fail as a consequence.

Your task: find and fix the bug in the library source so that the full test suite passes again.

- Run the test suite with `pnpm install --frozen-lockfile` then `pnpm test`.
- Fix the *implementation*, not the tests. Do not edit, skip, or delete any test.
- The fix should be minimal and correct — restore the intended behavior of the function.

You are done when `pnpm test` passes with no failures.
