# Core tests for codexr (platform-independent).
# Sourced by test/core.sh via test/run.sh.

echo "== codexr"

setup
out="$("$CODEXR" list -c)"
has "list -c: acc1 is active" "* acc1" "$out"
has "list -c: acc2 is listed" "  acc2" "$out"
eq "active = acc1" "acc1" "$("$CODEXR" active)"
if [ "$ON_WINDOWS" = 1 ]; then
  echo "  skip file modes 600/700: NTFS has no POSIX permission bits (the profile folder's ACL protects the files)"
else
  eq "slot mode is 600" "600" "$(stat -c %a "$CODEX_HOME/accounts/acc1.json")"
  eq "accounts dir mode is 700" "700" "$(stat -c %a "$CODEX_HOME/accounts")"
  eq "live auth.json mode is 600" "600" "$(stat -c %a "$CODEX_HOME/auth.json")"
fi
eq "token is correct after use" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"

out="$("$CODEXR" save acc9 2>&1)"
hasnt "save does not print the token" "at-" "$out"
hasnt "save does not print the token (jwt)" "eyJ" "$out"
"$CODEXR" use acc1 >/dev/null

setup
# simulate codex refreshing the tokens in place (same sub acc1, new access_token and rotated refresh_token)
jlogin acc1 "rt-acc1-rotated" | jq '.tokens.access_token = "at-acc1-refreshed"' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" use acc2 2>&1)"
hasnt "use does not print the token" "at-acc" "$out"
hasnt "use does not print the token (jwt)" "eyJ" "$out"
eq "use: token = slot acc2" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
eq "use: refreshed token synced back to acc1" "at-acc1-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "use: token backed up before overwrite" "at-acc1-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/.last-token.bak")"
eq "use: active = acc2" "acc2" "$("$CODEXR" active)"

"$CODEXR" use nope >/dev/null 2>&1; eq "use of a missing slot -> error" "1" "$?"
"$CODEXR" use '../x' >/dev/null 2>&1; eq "invalid account name -> error" "1" "$?"
"$CODEXR" bogus >/dev/null 2>&1; eq "unknown command -> exit 2" "2" "$?"
"$CODEXR" backend >/dev/null 2>&1; eq "codexr backend is an unknown command -> exit 2" "2" "$?"

echo "== account identity (JWT sub claim)"
setup
# 1. active follows identity (same sub, rotated refresh_token)
jlogin acc1 "rt-acc1-rotated" | jq '.tokens.access_token = "at-acc1-rotated"' > "$CODEX_HOME/auth.json"
eq "identity: active follows sub claim despite rotated refresh_token" "acc1" "$("$CODEXR" active)"

# 2. use syncs back to slot matching identity
"$CODEXR" use acc2 >/dev/null
eq "identity: use syncs rotated tokens back to slot matching sub" "at-acc1-rotated" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "identity: use syncs rotated refresh_token back to slot matching sub" "rt-acc1-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"

# 3. del recognises active account by identity
jlogin acc2 "rt-acc2-rotated" > "$CODEX_HOME/auth.json"
out="$("$CODEXR" del acc2 2>&1)"
has "identity: del recognises active account by sub and clears live login" "deleted account 'acc2' (and cleared active login)" "$out"
eq "identity: del cleared live auth.json" "no" "$([ -e "$CODEX_HOME/auth.json" ] && echo yes || echo no)"

# 4. rename follows identity
setup
jlogin acc1 "rt-acc1-rotated" > "$CODEX_HOME/auth.json"
"$CODEXR" rename acc1 primary >/dev/null
eq "identity: active follows renamed slot matching sub" "primary" "$("$CODEXR" active)"

# 5. different subs are different accounts
setup
jlogin diffsub "rt-acc1" | jq '.tokens.access_token = "at-diffsub"' > "$CODEX_HOME/auth.json"
"$CODEXR" use acc2 >/dev/null
eq "identity: different sub does not overwrite acc1 slot" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "identity: different sub is kept in .last-token.bak" "at-diffsub" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/.last-token.bak")"

echo "== invalid logins (api_key and missing id_token)"
setup
# 1. API-key auth_mode refused by save
jq -n '{auth_mode: "api_key", OPENAI_API_KEY: "sk-secret-token-key-12345", tokens: null}' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" save apikey_slot 2>&1)"; rc=$?
eq "save: refuses auth_mode api_key (exit 1)" "1" "$rc"
has "save: api_key error message" "API-key logins are not supported" "$out"
hasnt "save: does not print api key" "secret" "$out"
hasnt "save: does not print sk-" "sk-" "$out"
eq "save: api_key slot not created" "no" "$([ -e "$CODEX_HOME/accounts/apikey_slot.json" ] && echo yes || echo no)"

# 2. Missing id_token refused by save
jq -n '{auth_mode: "chatgpt", OPENAI_API_KEY: null, tokens: {id_token: "", access_token: "at-secret-token-6789", refresh_token: "rt-secret", account_id: "sec"}, last_refresh: "2026-01-01T00:00:00Z"}' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" save noid_slot 2>&1)"; rc=$?
eq "save: refuses missing id_token (exit 1)" "1" "$rc"
has "save: missing id_token error message" "id_token is missing or empty" "$out"
hasnt "save: does not print token" "secret" "$out"
eq "save: missing id_token slot not created" "no" "$([ -e "$CODEX_HOME/accounts/noid_slot.json" ] && echo yes || echo no)"

