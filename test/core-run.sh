# codex-run's cooldown also probes the quota (codexr cooldown -> app-server), so the args log holds app-server lines too:
# these views keep only the exec calls
xlog() { grep -F '|exec ' "$FAKE_ARGS_LOG"; }
xlines() { xlog | wc -l | tr -d ' '; }

# Core tests for codex-run and concurrency.
# Sourced by test/core.sh from test/run.sh.

echo "== codex-run"

# Immediate success: default flags, prompt on stdin, logging
setup
export FAKE_PROMPT_LOG="$T/prompt.log"
runit; rc=$?
eq "immediate success: exit 0" "0" "$rc"
eq "runs only once" "1" "$(xlines)"
first="$(xlog | sed -n 1p)"
has "uses the acc1 account" "acc1|" "$first"
has "carries -m gpt-6-luna" "-m gpt-6-luna" "$first"
has "carries -c model_reasoning_effort=\"max\"" '-c model_reasoning_effort="max"' "$first"
has "carries -c cli_auth_credentials_store=\"file\"" '-c cli_auth_credentials_store="file"' "$first"
has "carries -C <workdir>" "-C $T/work" "$first"
has "default sandbox workspace-write" "--sandbox workspace-write" "$first"
eq "prompt reaches codex on stdin (FAKE_PROMPT_LOG)" "do the thing" "$(cat "$FAKE_PROMPT_LOG")"
hasnt "logged argv has no prompt" "do the thing" "$first"
eq "logged argv ends with -" "-" "$(xlog | awk '{print $NF}')"
unset FAKE_PROMPT_LOG

# Custom --model and --effort flags
setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --model custom-model --effort low 2>"$T/run.err"; rc=$?
eq "codex-run with custom model and effort: exit 0" "0" "$rc"
first="$(xlog | sed -n 1p)"
has "passes custom --model" "-m custom-model" "$first"
has "passes custom --effort" '-c model_reasoning_effort="low"' "$first"

# Sandbox modes: read-only, workspace-write, --yolo
setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --sandbox read-only 2>"$T/run.err"; rc=$?
eq "codex-run --sandbox read-only: exit 0" "0" "$rc"
has "passes --sandbox read-only" "--sandbox read-only" "$(xlog)"

setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --yolo 2>"$T/run.err"; rc=$?
eq "codex-run --yolo: exit 0" "0" "$rc"
first="$(xlog | sed -n 1p)"
has "passes --yolo flag" "--dangerously-bypass-approvals-and-sandbox" "$first"
hasnt "--yolo omits --sandbox" "--sandbox" "$first"

# Usage-limit error (FAKE_QUOTA_TOKENS): immediate kill, cooldown, next/use switch, resume thread
setup
export FAKE_QUOTA_TOKENS="acc1"
start=$SECONDS
runit; rc=$?
elapsed=$((SECONDS - start))
eq "acc1 out of quota -> switch to acc2, exit 0" "0" "$rc"
eq "runs twice" "2" "$(xlines)"
second="$(xlog | sed -n 2p)"
has "second run uses the acc2 account" "acc2|" "$second"
has "second run resumes the same thread id" "exec resume fake-thread-1" "$second"
has "resumed attempt uses -c sandbox_mode" '-c sandbox_mode="workspace-write"' "$second"
hasnt "resumed attempt omits -C" "-C $T/work" "$second"
hasnt "resumed attempt omits --sandbox" "--sandbox" "$second"
hasnt "second run does not resend the original prompt" "do the thing" "$second"
eq "acc1 cooldown 18000s (5h)" "$((1000000 + 18000))" "$(cd_of acc1)"
eq "active = acc2" "acc2" "$("$CODEXR" active)"
[ "$elapsed" -lt 20 ] && pass "killed immediately, did not wait for sleep 30 (${elapsed}s)" || fail "killed immediately, did not wait for sleep 30" "took ${elapsed}s"
eq "log shows thread.started twice" "2" "$(grep -c '"type":"thread.started"' "$T/run.jsonl")"
eq "both thread.started have the same thread_id" "fake-thread-1 fake-thread-1" "$(jq -r 'select((.type // "") == "thread.started") | .thread_id' "$T/run.jsonl" | xargs)"
sleep 0.3
if command -v pgrep >/dev/null; then
  eq "no fake-codex process left behind" "0" "$(pgrep -fc "$HERE/fake-codex" || true)"
else
  echo "  skip 'no fake-codex process left behind': no pgrep on this system"
fi
unset FAKE_QUOTA_TOKENS

