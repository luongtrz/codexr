# Parallel codex runs (max 20 at a time)

Read this when running several independent tasks at once.

**Limit:** up to **20** concurrent codex runs (`codex-task` implement runs and `codex-run` read-only explore runs combined). The reason is that codex and `codex-task` run no tests, so parallel codex runs do not load the machine; the compute load comes from YOUR verification afterwards, so run verification commands one at a time (one worktree at a time), never multiple test suites at once. Count live runs before launching more:
```bash
pgrep -fc 'codex-(task run --name|run --prompt)'
```
Other sessions' runs on the host count toward this limit.

## Rules

- **One background tool call per task (NEVER bundle into a wrapper script or `wait` loop):** launch each `codex-task run` or `codex-run` as its own separate background command tool call. Never write a batch launcher (`launch.sh`, `queue.sh`, or `for pid in "${pids[@]}"; do wait "$pid"; done`) that spawns multiple `codex-task` processes inside a single command. A bundled command hides individual task progress in the UI and delays your wakeup notification until the slowest task in the batch finishes. With separate background tool calls, the system notifies you as soon as each individual task finishes so you can review, test, and integrate it immediately.
- **Implement tasks: one git worktree per run** — `codex-task run --name <task> --base <same-sha> …` creates and prepares it (setup + copied files from `.codex-sessions/codex-task.conf`), so give each parallel run its own `--name` and the same `--base`. Never let two runs write to the same worktree — disjoint files collide in concurrent builds/linters and make diffs impossible to attribute.
- **Splitting a multi-part feature across parallel runs:** split by non-overlapping `--scope` paths (e.g. DB/repo layer, service layer, API handler) and specify exact exported names, function signatures, types, and error constants that both sides rely on in each task file (the sibling's code does not exist in that worktree yet). For tasks where `SETUP_CMDS` is unneeded, pass `--no-setup` to save time. Note that `COPY_FILES` in `codex-task` copies from the main checkout: if your current branch is in a linked worktree with files not yet on the main checkout, copy them into the worktree before verification.
- Read-only review / exploration runs can share the main repository checkout (`--add-dir "$REPO"` with `--sandbox read-only`).
- Each parallel run consumes tokens; all runs share the same account pool managed by `codexr`. Account rotation in one run acquires `.swap.lock` atomically so parallel processes do not corrupt account state.
- If tasks touch the same files heavily, run them sequentially in one worktree instead; parallelism pays only when the conflict surface is small.

## Integrate as each task finishes, one run at a time

As each background task completes and triggers a wakeup notification:
1. Review its worktree diff and run targeted checks yourself (one worktree at a time).
2. Commit/integrate it on the target branch before or while waiting on remaining tasks.
3. If tasks touched adjacent files or shared configs, resolve any merge conflicts, then re-run verification on the integrated branch before pushing.
4. Clean up the finished worktree: `codex-task rm <task> -f`.

## More than 20 tasks

Launch up to 20 separate background tool calls first. Each time one finishes and wakes you up, review/integrate it, clean it up, and launch the next unstarted task as its own separate background tool call. Never use a background `queue.sh` or `wait` loop.