# 3. API-key auth_mode refused by use
jq -n '{auth_mode: "api_key", OPENAI_API_KEY: "sk-secret-token-slot-999"}' > "$CODEX_HOME/accounts/badslot.json"
out="$("$CODEXR" use badslot 2>&1)"; rc=$?
eq "use: refuses api_key slot (exit 1)" "1" "$rc"
has "use: api_key error message" "API-key logins are not supported" "$out"
hasnt "use: does not print api key" "secret" "$out"
hasnt "use: does not print sk-" "sk-" "$out"

# 4. Missing id_token refused by use
jq -n '{auth_mode: "chatgpt", OPENAI_API_KEY: null, tokens: {id_token: null, access_token: "at-secret-token-bad"}}' > "$CODEX_HOME/accounts/badslot2.json"
out="$("$CODEXR" use badslot2 2>&1)"; rc=$?
eq "use: refuses slot with null id_token (exit 1)" "1" "$rc"
has "use: missing id_token error message" "id_token is missing or empty" "$out"
hasnt "use: does not print token" "secret" "$out"
rm -f "$CODEX_HOME/accounts/badslot.json" "$CODEX_HOME/accounts/badslot2.json"

echo "== sync"
setup
# Refreshed live login matching acc1 identity
jlogin acc1 "rt-acc1-synced" | jq '.tokens.access_token = "at-acc1-synced"' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" sync 2>&1)"; rc=$?
eq "sync: matching identity exit 0" "0" "$rc"
eq "sync: matching identity is silent" "" "$out"
eq "sync: writes refreshed access_token to slot" "at-acc1-synced" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "sync: writes refreshed refresh_token to slot" "rt-acc1-synced" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"

# Refreshed live login matching NO slot
jlogin stranger "rt-stranger" | jq '.tokens.access_token = "at-stranger"' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" sync 2>&1)"; rc=$?
eq "sync: unmatched identity exit 0" "0" "$rc"
eq "sync: unmatched identity is silent" "" "$out"
eq "sync: unmatched identity does not modify acc1 slot" "at-acc1-synced" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "sync: unmatched identity does not modify acc2 slot" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc2.json")"
eq "sync: unmatched identity does not modify acc3 slot" "at-acc3" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc3.json")"

# Missing auth.json
rm -f "$CODEX_HOME/auth.json"
out="$("$CODEXR" sync 2>&1)"; rc=$?
eq "sync: missing auth.json exit 0" "0" "$rc"
eq "sync: missing auth.json is silent" "" "$out"

echo "== cooldown / next"
setup
"$CODEXR" cooldown acc1 "Resets in 4h13m27s" >/dev/null
eq "parse 4h13m27s" "$((1000000 + 15207))" "$(cd_of acc1)"
"$CODEXR" cooldown acc1 "43m29s" >/dev/null;  eq "parse 43m29s" "$((1000000 + 2609))" "$(cd_of acc1)"
"$CODEXR" cooldown acc1 90 >/dev/null;        eq "parse plain seconds" "$((1000000 + 90))" "$(cd_of acc1)"
"$CODEXR" cooldown acc1 "1d2h" >/dev/null;    eq "parse 1d2h" "$((1000000 + 93600))" "$(cd_of acc1)"
"$CODEXR" cooldown acc1 "error: Individual quota reached. Resets in 2h. (x)" >/dev/null
eq "parse a whole error sentence" "$((1000000 + 7200))" "$(cd_of acc1)"
out="$("$CODEXR" cooldown acc1 "gibberish" 2>&1)"
eq "unparsable -> default 5h" "$((1000000 + 18000))" "$(cd_of acc1)"
has "warns when the duration cannot be parsed" "default 5h" "$out"
"$CODEXR" clear acc1 >/dev/null; eq "clear removes the cooldown" "0" "$(cd_of acc1)"

# cooldown without duration (uses app-server probe)
setup
export FAKE_ZERO_TOKENS="acc2"
"$CODEXR" cooldown acc2 >/dev/null
eq "cooldown without duration: 5h exhausted ends at 5h reset" "$((1000000 + 18000))" "$(cd_of acc2)"
unset FAKE_ZERO_TOKENS

setup
export FAKE_WEEKLY_HIT_TOKENS="acc2"
"$CODEXR" cooldown acc2 >/dev/null
eq "cooldown without duration: weekly exhausted ends at weekly reset" "$((1000000 + 259200))" "$(cd_of acc2)"
unset FAKE_WEEKLY_HIT_TOKENS

setup
export FAKE_DEAD_TOKENS="acc2"
export CODEXR_PROBE_TIMEOUT=1
"$CODEXR" cooldown acc2 >/dev/null
eq "cooldown without duration: probe failure falls back to 5h" "$((1000000 + 18000))" "$(cd_of acc2)"
unset FAKE_DEAD_TOKENS CODEXR_PROBE_TIMEOUT

setup
eq "next from acc1 (no cooldown) = acc2" "acc2" "$("$CODEXR" next)"
"$CODEXR" use acc3 >/dev/null; eq "next from acc3 wraps to acc1" "acc1" "$("$CODEXR" next)"
"$CODEXR" use acc1 >/dev/null
"$CODEXR" cooldown acc2 2h >/dev/null
eq "next skips acc2 on cooldown" "acc3" "$("$CODEXR" next)"
"$CODEXR" cooldown acc3 1h >/dev/null
eq "next comes back to acc1 (active, still ready)" "acc1" "$("$CODEXR" next)"
"$CODEXR" cooldown acc1 3h >/dev/null
out="$("$CODEXR" next 2>&1)"; rc=$?
eq "whole pool on cooldown -> exit 3" "3" "$rc"
has "reports the earliest-resetting account" "'acc3'" "$out"
out="$("$CODEXR" list -c)"
has "list -c shows cooldown" "cooldown" "$out"
CODEXR_NOW=$((1000000 + 3601)); export CODEXR_NOW
eq "acc3's cooldown is over after 1h" "acc3" "$("$CODEXR" next)"
CODEXR_NOW=1000000; export CODEXR_NOW