# FAKE_QUOTA_EXIT=1 variant
setup
export FAKE_QUOTA_TOKENS="acc1" FAKE_QUOTA_EXIT=1
runit; rc=$?
eq "quota with immediate exit 1: switch to acc2, exit 0" "0" "$rc"
eq "quota with immediate exit 1: runs twice" "2" "$(xlines)"
eq "quota with immediate exit 1: active = acc2" "acc2" "$("$CODEXR" active)"
eq "quota with immediate exit 1: log shows thread.started twice" "2" "$(grep -c '"type":"thread.started"' "$T/run.jsonl")"
eq "quota with immediate exit 1: both thread.started have same id" "fake-thread-1 fake-thread-1" "$(jq -r 'select((.type // "") == "thread.started") | .thread_id' "$T/run.jsonl" | xargs)"
unset FAKE_QUOTA_TOKENS FAKE_QUOTA_EXIT

# Resumed attempt with --sandbox read-only uses -c sandbox_mode="read-only"
setup
export FAKE_QUOTA_TOKENS="acc1"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --sandbox read-only 2>"$T/run.err"; rc=$?
eq "resumed with read-only sandbox: exit 0" "0" "$rc"
second="$(xlog | sed -n 2p)"
has "resumed read-only uses -c sandbox_mode=\"read-only\"" '-c sandbox_mode="read-only"' "$second"
hasnt "resumed read-only omits -C" "-C $T/work" "$second"
hasnt "resumed read-only omits --sandbox" "--sandbox" "$second"
unset FAKE_QUOTA_TOKENS

# Resumed attempt with --yolo
setup
export FAKE_QUOTA_TOKENS="acc1"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --yolo 2>"$T/run.err"; rc=$?
eq "resumed with yolo: exit 0" "0" "$rc"
second="$(xlog | sed -n 2p)"
has "resumed yolo uses --dangerously-bypass-approvals-and-sandbox" "--dangerously-bypass-approvals-and-sandbox" "$second"
hasnt "resumed yolo omits -C" "-C $T/work" "$second"
hasnt "resumed yolo omits sandbox_mode" "sandbox_mode" "$second"
unset FAKE_QUOTA_TOKENS

# Two accounts in a row out of quota -> exit 0
setup
export FAKE_QUOTA_TOKENS="acc1 acc2"
runit; rc=$?
eq "two accounts in a row out of quota -> exit 0" "0" "$rc"
eq "runs three times" "3" "$(xlines)"
has "third run uses acc3" "acc3|" "$(xlog | sed -n 3p)"
has "third run still resumes the same conversation" "exec resume fake-thread-1" "$(xlog | sed -n 3p)"
unset FAKE_QUOTA_TOKENS

# Whole pool out of quota -> exit 5
setup
export FAKE_QUOTA_TOKENS="acc1 acc2 acc3"
runit; rc=$?
eq "whole pool out of quota -> exit 5" "5" "$rc"
has "reports the whole pool is out of quota" "whole pool is out of quota" "$(cat "$T/run.err")"
out="$("$CODEXR" next 2>&1)"; eq "state: all 3 on cooldown" "3" "$?"
unset FAKE_QUOTA_TOKENS

# Exceeding CODEX_RUN_MAX_SWITCH -> exit 6
setup
export FAKE_QUOTA_TOKENS="acc1 acc2 acc3" CODEX_RUN_MAX_SWITCH=1
runit; rc=$?
eq "exceeding the max number of switches -> exit 6" "6" "$rc"
has "the message names the limit" "switched accounts 1 times" "$(cat "$T/run.err")"
unset FAKE_QUOTA_TOKENS CODEX_RUN_MAX_SWITCH

# Auth error (FAKE_AUTH=1) -> exit 4 with no switch
setup
export FAKE_AUTH=1
runit; rc=$?
eq "auth error -> exit 4" "4" "$rc"
eq "auth error: account is not switched" "acc1" "$("$CODEXR" active)"
eq "auth error: runs only once" "1" "$(xlines)"
has "auth error message names the account" "login error on account 'acc1'" "$(cat "$T/run.err")"
unset FAKE_AUTH

# No active account -> exit 4
setup
rm -f "$CODEX_HOME/accounts/state.json" "$CODEX_HOME/auth.json"
runit; rc=$?
eq "no active account -> exit 4" "4" "$rc"
eq "codex is not run when there is no active account" "0" "$(xlines)"

