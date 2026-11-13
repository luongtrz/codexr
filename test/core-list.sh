# List, quota probe, terminal, colour, and test (Hi) scenarios for codexr.
# Sourced by test/run.sh via test/core.sh.

echo "== list (measures real quota)"
setup
out="$("$CODEXR" list 2>&1)"; rc=$?
eq "list: exit 0" "0" "$rc"
has "list: has ACCOUNT column" "ACCOUNT" "$out"
has "list: has PLAN column" "PLAN" "$out"
has "list: has CODEX 5H column" "CODEX 5H" "$out"
has "list: has CODEX WEEK column" "CODEX WEEK" "$out"
has "list: has STATUS column" "STATUS" "$out"
hasnt "list: no CLAUDE column" "CLAUDE" "$out"
hasnt "list: no ARGON column" "ARGON" "$out"
has "list: * marks the selected account" "* acc1" "$out"
has "list: other accounts have no *" "  acc2" "$out"
has "list: acc1 5h = 60%" " 60%" "$out"
has "list: acc2 5h = 70%" " 70%" "$out"
has "list: acc3 5h = 80%" " 80%" "$out"
has "list: acc1 week = 50%" " 50%" "$out"
has "list: acc2 week = 60%" " 60%" "$out"
has "list: acc3 week = 70%" " 70%" "$out"
has "list: acc1 plan = plus" "plus" "$out"
has "list: has 5h reset-time column" "13/01/1970 01:46 AM" "$out"
has "list: has weekly reset-time column" "15/01/1970 08:46 PM" "$out"
has "list: has the 'Measured at' line" "Measured at 12/01/1970 08:46 PM" "$out"
hasnt "list: no Claude/Argon lines" "Claude" "$out"
hasnt "list: does not print refresh tokens" "rt-" "$out"
hasnt "list: does not print access tokens" "at-" "$out"
eq "list: stores the acc1 snapshot p5=60" "60" "$(jq -r '.quota.acc1.p5' "$CODEX_HOME/accounts/state.json")"
eq "list: stores the acc1 snapshot pw=50" "50" "$(jq -r '.quota.acc1.pw' "$CODEX_HOME/accounts/state.json")"
eq "list: stores the acc3 snapshot p5=80" "80" "$(jq -r '.quota.acc3.p5' "$CODEX_HOME/accounts/state.json")"
eq "list: stores the acc3 snapshot pw=70" "70" "$(jq -r '.quota.acc3.pw' "$CODEX_HOME/accounts/state.json")"
eq "list: stores the acc1 plan=plus" "plus" "$(jq -r '.quota.acc1.plan' "$CODEX_HOME/accounts/state.json")"
eq "list: remaining% = 100 - usedPercent" "60" "$(jq -r '.quota.acc1.p5' "$CODEX_HOME/accounts/state.json")"
eq "list: does not change the active account" "acc1" "$("$CODEXR" active)"
eq "list: the live auth file is not changed (still acc1)" "acc1" "$(jq -r '.tokens.account_id' "$CODEX_HOME/auth.json")"
seen="$(cut -d'|' -f1 "$FAKE_ARGS_LOG" | sort | tr '\n' ' ')"
eq "list: codex ran with each slot's own login" "acc1 acc2 acc3 " "$seen"
eq "list: no probe temp directories left behind" "0" "$(ls -d "$CODEX_HOME"/accounts/.probe.* 2>/dev/null | wc -l | tr -d ' ')"
eq "list: no fake-codex app-server process survives" "0" "$(pgrep -f "$CODEXR_BIN.*app-server" | wc -l | tr -d ' ')"

"$CODEXR" list --claude >/dev/null 2>&1
eq "list: no --claude option -> exit 2" "2" "$?"

# the active account is measured with the live auth file
setup
jlogin acc1 "rt-acc1-live" >"$CODEX_HOME/auth.json"
"$CODEXR" list >/dev/null 2>&1
eq "list: the live auth file is left intact" "rt-acc1-live" "$(jq -r .tokens.refresh_token "$CODEX_HOME/auth.json")"