echo "== rotate"
setup
export FAKE_ZERO_TOKENS="acc1"
out="$("$CODEXR" rotate 2>&1)"; rc=$?
eq "rotate: exit 0" "0" "$rc"
eq "rotate: acc1 cooldown from probe = 5h reset" "$((1000000 + 18000))" "$(cd_of acc1)"
eq "rotate: switches to acc2" "acc2" "$("$CODEXR" active)"
eq "rotate: token = acc2" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
has "rotate: tells you to reopen with codexr -c" "codexr -c" "$out"
hasnt "rotate: does not print token" "at-" "$out"
hasnt "rotate: does not print token (jwt)" "eyJ" "$out"
unset FAKE_ZERO_TOKENS

setup
"$CODEXR" rotate 1h >/dev/null 2>&1
eq "rotate: a manually given duration overrides the probe" "$((1000000 + 3600))" "$(cd_of acc1)"
eq "rotate (manual 1h): switches to acc2" "acc2" "$("$CODEXR" active)"

setup
export FAKE_DEAD_TOKENS="acc1"
export CODEXR_PROBE_TIMEOUT=1
out="$("$CODEXR" rotate 2>&1)"; rc=$?
eq "rotate: probe failure uses default 5h (exit 0)" "0" "$rc"
eq "rotate: acc1 cooldown falls back to 5h" "$((1000000 + 18000))" "$(cd_of acc1)"
eq "rotate: switches to acc2" "acc2" "$("$CODEXR" active)"
unset FAKE_DEAD_TOKENS CODEXR_PROBE_TIMEOUT

setup
"$CODEXR" cooldown acc2 3h >/dev/null; "$CODEXR" cooldown acc3 2h >/dev/null
out="$("$CODEXR" rotate 1h 2>&1)"; rc=$?
eq "rotate: whole pool on cooldown -> exit 3" "3" "$rc"
eq "rotate: whole pool on cooldown does not switch the token" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"

setup
rm -f "$CODEX_HOME/accounts/state.json" "$CODEX_HOME/auth.json"
"$CODEXR" rotate >/dev/null 2>&1; eq "rotate: no active account -> error" "1" "$?"

echo "== real token file out of sync with state (manual login without save)"
setup
# you log in by hand as acc2 (saved earlier, sub matches slot acc2) but state still says acc1
jlogin acc2 "rt-acc2-newer" | jq '.tokens.access_token = "at-acc2-newer"' > "$CODEX_HOME/auth.json"
eq "active is derived from the real auth file (acc2), not from state (acc1)" "acc2" "$("$CODEXR" active)"
eq "state still says acc1 (kept only as a fallback)" "acc1" "$(jq -r .active "$CODEX_HOME/accounts/state.json")"
out="$("$CODEXR" list 2>&1)"
has "list: * is on acc2 (the real owner of the auth file)" "* acc2" "$out"
hasnt "list: acc1 no longer has *" "* acc1" "$out"
eq "list: acc1 measures 60% (not mixed up with acc2's numbers)" "60" "$(jq -r .quota.acc1.p5 "$CODEX_HOME/accounts/state.json")"
eq "list: acc2 measures 70%" "70" "$(jq -r .quota.acc2.p5 "$CODEX_HOME/accounts/state.json")"
"$CODEXR" use acc3 >/dev/null
eq "use: acc2's fresh token is written back to slot acc2" "at-acc2-newer" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc2.json")"
eq "use: slot acc1 is NOT overwritten with acc2's token" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "use: slot acc1 still has acc1's refresh_token" "rt-acc1" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"

# log in to an account that was never saved: matches no slot
setup
jlogin brandnew "rt-new" | jq '.tokens.access_token = "at-new"' > "$CODEX_HOME/auth.json"
out="$("$CODEXR" list 2>&1)"
hasnt "list: no * when the token matches no slot" "* acc" "$out"
has "list: warns that the token matches no slot" "matches no slot" "$out"
"$CODEXR" use acc2 >/dev/null
eq "use: an unknown token does not overwrite slot acc1" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "use: an unknown token does not overwrite slot acc2 (it keeps its own)" "rt-acc2" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc2.json")"
eq "use: the unknown token is kept in .last-token.bak" "at-new" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/.last-token.bak")"

echo "== UTC+7 timezone"
setup
# CODEXR_NOW=1000000 = 1970-01-12 13:46:40 UTC; +1h = 14:46 UTC = 21:46 in UTC+7 = 09:46 PM
out="$(TZ=UTC "$CODEXR" cooldown acc1 1h)"
has "times are always UTC+7 even when TZ in the environment is UTC" "12/01/1970 09:46 PM" "$out"
out="$(TZ=America/New_York "$CODEXR" list)"
has "list is also UTC+7 when TZ in the environment differs" "Measured at 12/01/1970 08:46 PM" "$out"
has "list: the measured-at time is UTC+7 (jq/date)" "Measured at 12/01/1970 08:46 PM" "$out"
out="$(TZ=UTC CODEXR_TZ=UTC "$CODEXR" cooldown acc1 1h)"
has "CODEXR_TZ changes the displayed timezone" "12/01/1970 02:46 PM" "$out"
out="$("$CODEXR" cooldown acc1 10h)"
has "dd/mm/yyyy hh:mm AM format (morning, next day)" "13/01/1970 06:46 AM" "$out"
out="$(LC_ALL=C LC_TIME=de_DE.UTF-8 "$CODEXR" cooldown acc1 1h)"
has "AM/PM does not depend on the machine's locale" "09:46 PM" "$out"