# Old usage limit in log is not counted again
setup
echo '{"type":"error","message":"You'\''ve hit your usage limit. try again at Aug 8th, 2026 5:30 PM."}' >"$T/run.jsonl"
runit; rc=$?
eq "an old usage limit line in the log is not counted again" "0" "$rc"
eq "old log: runs only once" "1" "$(xlines)"

# Transient error before completed turn is a success
setup
export FAKE_TRANSIENT_ERROR=1
runit; rc=$?
eq "transient error before successful turn: exit 0" "0" "$rc"
eq "transient error: runs only once" "1" "$(xlines)"
unset FAKE_TRANSIENT_ERROR

# Refreshed token is synced back to account slot after run
setup
export FAKE_REFRESH=1
runit; rc=$?
eq "run with token refresh: exit 0" "0" "$rc"
eq "refreshed access_token synced back to acc1 slot" "at-acc1-refreshed" "$(jq -r '.tokens.access_token // empty' "$CODEX_HOME/accounts/acc1.json")"
eq "refreshed refresh_token synced back to acc1 slot" "rt-acc1-rotated" "$(jq -r '.tokens.refresh_token // empty' "$CODEX_HOME/accounts/acc1.json")"
unset FAKE_REFRESH

# Argument validation: missing --prompt, --add-dir, --log, invalid arguments
setup
"$RUN" --add-dir "$T/work" --log "$T/run.jsonl" 2>/dev/null; eq "missing --prompt -> exit 2" "2" "$?"
"$RUN" --prompt "$T/nonexistent" --add-dir "$T/work" --log "$T/run.jsonl" 2>/dev/null; eq "nonexistent --prompt -> exit 2" "2" "$?"
"$RUN" --prompt "$T/prompt.txt" --log "$T/run.jsonl" 2>/dev/null; eq "missing --add-dir -> exit 2" "2" "$?"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/nonexistent" --log "$T/run.jsonl" 2>/dev/null; eq "nonexistent --add-dir -> exit 2" "2" "$?"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" 2>/dev/null; eq "missing --log -> exit 2" "2" "$?"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --bogus 2>/dev/null; eq "unknown argument -> exit 2" "2" "$?"

# Sandbox validation and CODEX_RUN_SANDBOX env
setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --sandbox invalid 2>/dev/null; eq "invalid --sandbox -> exit 2" "2" "$?"
CODEX_RUN_SANDBOX=invalid "$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" 2>/dev/null; eq "invalid CODEX_RUN_SANDBOX -> exit 2" "2" "$?"
CODEX_RUN_SANDBOX=read-only runit; rc=$?
eq "CODEX_RUN_SANDBOX default env applied: exit 0" "0" "$rc"
has "CODEX_RUN_SANDBOX default passed to codex" "--sandbox read-only" "$(xlog)"

# Explicit --conversation flag
setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --conversation "conv-custom-123" 2>"$T/run.err"; rc=$?
eq "codex-run --conversation: exit 0" "0" "$rc"
eq "codex-run --conversation: runs once" "1" "$(xlines)"
first="$(xlog | sed -n 1p)"
has "codex-run --conversation: first call resumes conversation" "exec resume conv-custom-123" "$first"
has "codex-run --conversation: uses -c sandbox_mode" '-c sandbox_mode="workspace-write"' "$first"

setup
export FAKE_QUOTA_TOKENS="acc1"
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --conversation "conv-custom-123" 2>"$T/run.err"; rc=$?
eq "codex-run --conversation with 429: exit 0" "0" "$rc"
eq "codex-run --conversation with 429: runs twice" "2" "$(xlines)"
first="$(xlog | sed -n 1p)"
second="$(xlog | sed -n 2p)"
has "codex-run --conversation with 429: first call carries resume conv-custom-123" "exec resume conv-custom-123" "$first"
has "codex-run --conversation with 429: second call keeps resuming same conversation" "exec resume conv-custom-123" "$second"
unset FAKE_QUOTA_TOKENS

setup
"$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" --conversation 2>/dev/null; rc=$?
eq "codex-run --conversation without ID -> exit 2" "2" "$rc"


echo "== codex-run: up to 10 account switches by default"

mk12() { # 12 accounts a01..a12, a01 in use
  T="$(mktemp -d)"; TMPS+=("$T")
  export CODEX_HOME="$T/home"; mkdir -p "$CODEX_HOME"
  export CODEXR_BIN="$HERE/fake-codex"
  export CODEXR_NOW=1000000
  export FAKE_ARGS_LOG="$T/args.log"; : >"$FAKE_ARGS_LOG"
  unset FAKE_QUOTA_TOKENS FAKE_AUTH CODEX_RUN_MAX_SWITCH FAKE_REFRESH FAKE_WEEK_ORDER
  local i a
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    a="a$i"
    jlogin "$a" >"$CODEX_HOME/auth.json"
    "$CODEXR" save "$a" >/dev/null
  done
  "$CODEXR" use a01 >/dev/null
  echo "do the thing" >"$T/prompt.txt"; mkdir -p "$T/work"
}