# list -c does not call codex
setup
"$CODEXR" list >/dev/null 2>&1
before="$(lines)"
out="$("$CODEXR" list -c 2>&1)"; rc=$?
eq "list -c: exit 0" "0" "$rc"
eq "list -c: does not call codex (line count unchanged)" "$before" "$(lines)"
has "list -c: still shows the saved data" " 70%" "$out"
has "list -c: suggests measuring again" "Oldest data measured at 12/01/1970 08:46 PM" "$out"
CODEXR_NOW=$((1000000 + 20000)); export CODEXR_NOW
out="$("$CODEXR" list -c 2>&1)"
has "list -c: past the 5h reset time it says the data is stale" "stale, past reset time" "$out"
CODEXR_NOW=1000000; export CODEXR_NOW
setup
out="$("$CODEXR" list -c 2>&1)"
has "list -c when nothing was ever measured" "No quota data yet" "$out"
has "list -c: status 'not measured'" "not measured" "$out"
"$CODEXR" list --bogus >/dev/null 2>&1; eq "list: unknown argument -> exit 2" "2" "$?"
"$CODEXR" quota >/dev/null 2>&1; eq "the quota command is gone -> exit 2" "2" "$?"

# out of 5h quota -> automatic cooldown, and next skips it
setup
export FAKE_ZERO_TOKENS="acc2"
out="$("$CODEXR" list 2>&1)"
has "list: 0% -> cooldown status" "cooldown, 5h00m left" "$out"
eq "list: 0% -> acc2 cooldown = 5h reset time" "$((1000000 + 18000))" "$(cd_of acc2)"
eq "list: acc1 is not on cooldown" "0" "$(cd_of acc1)"
eq "next skips acc2 (0% quota)" "acc3" "$("$CODEXR" next)"
unset FAKE_ZERO_TOKENS

# measuring a usable account clears a stale cooldown
setup
"$CODEXR" cooldown acc2 5h >/dev/null
out="$("$CODEXR" list 2>&1)"
eq "list: measuring a usable one clears a stale cooldown" "0" "$(cd_of acc2)"
hasnt "list: no cooldown status left" "cooldown" "$out"

# low
setup
export FAKE_LOW_TOKENS="acc3"
out="$("$CODEXR" list 2>&1)"
has "list: under 10% -> 'low'" "low" "$out"
unset FAKE_LOW_TOKENS

# dead account
setup
export FAKE_DEAD_TOKENS="acc2"
out="$("$CODEXR" list 2>&1)"; rc=$?
eq "list: one dead account -> exit 1" "1" "$rc"
has "list: dead account reports measure failed" "measure failed" "$out"
eq "list: the other accounts are still measured (acc3 p5=80)" "80" "$(jq -r '.quota.acc3.p5' "$CODEX_HOME/accounts/state.json")"
eq "list: the dead account has no snapshot" "null" "$(jq -r '.quota.acc2.p5 // null' "$CODEX_HOME/accounts/state.json")"
eq "list: the live auth is still acc1" "acc1" "$(jq -r '.tokens.account_id' "$CODEX_HOME/auth.json")"
unset FAKE_DEAD_TOKENS

# login refreshed during probe (FAKE_REFRESH=1)
setup
export FAKE_REFRESH=1
"$CODEXR" list >/dev/null 2>&1
eq "refresh: non-active slot acc2 gets new access token written back" "at-acc2-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc2.json")"
eq "refresh: non-active slot acc2 gets rotated refresh token written back" "rt-acc2-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc2.json")"
eq "refresh: slot acc3 gets new access token written back" "at-acc3-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc3.json")"
eq "refresh: slot acc3 gets rotated refresh token written back" "rt-acc3-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc3.json")"
eq "refresh: active slot acc1 gets new access token" "at-acc1-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "refresh: active slot acc1 gets rotated refresh token" "rt-acc1-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"
eq "refresh: live auth.json also gets new access token when unchanged" "at-acc1-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
eq "refresh: live auth.json also gets rotated refresh token when unchanged" "rt-acc1-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/auth.json")"
unset FAKE_REFRESH

# live file keeps newer login if changed meanwhile during probe
setup
LIVE_AUTH="$CODEX_HOME/auth.json"
WRAP="$T/wrap-refresh.sh"
cat >"$WRAP" <<EOF
#!/usr/bin/env bash
if [ -n "\${SIM_CONCURRENT_EDIT:-}" ] && [ "\$1" = "-c" ]; then
  jlogin acc1 "rt-acc1-concurrent" > "$LIVE_AUTH"