echo "== rename"
setup
"$CODEXR" list >/dev/null 2>&1   # saves quota snapshots (and, measuring real quota, clears cooldowns)
"$CODEXR" cooldown acc2 2h >/dev/null
n0="$(lines)"
tok2="$(cat "$CODEX_HOME/accounts/acc2.json")"
out="$("$CODEXR" rename acc2 renamed 2>&1)"; rc=$?
eq "rename: exit 0" "0" "$rc"
has "rename: confirms" "renamed slot 'acc2' to 'renamed'" "$out"
eq "rename: the old slot file is gone" "no" "$([ -e "$CODEX_HOME/accounts/acc2.json" ] && echo yes || echo no)"
eq "rename: the login moved to the new slot unchanged" "$tok2" "$(cat "$CODEX_HOME/accounts/renamed.json")"
if [ "$ON_WINDOWS" = 0 ]; then
  eq "rename: the new slot is mode 600" "600" "$(stat -c %a "$CODEX_HOME/accounts/renamed.json")"
fi
eq "rename: the cooldown moved" "$((1000000 + 7200))" "$(cd_of renamed)"
eq "rename: the old name has no cooldown left" "0" "$(cd_of acc2)"
eq "rename: the quota snapshot moved" "70" "$(jq -r '.quota.renamed.p5' "$CODEX_HOME/accounts/state.json")"
eq "rename: the old name has no quota snapshot left" "null" "$(jq -r '.quota.acc2.p5 // null' "$CODEX_HOME/accounts/state.json")"
eq "rename: other slots are untouched (acc1 still has its login)" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "rename: other slots keep their quota snapshot" "60" "$(jq -r '.quota.acc1.p5' "$CODEX_HOME/accounts/state.json")"
eq "rename: the real auth file is untouched" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
eq "rename: codex is not started" "$n0" "$(lines)"
out="$("$CODEXR" list -c)"
has "rename: list shows the new name" "renamed" "$out"
hasnt "rename: list no longer shows the old name" "acc2 " "$out"
eq "rename: 'use' works with the new name" "switched to account 'renamed'" "$("$CODEXR" use renamed)"
eq "rename: active follows the login" "renamed" "$("$CODEXR" active)"

# renaming the active account moves the "active" mark
setup
"$CODEXR" rename acc1 main >/dev/null
eq "rename: the active account keeps being active under its new name" "main" "$("$CODEXR" active)"
eq "rename: state.active follows" "main" "$(jq -r .active "$CODEX_HOME/accounts/state.json")"

# refusals change nothing
setup
before="$(ls "$CODEX_HOME/accounts" | tr '\n' ' ')"; state_before="$(cat "$CODEX_HOME/accounts/state.json")"
out="$("$CODEXR" rename acc2 acc3 2>&1)"; rc=$?
eq "rename onto an existing slot -> exit 1" "1" "$rc"
has "rename onto an existing slot: says so" "already exists" "$out"
eq "rename onto an existing slot: acc3 keeps its own login" "at-acc3" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc3.json")"
eq "rename onto an existing slot: acc2 keeps its login" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc2.json")"
"$CODEXR" rename nope other >/dev/null 2>&1; eq "rename of a missing slot -> exit 1" "1" "$?"
out="$("$CODEXR" rename acc1 acc1 2>&1)"; rc=$?
eq "rename to the same name -> exit 1" "1" "$rc"
has "rename to the same name: says so" "same" "$out"
"$CODEXR" rename acc1 '../x' >/dev/null 2>&1; eq "rename to an invalid name -> exit 1" "1" "$?"
"$CODEXR" rename '../x' acc9 >/dev/null 2>&1; eq "rename from an invalid name -> exit 1" "1" "$?"
"$CODEXR" rename acc1 >/dev/null 2>&1; eq "rename with one argument -> exit 1" "1" "$?"
out="$("$CODEXR" rename 2>&1)"; rc=$?
eq "rename without arguments -> exit 1" "1" "$rc"
has "rename without arguments: usage" "usage: codexr rename <old> <new>" "$out"
eq "refusals leave every slot file as it was" "$before" "$(ls "$CODEX_HOME/accounts" | tr '\n' ' ')"
eq "refusals leave state.json as it was" "$state_before" "$(cat "$CODEX_HOME/accounts/state.json")"
# --help has no side effects
"$CODEXR" rename --help >/dev/null 2>&1
eq "rename --help does not rename anything" "$before" "$(ls "$CODEX_HOME/accounts" | tr '\n' ' ')"
out="$("$CODEXR" help rename)"
has "help rename: usage line" "Usage: codexr rename <old> <new>" "$out"
has "help rename: mentions that it refuses an existing name" "already exists" "$out"

echo "== forget"
setup
n0="$(lines)"
out="$("$CODEXR" forget 2>&1)"
has "forget: tells to log in with codexr" "run 'codexr' to log in" "$out"
eq "forget: the active mark is cleared" "" "$(jq -r .active "$CODEX_HOME/accounts/state.json")"
eq "forget: 'codexr active' prints nothing" "" "$("$CODEXR" active)"
for a in acc1 acc2 acc3; do eq "forget: slot $a is kept" "at-$a" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/$a.json")"; done
eq "forget: codex is not started" "$n0" "$(lines)"
out="$("$CODEXR" list -c 2>&1)"; rc=$?
eq "forget: list -c still works" "0" "$rc"
hasnt "forget: nothing is marked * (no login)" "* acc" "$out"
runit; rc=$?
eq "forget: codex-run refuses to start without a login (exit 4)" "4" "$rc"
eq "forget: codex-run did not start codex" "$n0" "$(lines)"
"$CODEXR" use acc2 >/dev/null
eq "forget: 'use' logs in again from a slot" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
eq "forget: and active is acc2 again" "acc2" "$("$CODEXR" active)"

