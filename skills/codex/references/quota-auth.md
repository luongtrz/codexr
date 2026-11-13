# Quota, login and the account pool (codex-run exit 4 / 5 / 6, usage limits, auth errors)

Read this when `codex-run` or `codex-task` exits 4, 5, or 6, when a log indicates an authentication or usage-limit error, or when the user asks about accounts or quota.

Codex uses ChatGPT consumer accounts (`auth_mode == "chatgpt"`). The user maintains multiple account slots in a rotation pool. Logins are performed interactively by the user.

## STOP rule

If a run fails with an authentication error, or `codex-run` exits **4** (login error / no active account) or **5** (whole pool on cooldown): **STOP immediately and tell the user.** Do not retry in an automated loop and do not silently execute the task yourself.
- **Exit 4:** tell the user that a login is required (login is performed interactively with `codex` / `codexr`) and wait.
- **Exit 5:** tell the user the earliest reset time from the `codex-run` message, **in UTC+7**.
- **Exit 6:** `codex-run` switched accounts too many times (exceeded `CODEX_RUN_MAX_SWITCH`, default 10); inspect `codexr list` and the session log before relaunching.
- Resume the task automatically once the re-login is detected (see "Auto-continue" below); the user does not need to type "continue".

## Usage limits vs. STOP

When an account hits a usage limit during a run, OpenAI returns a message such as:
- `You've hit your usage limit. ... try again at Aug 8th, 2026 5:30 PM.`
- `{"codex_error_info":"usage_limit_exceeded"}`
- An `error` or `turn.failed` event matching `usage limit` (case-insensitive).

**A usage-limit error on an account is NOT a stop.**
`codex-run` stops codex immediately, sets a cooldown on that account until its reset time, switches to the next ready account via `codexr next` / `codexr use`, and resumes the same conversation thread via `codex exec resume <thread_id>`.
Do not prompt the user or pause when this happens. A stop is only required on **exit 4** (login failure) or **exit 5** (all accounts in the pool are on cooldown).

Auth error strings that indicate exit 4:
- `refresh token`, `sign in again`, `log out and sign in`, `not logged in`, `401 unauthorized`, `invalid_api_key`
- No active account saved in the pool.

## Login store facts

1. **File backend on all platforms:** `$CODEX_HOME/auth.json` (default `~/.codex/auth.json`) on both Linux and Windows.
2. **ChatGPT auth only:** only `auth_mode == "chatgpt"` logins are accepted; API key logins are rejected with a clear message.
3. **Slots and state:** slots live in `$CODEX_HOME/accounts/<name>.json`, with metadata in `state.json` (`active`, `cooldown`, `quota`, `ui_order`) and concurrency managed by `$CODEX_HOME/accounts/.swap.lock`.
4. **Credential store override:** every process started by `codexr`, `codex-run`, and `codex-task` passes `-c cli_auth_credentials_store="file"`, preventing interference from OS credential-store settings.
5. **Account identity:** stable user ID decoded from the `id_token` JWT payload (`sub`, falling back to `tokens.account_id`). When tokens refresh in place during a run, identity-checked write-back safely updates the matching slot file.
6. **Privacy rule:** never read `auth.json` or slot files (`accounts/*.json`) directly, and never display or log token contents.

## The account pool (`codexr` commands)

`codexr` manages multiple accounts, measures real quota, and switches active credentials:

- `codexr list` (alias `codexr ls`): probes the real quota of every saved account via the codex app-server JSON-RPC over stdio (`account/rateLimits/read`, 0 tokens, no model call) in parallel using temporary directories. Shows `ACCOUNT`, `PLAN`, `CODEX 5H` (% left and reset time), `CODEX WEEK` (% left and reset time), and `STATUS`. Rows are ordered by weekly reset time soonest first; `*` marks the active account.
- `codexr list -c` (`--cached`): displays saved numbers from the last measurement without calling codex.
- `codexr list -w` (`--wide`): disables responsive column trimming.
- `codexr rotate [<duration>]`: puts the active account on cooldown (for `<duration>`, or auto-probed) and switches to the next ready account.
- `codexr use <name>`: switches active credentials to slot `<name>`. Refreshed tokens in use are written back to their slot first.
- `codexr save <name>`: saves the current live login as slot `<name>` and marks it active.
- `codexr rename <old> <new>`: renames slot `<old>` to `<new>` along with its state.
- `codexr del <name>` (alias `rm`): permanently removes slot `<name>`.
- `codexr cooldown <name> [<time>]`: sets cooldown on `<name>` (duration like `4h13m`, or auto-probed if omitted).
- `codexr clear <name>`: removes cooldown from `<name>`.
- `codexr next [-v]`: prints the name of the next ready account (soonest weekly reset).
- `codexr active`: prints the name of the active account slot.
- `codexr forget [-f]`: removes live `auth.json` on this machine so the next run prompts for login.
- `codexr test [-w] [<name>...]`: sends "Hi" to accounts to test/ping (1 real request per account, burns quota; **only when the user explicitly asks**).
- `codexr run <args>` (or bare `codexr`): starts codex using the credentials of the active slot (default model `gpt-6-luna`, reasoning effort `max`).

Always report reset times to the user in **UTC+7** (`codexr` outputs in UTC+7 by default via `CODEXR_TZ`).

## Auto-continue after the user re-logs in

The user does not need to type "continue" after re-logging in; detect it and resume:
1. When exit 4 or 5 occurs, notify the user which task stopped and the reason.
2. Watch for credential updates via `stat -c %Y "$CODEX_HOME/auth.json"` (never read the file contents) or monitor `codexr list`.
3. Confirm with `codexr list` (0 tokens) that the account is active and ready.
4. Resume the stopped task:
   - For an implement task: `codex-task run --name <task> --resume --task <repo>/.codex-sessions/<task>.task.txt --scope '<pathspec>'`
   - For a read-only explore task: `codex-run --prompt "$PROMPT" --add-dir "$REPO" --log "$LOG" --conversation <thread_id> --sandbox read-only`
