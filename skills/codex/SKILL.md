---
name: codex
description: Delegate a well-scoped coding or read-only investigation task to the local `codex` CLI (a separate agent) to save orchestrator tokens. Implement tasks go through `codex-task run` (worktree, setup, scope check, compact summary; it runs no tests); read-only exploration through `codex-run`. Use only for self-contained tasks with a mechanical way to verify the result; never for architecture decisions or ambiguous requirements. codex runs in a sandbox, so implement tasks run only in a dedicated git worktree and every prompt carries the HARD RULES block (codex-task adds it).
---

# Delegate work to codex

`codex` is a separate coding-agent CLI (`codex`). Launch it only through `codex-task` (implement) or `codex-run` (read-only). Paths like `references/…` are relative to this skill's base directory; **read a reference file only when its situation comes up** — they are kept out of this file on purpose to save context.

## Invariants

1. **Model & reasoning effort:** default model `gpt-6-luna` with reasoning effort `max`. Always passed explicitly by `codex-run` (via `lib/defaults.sh`, passing `-m gpt-6-luna -c model_reasoning_effort="max"` on every call so `~/.codex/config.toml` never leaks in). Use `--model` / `--effort` flags or `CODEXR_MODEL` / `CODEXR_EFFORT` environment variables only when the user explicitly asks. Other models in the catalog (`gpt-6.1-sol`, `gpt-6-astra`, `gpt-6.1-terra`, `gpt-6-sol`, `gpt-5.6-*`) are used **only when the user asks**. For transient errors or server outages, see `references/503-fallback.md`.
2. **Never a bare `codex exec` or `codex` for delegated work.** The pool login is handled by `codexr` and `codex-run`, which force `cli_auth_credentials_store="file"` and rotate accounts on a usage-limit error. The user starts interactive codex with plain `codexr`.
3. **Never trust codex's exit code or report.** `codex-task` only checks scope and forbidden files, and runs no tests; you read the diff and run tests yourself. Always check that the worktree diff is non-empty. Note: if an earlier turn hit a usage limit or transient failure, verify the worktree diff against the acceptance criteria before trusting it.
4. **Implement tasks only via `codex-task`** (it creates the worktree; never ask codex to create worktrees). Explore / bug-finding tasks target the repo read-only via `codex-run --sandbox read-only --add-dir "$REPO"` (always pass `--add-dir`: sets workspace root `-C DIR`).
5. **One small task per session**, exact files/lines in the task file (quota burns with context size; `references/logs-and-costs.md`). At most **20 runs in parallel** (`references/parallel.md`). Check `pgrep -fc 'codex-(task run --name|run --prompt)'` before launching more. **Launch each `codex-task` or `codex-run` as its own separate background tool call** — never bundle multiple tasks into one shell loop, wrapper script (`launch.sh`), or `for pid in ...; wait` command (bundling hides per-task status and delays completion notifications until the slowest task finishes).
6. **Task files and logs live in `<repo>/.codex-sessions/`** (gitignored), never `/tmp` or an arbitrary scratch directory. Keep the logs, delete prompt files when done. Never read the `.jsonl` unless debugging: the summary is the report.
7. **Report reset times to the user in UTC+7** (`codexr` prints them so). Never read `auth.json` or slot files (`accounts/*.json`) directly (only `codexr` and `stat` touch them; never inspect token contents).
8. **codex never runs tests.** No prompt may ask codex to run tests, builds, type-checks or linters, not even "one test file": the HARD RULES blocks and the `codex-task` prompt tail forbid it, so the task file must not contradict that (write acceptance criteria as observable code behavior, never "make tests pass"). `codex-task` has no verify step either: the orchestrator is the only one who runs tests, after codex has answered and the diff is read, one targeted command at a time.

## When to use / not

