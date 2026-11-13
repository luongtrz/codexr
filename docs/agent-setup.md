# Orchestrator Agent Setup (`CLAUDE.md` / `GEMINI.md` / `AGENTS.md`)

When using an AI coding assistant (Claude Code, Gemini CLI / Antigravity, Codex, etc.) as an orchestrator that delegates coding and exploration tasks to `codex` through `codex-task` and `codex-run`, install the [`skills/codex`](../skills/codex) skill and optionally add the role-split rule below to your agent's global instructions file.

## 1. Install the `codex` skill

Copy [`skills/codex`](../skills/codex) into your agent's skills directory:

```bash
# Claude Code
mkdir -p ~/.claude/skills
cp -r ~/tools/codex-acct/skills/codex ~/.claude/skills/

# Gemini CLI / Antigravity
mkdir -p ~/.gemini/skills
cp -r ~/tools/codex-acct/skills/codex ~/.gemini/skills/

# Codex (if loading skills from ~/.codex/skills; otherwise point AGENTS.md at skills/codex)
mkdir -p ~/.codex/skills
cp -r ~/tools/codex-acct/skills/codex ~/.codex/skills/
```

## 2. Optional global instructions (`CLAUDE.md` / `GEMINI.md` / `AGENTS.md`)

Add the snippet below to `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, or your project's `AGENTS.md` if you want the main agent to act strictly as planner and reviewer while delegating implementation work to `codex`:

```markdown
## Role split: Orchestrator = planner & reviewer, codex = sub-agent coder

The main agent does NOT write or edit project code itself — **except** when it has already traced the exact line(s) to change during investigation (where delegating would cost more than the fix). Otherwise, delegate all implementation work to `codex`:
- Implement tasks go through `codex-task run`
- Read-only exploration tasks go through `codex-run --sandbox read-only`

Before any `codex` run, load and follow the `codex` skill (`SKILL.md`): default model `gpt-6-luna` with reasoning effort `xhigh` (overridable with `--model` / `--effort` or `CODEXR_MODEL` / `CODEXR_EFFORT`), flags, exit codes, usage-limit rotation, and git worktree rules all live there. If `codex` is unavailable (login failure or the whole account pool is on cooldown), STOP and tell the user so they can re-login — do not silently fall back to coding it yourself.

Orchestrator responsibilities:
- **Plan, don't over-specify** — do only enough investigation to write a clear plan: goal, root cause or suspected area, relevant files, the pattern to mirror, and acceptance criteria. Do NOT pre-trace every line or write out the full code in the prompt — let `codex` locate and implement the details, then trace the code during review. Keep one bug or logical change per `codex` session; every prompt carries the `HARD RULES` block (`codex-task` appends it automatically).
- **Isolate** — implement tasks run only inside a dedicated git worktree created by `codex-task run` (never the main checkout); read-only exploration tasks may target the repository via `codex-run --add-dir <repo> --sandbox read-only`.
- **Launch individually** — launch each `codex-task run` or `codex-run` as its own separate background tool call (never bundle multiple tasks into one shell loop, wrapper script like `launch.sh`, or `for pid in ...; wait` command). Bundling hides individual task status from the user and blocks completion notifications until the slowest task finishes.
- **Review & verify** — treat `codex`'s output as untrusted: read the full diff, run build/lint/type-check/tests yourself, and verify `codex`'s conclusions against the code. If the result is wrong, send `codex` a corrected follow-up prompt (`codex-task run --name <task> --resume ...`) rather than fixing it by hand.
- **Integrate** — stage verified in-scope changes, commit, and clean up the worktree (`codex-task rm <task> -f`).
```
