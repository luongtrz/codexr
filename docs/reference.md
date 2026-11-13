# codexr: full reference

Overview and quick install: [README](../README.md).

codexr is the Codex CLI counterpart of [agyr](https://github.com/luongtrz/agyr): it rotates between several ChatGPT accounts for the official OpenAI `codex` CLI, shows the real quota of each account, and ships a headless runner with usage-limit failover plus a git-worktree task wrapper for AI orchestrators.

Works exclusively with the official `codex` binary by swapping authentication credentials back and forth between saved slots (`$CODEX_HOME/accounts/`). Linux and Windows (Git Bash) use the same file-based credential store (`$CODEX_HOME/auth.json`). Linux is the tested platform; the Windows layer has not been tried on a real Windows machine yet. No proxy is used, and it never reads or prints token contents.

> Disclaimer: Switching between multiple ChatGPT accounts may violate OpenAI's terms of service or acceptable use policies for certain plans. You are solely responsible for how you use this tool. Use your own accounts, use in moderation, and be aware that there is no guarantee against account restrictions or enforcement actions.

Provides three commands in `bin/`:

- `codexr`: manage slots, inspect quota, switch accounts. Starts interactive `codex` with the selected account.
- `codex-run`: run a headless `codex exec` task and automatically switch accounts on usage limit exhaustion, resuming the same conversation thread. Primarily called by an AI orchestrator via the `codex` skill; see [codex-run](#codex-run-for-ai-agents).
- `codex-task`: run an end-to-end implement task in a dedicated git worktree, check scope, and clean up; see [codex-task](#codex-task-for-ai-agents).

## Installation

If you are an AI agent asked to install this repository on a machine, read [AGENT.MCP.md](../AGENT.MCP.md) for step-by-step instructions and hard rules (never log in, never save/modify slots, never read token files).

Requires `bash`, `git`, and `jq`.
- **Linux:** `timeout` (coreutils) and `setsid` (util-linux) are used when available, though not strictly required.
- **Windows (Git Bash / MSYS):** `jq` (e.g. `winget install jqlang.jq`), `cygpath`, and `taskkill` (included with Git for Windows).

```bash
# Unified auto-detect installer (recommended):
bash install.sh

# Or invoke the specific platform installer directly:
bash platforms/linux/install.sh        # Linux: creates symlinks in ~/.local/bin
bash platforms/windows/install.sh      # Windows: creates Git Bash + .cmd wrappers in ~/.local/bin
```

The install scripts only create symlinks or wrappers; they never log in or read token files. After installation, `codexr help` should work and `bash test/run.sh` should pass without needing any login. For installing the `codex` skill and orchestrator rules, see [docs/agent-setup.md](agent-setup.md).

### Repository layout

- `bin/`: the three entry-point commands (`codexr`, `codex-run`, `codex-task`), free of platform-specific code.
- `lib/`: shared defaults (`defaults.sh`, defining default model `gpt-6-luna` and reasoning effort `max`).
- `install.sh`: unified root installer (auto-detects OS via `uname -s`).
- `platforms/linux/`: `platform.sh` (Linux invocation layer: `setsid`, detached execution) and `install.sh` (symlink installer).
- `platforms/windows/`: `platform.sh` (Git Bash invocation layer: path conversion with `cygpath -m`, process tree termination with `taskkill`, CRLF handling for `jq`) and `install.sh` (writes bash and `.cmd` batch wrappers).
- `skills/codex/`: the `codex` skill (`SKILL.md` and `references/`) for AI orchestrators (Claude Code, etc.).
- `templates/`: runtime templates used by `codex-task` (`hard-rules.txt`, `codex-task.conf.example`).
- `docs/`: design contract (`design.md`), technical reference (`reference.md`), and orchestrator setup guide (`agent-setup.md`).
- `test/`: modular test suite (`run.sh` runner, `core.sh` platform-independent suite, `linux.sh` Linux suite, `windows.sh` Windows suite, and fake helpers `fake-codex`, `fake-codex-run`).

## How it works & credential storage

`codexr` uses the same file-based credential backend on both Linux and Windows. Codex keeps its ChatGPT credentials in `$CODEX_HOME/auth.json` on both platforms, so credentials can be managed and swapped identically across operating systems.

### Credential storage and slots

- **Login store (`$CODEX_HOME/auth.json`):** `CODEX_HOME` defaults to `~/.codex` (resolving symlinks via `readlink -f`). The active login is stored in `$CODEX_HOME/auth.json` containing `auth_mode`, `OPENAI_API_KEY`, `tokens{id_token, access_token, refresh_token, account_id}`, and `last_refresh`. Only `auth_mode == "chatgpt"` logins are supported; API-key logins (`api_key` or `apikey`) are refused with a clear error.
- **Account slots (`$CODEX_HOME/accounts/<name>.json`):** Each saved account is an exact copy of `auth.json`. Slot metadata and state are stored in `$CODEX_HOME/accounts/state.json` (tracking `active`, `cooldown`, `quota`, and `ui_order`).
- **Forced file credentials store:** To stay immune to external credential store configurations (such as a user's `cli_auth_credentials_store` setting in `config.toml`), every `codex` invocation by `codexr`, `codex-run`, and `codex-task` explicitly passes `-c cli_auth_credentials_store="file"`.
- **Slot naming:** Slot names must match `^[A-Za-z0-9_-]+$` (ASCII letters, digits, `-`, and `_`). Spaces, dots, slashes, or special characters are forbidden.
- **File permissions:** On Linux, credentials and state are protected using `umask 077`, directory permissions `chmod 700`, and file permissions `chmod 600`. On Windows, files are protected by NTFS user profile permissions. Secret tokens are never printed or logged.

### Account identity and write-back

- **Account identity from `id_token` `sub` claim:** Codex rotates the `refresh_token` on every token refresh, so the refresh token is single-use and changes frequently. To reliably identify accounts across refreshes, `codexr` extracts the stable user ID from the `sub` claim decoded from the JWT payload in `tokens.id_token` (falling back to `tokens.account_id`). JWT payload decoding uses pure bash and `jq` (base64url decoding, no network calls). The identity string (prefixed with `sub:`) is compared internally and never displayed.
- **Single-use refresh token handling & write-back:** When `codex` runs, it refreshes tokens in place.
  - In `codexr use` and `codexr sync`, a private snapshot of the live login (`live_snapshot`) is taken. The refreshed credentials are written back to the slot whose account identity matches that snapshot. If the active login belongs to no saved slot, no slot is overwritten, and the login is backed up to `accounts/.last-token.bak`.
  - In `measure_one` (used by `codexr list` and `codexr test`), each probe runs inside an isolated temporary `CODEX_HOME`. If `codex` refreshed the login during the probe, the new token is saved back to the slot of the same identity. Furthermore, if the live login in use is still the exact copy that was probed, the refreshed token is written to the live `auth.json` as well, ensuring that a spent single-use refresh token is not left behind.

### Cross-platform locking & atomic writes

- **Cross-platform lock (`accounts/.swap.lock`):** Serializes all login swaps, slot writes, and `state.json` updates using exclusive atomic file creation (`set -o noclobber`) containing the process PID. If an old lock exists, `codexr` checks whether the owning process is still alive (`kill -0`) before safely removing a stale lock.
- **Atomic file writes:** Live tokens, slot files, backups, and `state.json` are written to temporary files in the same directory (`mktemp`), set to `chmod 600`, and atomically moved into place (`mv -f`).

## One-time setup

For each ChatGPT account, sign in with `codexr` and save the slot. This must be done interactively in a browser. Do not use codex's built-in logout command (which may revoke credentials at OpenAI); instead, use `codexr forget` to clear the local login while preserving saved slots:

```bash
codexr                            # sign in to account 1 in browser, then quit codex
codexr save acct1                 # save active login as slot acct1
codexr forget                     # clear active login locally
codexr                            # sign in to account 2 in browser, then quit codex
codexr save acct2
codexr forget
codexr                            # sign in to account 3 in browser, then quit codex
codexr save acct3
codexr use acct1                  # select active account
codexr list                       # verify all slots and inspect quota
```

- `codexr forget` removes `$CODEX_HOME/auth.json` locally and clears `state.json`'s active entry, while leaving saved slots untouched. Nothing is revoked upstream at OpenAI.
- `codexr forget` backs up the live login to `accounts/.last-token.bak`. If the active login has not yet been saved to a slot, `codexr forget` refuses (exit 1) to prevent accidental credential loss; pass `-f` or `--force` to discard it anyway.
- If you sign in manually without running `codexr save`, `codexr list` warns that the active login matches no slot, and `codexr use` will never overwrite any saved slot with it.

## Commands

```bash
codexr list [-c] [-w]           # measure real quota of all accounts and print table (* = selected account)
codexr list -c                  # print cached numbers without calling codex (fast)
codexr list -w                  # wide output; keep PLAN column even on narrow terminals
codexr use <name>               # switch to slot <name>
codexr rotate [<duration>]      # interactive codex ran out of quota: cool down active account + switch to next ready account
codexr cooldown <name> [<time>] # mark account on cooldown (omitted duration probes app-server for resetsAt; or e.g. 4h13m)
codexr clear <name>             # clear an account's cooldown
codexr next [-v]                # print ready account whose weekly limit resets soonest (exit 3 if all on cooldown); -v explains why
codexr active                   # print active account name (matched by identity)
codexr save <name>              # save current login ($CODEX_HOME/auth.json) as a slot
codexr rename <old> <new>       # rename slot (login, cooldown, and quota move with it; refuses if <new> exists)
codexr del <name>               # permanently delete slot <name> (alias: rm; removes slot file, state, and active login if matching)
codexr swapui <n1> <n2>         # swap UI display order of two accounts in codexr list without affecting codexr next rotation
codexr swapui --reset           # restore default weekly reset display order in codexr list
codexr test [-w] [name...]      # send "Hi" to accounts (1 real request each) to start 5-hour window (spends real quota)
codexr forget [-f]              # drop current local login to sign in to another account; refuses if unsaved (-f to force)
codexr run [codex args]         # start codex with selected account (defaults to model gpt-6-luna, reasoning effort max)
codexr [codex args]             # shorthand for `codexr run [codex args]` (bare `codexr` launches interactive codex)
codexr sync                     # internal: write live login back into its slot if refreshed
codexr help [command]           # overview, or detailed help for one command (`codexr <command> --help` also works)
```

## When interactive codex runs out of quota

When `codex` reports that a usage limit has been reached, exit `codex` (a running process retains credentials in memory) and run:

```bash
codexr rotate        # cool down current account (probes reset time or uses duration) + switch to next ready account
codexr               # reopen codex with the new account
```

- `codexr rotate [<duration>]` accepts a duration (e.g. `codexr rotate 4h13m`, `90` seconds, `1d2h`, or a string containing `Resets in ...`).
- When `<duration>` is omitted, `codexr rotate` probes the account's quota via the `app-server` to obtain the exact `resetsAt` timestamp (falling back to 5 hours if unparseable).
- If every account in the pool is on cooldown, it exits with code `3` without changing credentials and reports the earliest reset time on stderr.

## `codexr list`: inspecting quota

```
┌────────────────────┬──────────────┬─────────────────────────────┬─────────────────────────────┬───────────────────────────────────────────────┐
│ ACCOUNT            │ PLAN         │ CODEX 5H                    │ CODEX WEEK                  │ STATUS                                        │
├────────────────────┼──────────────┼─────────────────────────────┼─────────────────────────────┼───────────────────────────────────────────────┤
│ acct1              │ plus         │   1%  01/10/2026 04:02 PM   │  67%  07/10/2026 09:24 AM   │ low                                           │
│ acct2              │ plus         │   1%  01/10/2026 03:03 PM   │  75%  07/10/2026 11:46 AM   │ low                                           │
│ * work             │ pro          │  46%  01/10/2026 05:53 PM   │  74%  07/10/2026 02:02 PM   │ ready                                         │
│ acct3              │ plus         │ 100%  01/10/2026 07:14 PM   │ 100%  08/10/2026 02:02 PM   │ ready                                         │
└────────────────────┴──────────────┴─────────────────────────────┴─────────────────────────────┴───────────────────────────────────────────────┘
Measured at 01/10/2026 02:58 PM   (* = selected account)
```

`codexr list` probes the real quota of **every saved account in parallel** using the `codex app-server` JSON-RPC interface. It consumes **0 model tokens** and completes in a few seconds.

### The app-server probe
Each probe runs with a temporary `CODEX_HOME` holding a private copy of the slot's `auth.json`. The probe communicates with `codex -c cli_auth_credentials_store="file" app-server` over stdio:
1. Sends `initialize` notification.
2. Sends `initialized` notification.
3. Sends `account/rateLimits/read` request (`id: 2`).

The JSON-RPC response contains `.result.rateLimits`:
- `primary`: `{usedPercent, windowDurationMins: 300, resetsAt}` (the 5-hour limit).
- `secondary`: `{usedPercent, windowDurationMins: 10080, resetsAt}` (the weekly limit).
- `planType`: `"plus"`, `"pro"`, `"team"`, etc.
- `rateLimitReachedType`: `null` or a limit indicator.
- `ordinaryUsageAllowed`: `true` or `false`.

Probes are detached via `setsid -w` on Linux to avoid terminal contention. If `codex` refreshed credentials during the probe, the new tokens are written back to the slot and live login.

### Columns, colours, and ordering
- **Columns:**
  - `*`: marks the slot whose identity matches the live `auth.json`.
  - `ACCOUNT`: slot name.
  - `PLAN`: subscription plan (`plus`, `pro`, `team`, ...). Automatically hidden on narrow terminals to fit width, unless `-w` / `--wide` is specified.
  - `CODEX 5H`: percentage remaining (`100 - usedPercent`) and reset timestamp for the 5-hour window.
  - `CODEX WEEK`: percentage remaining and reset timestamp for the weekly window.
  - `STATUS`: status value and time left.
- **Colours:** remaining percentage is **green** above 40%, **yellow** from 11% to 40%, **red** at 10% or below. Status is green for `ready`; yellow for `not measured` and `stale, past reset time`; red for `low`, `weekly limit reached`, `cooldown`, and `measure failed`. Configured by `CODEXR_COLOR` (`auto`, `always`, `never`) and `NO_COLOR`.
- **Status values:**
  - `ready`: quota available (>10%).
  - `low`: 10% or less remaining in either window.
  - `weekly limit reached, <time> left`: weekly limit exhausted (`pw == 0` and `rw > now`).
  - `cooldown, <time> left`: account marked on cooldown.
  - `not measured`: no probe data yet.
  - `stale, past reset time`: cached probe data is past its reset timestamp (with `-c`).
  - `measure failed`: probe failed (auth error, timeout, or missing response; exit code 1).
- **Automatic cooldown sync:** an account whose usage limits are exhausted (`ordinaryUsageAllowed == false`, `rateLimitReachedType != null`, or 0% remaining) automatically receives a cooldown ending at the reset time of the exhausted window (the weekly reset if both are exhausted). When an account has quota remaining, any existing cooldown is automatically removed.
- **Row order:** accounts are ordered by weekly limit reset time (`rw`), soonest first. Accounts without data appear last; ties break by name. Custom order can be applied with `codexr swapui`.

## `codexr test`: sending "Hi" to each account

```
$ codexr test
Sending "Hi" to 3 account(s): one real request each, so it uses a little quota...
┌────────────────────┬────────────────────────────────────────────────┬──────────────┬─────────────────────────────────────┐
│ ACCOUNT            │ HI                                             │ CODEX 5H     │ RESETS                              │
├────────────────────┼────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────┤
│   acct3            │ ok in 4s: "Hello! How can I help"              │  16%>16%     │ 05/10/2026 04:49 PM                 │
│   work             │ ok in 3s: "Hello! How can I assist"            │ 100%>99%     │ 05/10/2026 07:31 PM (was 07:04 PM)  │
│   acct1            │ skipped (cooldown, 45m left)                   │ -            │ -                                   │
└────────────────────┴────────────────────────────────────────────────┴──────────────┴─────────────────────────────────────┘
Measured at 05/10/2026 02:19 PM   (CODEX 5H = before>after; RESETS = end of the account's current 5-hour window; "(was ...)" = it moved because of the Hi)
```

`codexr test` sends one real request (`"Hi"`) to each account to start its 5-hour limit window:
- **Spends real quota:** sends one `codex exec "Hi"` call per account using default model `gpt-6-luna` with reasoning effort `low` (`CODEXR_TEST_EFFORT`), in an empty temporary directory with a read-only sandbox.
- **Purpose:** tests account responsiveness and starts the 5-hour countdown window across accounts. The `RESETS` column shows the post-call reset time, and displays `(was hh:mm AM/PM)` when the call shifted the reset window forward.
- **Parallel execution:** all accounts are tested concurrently in temporary directories without modifying the active login. Any tokens refreshed during testing are saved back to their respective slots.
- **Options & arguments:**
  - Without arguments, accounts currently on cooldown are skipped. Named accounts (`codexr test acct1 work`) are always tested.
  - `-w`, `--wide`: disables responsive table formatting to print full column widths.
- **Environment:** `CODEXR_TEST_TIMEOUT` (seconds per account, default 120), `CODEXR_TEST_EFFORT` (reasoning effort, default `low`).
- **Exit codes:** `0` if all tested accounts answered successfully, `1` if any account failed.

## Deleting an account slot (`codexr del`, alias `rm`)

```bash
codexr del <name>        # permanently delete a saved slot (alias: codexr rm <name>)
```

Permanently removes:
- The saved slot credential file (`$CODEX_HOME/accounts/<name>.json`).
- Cooldown, quota, and UI display order records for `<name>` in `accounts/state.json`.
- The live login (`$CODEX_HOME/auth.json`) and `accounts/.last-token.bak` if the active account matches `<name>`, clearing `state.json`'s active entry.

Refuses (exit 1) if `<name>` is invalid or the slot does not exist.

## Customizing display order (`codexr swapui`)

```bash
codexr swapui <name1> <name2>    # swap UI display positions of two accounts in codexr list
codexr swapui --reset            # restore default weekly reset display order in codexr list
```

Customizes the row order in `codexr list` without affecting account rotation (`codexr next`). Account rotation strictly follows weekly reset time regardless of UI ordering.

## Time zone

All displayed timestamps default to **UTC+7** in `dd/mm/yyyy hh:mm AM|PM` format (e.g. `01/10/2026 07:14 PM`), regardless of the host machine's locale or system timezone. Override with `CODEXR_TZ` (e.g. `CODEXR_TZ=UTC`; in POSIX TZ syntax `UTC-7` represents UTC+7, which is the default). `LC_TIME=C` is exported so AM/PM formatting remains consistent.

## `codex-run` (for AI agents)

`codex-run` executes a headless `codex exec` task. It continuously monitors the output stream; when an account hits usage limits, it stops `codex` immediately, sets a cooldown on the exhausted account, switches to the next ready account with `codexr next`, and resumes the same conversation thread via `codex exec resume <thread_id>`.

```bash
codex-run --prompt FILE --add-dir DIR --log FILE.jsonl [--model M] [--effort E] [--sandbox MODE] [--yolo] [--conversation ID]
```

### Options
- `--prompt FILE`: path to the prompt file. Prompt content is fed to `codex` via stdin (`-`), eliminating command-line length limitations and path mangling issues.
- `--add-dir DIR`: workspace directory `codex` works in (passed as `-C DIR`).
- `--log FILE`: path to the JSONL log file (audit trail).
- `--model M`: model override (defaults to `gpt-6-luna` or `CODEXR_MODEL`).
- `--effort E`: reasoning effort level override (defaults to `max` or `CODEXR_EFFORT`).
- `--sandbox MODE`: sandbox mode: `read-only` or `workspace-write` (default `workspace-write`, override via `CODEX_RUN_SANDBOX`). Network access remains off inside the sandbox.
- `--yolo`: bypass approvals and sandbox (`--dangerously-bypass-approvals-and-sandbox`).
- `--conversation ID`: resume an existing conversation thread ID instead of starting fresh.

### Account failover and resume
- **Usage-limit detection:** while `codex` runs, `codex-run` polls the log every `CODEX_RUN_POLL` seconds (default 1). If an `error` or `turn.failed` event contains `usage limit` or `codex_error_info: "usage_limit_exceeded"`, `codex-run` initiates failover.
- **Failover process:**
  1. Stops `codex` immediately (`platform_kill_tree` on Windows; process group SIGTERM/SIGKILL on Linux).
  2. Calls `codexr sync` to save any refreshed credentials.
  3. Parses any reported reset date (e.g. `"try again at Aug 8th, 2026 5:30 PM"`) and sets cooldown on the account (`codexr cooldown <current>`).
  4. Queries `codexr next -v` for the next ready account (selecting the one whose weekly limit resets soonest).
  5. Switches credentials using `codexr use <next>`.
  6. Resumes the conversation thread: `codex exec resume <thread_id>` with a continuation notice (`"Continue the task from where you stopped..."`). Because `codex exec resume` lacks `-C` and `--sandbox` flags, `codex-run` changes working directory to `--add-dir` and passes `-c sandbox_mode="..."`.
- **Exit codes:**
  - `0`: task completed successfully.
  - `1`: other `codex` failure.
  - `2`: bad arguments.
  - `4`: authentication or login error (user must log in again).
  - `5`: entire account pool is out of quota (all accounts on cooldown).
  - `6`: exceeded `CODEX_RUN_MAX_SWITCH` (default 10) switches.

### Parallel runs and slot safety
Multiple `codex-run` processes can run concurrently:
- **Exclusive locking (`accounts/.swap.lock`):** serializes all credential switches and slot writes.
- **Atomic private snapshots:** `codexr use`, `sync`, and `forget` take a private snapshot of credentials before reading or writing, preventing race conditions where one account's credentials overwrite another slot.
- **Identity-checked write-back:** refreshed tokens are only saved back to the slot that matches the identity claim in the `id_token`.
- **Remaining limitation:** parallel processes share the single live `$CODEX_HOME/auth.json`. If process B switches accounts between process A's `codexr use` and `codex` reading `auth.json`, an unexpected cooldown could be attributed to the wrong account name until the next `codexr list` reconciles state.

## `codex-task` (for AI agents)

`codex-task` is a deterministic wrapper that executes a **single delegated implement task end to end** without any LLM in the wrapper: it creates an isolated git worktree, runs setup commands, invokes `codex-run`, verifies scope and forbidden files, and writes a compact summary. It runs no tests itself; the reviewing agent verifies the diff and runs targeted tests afterwards. For read-only exploration, call `codex-run` directly against the workspace.

### Typical workflow

1. Write the task specification to `<repo>/.codex-sessions/<task>.task.txt` (task description, plan, acceptance criteria).
2. Run `codex-task run --name <task> --task <repo>/.codex-sessions/<task>.task.txt --scope 'paths' --model gpt-6-luna --effort max` in the background.
3. Read `.codex-sessions/<task>.summary.txt` and inspect `git diff` in `.worktrees/codex-<task>`.
4. For a correction round: write a follow-up task file and run `codex-task run --name <task> --resume --task fix.txt --scope 'paths' --model gpt-6-luna --effort max` (resumes the same conversation thread from `.codex-sessions/<task>.jsonl` and implies `--reuse-worktree --no-setup`).
5. Reviewer verifies code and runs tests.
6. Clean up with `codex-task rm <task> -f`.

### Configuration file

`codex-task` sources `<repo>/.codex-sessions/codex-task.conf` (or `$CODEX_TASK_CONF`) as a bash script defining:
- `SETUP_CMDS`: array of bash commands executed in order inside the worktree before `codex` starts.
- `COPY_FILES`: array of repo-relative file/directory paths copied from the main checkout into the worktree after `SETUP_CMDS`.

See [templates/codex-task.conf.example](../templates/codex-task.conf.example).

### `run` options

| Option | Meaning |
|---|---|
| `--name NAME` | Task name (`[a-z0-9-]+`, required). Creates worktree `<repo>/.worktrees/codex-NAME`, branch `codex/NAME`, and session files `<repo>/.codex-sessions/NAME.*`. |
| `--task FILE` | File containing only the task body of the prompt (required). |
| `--repo DIR` | Main checkout (default: current directory; resolves linked worktrees back to the main checkout). |
| `--base REF` | Commit-ish for the new branch (default: `HEAD` of the invoking directory). |
| `--scope PATHSPEC` | Repeatable pathspec of files allowed to be modified (relative to worktree root). |
| `--allow-path PATH` | Repeatable override allowing a normally forbidden path to be modified. |
| `--no-setup` | Skip `SETUP_CMDS` and `COPY_FILES`. |
| `--reuse-worktree` | Reuse an existing worktree instead of failing. |
| `--resume` | Resume the previous `codex` conversation thread from `.codex-sessions/NAME.jsonl` (implies `--reuse-worktree --no-setup`). |
| `--model M` | Model ID passed through to `codex-run`. |
| `--effort E` | Reasoning effort level passed through to `codex-run`. |

### `rm` subcommand

```bash
codex-task rm NAME [-f] [--repo DIR]
```

Removes worktree `<repo>/.worktrees/codex-NAME`, branch `codex/NAME`, and `.codex-sessions/NAME.prompt.txt`, while keeping audit logs (`NAME.jsonl`, `NAME.summary.txt`, `NAME.setup.log`, and `usage.tsv`). Without `-f` / `--force`, refuses (exit 2) if the worktree has uncommitted/untracked changes or if `codex/NAME` has commits not reachable from the main checkout's `HEAD`.

### Exit codes

- `0`: Success (`run`: `codex-run` succeeded and no scope violation; `rm`: removed).
- `1, 4, 5, 6`: Propagated from `codex-run`.
- `2`: Invalid arguments, config error, worktree conflict, resume error, or `rm` refused.
- `7`: Setup commands failed (`RESULT=SETUP_FAILED`).
- `8`: Scope or forbidden-path violation (`RESULT=SCOPE_VIOLATION`).

### Summary file layout

Written to `.codex-sessions/NAME.summary.txt` and printed to stdout:
- First line: `RESULT=OK`, `RESULT=SCOPE_VIOLATION`, `RESULT=SETUP_FAILED`, or `RESULT=CODEX_FAILED`.
- Environment metadata: `worktree`, `branch`, `base`.
- `codex`: status (`OK` or `ERROR`), turns, tokens (cached count), elapsed seconds.
- `changed files`: `git diff --stat` and untracked files (`??`).
- `scope`: `scope: OK` or list of violation lines.
- `codex report`: up to 25 lines of the last agent message.
- `logs`: paths to `.jsonl` and `.setup.log`.

### Scope and forbidden-path checks

- **Forbidden files by default:** `.env*`, lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`), and agent instruction files (`CLAUDE*.md`, `AGENTS.md`, `CODEX*.md`). Override per path using `--allow-path`.
- **Scope check:** when `--scope` is given, any modified or untracked file outside the specified pathspecs triggers a violation.
- **HEAD movement check:** `codex` is forbidden from committing. If `START_HEAD != NOW_HEAD`, `codex-task` flags a scope violation.

### Usage log (`usage.tsv`)

Every `codex-task run` that completes summary output appends a tab-separated row to `<repo>/.codex-sessions/usage.tsv` with columns:
`timestamp`, `name`, `result`, `codex_status`, `turns`, `tokens`, `codex_seconds`, `exit_code`.

### Known limitations of `codex-task`

- The worktree branches from `--base` and does not inherit uncommitted changes from the main checkout.
- Scope and forbidden-path checks only inspect files reported by `git status` or `git diff` (gitignored files are not checked).

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CODEX_HOME` | `~/.codex` | Codex home and credential directory |
| `CODEXR_BIN` | `codex` | Codex CLI binary name or path |
| `CODEXR_MODEL` | `gpt-6-luna` | Default model for `codexr` and `codex-run` |
| `CODEXR_EFFORT` | `max` | Default reasoning effort for `codexr` and `codex-run` |
| `CODEXR_TZ` | `UTC-7` (UTC+7) | Time zone for displayed timestamps |
| `CODEXR_NOW` | current epoch | Test hook: override current epoch timestamp |
| `CODEXR_COLOR` | `auto` | Table colour output: `auto`, `always`, or `never` |
| `CODEXR_TEST_TIMEOUT` | `120` | Per-account timeout in seconds for `codexr test` |
| `CODEXR_TEST_EFFORT` | `low` | Reasoning effort level for `codexr test` |
| `CODEXR_PROBE_TIMEOUT` | `30` | Timeout in seconds for app-server quota probe |
| `CODEX_RUN_MAX_SWITCH` | `10` | Maximum account switches per `codex-run` task |
| `CODEX_RUN_POLL` | `1` | Polling interval in seconds for `codex-run` |
| `CODEX_RUN_SANDBOX` | `workspace-write` | Default sandbox mode (`read-only` or `workspace-write`) |
| `CODEX_TASK_CONF` | `<repo>/.codex-sessions/codex-task.conf` | Path override for task configuration file |

## Skill `codex` and orchestrator setup

`skills/codex/` contains the `codex` skill (`SKILL.md` and `references/`), and [docs/agent-setup.md](agent-setup.md) contains the recommended orchestrator configuration and role-split rules.

The `HARD RULES` template for implement tasks is in `templates/hard-rules.txt` (automatically appended by `codex-task`), and configuration examples live in `templates/codex-task.conf.example`.

## Tests

```bash
bash test/run.sh              # all suites (core + linux + windows)
bash test/run.sh core         # platform-independent core suite
bash test/run.sh linux        # Linux suite
bash test/run.sh windows      # Windows suite
```

The test suites run against mock environments using fake tokens and fake binaries (`test/fake-codex`, `test/fake-codex-run`) without touching real credentials or connecting to external networks.

## Known limitations

- Running interactive `codex` processes retain credentials in memory; restart `codex` after switching accounts with `codexr use`.
- `codex-run` stops `codex` and resumes conversation threads using `codex exec resume` rather than hot-swapping credentials in-flight.
- Parallel `codex-run` processes share the live credential pool on a best-effort basis.
