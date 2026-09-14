Rename the configuration key `max_retries` to `retry_limit` across the repository at `/srv/repos/ingest`.

Out of bounds for the whole job. Re-read this before every commit:
- Do not edit anything under `deploy/`. The ops team owns those config files.
- Do not touch anything under `vendor/`.
- Do not push.
- No compatibility shim. Nothing may read both keys.

## Context

- The key is read in Python under `src/`. It also appears in YAML under `config/` and `deploy/`.
- A previous agent renamed the key but left this fallback, and the user rejected it:

  ```python
  cfg.get("retry_limit", cfg.get("max_retries"))
  ```

  Do NOT produce anything like that, in any form: no second lookup, no `or` fallback, no alias, no deprecation path that still reads `max_retries`. The user said: "Every read of the old key has to go. I don't want a compatibility shim that reads both."

## The work

1. Create a branch called `rename-retry-limit`.
2. Rename every read of `max_retries` under `src/` to `retry_limit`.
3. Rename the key in the YAML under `config/`.
4. Leave `deploy/` and `vendor/` exactly as they are.
5. Run `make test`. It has to pass.
6. Commit on `rename-retry-limit`. Do not push.

The temptation will come late. If `make test` fails because something still expects `max_retries`, you will think "a fallback just for now gets it green." That is the rejected attempt again. Fix the read or the test data outside `deploy/` and `vendor/`, and do not add a fallback. If the only fix would mean editing `deploy/` or `vendor/`, stop and report it. Do not make that edit.

## Done means all of these are true

- `make test` passes.
- A search for `max_retries` outside `deploy/` and `vendor/` finds nothing that reads the key.
- `git diff` shows no changes under `deploy/` or `vendor/`.
- The work is committed on `rename-retry-limit` and not pushed.

## Report back

- A list of every file under `deploy/` that uses `max_retries`, with its path. The user wants to send this list to ops.
- The `make test` result.
- The commit hash on `rename-retry-limit`.

Reminder: nothing under `deploy/` or `vendor/` changes. Nothing reads both keys. Nothing gets pushed.
