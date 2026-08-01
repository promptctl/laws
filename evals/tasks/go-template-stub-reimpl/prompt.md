Two helper functions in this library have been gutted: their files still export the right
signatures, but the bodies just throw `not implemented`, and the test suite fails because of it.

Your task: reimplement the missing behavior so the repository's own quality gates all pass.

- Run the test suite with `pnpm install --frozen-lockfile` then `pnpm test` to see what is broken.
- Implement the *library source*, not the tests. Do not modify or delete any existing test or
  conformance fixture.
- Match the documented contract of each helper exactly — these functions mirror Go sprig
  semantics, and the tests encode the corner cases.

You are done when `pnpm test`, `pnpm typecheck`, and `pnpm lint` all pass with no failures.
