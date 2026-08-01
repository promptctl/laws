Several tests in this repository are failing: more than one bug has crept into the library
source, in more than one area of the codebase.

Your task: find and fix every bug so the repository's own quality gates all pass again.

- Run the test suite with `pnpm install --frozen-lockfile` then `pnpm test`.
- Fix the *implementation*, not the tests. Do not modify or delete any existing test or
  conformance fixture.
- The fixes should be minimal and correct — restore the intended behavior of each function.

You are done when `pnpm test`, `pnpm typecheck`, and `pnpm lint` all pass with no failures.