mk12
export FAKE_QUOTA_TOKENS="a01 a02 a03 a04 a05 a06 a07 a08 a09 a10"
runit; rc=$?
eq "10 exhausted accounts -> 10 switches are allowed by default, the 11th account answers (exit 0)" "0" "$rc"
eq "that took 11 runs" "11" "$(xlines)"
has "the last run used a11" "a11|" "$(xlog | tail -1)"

mk12
export FAKE_QUOTA_TOKENS="a01 a02 a03 a04 a05 a06 a07 a08 a09 a10 a11"
runit; rc=$?
eq "11 exhausted accounts -> the 11th switch is refused (exit 6)" "6" "$rc"
has "the message names the limit" "switched accounts 10 times" "$(cat "$T/run.err")"
unset FAKE_QUOTA_TOKENS

has "codex-run --help: documents the default of 10" "CODEX_RUN_MAX_SWITCH (default 10)" "$("$RUN" --help 2>&1)"

mk12
export FAKE_QUOTA_TOKENS="a01 a02 a03" CODEX_RUN_MAX_SWITCH=2
runit; rc=$?
eq "CODEX_RUN_MAX_SWITCH still overrides the default (2 -> exit 6)" "6" "$rc"
has "the message names the limit (2)" "switched accounts 2 times" "$(cat "$T/run.err")"
unset FAKE_QUOTA_TOKENS CODEX_RUN_MAX_SWITCH


echo "== concurrency: many codexr / codex-run at the same time must never mix up logins (file backend)"

# the lock must be exclusive even where mkdir is not (uutils mkdir let several parallel callers all succeed)
if [ "$ON_WINDOWS" = 1 ]; then LOCK_ROUNDS=10 PAR_USE=8 PAR_LIST=3; else LOCK_ROUNDS=60 PAR_USE=40 PAR_LIST=12; fi
bad=0
for r in $(seq 1 "$LOCK_ROUNDS"); do
  D="$(mktemp -d)"; TMPS+=("$D")
  for i in $(seq 1 12); do ( set -o noclobber; { echo "$i" >"$D/lock"; } 2>/dev/null && echo ok >>"$D/oks" ) & done; wait
  [ "$(wc -l <"$D/oks" 2>/dev/null || echo 0)" = 1 ] || bad=$((bad + 1))
done
eq "the exclusive-create primitive used for the lock is atomic (60 rounds x 12 parallel)" "0" "$bad"
grep -q 'until mkdir' "$CODEXR" && fail "codexr must not build its lock on mkdir" || pass "codexr does not build its lock on mkdir"