- **Use** when the task is small and self-contained enough for one prompt with no back-and-forth, and either mechanically verifiable (build/lint/test, diff mirrors an existing pattern) or a read-only investigation whose findings you can sanity-check; or when you want a real separate-process perspective.
- **Don't** for architecture/design decisions, security-sensitive code or nuanced judgment calls; anything you can't fully specify in one prompt (codex has zero context from this conversation); big multi-bug batches (split them); or when writing the task file takes the same research as doing it (then just do it). If you already found the exact line(s), edit directly.

## Workflow: implement task (`codex-task`)

1. **Plan, don't over-specify:** goal, root cause / suspected area, relevant files, the pattern to mirror, acceptance criteria. Don't pre-trace every line or paste full code — review traces the code afterwards.
2. **Write ONLY the task part** to `<repo>/.codex-sessions/<task>.task.txt`: Repo/stack, Task, Plan, Acceptance criteria, an ENVIRONMENT NOTE ("the env is prepared; on an env failure STOP: no package installs, no symlinks, no copying from outside"). Do not write the working directory, scope, or HARD RULES: `codex-task` adds them. Never tell codex to run or "make pass" any test/build/lint (invariant 8).
3. **Run in the background** (**one separate tool call per task** — never a batch script or `wait` loop) and wait for each completion notification — don't poll:
   ```bash
   codex-task run --name <task> --task <repo>/.codex-sessions/<task>.task.txt \
     --scope '<pathspec>' [--scope …] [--base <ref>] [--model <model>] [--effort <effort>]
   ```
   `--name`: task name (`[a-z0-9-]+`). Creates worktree `<repo>/.worktrees/codex-<task>`, branch `codex/<task>`, and session files `<repo>/.codex-sessions/<task>.*`.
   `--base`: commit-ish the worktree branches from (default: `HEAD` of the current directory/worktree). When running from a linked worktree whose branch differs from the main checkout, pass `--base <branch|sha>` explicitly.
   `--scope`: pathspec codex may change (repeatable; relative to worktree root). Any modification outside scope or moved HEAD is flagged as a scope violation.
   Setup and file copies come from `<repo>/.codex-sessions/codex-task.conf` (`SETUP_CMDS` and `COPY_FILES`). `codex-task` runs NO tests: you run them afterwards (step 5). stdout = a compact summary, also saved as `.codex-sessions/<task>.summary.txt`; progress goes to stderr.
4. **Read the exit code and the summary:**

   | exit | Meaning | Do |
   |---|---|---|
   | 0 | codex finished and scope is ok (`RESULT=OK`); NOTHING was tested | check `changed files` is non-empty. Note: if an error occurred or an account rotated, review the diff and run tests yourself before trusting it |
   | 8 | `RESULT=SCOPE_VIOLATION` | read the violation lines; send codex a corrected follow-up (see "Correction round" below), don't hand-fix |
   | 7 | setup failed (`RESULT=SETUP_FAILED`, worktree kept) | fix the environment, rerun with `--reuse-worktree` (setup reruns) |
   | 2 | bad arguments, config error, rm refused, or resume error | fix the command |
   | 4 | login error / no active account | **STOP**, tell the user; `references/quota-auth.md` |
   | 5 | whole pool on cooldown | **STOP**, tell the user the earliest reset (in UTC+7); `references/quota-auth.md` |
   | 1, 6 | other codex failure (1) / too many account switches (6) | check `changed files:` and `codex report:` in the summary — if edits are complete, check scope/diff and run tests; otherwise inspect log for errors; see `references/quota-auth.md` and `references/503-fallback.md` |

   **A usage-limit error on one account is NOT a stop, and the user does not switch accounts for it.** `codex-run` (and `codex-task`, which calls it) stops codex immediately, puts that account on cooldown, switches to the next ready account via `codexr` and resumes the same conversation thread automatically. Do not tell the user "out of quota, switch accounts" for a usage limit and do not wait for them. Stop only on exit 4 (login) or exit 5 (every account on cooldown: tell the user the earliest reset in UTC+7). Never retry in a loop or fall back to doing the task yourself on 4/5.

   **Correction round** (review or your tests found a problem in what codex wrote): continue the SAME codex conversation thread, since codex remembers what it did. Write a short new task file (what is wrong, file/line, what it should do; the code already in the worktree is codex's earlier work, fix it, don't redo it) and run:
   ```bash
   codex-task run --name <task> --resume --task <new-task-file> --scope '<pathspec>' [--model M] [--effort E]
   ```
   `--resume` takes the thread ID from the last `thread.started` event of `.codex-sessions/<task>.jsonl` and implies `--reuse-worktree --no-setup`; it exits 2 if there is no log or thread ID. Use `--reuse-worktree --no-setup` WITHOUT `--resume` (fresh conversation) only when the old conversation went off-track or has grown huge (quota burns with context size). Same rules as any run: codex runs no tests, you review the diff and test again afterwards.

   **Round limit:** at most 2 `--resume` rounds per task. Before declaring a run stuck, check `grep -c '^{' .codex-sessions/<task>.jsonl` and `tail -1` to verify if events are still growing. If the task still is not right after 2 rounds, or event count has stopped growing for ~10 min, stop it: kill the `codex-task`, `codex-run` and child `codex` processes. Commit the reviewed good part on `codex/<task>` (the worktree branch, not the target branch) so nothing is lost, then start a fresh conversation on the same worktree with a narrow task file: `codex-task run --name <task> --reuse-worktree --no-setup --task <narrow-task-file> --scope '<pathspec>'`.
