# AGENT.MCP.md: install and check codexr

Read this file when a user asks you to install codexr on a machine. You are an AI agent with shell access. This file is not an MCP server.

## 0. What you are installing

codexr switches between several ChatGPT accounts for the official `codex` CLI. When one account runs out of quota (hits its usage limit), `codex-run` moves the same task to the next ready account and resumes the same conversation thread (`codex exec resume <thread_id>`). It also shows the real quota of each account across 5-hour and weekly windows.

- Repository: https://github.com/luongtrz/codexr (MIT).
- Commands it installs: `codexr`, `codex-run`, `codex-task`.
- Codex login is interactive (browser / ChatGPT auth). Only the user can log in. Your job is to install, verify, and hand the logins back to the user.

Using several accounts this way may conflict with OpenAI's terms of service for some plans. Say so once to the user when you install it.

## 1. Hard rules

1. Never read, print, `cat`, `grep`, open or copy these: `$CODEX_HOME/auth.json` (or `~/.codex/auth.json`), any file under `$CODEX_HOME/accounts/`, and `accounts/.last-token.bak`. Allowed: `test -f`, `stat -c %Y` (modification time), and listing slot file names.
2. Do not log in to OpenAI. Do not run `codexr save`, `forget`, `rename`, `use`, `rotate`, `cooldown`, `clear` or `test` unless the user asks for that action in this conversation. `codexr test` sends real requests and spends quota.
3. Never modify slot files directly. Always use `codexr` commands (`codexr`, `codexr run ...`, `codex-run`, `codex-task`).
4. Do not overwrite, move or delete any file outside the clone and the three commands you install. That includes `~/.claude/CLAUDE.md`, an existing `~/.claude/skills/codex`, and any existing file in the bin directory. Show the diff and ask first.
5. Do not commit, push, change git remotes, or edit the user's shell profile.
6. Do not uninstall, and do not delete `~/.codex/accounts/`, unless the user asks in this conversation.
7. If a step opens a browser or asks for authentication, stop and hand it to the user.

## 2. Check the machine

Run these and report the results to the user:

```bash
uname -s                                              # Linux, or MINGW*/MSYS*/CYGWIN* for Git Bash on Windows
for c in bash git jq; do command -v "$c" >/dev/null && echo "ok: $c" || echo "MISSING: $c"; done
command -v codex >/dev/null && codex --version 2>/dev/null | head -1 || echo "MISSING: codex"
ls -l ~/.local/bin 2>/dev/null | grep -E ' (codexr|codex-run|codex-task)(\.cmd)?$' || echo "no codexr commands in ~/.local/bin yet"
```

Requirements:

- **All platforms:** bash, git, jq.
- **Linux:** `timeout` and `setsid` are used when present (coreutils and util-linux). Not required.
- **Windows (Git Bash):** jq (`winget install jqlang.jq`), and `cygpath` and `taskkill` (both come with Git for Windows).
- **codex:** the official OpenAI Codex CLI, installed by the user. Tested with codex-cli 0.167.x on Linux; the Windows (Git Bash) layer has not been tested on a real Windows machine yet. Do not install codex yourself unless the user asks.

If a required tool is missing, stop. Tell the user the install command for that system. Do not install packages without asking.

## 3. Get the code

Default location: `~/tools/codex-acct`. Use another path only if the user names one.

```bash
export REPO="$HOME/tools/codex-acct"
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" status --short            # must print nothing; if it lists files, stop and ask the user
  git -C "$REPO" pull --ff-only
else
  git clone https://github.com/luongtrz/codexr.git "$REPO"
fi
git -C "$REPO" log --oneline -1
```

The repository has these folders: `bin/` (the three commands), `lib/` (shared defaults), `install.sh` (unified installer), `platforms/linux/` and `platforms/windows/` (platform code and install scripts), `skills/codex/` (orchestrator skill), `templates/`, `docs/`, `test/`.

## 4. Install the commands

Run the unified installer (auto-detects Linux vs Windows):

```bash
bash "$REPO/install.sh"
```

Or run the platform-specific installer directly:

Linux:

```bash
bash "$REPO/platforms/linux/install.sh"
```