fi
exec "$CODEXR_BIN" "\$@"
EOF
chmod +x "$WRAP"
SIM_CONCURRENT_EDIT=1 FAKE_REFRESH=1 CODEXR_BIN="$WRAP" "$CODEXR" list >/dev/null 2>&1
eq "refresh: live auth.json keeps newer login when changed meanwhile" "rt-acc1-concurrent" "$(jq -r .tokens.refresh_token "$CODEX_HOME/auth.json")"
eq "refresh: slot acc1 got rotated refresh token" "rt-acc1-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"

# crosstalk prevention (FAKE_CROSSTALK_TOKENS)
setup
export FAKE_CROSSTALK_TOKENS="acc2"
"$CODEXR" list >/dev/null 2>&1
eq "crosstalk: foreign login during probe does not replace slot (acc2)" "rt-acc2" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc2.json")"
eq "crosstalk: foreign login during probe does not touch live auth.json" "rt-acc1" "$(jq -r .tokens.refresh_token "$CODEX_HOME/auth.json")"
eq "crosstalk: no slot holds the intruder's login" "0" "$(grep -l 'intruder' "$CODEX_HOME"/accounts/*.json 2>/dev/null | wc -l | tr -d ' ')"
unset FAKE_CROSSTALK_TOKENS

# missing codex binary -> print saved data
setup
"$CODEXR" list >/dev/null 2>&1
out="$(CODEXR_BIN=/nonexistent/codex "$CODEXR" list 2>&1)"; rc=$?
eq "list: no codex -> still exit 0" "0" "$rc"
has "list: no codex -> warning" "codex not found" "$out"
has "list: no codex -> still shows the saved data" " 70%" "$out"

# no accounts yet
setup
rm -rf "$CODEX_HOME/accounts"
out="$("$CODEXR" list 2>&1)"; rc=$?
eq "list: no accounts -> exit 0" "0" "$rc"
has "list: no accounts -> instructions" "no accounts yet" "$out"

echo "== terminal"
if command -v script >/dev/null; then
  setup
  export FAKE_TTY=1
  cat >"$T/tty.sh" <<EOS
snap() { stty -a | grep -oE -- '(^|[ ])-?(onlcr|icanon|echo)([ ;]|\$)' | tr -d ' ;' | tr '\n' ' '; }
a="\$(snap)"
"$CODEXR" list >/dev/null 2>&1
b="\$(snap)"
[ -n "\$a" ] && [ "\$a" = "\$b" ] && echo SAME || echo "DIFF: [\$a] -> [\$b]"
EOS
  out="$(script -qec "bash $T/tty.sh" /dev/null 2>&1 | tr -d '\r' | tail -n 1)"
  eq "list: leaves the terminal settings unchanged (parallel codex does not touch the tty)" "SAME" "$out"
  unset FAKE_TTY
else
  echo "  (skipped: no 'script' command)"
fi