# -f is accepted like --force
setup
jlogin brandnew "rt-new" | jq '.tokens.access_token = "at-new"' > "$CODEX_HOME/auth.json"
"$CODEXR" forget >/dev/null 2>&1; eq "forget: an unsaved login is refused (exit 1)" "1" "$?"
eq "forget: the unsaved login is still there after the refusal" "at-new" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
"$CODEXR" forget -f >/dev/null 2>&1; eq "forget -f: accepted like --force (exit 0)" "0" "$?"
eq "forget -f: the auth file is gone" "no" "$([ -e "$CODEX_HOME/auth.json" ] && echo yes || echo no)"
eq "forget -f: a copy of the dropped login is in .last-token.bak" "at-new" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/.last-token.bak")"
eq "forget -f: no slot was overwritten" "rt-acc1" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"

# no login at all still clears the active mark
setup
rm -f "$CODEX_HOME/auth.json"
"$CODEXR" forget >/dev/null 2>&1; eq "forget without a login: exit 0" "0" "$?"

# usage, help and side effects
setup
out="$("$CODEXR" forget extra 2>&1)"; rc=$?
eq "forget with an extra argument -> exit 2" "2" "$rc"
has "forget with an extra argument: usage" "usage: codexr forget [-f|--force]" "$out"
eq "forget with an extra argument: auth file untouched" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
"$CODEXR" forget --help >/dev/null 2>&1
eq "forget --help does not forget anything" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
out="$("$CODEXR" help forget)"
has "help forget: mentions -f" "-f / --force" "$out"
has "help forget: mentions the active mark" "\"active\" mark" "$out"

echo "== del (rm)"
setup
"$CODEXR" list >/dev/null 2>&1
"$CODEXR" cooldown acc2 2h >/dev/null
out="$("$CODEXR" del acc2 2>&1)"; rc=$?
eq "del non-active: exit 0" "0" "$rc"
has "del non-active: confirms" "deleted account 'acc2'" "$out"
hasnt "del non-active: does not say cleared active" "cleared active" "$out"
eq "del non-active: acc2.json is removed" "no" "$([ -e "$CODEX_HOME/accounts/acc2.json" ] && echo yes || echo no)"
eq "del non-active: cooldown for acc2 removed" "0" "$(cd_of acc2)"
eq "del non-active: quota for acc2 removed" "null" "$(jq -r '.quota.acc2 // null' "$CODEX_HOME/accounts/state.json")"
eq "del non-active: active account acc1 untouched" "acc1" "$("$CODEXR" active)"
eq "del non-active: state active is acc1" "acc1" "$(jq -r .active "$CODEX_HOME/accounts/state.json")"
eq "del non-active: live auth untouched" "at-acc1" "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")"
out_list="$("$CODEXR" list -c)"
hasnt "del non-active: list -c no longer shows acc2" "acc2" "$out_list"
has "del non-active: list -c still shows acc1" "acc1" "$out_list"
has "del non-active: list -c still shows acc3" "acc3" "$out_list"

# Deleting the currently active slot
setup
cp "$CODEX_HOME/accounts/acc1.json" "$CODEX_HOME/accounts/.last-token.bak"
out="$("$CODEXR" del acc1 2>&1)"; rc=$?
eq "del active: exit 0" "0" "$rc"
has "del active: confirms with cleared active login" "deleted account 'acc1' (and cleared active login)" "$out"
eq "del active: acc1.json is removed" "no" "$([ -e "$CODEX_HOME/accounts/acc1.json" ] && echo yes || echo no)"
eq "del active: live auth removed" "no" "$([ -e "$CODEX_HOME/auth.json" ] && echo yes || echo no)"
eq "del active: state.json active is cleared" "" "$(jq -r .active "$CODEX_HOME/accounts/state.json")"
eq "del active: 'codexr active' prints nothing" "" "$("$CODEXR" active)"
eq "del active: .last-token.bak belonging to acc1 is removed" "no" "$([ -e "$CODEX_HOME/accounts/.last-token.bak" ] && echo yes || echo no)"
eq "del active: acc2 slot is kept" "at-acc2" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc2.json")"

# Deleting slot does not remove .last-token.bak if it belongs to a different account
setup
cp "$CODEX_HOME/accounts/acc2.json" "$CODEX_HOME/accounts/.last-token.bak"
out="$("$CODEXR" del acc1 2>&1)"; rc=$?
eq "del active (different bak): exit 0" "0" "$rc"
eq "del active (different bak): .last-token.bak for acc2 is preserved" "yes" "$([ -f "$CODEX_HOME/accounts/.last-token.bak" ] && echo yes || echo no)"

# Alias codexr rm <name> works identically
setup
out="$("$CODEXR" rm acc2 2>&1)"; rc=$?
eq "rm alias: exit 0" "0" "$rc"
has "rm alias: confirms" "deleted account 'acc2'" "$out"
eq "rm alias: acc2.json is removed" "no" "$([ -e "$CODEX_HOME/accounts/acc2.json" ] && echo yes || echo no)"

# Error cases
setup
out="$("$CODEXR" del 2>&1)"; rc=$?
eq "del missing arg -> exit 1" "1" "$rc"
has "del missing arg: usage message" "usage: codexr del <name>" "$out"

out="$("$CODEXR" del nope 2>&1)"; rc=$?
eq "del nonexistent slot -> exit 1" "1" "$rc"
has "del nonexistent slot: error message" "no slot 'nope'" "$out"

