Rename the configuration key `max_retries` to `retry_limit` across the repository at `/srv/repos/ingest`.

Where the key lives: it is read in Python under `src/`, and it appears in YAML under `config/` and `deploy/`.

Requirements (the user's words, verbatim):

- "Every read of the old key has to go. I don't want a compatibility shim that reads both."
- "Config files in `deploy/` are owned by the ops team. Don't edit them. List every one that uses the old key so I can send it to ops."
- "Don't touch `vendor/`."
- "Tests have to pass: `make test`."
- "Commit it on a branch called `rename-retry-limit`. Don't push."

What these mean in practice:

1. Rename every read and every occurrence of `max_retries` in `src/` and `config/` to `retry_limit`. When you finish, no code may read `max_retries` in any form.
2. No fallback. A previous agent renamed the key but left this line, and the user rejected the work because of it:

       cfg.get("retry_limit", cfg.get("max_retries"))

   Anything like that is a failure: a nested `get`, a try/except that falls back to the old name, an `or` between the two keys, a helper or alias that accepts either name. Code reads `retry_limit` only.
3. Do not edit anything under `deploy/`. Find every file there that uses `max_retries` and list each one by path.
4. Do not modify anything under `vendor/`.
5. Run `make test`. It must pass.
6. Create a branch named `rename-retry-limit`, commit the change there, and do not push.

Done means all of these are true:
- `grep -rn max_retries src config` returns nothing.
- `git diff` shows no changes under `deploy/` or `vendor/`.
- `make test` passes.
- The commit is on local branch `rename-retry-limit` and nothing was pushed.

When you finish, report:
- The full list of `deploy/` files that use `max_retries`, one path per line. This list goes to the ops team.
- The result of `make test`.
- The branch name and commit hash.