echo "== colour"
ESC=$'\033'
GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"; RED="${ESC}[31m"
strip() { sed "s/${ESC}\[[0-9;]*m//g"; }
setup
"$CODEXR" list >/dev/null 2>&1
out="$("$CODEXR" list -c)"
hasnt "not on a terminal -> no colour codes" "$ESC" "$out"
plain="$out"
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "always: >40% -> green" "${GREEN} 60%" "$out"
has "always: the ready status is green" "${GREEN}ready" "$out"
eq "always: with the colour codes stripped it equals the plain output (alignment intact)" "$plain" "$(strip <<<"$out")"
out="$(CODEXR_COLOR=never NO_COLOR= "$CODEXR" list -c)"
hasnt "never: no colour codes" "$ESC" "$out"

setup
FAKE_P5=30 "$CODEXR" list >/dev/null 2>&1
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "always: 11-40% -> yellow" "${YELLOW} 30%" "$out"
setup
FAKE_P5=5 "$CODEXR" list >/dev/null 2>&1
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "always: <=10% -> red" "${RED}  5%" "$out"
has "always: 'low' is red" "${RED}low" "$out"
setup
FAKE_P5=0 "$CODEXR" list >/dev/null 2>&1
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "always: 0% -> red" "${RED}  0%" "$out"
has "always: cooldown is red" "${RED}cooldown" "$out"
setup
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "always: 'not measured' is yellow" "${YELLOW}not measured" "$out"
setup
export FAKE_DEAD_TOKENS="acc2"
out="$(CODEXR_COLOR=always "$CODEXR" list 2>&1)"
has "always: 'measure failed' is red" "${RED}measure failed" "$out"
unset FAKE_DEAD_TOKENS

if command -v script >/dev/null; then
  setup
  "$CODEXR" list >/dev/null 2>&1
  out="$(script -qec "$CODEXR list -c" /dev/null 2>&1)"
  has "on a terminal (auto) -> coloured" "${GREEN}" "$out"
  out="$(NO_COLOR=1 script -qec "$CODEXR list -c" /dev/null 2>&1)"
  hasnt "NO_COLOR -> colour off even on a terminal" "$ESC[3" "$out"
  out="$(CODEXR_COLOR=never script -qec "$CODEXR list -c" /dev/null 2>&1)"
  hasnt "CODEXR_COLOR=never -> colour off even on a terminal" "$ESC[3" "$out"
fi

echo "== list: weekly limit used up"
setup
export FAKE_WEEKLY_HIT_TOKENS="acc2"
out="$("$CODEXR" list 2>&1)"; rc=$?
row2="$(grep '  acc2 ' <<<"$out")"
eq "weekly limit used up: exit 0, not a measuring failure" "0" "$rc"
hasnt "weekly limit used up: not reported as 'measure failed'" "measure failed" "$out"
has "weekly limit used up: status says so, with the time left" "weekly limit reached, 72h00m left" "$row2"
has "weekly limit used up: the weekly column shows 0%" "  0%" "$row2"
eq "weekly limit used up: cooldown until the weekly reset (1000000 + 3 days)" "$((1000000 + 259200))" "$(cd_of acc2)"
eq "weekly limit used up: next skips the account" "acc3" "$("$CODEXR" next)"
has "the other accounts are measured as usual" "60%" "$(grep '\* acc1' <<<"$out")"
out="$("$CODEXR" list -c)"
has "list -c: same status from the saved data" "weekly limit reached" "$(grep '  acc2 ' <<<"$out")"
hasnt "list -c: not stale" "stale" "$(grep '  acc2 ' <<<"$out")"
out="$(CODEXR_COLOR=always "$CODEXR" list -c)"
has "the weekly-limit status is red" "${ESC:-$'\033'}[31mweekly limit reached" "$out"
eq "weekly limit used up: the row is as wide as the others up to the status" "$(grep '  acc3 ' <<<"$("$CODEXR" list -c)" | cut -c1-65 | wc -c | tr -d ' ')" "$(grep '  acc2 ' <<<"$("$CODEXR" list -c)" | cut -c1-65 | wc -c | tr -d ' ')"

unset FAKE_WEEKLY_HIT_TOKENS
out="$("$CODEXR" list 2>&1)"
hasnt "after the weekly reset: no weekly-limit status" "weekly limit reached" "$out"
eq "after the weekly reset: the cooldown is cleared" "0" "$(cd_of acc2)"
eq "after the weekly reset: the weekly number is back" "60" "$(jq -r .quota.acc2.pw "$CODEX_HOME/accounts/state.json")"

setup
export FAKE_DEAD_TOKENS="acc3"
"$CODEXR" list >/dev/null 2>&1; eq "a dead account is still a measuring failure (exit 1)" "1" "$?"
unset FAKE_DEAD_TOKENS

echo "== list: rows ordered by the weekly reset time"
order_of() { grep -oE '[│ ]*[ *] +acc[0-9]' <<<"$1" | tr -d '│ *' | tr '\n' ' '; }
setup
export FAKE_WEEK_ORDER=1
out="$("$CODEXR" list 2>/dev/null)"
eq "list: soonest weekly reset first (acc3, acc2, acc1; not by name)" "acc3 acc2 acc1 " "$(order_of "$out")"
eq "list -c: same order from the saved data" "acc3 acc2 acc1 " "$(order_of "$("$CODEXR" list -c)")"
has "list: the selected account keeps its * wherever it lands" "* acc1" "$out"

# an account that was never measured goes last
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" test acc2 >/dev/null 2>&1
eq "list -c: the measured account first, never-measured ones after it by name" "acc2 acc1 acc3 " "$(order_of "$("$CODEXR" list -c)")"

# an account that fails to measure goes last, even if its week would reset first
setup
export FAKE_WEEK_ORDER=1 FAKE_DEAD_TOKENS="acc3"
eq "list: an account that failed to measure is listed last" "acc2 acc1 acc3 " "$(order_of "$("$CODEXR" list 2>/dev/null)")"
unset FAKE_DEAD_TOKENS

# ... also when it has an older snapshot whose week would reset first (stale numbers must not decide the position)
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" list >/dev/null 2>&1
eq "list: with a snapshot, acc3 (earliest week) is first" "acc3 acc2 acc1 " "$(order_of "$("$CODEXR" list -c)")"
export FAKE_DEAD_TOKENS="acc3"
eq "list: a failed account with an old, earliest snapshot is still listed last" "acc2 acc1 acc3 " "$(order_of "$("$CODEXR" list 2>/dev/null)")"
unset FAKE_DEAD_TOKENS

# without differences the order is by name
setup
unset FAKE_WEEK_ORDER
eq "list: equal weekly resets are ordered by name" "acc1 acc2 acc3 " "$(order_of "$("$CODEXR" list 2>/dev/null)")"

# colours and the list header still line up with the rows
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" list >/dev/null 2>&1
eq "list: the table has one row per account plus the header" "4" "$("$CODEXR" list -c | grep -cE '[│ ]*(ACCOUNT|acc[0-9])')"
has "list: header separator" "├" "$("$CODEXR" list -c)"
unset FAKE_WEEK_ORDER
has "help list: says how the rows are ordered" "ordered by when the weekly limit resets" "$("$CODEXR" help list)"

echo "== test (Hi to every account)"
hi_lines() { grep -F -- '|exec ' "$FAKE_ARGS_LOG"; }
hi_count() { hi_lines | wc -l | tr -d ' '; }
setup
mkdir -p "$T/tmp"
out="$(TMPDIR="$T/tmp" "$CODEXR" test 2>"$T/test.err")"; rc=$?
err="$(cat "$T/test.err")"
eq "test: exit 0" "0" "$rc"
has "test: heads-up on stderr that it uses real quota" "one real request each" "$err"
has "test: table header ACCOUNT" "ACCOUNT" "$out"
has "test: table header HI" "HI" "$out"
has "test: table header CODEX 5H" "CODEX 5H" "$out"
has "test: table header RESETS" "RESETS" "$out"
eq "test: all three accounts answered" "3" "$(grep -c 'ok in' <<<"$out")"
has "test: acc1 5h before>after" "60%>60%" "$out"
has "test: acc2 5h before>after" "70%>70%" "$out"
has "test: acc3 5h before>after" "80%>80%" "$out"
has "test: shows the reset time" "13/01/1970 01:46 AM" "$out"
eq "test: exactly one Hi per account" "3" "$(hi_count)"
has "test: header separator" "├" "$out"
eq "test: each Hi uses its own account's login" "acc1 acc2 acc3 " "$(hi_lines | cut -d'|' -f1 | sort | tr '\n' ' ')"
eq "test: every Hi uses gpt-6-luna" "3" "$(hi_lines | grep -c -- '-m gpt-6-luna')"
eq "test: every Hi uses model_reasoning_effort=low" "3" "$(hi_lines | grep -c -- 'model_reasoning_effort=low')"
hasnt "test: Hi never gets dangerous permissions" "--dangerously-bypass-approvals-and-sandbox" "$(hi_lines)"
eq "test: quota is measured before and after each Hi (2 per account)" "6" "$(grep -cF -- '|app-server' "$FAKE_ARGS_LOG")"
eq "test: the new 5h % is saved" "60" "$(jq -r .quota.acc1.p5 "$CODEX_HOME/accounts/state.json")"
eq "test: the account in use does not change" "acc1" "$("$CODEXR" active)"
eq "test: the real auth file is untouched" "acc1" "$(jq -r .tokens.account_id "$CODEX_HOME/auth.json")"
eq "test: no temp directory left behind in TMPDIR" "0" "$(ls -A "$T/tmp" 2>/dev/null | wc -l | tr -d ' ')"
hasnt "test: does not print any token" "rt-" "$out"

# accounts on cooldown are skipped when no names are given
setup
"$CODEXR" cooldown acc2 2h >/dev/null
out="$("$CODEXR" test 2>/dev/null)"; rc=$?
eq "test: exit 0 with a skipped account" "0" "$rc"
has "test: says acc2 is skipped because of its cooldown" "skipped (cooldown, 2h00m left)" "$out"
eq "test: only the other two got a Hi" "2" "$(hi_count)"
hasnt "test: acc2 got no Hi" "acc2|" "$(hi_lines)"
eq "test: acc2's cooldown is kept" "$((1000000 + 7200))" "$(cd_of acc2)"

# a named account is always tried; the fresh measurement clears a cooldown that was wrong
setup
"$CODEXR" cooldown acc2 2h >/dev/null
out="$("$CODEXR" test acc2 2>/dev/null)"; rc=$?
eq "test <name>: exit 0" "0" "$rc"
eq "test <name>: only that account got a Hi" "1" "$(hi_count)"
has "test <name>: it was sent to acc2" "acc2|" "$(hi_lines)"
hasnt "test <name>: the other accounts are not listed" "acc1" "$out"
eq "test <name>: it still had quota, so the cooldown is cleared" "0" "$(cd_of acc2)"
"$CODEXR" test acc1 acc3 acc1 >/dev/null 2>&1
eq "test <names>: two more Hi, a repeated name counts once" "3" "$(hi_count)"
n0="$(lines)"
out="$("$CODEXR" test nope 2>&1)"; rc=$?
eq "test <unknown slot> -> exit 1" "1" "$rc"
has "test <unknown slot>: says so" "no slot 'nope'" "$out"
"$CODEXR" test acc1 '../x' >/dev/null 2>&1; eq "test with an invalid name -> exit 1" "1" "$?"
eq "test: refused names start no codex" "$n0" "$(lines)"

# the reset time before the Hi is shown when the Hi moved it
setup
out="$("$CODEXR" test acc1 2>/dev/null)"
hasnt "test: no '(was ...)' on the account's row when the reset time did not move" "(was" "$(grep '  acc1 ' <<<"$out")"
setup
export FAKE_HI_SHIFT=1
out="$("$CODEXR" test acc1 2>/dev/null)"
has "test: the new reset time is shown (01:46 AM + 10 min)" "01:56 AM" "$(grep '  acc1 ' <<<"$out")"
has "test: and the time before it, because the Hi moved it" "(was 01:46 AM)" "$(grep '  acc1 ' <<<"$out")"
unset FAKE_HI_SHIFT

# an account whose Hi fails
setup
export FAKE_HI_ERROR_TOKENS="acc2"
out="$("$CODEXR" test 2>/dev/null)"; rc=$?
eq "test: an account that cannot answer -> exit 1" "1" "$rc"
has "test: shows the error of that account" "failed: You've hit your usage limit" "$out"
eq "test: the other two still answered" "2" "$(grep -c 'ok in' <<<"$out")"
unset FAKE_HI_ERROR_TOKENS

# a codex that hangs is cut off by the timeout (and does not stall the others)
setup
export FAKE_QUOTA_TOKENS="acc1" CODEXR_TEST_TIMEOUT=2
start=$SECONDS
out="$("$CODEXR" test acc1 acc2 2>/dev/null)"; rc=$?
elapsed=$((SECONDS - start))
eq "test: a hanging codex -> exit 1" "1" "$rc"
has "test: says codex gave no answer" "codex gave no answer" "$out"
eq "test: the other account still answered" "1" "$(grep -c 'ok in' <<<"$out")"
[ "$elapsed" -lt 20 ] && pass "test: the hang was cut off by CODEXR_TEST_TIMEOUT (${elapsed}s)" || fail "test: the hang was cut off by CODEXR_TEST_TIMEOUT" "took ${elapsed}s"
sleep 0.5
eq "test: no fake-codex process left behind" "0" "$(pgrep -fc "$CODEXR_BIN" || true)"
unset FAKE_QUOTA_TOKENS CODEXR_TEST_TIMEOUT

# every account on cooldown: nothing is sent
setup
for a in acc1 acc2 acc3; do "$CODEXR" cooldown "$a" 2h >/dev/null; done
n0="$(lines)"
out="$("$CODEXR" test 2>&1)"; rc=$?
eq "test: all on cooldown -> exit 0" "0" "$rc"
has "test: says there is nothing to do" "nothing to do" "$out"
eq "test: nothing was sent" "$n0" "$(lines)"

# no codex / no accounts
setup
out="$(CODEXR_BIN=/nonexistent/codex "$CODEXR" test 2>&1)"; rc=$?
eq "test: no codex -> exit 1" "1" "$rc"
has "test: no codex -> message" "codex not found" "$out"
rm -rf "$CODEX_HOME/accounts"
out="$("$CODEXR" test 2>&1)"; rc=$?
eq "test: no accounts -> exit 0" "0" "$rc"
has "test: no accounts -> hint" "no accounts yet" "$out"

# help
setup
n0="$(lines)"
"$CODEXR" test --help >/dev/null 2>&1
eq "test --help sends nothing" "$n0" "$(lines)"
out="$("$CODEXR" help test)"
has "help test: warns that it is a real request" "ONE REAL REQUEST" "$out"
has "help test: names the model" "gpt-6-luna" "$out"
has "help test: says the window idea is an assumption to check" "THAT IS AN ASSUMPTION" "$out"
hasnt "help test: no unsupported claim that was observed" "Observed:" "$out"
has "help test: documents the timeout variable" "CODEXR_TEST_TIMEOUT" "$out"
has "overview describes test" "Send \"Hi\" to every account" "$("$CODEXR" help)"

echo "== responsive terminal width (-w / --wide)"
setup
"$CODEXR" list >/dev/null 2>&1
# At 100 columns: PLAN is hidden
out="$(CODEXR_RESPONSIVE=1 CODEXR_COLUMNS=100 "$CODEXR" list -c)"
hasnt "responsive 100: PLAN hidden" "PLAN" "$out"
has "responsive 100: has STATUS" "STATUS" "$out"
has "responsive 100: has CODEX 5H" "CODEX 5H" "$out"
has "responsive 100: has CODEX WEEK" "CODEX WEEK" "$out"
has "responsive 100: notes hidden PLAN column" "Note: PLAN column hidden to fit terminal width 100" "$out"

# With -w: forced full width
out="$("$CODEXR" list -c -w)"
has "responsive -w: PLAN shown" "PLAN" "$out"
has "responsive -w: CODEX 5H shown" "CODEX 5H" "$out"
has "responsive -w: CODEX WEEK shown" "CODEX WEEK" "$out"
hasnt "responsive -w: no hidden note" "column hidden" "$out"

# At 140 columns: PLAN kept
out="$(CODEXR_RESPONSIVE=1 CODEXR_COLUMNS=140 "$CODEXR" list -c)"
has "responsive 140: PLAN shown" "PLAN" "$out"
has "responsive 140: CODEX 5H shown" "CODEX 5H" "$out"
has "responsive 140: CODEX WEEK shown" "CODEX WEEK" "$out"
hasnt "responsive 140: no hidden note" "column hidden" "$out"

# codexr test responsive
setup
out="$(CODEXR_COLOR=never CODEXR_RESPONSIVE=1 CODEXR_COLUMNS=90 "$CODEXR" test 2>/dev/null)"
has "test responsive 90: header has RESETS" "RESETS" "$out"
has "test responsive 90: header has HI" "HI" "$out"

out_wide="$(CODEXR_COLOR=never CODEXR_RESPONSIVE=1 CODEXR_COLUMNS=90 "$CODEXR" test -w 2>/dev/null)"
has "test responsive -w: header has RESETS" "RESETS" "$out_wide"
has "test responsive -w: header has HI" "HI" "$out_wide"

has "help list: mentions -w" "-w, --wide" "$("$CODEXR" help list)"
hasnt "help list: does not mention --claude" "--claude" "$("$CODEXR" help list)"
has "help test: mentions -w" "-w, --wide" "$("$CODEXR" help test)"