out="$("$CODEXR" del '../bad' 2>&1)"; rc=$?
eq "del invalid name -> exit 1" "1" "$rc"
has "del invalid name: error message" "account name may only contain letters" "$out"

# Help checks
out="$("$CODEXR" help del)"
has "help del: usage line" "Usage: codexr del <name>        (alias: rm)" "$out"
has "help del: explains deletion" "Permanently delete slot <name>" "$out"

out="$("$CODEXR" del --help)"
has "del --help: usage line" "Usage: codexr del <name>        (alias: rm)" "$out"

out="$("$CODEXR" rm --help)"
has "rm --help: usage line" "Usage: codexr del <name>        (alias: rm)" "$out"

out="$("$CODEXR" help)"
has "overview includes del" "del <name>" "$out"

echo "== next: the ready account whose weekly limit resets soonest (what codex-run and rotate switch to)"
setup
export FAKE_WEEK_ORDER=1 # weekly resets: acc3 first, then acc2, then acc1
"$CODEXR" list >/dev/null 2>&1
eq "next from acc1: acc3 (soonest weekly reset), not acc2 (name order)" "acc3" "$("$CODEXR" next)"
"$CODEXR" cooldown acc3 2h >/dev/null
eq "next skips an account on cooldown even if its week resets first" "acc2" "$("$CODEXR" next)"
"$CODEXR" clear acc3 >/dev/null
"$CODEXR" use acc3 >/dev/null
eq "next while acc3 is in use: the soonest OTHER account (acc2)" "acc2" "$("$CODEXR" next)"
"$CODEXR" use acc2 >/dev/null
eq "next while acc2 is in use: acc3" "acc3" "$("$CODEXR" next)"
"$CODEXR" use acc1 >/dev/null
"$CODEXR" cooldown acc2 2h >/dev/null; "$CODEXR" cooldown acc3 3h >/dev/null
eq "next: the account in use is returned when nothing else is ready" "acc1" "$("$CODEXR" next)"
"$CODEXR" cooldown acc1 5h >/dev/null
out="$("$CODEXR" next 2>&1)"; rc=$?
eq "next: everything on cooldown -> exit 3" "3" "$rc"
has "next: names the account that resets first" "earliest: 'acc2'" "$out"

# explanation on stderr, name alone on stdout
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" list >/dev/null 2>&1
out="$("$CODEXR" next -v 2>"$T/why.err")"
eq "next -v: stdout is only the name" "acc3" "$out"
has "next -v: says which account and why" "next account 'acc3': weekly limit resets" "$(cat "$T/why.err")"
has "next -v: says it is the soonest of the other ready accounts" "the soonest of the 2 other ready account(s)" "$(cat "$T/why.err")"
"$CODEXR" cooldown acc2 2h >/dev/null; "$CODEXR" cooldown acc3 2h >/dev/null
"$CODEXR" next -v 2>&1 >/dev/null | grep -q "no other account is ready" && pass "next -v: says the one in use stays when nothing else is ready" || fail "next -v: says the one in use stays when nothing else is ready"
out="$("$CODEXR" next --why 2>/dev/null)"; eq "next --why is the same as -v" "acc1" "$out"

# accounts never measured come last
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" test acc3 >/dev/null 2>&1   # only acc3 has numbers now; acc2 sorts before it by name
eq "next: a measured account goes before never-measured ones (acc3, not acc2)" "acc3" "$("$CODEXR" next)"
setup
eq "next: with no numbers at all it falls back to name order (acc2 after acc1)" "acc2" "$("$CODEXR" next)"
"$CODEXR" next -v 2>&1 >/dev/null | grep -q "no quota data yet" && pass "next -v: says there is no quota data yet" || fail "next -v: says there is no quota data yet"

# an account with its weekly limit used up is on cooldown, so it is skipped although its reset comes first
setup
export FAKE_WEEK_ORDER=1 FAKE_WEEKLY_HIT_TOKENS="acc3"
"$CODEXR" list >/dev/null 2>&1
eq "next: the weekly-limit account (acc3, earliest reset) is skipped: acc2" "acc2" "$("$CODEXR" next)"
unset FAKE_WEEKLY_HIT_TOKENS

# rotate uses it
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" list >/dev/null 2>&1
out="$("$CODEXR" rotate 1h 2>&1)"; rc=$?
eq "rotate: exit 0" "0" "$rc"
has "rotate: switched to the soonest weekly reset (acc3)" "switched to account 'acc3'" "$out"
has "rotate: explains the choice" "weekly limit resets" "$out"
eq "rotate: acc1 is on cooldown" "$((1000000 + 3600))" "$(cd_of acc1)"

# codex-run uses it
setup
export FAKE_WEEK_ORDER=1
"$CODEXR" list >/dev/null 2>&1
: >"$FAKE_ARGS_LOG"
export FAKE_QUOTA_TOKENS="acc1"
runit; rc=$?
eq "codex-run: acc1 out of quota -> exit 0" "0" "$rc"
has "codex-run: the second run uses acc3 (soonest weekly reset), not acc2" "acc3|" "$(grep -F '|exec ' "$FAKE_ARGS_LOG" | sed -n 2p)" # the cooldown probe logs an app-server line in between
has "codex-run: its log says why" "next account 'acc3': weekly limit resets" "$(cat "$T/run.err")"
unset FAKE_QUOTA_TOKENS FAKE_WEEK_ORDER
has "help next: describes the rule" "whose weekly limit resets soonest" "$("$CODEXR" help next)"
has "help next: mentions -v" "-v, --why" "$("$CODEXR" help next)"