This creates symbolic links from `~/.local/bin/<name>` to `$REPO/bin/<name>`.

Windows (Git Bash):

```bash
bash "$REPO/platforms/windows/install.sh"
```

Git Bash cannot make working symlinks here, so this writes both bash wrappers (`~/.local/bin/<name>`) and Windows CMD/PowerShell batch wrappers (`~/.local/bin/<name>.cmd`) that invoke `$REPO/bin/<name>`. This allows running `codexr`, `codex-run`, and `codex-task` directly from Git Bash, PowerShell, and Command Prompt. The clone path is written into the wrappers. If the clone is moved, run the script again.

All installers:

- stop with exit 1 when `jq` or `git` is missing;
- refuse to replace a regular file (Linux), or a file that is not a wrapper for this clone (Windows, checking both `<name>` and `<name>.cmd`), and print why. If that happens, show the file to the user and ask. Do not delete it;
- print a note when the bin directory is not on `PATH`.

If `~/.local/bin` is not on `PATH`, tell the user to add `export PATH="$HOME/.local/bin:$PATH"` to their shell profile. Do not edit the profile yourself.

## 5. Verify without logging in

```bash
export PATH="$HOME/.local/bin:$PATH"
codexr help | head -1           # codexr — rotate between multiple OpenAI codex (ChatGPT) accounts
codex-run --help | head -1      # codex-run — run one codex task headless, rotating accounts when one runs out of quota
codex-task --help | head -1     # codex-task — deterministic wrapper running one delegated implement task end to end
```

Then run the test suite. It uses a fake codex binary and fake credentials and never touches a real login. It takes several minutes, so run it with a long timeout or in the background:

```bash
LOG=$(mktemp)
bash "$REPO/test/run.sh" > "$LOG" 2>&1; echo "exit=$?"
grep '^result:' "$LOG"
```

Expected: `exit=0` and `result: ... pass, 0 fail` (`0 fail` is the requirement; check count may vary across versions). If anything fails, report the lines that start with `FAIL` and stop.

Do not run `codexr list` yet. It needs logins that the user has not saved.

## 6. Hand the logins to the user

These steps need the user's ChatGPT account and a browser. Explain them, then wait for the user to confirm each account.

1. For each ChatGPT account, in a normal terminal: run `codexr`. It starts codex with the selected slot. Finish the login, then quit codex.
2. Save that login under a name: `codexr save <name>`. A name may contain only letters, digits, `-` and `_` (for example `work` or `personal`).
3. Before the next account, run `codexr forget`. It removes the login on this machine only (`$CODEX_HOME/auth.json`). It does not revoke tokens at OpenAI. Do not use codex's own logout.
4. Repeat for each account.
5. Check: `codexr list` must show a different quota line for each saved account. A slot that shows `measure failed` has an expired or revoked login: the user logs in again and runs `codexr save <name>` for it.
6. Choose the account to use: `codexr use <name>`.

After the user confirms the saves, you may run `codexr list -c`. It prints the saved numbers without starting codex. Do not run `codexr list` without asking, because it probes quota across accounts.

## 7. Optional: the `codex` skill

Install this only if the user runs Claude Code or another AI orchestrator on this machine and wants the `codex` skill (see [docs/agent-setup.md](docs/agent-setup.md)). The skill tells the orchestrator how to hand work to codex through `codex-task` and `codex-run`.

```bash
SKILL="$HOME/.claude/skills/codex"
if [ -e "$SKILL" ]; then
  diff -r "$REPO/skills/codex" "$SKILL" && echo "skill already identical"
else
  mkdir -p "$HOME/.claude/skills" && cp -r "$REPO/skills/codex" "$SKILL" && echo "skill installed"
fi
```

If a different skill is already there, show the diff and ask. Do not touch `~/.claude/CLAUDE.md`: it belongs to the user.

## 8. What the commands do