5. **Review** (tiered): mechanical change → summary + skim the diff + one targeted check; risky (auth, payment, migrations, concurrency) → read the full `git -C <repo>/.worktrees/codex-<task> diff` and run the key checks yourself. Nothing has been tested before this point (neither codex nor `codex-task` runs tests), so this is the only test run: targeted, run in the worktree, one command at a time.
6. **Integrate and clean up:** stage only in-scope files explicitly (never `git add -A`), commit on the worktree branch `codex/<task>` (only when the user asks), cherry-pick/ff to the target branch, then `codex-task rm <task> -f` (without `-f` it refuses after a cherry-pick: the commits are not reachable from HEAD). It keeps the logs/summary and appends nothing else; `.codex-sessions/usage.tsv` accumulates tokens and seconds per task.

If `codex-task` is unavailable or too rigid: `references/manual-worktree.md`.

## Workflow: explore / bug-finding task (read-only, `codex-run`)

Write the task part to `.codex-sessions/<task>.task.txt` (say which verify commands were already run and point at exact files), append the read-only HARD RULES, run, then confirm the repo is untouched:
```bash
{ cat "$REPO/.codex-sessions/<task>.task.txt"; echo; \
  sed "s#<ABS_PATH>#$REPO#g" "$SKILL_DIR/references/hard-rules-explore.txt"; } > "$REPO/.codex-sessions/<task>.txt"
codex-run --prompt "$REPO/.codex-sessions/<task>.txt" --add-dir "$REPO" --log "$REPO/.codex-sessions/<task>.jsonl" --sandbox read-only   # background
grep '^{' "$REPO/.codex-sessions/<task>.jsonl" | jq -c 'select((.type // .event) == "turn.completed") | {usage}'
git -C "$REPO" status --short                                        # must still be clean
```
`codex-run` exit codes are the same as above (0 ok, 1, 2, 4, 5, 6). Check findings against the code before reporting them; delete the prompt files afterwards.

## References (read on demand)

- `references/quota-auth.md` — exit 4/5/6, usage limits, account pool (`codexr`), credentials store, reset times, auto-continue after re-login
- `references/503-fallback.md` — transient server errors, retry rules, and stuck sessions
- `references/parallel.md` — running several tasks at once (max 20), integration, queueing tasks
- `references/logs-and-costs.md` — codex exec --json events, jq commands, why quota burns with context, smoke test
- `references/manual-worktree.md` — the manual implement workflow `codex-task` automates
- `references/hard-rules-explore.txt` — HARD RULES block for read-only tasks (`<ABS_PATH>` placeholder); the implement block is `templates/hard-rules.txt`
