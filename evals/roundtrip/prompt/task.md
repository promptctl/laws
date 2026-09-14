# Task: write the subagent prompt

You are delegating a job to a fresh subagent that sees nothing except the prompt you
write. Write that prompt. Output only the prompt text. Carry every requirement below into
it. Do not add requirements, constraints, or facts that are not given.

## The job

Rename the configuration key `max_retries` to `retry_limit` across the repository at
`/srv/repos/ingest`.

## The user's requirements, verbatim

- "Every read of the old key has to go. I don't want a compatibility shim that reads both."
- "Config files in `deploy/` are owned by the ops team. Don't edit them. List every one
  that uses the old key so I can send it to ops."
- "Don't touch `vendor/`."
- "Tests have to pass: `make test`."
- "Commit it on a branch called `rename-retry-limit`. Don't push."

## Facts

- The key is read in Python under `src/` and appears in YAML under `config/` and
  `deploy/`.
- A previous attempt by another agent renamed the key but left the fallback
  `cfg.get("retry_limit", cfg.get("max_retries"))`. The user rejected it.

## Reader

The subagent. It has shell access to the repository and nothing else from this
conversation.