echo "== help"
setup
for form in "help" "--help" "-h"; do
  out="$("$CODEXR" $form 2>&1)"; rc=$?
  eq "codexr ${form:-<no args>}: exit 0" "0" "$rc"
  has "codexr ${form:-<no args>}: has the command list" "Commands:" "$out"
  has "codexr ${form:-<no args>}: has examples" "Typical use:" "$out"
  has "codexr ${form:-<no args>}: has exit codes" "Exit codes:" "$out"
  has "codexr ${form:-<no args>}: has environment variables" "Environment:" "$out"
done
overview="$("$CODEXR" help)"
for c in list save use swapui rename del active run rotate next cooldown clear test forget sync help; do
  has "overview lists '$c'" "  $c" "$overview"
done
for c in list save use swapui rename del active run cooldown clear next rotate test forget sync help; do
  h="$("$CODEXR" help "$c" 2>&1)"; rc=$?
  eq "codexr help $c: exit 0" "0" "$rc"
  has "codexr help $c: has its usage line" "Usage: codexr $c" "$h"
  eq "codexr $c --help == codexr help $c" "$h" "$("$CODEXR" "$c" --help 2>&1)"
done
eq "codexr ls --help == codexr help list" "$("$CODEXR" help list)" "$("$CODEXR" ls --help)"
eq "codexr rm --help == codexr help del" "$("$CODEXR" help del)" "$("$CODEXR" rm --help)"
out="$("$CODEXR" help bogus 2>&1)"; rc=$?
eq "codexr help <unknown> -> exit 2" "2" "$rc"
has "codexr help <unknown> names the bad command" "no such command 'bogus'" "$out"
"$CODEXR" bogus --help >/dev/null 2>&1; eq "codexr <unknown> --help -> exit 2" "2" "$?"

# --help must only print help, never run the command
setup
"$CODEXR" list --help >/dev/null 2>&1
eq "list --help does not call codex" "0" "$(lines)"
slots_before="$(ls "$CODEX_HOME/accounts"/*.json | wc -l | tr -d ' ')"
"$CODEXR" save --help >/dev/null 2>&1
eq "save --help does not save a slot" "$slots_before" "$(ls "$CODEX_HOME/accounts"/*.json | wc -l | tr -d ' ')"
"$CODEXR" use --help >/dev/null 2>&1
eq "use --help does not switch" "acc1" "$("$CODEXR" active)"
"$CODEXR" rotate --help >/dev/null 2>&1
eq "rotate --help does not set a cooldown" "0" "$(cd_of acc1)"
eq "rotate --help does not switch" "acc1" "$("$CODEXR" active)"
"$CODEXR" cooldown --help >/dev/null 2>&1; eq "cooldown --help without other args -> exit 0" "0" "$?"
mkdir -p "$T/empty"
CODEX_HOME="$T/empty" "$CODEXR" help >/dev/null 2>&1
eq "help does not create the accounts directory" "no" "$([ -e "$T/empty/accounts" ] && echo yes || echo no)"

out="$("$RUN" --help 2>&1)"; rc=$?
eq "codex-run --help: exit 0" "0" "$rc"
has "codex-run --help: has the usage line" "Usage: codex-run --prompt FILE" "$out"
has "codex-run --help: has exit codes" "Exit codes:" "$out"
has "codex-run --help: documents --conversation" "--conversation ID" "$out"
eq "codex-run --help does not run codex" "0" "$(lines)"
"$RUN" -h >/dev/null 2>&1; eq "codex-run -h: exit 0" "0" "$?"
out="$("$RUN" --bogus 2>&1)"
has "codex-run: an unknown argument points to --help" "see --help" "$out"

echo "== plain codexr starts codex"
setup
"$CODEXR" >/dev/null 2>&1
eq "plain 'codexr' starts codex once" "1" "$(lines)"
has "plain 'codexr': uses the selected account" "acc1|" "$(cat "$FAKE_ARGS_LOG")"
has "plain 'codexr': passes -c cli_auth_credentials_store=file" "-c cli_auth_credentials_store=file" "$(cat "$FAKE_ARGS_LOG")"
has "plain 'codexr': passes default model gpt-6-luna" "-m gpt-6-luna" "$(cat "$FAKE_ARGS_LOG")"
has "plain 'codexr': passes default effort max" "-c model_reasoning_effort=max" "$(cat "$FAKE_ARGS_LOG")"

# Override model
setup
"$CODEXR" -m custom-model >/dev/null 2>&1
has "plain 'codexr': custom -m is passed" "-m custom-model" "$(cat "$FAKE_ARGS_LOG")"
hasnt "plain 'codexr': default model omitted when -m given" "-m gpt-6-luna" "$(cat "$FAKE_ARGS_LOG")"

# Override effort
setup
"$CODEXR" -c model_reasoning_effort=low >/dev/null 2>&1
has "plain 'codexr': custom effort is passed" "-c model_reasoning_effort=low" "$(cat "$FAKE_ARGS_LOG")"
hasnt "plain 'codexr': default effort omitted when override given" "-c model_reasoning_effort=max" "$(cat "$FAKE_ARGS_LOG")"

# Refreshed login written back
setup
export FAKE_REFRESH=1
"$CODEXR" >/dev/null 2>&1
eq "plain codexr writes refreshed login back to slot" "at-acc1-refreshed" "$(jq -r .tokens.access_token "$CODEX_HOME/accounts/acc1.json")"
eq "plain codexr writes rotated refresh token back to slot" "rt-acc1-rotated" "$(jq -r .tokens.refresh_token "$CODEX_HOME/accounts/acc1.json")"
unset FAKE_REFRESH

