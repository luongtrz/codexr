# codexr: design contract

codexr is the Codex CLI counterpart of [agyr](https://github.com/luongtrz/agyr): it rotates between several ChatGPT accounts for the official `codex` binary, shows the real quota of each account, and ships a headless runner with usage-limit failover plus a git-worktree task wrapper for AI orchestrators.

The three commands keep agyr's names, layout and exit codes so the two tools feel the same:

| agyr | codexr | role |
|---|---|---|
| `agyr` | `codexr` | account slots, quota table, switching; a bare `codexr` starts `codex` with the selected account |
| `agy-run` | `codex-run` | headless `codex exec` with automatic account failover and conversation resume |
| `agy-task` | `codex-task` | one delegated task in a dedicated git worktree, scope check, compact summary |

This file is the shared contract: every area of the code follows the decisions below.

## 1. Binary, model, effort

- Binary: `codex` (override `CODEXR_BIN`). Tested against codex-cli 0.167.x.
- Default model **`gpt-6-luna`** with reasoning effort **`max`**. The values live in `lib/defaults.sh` (`CODEXR_DEFAULT_MODEL`, `CODEXR_DEFAULT_EFFORT`, overridable with `CODEXR_MODEL` / `CODEXR_EFFORT`) and are sourced by all three commands; never hard-code the literals elsewhere.
- Every codex call passes `-m <model> -c model_reasoning_effort="<effort>"` explicitly, so the user's `~/.codex/config.toml` default never leaks in. `--model` / `--effort` flags override per call.

## 2. Login store (one backend, all platforms)

- `CODEX_HOME` (the variable codex itself honours; default `~/.codex`, may be a symlink, resolve with `readlink -f`).
- Live login: `$CODEX_HOME/auth.json` with `auth_mode`, `OPENAI_API_KEY`, `tokens{id_token,access_token,refresh_token,account_id}`, `last_refresh`. Only `auth_mode == "chatgpt"` logins are accepted; an API-key login is refused with a clear message.
- Slots: `$CODEX_HOME/accounts/<name>.json` (a copy of auth.json), plus `state.json` (`active`, `cooldown`, `quota`, `ui_order` as in agyr) and `.swap.lock`. Same lock, atomic-write, `umask 077` / `chmod 600` rules as agyr. Slot names: `[A-Za-z0-9_-]+`.
- Same file backend on Linux and Windows (Codex keeps the ChatGPT login in auth.json on both). agyr's `wincred` backend, `CODEXR_BACKEND`, `platforms/windows/cred.*` and the D-Bus keyring bypass are removed. To stay immune to a user's `cli_auth_credentials_store = "keyring"` setting, every codex process started by codexr / codex-run / codex-task gets `-c cli_auth_credentials_store="file"`.
- Never print token contents (not even claims). Tests use fake tokens only.

## 3. Account identity

Codex rotates the `refresh_token` on every refresh, so agyr's "same refresh_token" identity does not work. Identity is the stable user id decoded from the `id_token` JWT payload (`sub`, falling back to `tokens.account_id`), compared as a string and never printed. JWT decoding is pure bash/jq (base64url, no network).

Codex refreshes tokens in place, so after anything that may run codex (`codex-run` attempt, `codexr list` probe, `codexr use`), the live (or temp-home) `auth.json` is written back into the slot of the same identity only (identity-checked write-back, as agyr does).

## 4. Quota (0 tokens)

Probe = the codex app-server JSON-RPC over stdio, run with a temporary `CODEX_HOME` that holds a copy of the slot's auth.json (so it never touches the live login):

```
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codexr","title":"codexr","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}' ; sleep N \
 | CODEX_HOME=$tmp codex app-server        # one JSON object per line on stdout
```

Take the line with `"id":2`. Shape (verified on codex-cli 0.167.2):

```
.result.rateLimits.primary   = {usedPercent, windowDurationMins:300,   resetsAt:<epoch>}   # the 5-hour window
.result.rateLimits.secondary = {usedPercent, windowDurationMins:10080, resetsAt:<epoch>}   # the weekly window
.result.rateLimits.planType  = "plus" | "pro" | "team" | ...
.result.rateLimits.rateLimitReachedType = null | "rate_limit_reached" | ...
.result.ordinaryUsageAllowed = true | false
```

Close stdin after the reply (or kill the process group), use a timeout, ignore the other notification lines. An auth failure (expired / revoked login) shows up as an error object or no `id:2` reply: report `measure failed`.

- agyr shows *remaining* percent: remaining = 100 - usedPercent. Columns: `ACCOUNT  PLAN  CODEX 5H  CODEX WEEK  STATUS` (reset time next to each percentage). No `--claude` columns: Codex has one shared quota across models.
- An account is exhausted when `ordinaryUsageAllowed` is false, `rateLimitReachedType` is non-null, or a window has remaining 0. Cooldown ends at the `resetsAt` of the exhausted window (the weekly one if both are exhausted, since that is the later one).
- `codexr cooldown NAME` without a duration probes that account and sets the cooldown from `resetsAt` (fallback `DEFAULT_COOLDOWN`, 5h); with a duration (`4h13m`) it behaves as in agyr.

## 5. Headless runs (`codex-run`)

- `codex exec --json -m <model> -c model_reasoning_effort=... -c cli_auth_credentials_store="file"`; the workspace root is passed with `-C DIR` (`codex-run` keeps agy-run's `--add-dir DIR` flag name for the workspace). The prompt is the content of `--prompt FILE`.
- Sandbox: `workspace-write` by default (`--sandbox read-only|workspace-write` flag, `CODEX_RUN_SANDBOX` env); `--yolo` selects `--dangerously-bypass-approvals-and-sandbox`. Network stays off in the sandbox. `codex exec resume` has no `-C` / `-s` flags: resume attempts `cd` into the workspace and pass `-c sandbox_mode="..."`.
- Event stream (JSONL on stdout): `thread.started` (`thread_id` = the conversation id), `turn.started`, `item.completed` (`item.type == "agent_message"`, `.item.text`), `turn.completed` (`.usage.{input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens}`), failures as `error` / `turn.failed` events whose message matches `usage limit` (case-insensitive), e.g. `You've hit your usage limit. ... try again at Aug 8th, 2026 5:30 PM.` (the rollout logs also carry `codex_error_info":"usage_limit_exceeded"`).
- On a usage-limit failure: stop codex at once (kill the process group), `codexr cooldown <current>` (auto, see section 4), `codexr next`, `codexr use`, and resume the same thread with `codex exec resume <thread_id> ...`. Exit codes as in agy-run: `0` done, `1` other codex failure, `2` bad arguments, `4` login error or no active account, `5` whole pool out of quota, `6` more than `CODEX_RUN_MAX_SWITCH` (default 10) switches.

## 6. Task wrapper (`codex-task`)

Same behaviour as agy-task with the renames: sessions in `<repo>/.codex-sessions/`, worktree `<repo>/.worktrees/codex-NAME`, branch `codex/NAME`, config `.codex-sessions/codex-task.conf` (`CODEX_TASK_CONF`), usage log `usage.tsv`. It still runs no tests and checks scope, forbidden files and HEAD movement. `--model` / `--effort` are passed through to `codex-run`. The summary reads the codex JSONL: `codex:` line with status, turns, tokens, seconds; `codex report:` = the last `agent_message` text (up to 25 lines).

## 7. Environment variables

`CODEX_HOME`, `CODEXR_BIN`, `CODEXR_MODEL`, `CODEXR_EFFORT`, `CODEXR_TZ` (default `UTC-7`, i.e. UTC+7), `CODEXR_NOW` (tests), `CODEXR_COLOR`, `CODEXR_TEST_TIMEOUT`, `CODEX_RUN_MAX_SWITCH`, `CODEX_RUN_POLL`, `CODEX_RUN_SANDBOX`, `CODEX_TASK_CONF`. The agyr names `AGY_*` / `AGYR_*` disappear.

## 8. Platform layer

`platforms/<os>/platform.sh` keeps agyr's function and array names (`platform_init`, `platform_arg_path`, `platform_kill_tree`, `PLATFORM_DETACH`, `PLATFORM_DETACH_WAIT`) so the three commands source it unchanged; keyring-bypass and `NOCONV` arrays that no longer apply are removed together with their users. Windows (Git Bash) only adds path conversion, `taskkill` tree kill and the `.cmd` wrappers.
