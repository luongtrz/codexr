# Reading codex logs, and why quota burns (read when auditing a run or planning a batch)

## codex exec --json event stream

`codex-run` executes codex via `codex exec --json` (or `codex exec resume <thread_id> --json`), capturing JSONL output to the session log file.

Key events in the JSONL stream:
- `thread.started`: emitted once when the conversation begins. Contains `.thread_id` (the conversation ID used for `--resume` or `--conversation`).
- `turn.started`: emitted at the beginning of each turn.
- `item.completed`: emitted when an item completes. When `(.item.type // "") == "agent_message"`, `.item.text` contains the assistant's message.
- `turn.completed`: emitted when a turn finishes. Contains `.usage` with token metrics:
  - `.usage.input_tokens`
  - `.usage.cached_input_tokens`
  - `.usage.output_tokens`
  - `.usage.reasoning_output_tokens`
- `error` / `turn.failed`: emitted if an error occurs. Contains `.message` or `.error.message`.

Because non-JSON status lines may occasionally appear on stderr/stdout, always use `grep '^{' "$LOG"` before piping into `jq`.

```bash
# live feed of agent messages for the user
tail -f "$LOG" | grep --line-buffered '^{' | jq -r --unbuffered 'select((.type // .event) == "item.completed" and ((.item.type // "") == "agent_message")) | .item.text // empty'

# check whether a running session is still making progress (event count and latest event)
grep -c '^{' "$LOG" && grep '^{' "$LOG" | tail -1

# get the conversation / thread ID
grep '^{' "$LOG" | jq -r 'select((.type // .event) == "thread.started") | .thread_id // empty' | tail -1

# calculate total token usage across all turns
grep '^{' "$LOG" | jq -s '[.[] | select((.type // .event) == "turn.completed")] | map(.usage) | {input_tokens: map(.input_tokens // 0) | add, output_tokens: map(.output_tokens // 0) | add, cached_tokens: map(.cached_input_tokens // 0) | add, reasoning_tokens: map(.reasoning_output_tokens // 0) | add, turns: length}'

# view the final assistant report text
grep '^{' "$LOG" | jq -r 'select((.type // .event) == "item.completed" and ((.item.type // "") == "agent_message")) | .item.text' | tail -1

# inspect any errors in the run
grep '^{' "$LOG" | jq -c 'select((.type // .event) | test("error|turn\\.failed"))'
```

Give the user the `tail -f … | jq` command whenever they want to monitor real-time progress.

## Workspace directory (`--add-dir` / `-C DIR`)

`codex-run` accepts `--add-dir <DIR>` and passes it to `codex exec` via `-C <DIR>`. For resuming sessions (`codex exec resume`), `codex-run` changes working directory to that target directory so codex runs with the correct workspace context. Always pass `--add-dir`: for implement tasks, `codex-task` passes the dedicated worktree path automatically.

## Why quota burns fast

Each tool call and conversational turn resends the entire conversation history. As context grows, token consumption scales with every subsequent step:
- Baseline turns cost tens of thousands of tokens; sessions with deep back-and-forth or large file reads can reach context limits and burn hundreds of thousands of tokens per turn.
- Prompt caching (`cached_input_tokens`) reduces billing weight on repeated prefixes, but uncached reads and generated outputs still consume quota.
- Aggravators: bundling multiple tasks into one prompt, repeatedly reading massive files (e.g. thousands of lines of JSON, lockfiles, or large generated source files), and unbounded correction rounds.

Rules to keep consumption low:
1. **One small task per session:** never bundle several unrelated bugs or features into one prompt.
2. **Point to exact files and line ranges:** guide codex directly to the relevant code so it does not waste turns searching or reading irrelevant files.
3. **Cap correction rounds:** limit `--resume` follow-ups to at most 2 rounds per task.

## Smoke test

To verify that codex CLI execution and credentials work properly:
```bash
PROMPT_FILE="$(mktemp)"
echo "Reply with 'PONG' and nothing else." > "$PROMPT_FILE"
codex-run --prompt "$PROMPT_FILE" --add-dir "$PWD" --log "smoke-test.jsonl" --sandbox read-only
rm -f "$PROMPT_FILE" smoke-test.jsonl
```
A successful run returns exit code 0, emits `thread.started` and `turn.completed`, and finishes in a single turn.
