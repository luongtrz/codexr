# Manual implement workflow (fallback when `codex-task` is unavailable or too rigid)

Read this only if `codex-task` cannot be used directly. This is the exact process that `codex-task run` automates: creating the worktree, setting up dependencies, assembling the prompt with HARD RULES, running `codex-run`, and verifying the result.

1. **Create the worktree (you create it, never codex):**
   ```bash
   cd "$REPO" && git status --short                  # verify working copy is clean
   git worktree add --no-track ".worktrees/codex-<task>" -b "codex/<task>" [<base-ref>]
   WT="$REPO/.worktrees/codex-<task>"
   ```
   Ensure `.worktrees/` and `.codex-sessions/` are ignored in `.gitignore` or `.git/info/exclude`. When branching from a remote tracking branch, use `--no-track`.

2. **Prepare the worktree:**
   In `$WT`, run necessary setup commands (e.g. package installation, code generation, or copying untracked configuration from the main checkout). Check that setup succeeded and that the build/lint baseline is clean before launching codex.
   Always include an ENVIRONMENT NOTE in the task prompt: the environment is prepared; on an environment failure STOP (no package installs, no symlinks, no copying from outside).

3. **Assemble the prompt:**
   Write the task description to `.codex-sessions/<task>.task.txt` (Repo/stack, Task, Plan, Scope, Acceptance criteria; working directory = `$WT`), then append the HARD RULES template with `<ABS_PATH>` replaced:
   ```bash
   { cat "$REPO/.codex-sessions/<task>.task.txt"; echo; \
     sed "s#<ABS_PATH>#$WT#g" "$REPO/templates/hard-rules.txt"; } > "$REPO/.codex-sessions/<task>.prompt.txt"
   ```

4. **Run via `codex-run`:**
   Execute in the background and wait for the completion notification:
   ```bash
   codex-run --prompt "$REPO/.codex-sessions/<task>.prompt.txt" --add-dir "$WT" --log "$REPO/.codex-sessions/<task>.jsonl"
   ```

5. **Verify yourself in `$WT`:**
   Check `git -C "$WT" status` and `git -C "$WT" diff`. Run tests, builds, and linters yourself in `$WT`.

6. **Clean up:**
   Remove prompt files (`.codex-sessions/<task>*.prompt.txt`), keep the JSONL audit log, remove the worktree with `git worktree remove "$WT"`, and delete or merge the branch `codex/<task>`.

Beyond this manual flow, `codex-task run` provides automatic baseline content hashing, strict `--scope` path validation, forbidden file detection, verification that codex did not commit (moved HEAD), compact summary reporting, and token usage accounting in `.codex-sessions/usage.tsv`.
