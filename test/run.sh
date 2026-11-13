#!/usr/bin/env bash
# Test harness and runner for codexr, codex-run, and codex-task.
# Uses fake logins and fake-codex; never touches real logins.
#
# Helpers available to test suites:
#   setup                 fresh temp CODEX_HOME with acc1, acc2, acc3; acc1 active; sets CODEXR_BIN, CODEXR_NOW
#   jlogin NAME [REFRESH] prints ChatGPT-shaped auth.json for NAME with JWT sub claim
#   cd_of NAME            cooldown epoch for account NAME from state.json
#   runit                 invokes codex-run with default test arguments
#   lines                 count lines in $FAKE_ARGS_LOG
#   pass NAME             record a passed assertion
#   fail NAME [MSG]       record a failed assertion
#   eq NAME EXP ACT       assert EXP == ACT
#   has NAME SUB TXT      assert TXT contains SUB
#   hasnt NAME SUB TXT    assert TXT does not contain SUB
#   cleanup               trap handler cleaning up temporary directories
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CODEXR="$HERE/../bin/codexr"
RUN="$HERE/../bin/codex-run"
TASK="$HERE/../bin/codex-task"
FAKE_TASK_RUN="$HERE/fake-codex-run"

export CODEXR_BIN="$HERE/fake-codex"
export CODEXR="$CODEXR"
export CODEX_RUN_POLL=0.1

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=1 ;; *) ON_WINDOWS=0 ;; esac

if jq -b -n . >/dev/null 2>&1; then jq() { command jq -b "$@"; }; fi

export TZ=UTC-7
export LC_TIME=C

REAL_AUTH="$HOME/.codex/auth.json"
REAL_MTIME_BEFORE="$(stat -c %Y "$REAL_AUTH" 2>/dev/null || echo none)"

real_codex_busy() { pgrep -x codex >/dev/null 2>&1 || pgrep -x codex-run >/dev/null 2>&1; }
REAL_BUSY=0; real_codex_busy && REAL_BUSY=1

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ $# -gt 1 ] && echo "       $2"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi; }
has() { if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1" "'$2' not found in: $3"; fi; }
hasnt() { if grep -qF -- "$2" <<<"$3"; then fail "$1" "must not contain '$2' in: $3"; else pass "$1"; fi; }

TMPS=()
cleanup() { for d in "${TMPS[@]}"; do rm -rf "$d"; done; }
trap cleanup EXIT

jlogin() {
  local name="$1"
  local refresh="${2:-rt-$name}"
  local b64
  b64="$(printf '{"sub":"%s"}' "$name" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\r\n')"
  local jwt="eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.${b64}."
  jq -n \
    --arg jwt "$jwt" \
    --arg at "at-$name" \
    --arg rt "$refresh" \
    --arg acct "$name" \
    '{
      auth_mode: "chatgpt",
      OPENAI_API_KEY: null,
      tokens: {
        id_token: $jwt,
        access_token: $at,
        refresh_token: $rt,
        account_id: $acct
      },
      last_refresh: "2026-01-01T00:00:00Z"
    }'
}

setup() {
  T="$(mktemp -d)"; TMPS+=("$T")
  export CODEX_HOME="$T/home"; mkdir -p "$CODEX_HOME"
  export CODEXR_BIN="$HERE/fake-codex"
  export CODEXR_NOW=1000000
  export FAKE_ARGS_LOG="$T/args.log"; : >"$FAKE_ARGS_LOG"
  unset FAKE_QUOTA_TOKENS FAKE_AUTH FAKE_DEAD_TOKENS FAKE_ZERO_TOKENS FAKE_P5 FAKE_LOW_TOKENS FAKE_WEEKLY_HIT_TOKENS FAKE_WEEK_ORDER FAKE_HI_SHIFT FAKE_REFRESH FAKE_CROSSTALK_TOKENS FAKE_TTY FAKE_QUOTA_EXIT FAKE_HI_ERROR_TOKENS FAKE_TRANSIENT_ERROR CODEX_RUN_MAX_SWITCH
  local a
  for a in acc1 acc2 acc3; do
    jlogin "$a" > "$CODEX_HOME/auth.json"
    "$CODEXR" save "$a" >/dev/null
  done
  "$CODEXR" use acc1 >/dev/null
  echo "do the thing" >"$T/prompt.txt"
  mkdir -p "$T/work"
}

cd_of() { jq -r --arg n "$1" '.cooldown[$n] // 0' "$CODEX_HOME/accounts/state.json"; }
runit() { "$RUN" --prompt "$T/prompt.txt" --add-dir "$T/work" --log "$T/run.jsonl" 2>"$T/run.err"; }
lines() { wc -l <"$FAKE_ARGS_LOG" | tr -d ' '; }

SUITES=("$@")
if [ "${#SUITES[@]}" -eq 0 ]; then
  SUITES=(core linux windows)
fi

for suite in "${SUITES[@]}"; do
  case "$suite" in
    core|linux|windows)
      . "$HERE/$suite.sh"
      ;;
    *)
      echo "usage: test/run.sh [core|linux|windows ...]" >&2
      exit 2
      ;;
  esac
done

echo "== safety"
real_codex_busy && REAL_BUSY=1
if [ "$REAL_BUSY" = 1 ]; then
  echo "  skip the real auth mtime check: real codex / codex-run processes are running and rewrite that file themselves"
else
  eq "the real auth file is untouched (mtime)" "$REAL_MTIME_BEFORE" "$(stat -c %Y "$REAL_AUTH" 2>/dev/null || echo none)"
fi
eq "no test code hard-codes the real codex directory" "0" "$(grep -n '\.codex' "$HERE/run.sh" "$HERE/core.sh" "$HERE/linux.sh" "$HERE/windows.sh" "$HERE/fake-codex" | grep -vc -e 'REAL_AUTH=' -e 'hard-codes the real codex directory')"

echo
echo "result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
