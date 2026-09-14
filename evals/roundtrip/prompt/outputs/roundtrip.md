<boundaries>
Do not edit anything under `deploy/` or `vendor/`. The `deploy/` config files belong to the ops team, and the user said: "Config files in `deploy/` are owned by the ops team. Don't edit them." The user also said: "Don't touch `vendor/`." Do not push.

A test or config lookup will fail at some point, and you will think a fallback that reads the old key too is the safe fix. It isn't. The user already rejected that exact fix from an earlier attempt.
</boundaries>

<task>
Rename the configuration key `max_retries` to `retry_limit` across the repository at `/srv/repos/ingest`.

Deliverables:
1. A commit on a new local branch named `rename-retry-limit` that contains the rename.
2. In your final message, list the path of every file under `deploy/` that uses `max_retries`, so the user can send the list to ops.
</task>

<requirements>
The user's words:
- "Every read of the old key has to go. I don't want a compatibility shim that reads both."
- "Config files in `deploy/` are owned by the ops team. Don't edit them. List every one that uses the old key so I can send it to ops."
- "Don't touch `vendor/`."
- "Tests have to pass: `make test`."
- "Commit it on a branch called `rename-retry-limit`. Don't push."
</requirements>

<context>
- The key is read by Python code under `src/`. It also appears in YAML under `config/` and `deploy/`.
- An earlier agent renamed the key but left this fallback: `cfg.get("retry_limit", cfg.get("max_retries"))`. The user rejected that work.
</context>

<do-not-produce>
- `cfg.get("retry_limit", cfg.get("max_retries"))`, which is the rejected fallback.
- Any other form that still reads `max_retries`, such as `cfg.get("max_retries")`, `cfg["max_retries"]`, `"max_retries" in cfg`, or a lookup that tries both keys.
- Any edit to a file under `deploy/` or `vendor/`.
- A push, or a commit on any branch other than `rename-retry-limit`.
</do-not-produce>

<done-when>
Stop once all of these are true:
- `grep -rn max_retries /srv/repos/ingest --exclude-dir=deploy --exclude-dir=vendor --exclude-dir=.git` prints nothing.
- `make test` exits 0.
- `git diff --name-only master...rename-retry-limit` (or the same comparison against the repo's default branch) lists no path under `deploy/` or `vendor/`.
- The work is committed on `rename-retry-limit` and nothing has been pushed.
- Your final message lists every file under `deploy/` that contains `max_retries`. Get the list from `grep -rln max_retries deploy/`.

Reminder: do not edit `deploy/` or `vendor/`, do not add a fallback that reads `max_retries`, and do not push.
</done-when>