- `codexr` (also `codexr run [args]`): start codex with the selected account and file credentials store forced (`-c cli_auth_credentials_store="file"`).
- `codexr list`: measure every saved account via app-server probe (0 tokens). `codexr list -c`: show the saved numbers only.
- `codexr use <name>`: select an account. `codexr active`: print the selected one.
- `codexr next`: print the ready account whose weekly limit resets soonest. Exit 3 when every account is on cooldown.
- `codexr rotate`: for the user's interactive codex that ran out of quota. It cools the current account down and switches to the next ready account.
- `codex-run --prompt FILE --add-dir DIR --log FILE.jsonl`: run one headless codex task. On a usage limit error, it switches accounts and resumes the same conversation (`codex exec resume <thread_id>`). Exit codes: 0 done, 1 other failure, 2 bad arguments, 4 login error, 5 every account out of quota, 6 too many switches.
- `codex-task run --name NAME --task FILE --scope PATH`: run one implement task in its own git worktree. Read `codex-task --help` before using it.

On exit 4 (login), stop and tell the user to log in again. On exit 5, stop and report the earliest reset time from `codexr list -c` (give it in the user's time zone, UTC+7 by default).

## 9. Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| `codexr: command not found` | `~/.local/bin` is not on `PATH` | Tell the user to add it (section 4). |
| `jq is required` | jq is missing | Install jq (Linux: package manager; Windows: `winget install jqlang.jq`). |
| `API-key logins are not supported` | `auth_mode` is `api_key` | codexr requires a ChatGPT login (`auth_mode: chatgpt`). |
| `measure failed` for one slot | the login was revoked or has expired | The user logs in again and runs `codexr save <name>`. |
| `codexr list` warns that the login matches no slot | the user logged in but did not save | The user runs `codexr save <name>`. |
| `another codexr is switching accounts` | another codexr holds the lock | Wait a moment and retry. Do not delete the lock file. |
| An install script refuses to replace a file | an unrelated file has the command name | Show the file to the user and ask. |

## 10. Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CODEX_HOME` | `~/.codex` | codex home directory |
| `CODEXR_BIN` | `codex` | codex binary |
| `CODEXR_MODEL` | `gpt-6-luna` | default model for codex-run and codex-task |
| `CODEXR_EFFORT` | `max` | default reasoning effort for codex-run and codex-task |
| `CODEXR_TZ` | `UTC-7` (UTC+7) | time zone for displayed times |
| `CODEXR_COLOR` | `auto` | `auto`, `always` or `never` |
| `CODEXR_TEST_TIMEOUT` | `120` | seconds an account may take in `codexr test` |
| `CODEXR_TEST_EFFORT` | `low` | reasoning effort for `codexr test` ping |
| `CODEX_RUN_MAX_SWITCH` | `10` | maximum account switches per `codex-run` |
| `CODEX_RUN_POLL` | `1` | seconds between two looks at the log |
| `CODEX_RUN_SANDBOX` | `workspace-write` | default sandbox mode for `codex-run` |
| `CODEX_TASK_CONF` | `<repo>/.codex-sessions/codex-task.conf` | task config path override |

## 11. Update and uninstall

- Update (only when the clone has no local changes): `git -C "$REPO" pull --ff-only`. On Linux the symlinks need no change. On Windows, run `bash "$REPO/install.sh"` (or `bash "$REPO/platforms/windows/install.sh"`) again. Then repeat section 5.
- Uninstall (only when the user asks): remove the three links or wrappers in the bin directory. Remove the clone only if the user asks. Never delete `~/.codex/accounts/`, which holds the user's saved logins, unless the user asks for that by name.

## 12. Known limits to tell the user

- Account switching has been verified with simulated codex runs and fake credentials. Verify with real accounts when the user logs in and `codexr list` shows different numbers for each slot.
- Parallel `codex-run` processes share the live auth file. While file locks protect switching and state updates, concurrent runs should ideally be coordinated.
- `codexr save` does not check whether the same login is already saved under another name.
- OpenAI can expire or revoke a session / refresh token. The slot then shows `measure failed`.
- Switching accounts may be against OpenAI's terms of service for some plans; use with accounts you own and in moderation.

## 13. Report back

When you finish, report to the user:

- the commit of the clone (`git -C "$REPO" log --oneline -1`);
- where the commands are installed and whether that directory is on `PATH`;
- the test result line (`result: ... pass, 0 fail`);
- whether the skill was installed;
- the login steps still waiting for the user (section 6).
