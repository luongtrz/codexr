# Transient server errors and retries

Read this when a `codex-run` or `codex-task` session ends with a server error, stream timeout, or unexpected failure (exit code 1), or when a running session appears stalled.

Unlike usage-limit errors (which trigger automatic account rotation to another slot in the pool), server-side errors or capacity issues (e.g. HTTP 500, 502, 503, 504, or stream disconnects) are upstream service issues. Codex shares a single quota pool across models, and default model `gpt-6-luna` with reasoning effort `max` remains the standard configuration; do NOT switch models on an outage unless the user explicitly instructs you to do so.

## When to retry

1. **Single transient failure:** if a run fails with a 500/502/503/504 server error, connection reset, or stream interruption at the very end of a turn:
   - First check `changed files:` and `codex report:` in the summary or `.codex-sessions/<task>.summary.txt`. If the edits are complete and the report is clear, inspect the diff and run tests yourself instead of re-running.
   - If changes are incomplete, wait ~30–60 seconds and resume the session using `--resume`:
     ```bash
     codex-task run --name <task> --resume --task <repo>/.codex-sessions/<task>.task.txt --scope '<pathspec>'
     ```
     For a read-only exploration task with `codex-run`, resume with:
     ```bash
     codex-run --prompt "$PROMPT" --add-dir "$REPO" --log "$LOG" --conversation <thread_id> --sandbox read-only
     ```

2. **Stalled sessions:**
   - Before assuming a session is frozen, check whether the log is still receiving events:
     ```bash
     grep -c '^{' <repo>/.codex-sessions/<task>.jsonl && grep '^{' <repo>/.codex-sessions/<task>.jsonl | tail -1
     ```
     `codex-run` only logs account switches or critical notices to stderr; the JSONL log is where streaming progress appears.
   - If no events have been appended for ~10 minutes, kill the stuck run:
     Terminate the `codex-task` process, `codex-run`, and the child `codex` process group.
   - Check if the worktree contains partial edits (`git -C <repo>/.worktrees/codex-<task> status`).
   - If partial work is good, resume with `--resume`. If the state is corrupted or unusable, clean up the worktree or start a fresh session with `--reuse-worktree --no-setup`.

3. **Persistent service downtime:**
   - If OpenAI services report sustained downtime or consecutive runs fail across accounts with upstream errors, STOP and notify the user rather than spinning in a retry loop.