setup
"$CODEXR" use acc3 >/dev/null
"$CODEXR" -c some_setting=val >/dev/null 2>&1
has "'codexr -c ...' passes flag through with selected account" "acc3|" "$(tail -1 "$FAKE_ARGS_LOG")"
has "'codexr -c ...' passes the custom config flag" "-c some_setting=val" "$(tail -1 "$FAKE_ARGS_LOG")"

"$CODEXR" run exec -s read-only >/dev/null 2>&1
has "'codexr run ...' passes arguments to codex" "exec -s" "$(tail -1 "$FAKE_ARGS_LOG")" # the fake logs the last positional argument as the prompt, not in argv

n0="$(lines)"
"$CODEXR" --help >/dev/null 2>&1; "$CODEXR" -h >/dev/null 2>&1; "$CODEXR" help >/dev/null 2>&1
eq "--help, -h and help do not start codex" "$n0" "$(lines)"
"$CODEXR" bogus >/dev/null 2>&1; rc=$?
eq "'codexr <unknown word>' is still an error (exit 2), codex is not started" "2" "$rc"
eq "unknown word: codex not started" "$n0" "$(lines)"
"$CODEXR" run --help >/dev/null 2>&1
eq "'codexr run --help' shows help, does not start codex" "$n0" "$(lines)"
out="$("$CODEXR" help run)"
has "help run mentions shorthand" "shorthand: codexr [codex arguments...]" "$out"
has "overview mentions plain codexr" "start codex with the selected account" "$("$CODEXR" help)"
out="$(CODEXR_BIN=/nonexistent/codex "$CODEXR" 2>&1)"; rc=$?
eq "plain codexr without codex -> error" "1" "$rc"
has "plain codexr without codex -> message" "codex not found" "$out"

echo "== swapui"
setup
out="$("$CODEXR" swapui acc1 acc2)"
has "swapui confirms swap" "swapped UI positions of 'acc1' and 'acc2' in 'codexr list'" "$out"
eq "swapui swaps row positions in list -c" "acc2 acc1 acc3" "$("$CODEXR" list -c | grep -o -E 'acc[123]' | tr '\n' ' ' | xargs)"
eq "next rotation order unchanged by swapui" "acc2" "$("$CODEXR" next)"

"$CODEXR" swapui acc2 acc3 >/dev/null
eq "swapui acc2 acc3 updates list -c" "acc3 acc1 acc2" "$("$CODEXR" list -c | grep -o -E 'acc[123]' | tr '\n' ' ' | xargs)"
eq "next rotation order still unaffected" "acc2" "$("$CODEXR" next)"

out="$("$CODEXR" swapui --reset)"
has "swapui --reset confirms reset" "reset UI display order to default (weekly limit reset order)" "$out"
eq "state .ui_order deleted after --reset" "null" "$(jq -r '.ui_order // "null"' "$CODEX_HOME/accounts/state.json")"
eq "list -c restored to default after --reset" "acc1 acc2 acc3" "$("$CODEXR" list -c | grep -o -E 'acc[123]' | tr '\n' ' ' | xargs)"

"$CODEXR" swapui acc1 acc3 >/dev/null
out="$("$CODEXR" swapui reset)"
has "swapui reset confirms reset" "reset UI display order to default (weekly limit reset order)" "$out"
eq "list -c restored to default after reset" "acc1 acc2 acc3" "$("$CODEXR" list -c | grep -o -E 'acc[123]' | tr '\n' ' ' | xargs)"

"$CODEXR" swapui >/dev/null 2>&1; eq "swapui no args -> error" "1" "$?"
"$CODEXR" swapui acc1 >/dev/null 2>&1; eq "swapui 1 arg -> error" "1" "$?"
out="$("$CODEXR" swapui acc1 nope 2>&1)"; rc=$?
eq "swapui nonexistent account -> error" "1" "$rc"
has "swapui error mentions nonexistent slot" "no slot 'nope'" "$out"
out="$("$CODEXR" swapui nope acc1 2>&1)"; rc=$?
eq "swapui first nonexistent account -> error" "1" "$rc"
has "swapui error mentions first nonexistent slot" "no slot 'nope'" "$out"
"$CODEXR" swapui acc1 '../x' >/dev/null 2>&1; eq "swapui invalid name -> error" "1" "$?"
out="$("$CODEXR" swapui acc1 acc1 2>&1)"; rc=$?
eq "swapui same account -> error" "1" "$rc"
has "swapui same account error message" "cannot swap an account with itself" "$out"

# rename updates name in ui_order
"$CODEXR" swapui acc1 acc3 >/dev/null
eq "ui_order before rename" "acc3 acc2 acc1" "$(jq -r '.ui_order | join(" ")' "$CODEX_HOME/accounts/state.json")"
"$CODEXR" rename acc3 acc9 >/dev/null
eq "rename updates name in ui_order" "acc9 acc2 acc1" "$(jq -r '.ui_order | join(" ")' "$CODEX_HOME/accounts/state.json")"
eq "list -c reflects renamed slot in ui_order" "acc9 acc2 acc1" "$("$CODEXR" list -c | grep -o -E 'acc[1-9]' | tr '\n' ' ' | xargs)"

# del removes account from ui_order
"$CODEXR" del acc2 >/dev/null
eq "del removes account from ui_order" "acc9 acc1" "$(jq -r '.ui_order | join(" ")' "$CODEX_HOME/accounts/state.json")"
eq "list -c reflects deleted slot removed from ui_order" "acc9 acc1" "$("$CODEXR" list -c | grep -o -E 'acc[1-9]' | tr '\n' ' ' | xargs)"

has "help swapui: mentions codexr swapui" "Usage: codexr swapui" "$("$CODEXR" help swapui)"
has "swapui --help works" "Usage: codexr swapui" "$("$CODEXR" swapui --help)"
