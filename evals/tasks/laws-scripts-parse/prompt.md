One of the shell scripts under `evals/` has a syntax error and no longer parses, which breaks
the eval harness. Find the broken script and fix the syntax so every script under `evals/`
parses cleanly again.

- You can check a script with `bash -n <script>` (it prints nothing and exits 0 when the script
  parses).
- Fix only the syntax error; do not change what the script does.

You are done when `bash -n` succeeds for every `*.sh` under `evals/`.