refresh_of() { jq -r '.tokens.refresh_token // empty' "$CODEX_HOME/accounts/$1.json"; }
mkjson() { # N slots s1..sN with JSON logins, s1 in use
  setup
  rm -f "$CODEX_HOME"/accounts/*.json "$CODEX_HOME/accounts/state.json"
  local i
  for i in $(seq 1 "$1"); do
    jlogin "s$i" >"$CODEX_HOME/auth.json"
    "$CODEXR" save "s$i" >/dev/null
  done
  "$CODEXR" use s1 >/dev/null
}
bad_slots() { local i out=""; for i in $(seq 1 "$1"); do [ "$(refresh_of "s$i")" = "rt-s$i" ] || out="$out s$i"; done; echo "$out"; }
for round in 1 2 3; do
  mkjson 4
  for i in $(seq 1 "$PAR_USE"); do "$CODEXR" use "s$(( (i % 4) + 1 ))" >/dev/null 2>&1 & done; wait
  eq "40 parallel 'use' (round $round): every slot still has its own login" "" "$(bad_slots 4)"
done
eq "after the parallel 'use': no temp file or lock left in the accounts dir" "0" "$(ls -A "$CODEX_HOME/accounts" | grep -cE '^\.snap|^\.swap\.lock|\.tmp|^\.state\.[A-Za-z0-9]+$|^[a-z0-9]+\.json\.[A-Za-z0-9]{6}$' || true)"
eq "after the parallel 'use': the live login is one of the slots'" "1" "$(for i in 1 2 3 4; do [ "$(jq -r '.tokens.refresh_token // empty' "$CODEX_HOME/auth.json")" = "rt-s$i" ] && echo y; done | wc -l | tr -d ' ')"
eq "after the parallel 'use': state.json is valid JSON" "ok" "$(jq -e . "$CODEX_HOME/accounts/state.json" >/dev/null 2>&1 && echo ok || echo broken)"

# 'use' while measurements run
mkjson 4
"$CODEXR" list >/dev/null 2>&1
for i in $(seq 1 "$PAR_LIST"); do "$CODEXR" use "s$(( (i % 4) + 1 ))" >/dev/null 2>&1 & "$CODEXR" list >/dev/null 2>&1 & done; wait
eq "parallel 'use' and 'list': every slot still has its own login" "" "$(bad_slots 4)"
eq "parallel 'use' and 'list': every slot measured as itself (4 snapshots, none lost)" "4" "$(jq -r '.quota | keys | length' "$CODEX_HOME/accounts/state.json")"

# state.json is a read-modify-write: parallel updates must not lose each other
mk12
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do "$CODEXR" cooldown "a$i" 1h >/dev/null 2>&1 & done; wait
eq "12 parallel 'cooldown': none is lost" "12" "$(jq -r '.cooldown | keys | length' "$CODEX_HOME/accounts/state.json")"

# the lock itself
setup
eq "'use' leaves no lock behind" "no" "$("$CODEXR" use acc2 >/dev/null; [ -e "$CODEX_HOME/accounts/.swap.lock" ] && echo yes || echo no)"
echo 999999 >"$CODEX_HOME/accounts/.swap.lock" # its owner is gone
"$CODEXR" use acc3 >/dev/null 2>&1; eq "a stale lock (dead owner) is cleared and 'use' works" "acc3" "$("$CODEXR" active)"
echo $$ >"$CODEX_HOME/accounts/.swap.lock" # its owner (this shell) is alive
start=$SECONDS
out="$(CODEXR_LOCK_WAIT=1 "$CODEXR" use acc1 2>&1)"; rc=$?
eq "a lock held by a live process: 'use' gives up (exit 1)" "1" "$rc"
has "... and says another codexr is switching" "another codexr is switching accounts" "$out"
[ $((SECONDS - start)) -le 5 ] && pass "... after about CODEXR_LOCK_WAIT seconds" || fail "... after about CODEXR_LOCK_WAIT seconds" "took $((SECONDS - start))s"
eq "... and the account in use did not change" "acc3" "$("$CODEXR" active)"
rm -f "$CODEX_HOME/accounts/.swap.lock"
mkdir -p "$CODEX_HOME/accounts/.swap.lock"; echo 999999 >"$CODEX_HOME/accounts/.swap.lock/pid" # an older codexr's lock directory, owner gone
"$CODEXR" use acc2 >/dev/null 2>&1; eq "a stale lock directory left by an older codexr is cleared" "acc2" "$("$CODEXR" active)"
eq "... and replaced by nothing (the lock is released)" "no" "$([ -e "$CODEX_HOME/accounts/.swap.lock" ] && echo yes || echo no)"
echo $$ >"$CODEX_HOME/accounts/.swap.lock" # live again for the checks below
for cmd in "save zz" "forget -f" "rename acc1 acc9" "cooldown acc1 1h"; do
  CODEXR_LOCK_WAIT=1 "$CODEXR" $cmd >/dev/null 2>&1; eq "a held lock also stops 'codexr $cmd' (exit 1)" "1" "$?"
done
rm -rf "$CODEX_HOME/accounts/.swap.lock"

# the login is written atomically and from one copy
setup
"$CODEXR" use acc2 >/dev/null
eq "after 'use': the live login is exactly the slot's" "$(cat "$CODEX_HOME/accounts/acc2.json")" "$(cat "$CODEX_HOME/auth.json")"
eq "'use' leaves no snapshot of a login in the accounts dir" "0" "$(ls -A "$CODEX_HOME/accounts" | grep -c '^\.snap' || true)"
if [ "$ON_WINDOWS" = 1 ]; then
  echo "  skip file modes 600: NTFS has no POSIX permission bits (the profile folder's ACL protects the files)"
else
  eq "the login files stay private (mode 600)" "600" "$(stat -c %a "$CODEX_HOME/auth.json")"
  eq "slot files stay private (mode 600)" "600" "$(stat -c %a "$CODEX_HOME/accounts/acc1.json")"
  eq "the backup stays private (mode 600)" "600" "$(stat -c %a "$CODEX_HOME/accounts/.last-token.bak")"
fi
