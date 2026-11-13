# codexr

Rotate between multiple ChatGPT accounts for the official OpenAI `codex` CLI so that a usage limit on one account does not stop your work, and inspect each account's real 5-hour and weekly quota.

codexr is the Codex counterpart of [agyr](https://github.com/luongtrz/agyr): it rotates between multiple ChatGPT accounts for the official `codex` CLI, shows real-time quota data across 5-hour and weekly windows, and provides headless task execution with automatic account failover.

---

## 3 Core USPs (Unique Selling Points)

- **100% Local & Privacy-First**
  No external servers, no cloud middleman. Your authentication tokens stay on your local disk (`$CODEX_HOME/accounts`) with `chmod 600`. `codexr` only copies them between files and compares account identities; it never prints them and never sends them anywhere.
- **Official Binary, No Proxy**
  No proxy server in the request path. `codexr` runs the official `codex` binary directly and only swaps the login file it reads.
- **Auto-Rotation on Usage Limits with Session Resume**
  Instantly detects usage-limit exhaustion, sets a precise cooldown based on OpenAI's reset timestamp, picks the ready account whose weekly limit resets soonest, and resumes the exact same thread (`codex exec resume <thread_id>`) without losing conversation context.

---

## Disclaimer

Switching accounts may be against OpenAI's terms of service for some subscription plans. Using multiple accounts is entirely your responsibility; use it with accounts you own and in moderation. `codexr` makes no guarantees of safety or immunity from account restrictions.

---

## Quick Installation

Requires `bash`, `git`, and `jq`.

### One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/luongtrz/codexr/main/install.sh | bash
```

To install into a custom directory (e.g., `~/bin`):
```bash
curl -fsSL https://raw.githubusercontent.com/luongtrz/codexr/main/install.sh | bash -s -- ~/bin
```

### Manual Clone

```bash
git clone https://github.com/luongtrz/codexr.git ~/tools/codex-acct

# Unified auto-detect installer (recommended):
bash ~/tools/codex-acct/install.sh

# Or invoke the specific platform installer directly:
bash ~/tools/codex-acct/platforms/linux/install.sh       # Linux: symlinks into ~/.local/bin
bash ~/tools/codex-acct/platforms/windows/install.sh     # Windows: Git Bash + .cmd wrappers into ~/.local/bin
```

AI agents installing this repository should follow [AGENT.MCP.md](AGENT.MCP.md).

---

## Platform Notes

- **One File Backend (Linux & Windows):** Codex stores its active login in `$CODEX_HOME/auth.json` (default: `~/.codex/auth.json`) on all platforms. `codexr` swaps login files directly in this location.
- **Credentials Store Override:** To stay immune to any user credentials store settings, `codexr`, `codex-run`, and `codex-task` pass `-c cli_auth_credentials_store="file"` on every `codex` process they start.
- **Windows Support:** Git Bash shell scripts and Windows `.cmd` wrappers (`codexr.cmd`, `codex-run.cmd`, `codex-task.cmd`) are installed into `~/.local/bin`, allowing commands to be run from Git Bash, Windows PowerShell, and Command Prompt (CMD). The Windows layer has not been tested on a real Windows machine yet; the test suite only checks its scripts and wrappers on Linux.

---

## Command Reference

### Daily Account Management

```bash
codexr list                  # Measure every account's quota and show a table (* = selected; 0 tokens)
codexr list -c               # Print cached quota data without calling codex (--cached)
codexr list -w               # Disable responsive table; always print all columns at full width (--wide)
codexr use <name>            # Switch to slot <name>
codexr save <name>           # Save current login as slot <name>
codexr swapui <n1> <n2>      # Swap UI display order of two accounts in 'codexr list' (--reset to restore)
codexr rename <old> <new>    # Rename a slot (saved login, cooldown, and quota data move with it)
codexr del <name>            # Permanently delete slot <name> (alias: rm)
codexr active                # Print the name of the account in use
codexr run [args]            # Start codex with the selected account; plain 'codexr' does the same
codexr rotate [duration]     # Interactive codex ran out of quota: cool this account down, switch to next
codexr next [-v]             # Print ready account whose weekly limit resets soonest (-v explains why)
codexr cooldown <name> [t]   # Mark an account as out of quota (no duration = probe quota via app-server)
codexr clear <name>          # Remove an account's cooldown
codexr test [name...]        # Send "Hi" to every account (uses real quota) to start each 5-hour window
codexr forget [-f]           # Drop login in use locally ($CODEX_HOME/auth.json), so codex asks for login
codexr sync                  # Internal: write the live login back into its slot
codexr help [command]        # Overview or details of one command
```

### Automation & AI Agents

- **`codex-run`**: Runs one `codex` task headless with automatic account rotation when one runs out of quota. Uses `codex exec --json`. On a usage-limit error, terminates codex immediately, sets account cooldown, switches to the next ready account whose weekly limit resets soonest, and resumes the same conversation (`codex exec resume <thread_id>`).
- **`codex-task`**: Deterministic wrapper running one delegated implement task end to end in a dedicated git worktree (`<repo>/.worktrees/codex-<name>`, branch `codex/<name>`), checking scope and generating a compact summary.
- **Default Model & Reasoning Effort**: Defaults to model `gpt-6-luna` with reasoning effort `max` (from `lib/defaults.sh`). Overridable per call with `--model` and `--effort`, or globally with `CODEXR_MODEL` and `CODEXR_EFFORT`.

---

## AI Agent Orchestration

`codexr` includes an orchestrator skill in `skills/codex/` designed for AI agents (Claude Code, etc.) to delegate coding and investigation tasks to `codex` as a sub-agent.

For complete setup instructions, see:
- [docs/agent-setup.md](docs/agent-setup.md): Complete guide to installing `skills/codex` and configuring AI orchestrators.
- [AGENT.MCP.md](AGENT.MCP.md): Agent setup and verification protocol.

---

## Getting Started (Adding Accounts)

1. **Sign in and save your first ChatGPT account:**
   ```bash
   codexr              # Start codex to sign in to ChatGPT account #1
   codexr save acc1    # Save the current login into slot 'acc1'
   ```

2. **Add a second account (and any additional accounts):**
   ```bash
   codexr forget       # Clear active local login (slot 'acc1' stays safe in accounts/)
   codexr              # Start codex to sign in to ChatGPT account #2
   codexr save acc2    # Save the login into slot 'acc2'
   ```

3. **Inspect real-time quota across all slots:**
   ```bash
   codexr list         # Probes quota via codex app-server (0 tokens)
   ```
   Example output:
   ```
   ┌──────────────────┬────────────┬───────────────────────────┬───────────────────────────┬─────────────────────────────────────────────┐
   │ ACCOUNT          │ PLAN       │ CODEX 5H                  │ CODEX WEEK                │ STATUS                                      │
   ├──────────────────┼────────────┼───────────────────────────┼───────────────────────────┼─────────────────────────────────────────────┤
   │ * acc1           │ plus       │ 100%  13/11/2026 02:18 PM │  86%  19/11/2026 01:44 PM │ ready                                       │
   │   acc2           │ plus       │  45%  13/11/2026 12:05 PM │  78%  18/11/2026 09:30 AM │ ready                                       │
   └──────────────────┴────────────┴───────────────────────────┴───────────────────────────┴─────────────────────────────────────────────┘
   Measured at 13/11/2026 10:28 AM   (* = selected account)
   ```

4. **Switch accounts manually (for interactive sessions):**
   ```bash
   codexr use acc1     # Switch to acc1
   codexr use acc2     # Switch to acc2
   ```

5. **Run automated tasks with automatic failover:**
   ```bash
   codex-run --prompt prompt.txt --add-dir . --log task.jsonl
   ```

---

## Documentation

- [docs/reference.md](docs/reference.md): In-depth technical architecture, full command specifications, platform details, environment variables, known limitations.
- [docs/agent-setup.md](docs/agent-setup.md): Complete guide to installing `skills/codex` and configuring AI orchestrators.
- [AGENT.MCP.md](AGENT.MCP.md): Guide for AI agents installing and verifying `codexr`.

---

## Repository Layout

- `bin/`: `codexr`, `codex-run`, `codex-task` executables.
- `lib/`: Shared defaults (`defaults.sh`).
- `install.sh`: Unified installer (supports both local execution and `curl ... | bash` piping).
- `platforms/linux/`: Linux platform backend and install script.
- `platforms/windows/`: Windows platform backend (Git Bash + `.cmd` wrappers, install script).
- `skills/codex/`: AI agent skill for delegating tasks via `codex-task` and `codex-run`.
- `templates/`: Templates used by `codex-task` (`hard-rules.txt`, `codex-task.conf.example`).
- `docs/`: Technical reference (`reference.md`), orchestrator guide (`agent-setup.md`), design contract (`design.md`).
- `test/`: Test runner (`run.sh`), shared core suite (`core.sh`), and platform suites (`linux.sh`, `windows.sh`).

---

## Tests

The test suite runs with fake tokens and a simulated `codex` binary; it never modifies real user credentials or consumes OpenAI quota.

```bash
bash test/run.sh              # Run all suites (fake codex, fake tokens, never touches real logins)
bash test/run.sh core         # Run platform-independent core tests
bash test/run.sh linux        # Run Linux platform tests
bash test/run.sh windows      # Run Windows platform tests
```

---

## License

MIT, see [LICENSE](LICENSE).
