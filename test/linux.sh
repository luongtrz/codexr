# Linux platform tests for codexr, codex-run, and codex-task.
# Sourced by test/run.sh.
#
# Covers Linux-specific functionality:
#   - File modes: 600 for slot JSON files, 700 for accounts directory
#   - Process-group management: setsid detachment and process tree termination
#   - Installer: symlinks in temp BIN_DIR for codexr, codex-run, codex-task

echo "== linux: file permissions (600 slots, 700 accounts dir)"
setup
if [ "$ON_WINDOWS" = 1 ]; then
  echo "  skip file modes 600/700: NTFS has no POSIX permission bits (the profile folder's ACL protects the files)"
else
  eq "accounts dir mode is 700" "700" "$(stat -c %a "$CODEX_HOME/accounts")"
  eq "slot mode is 600" "600" "$(stat -c %a "$CODEX_HOME/accounts/acc1.json")"
  eq "live auth.json mode is 600" "600" "$(stat -c %a "$CODEX_HOME/auth.json")"
fi

echo "== linux: process-group detach and clean termination"
. "$HERE/../platforms/linux/platform.sh"
eq "linux platform: platform_kill_tree returns 1" "1" "$(platform_kill_tree 12345 >/dev/null 2>&1; echo $?)"
eq "linux platform: platform_arg_path preserves path" "/tmp/test" "$(platform_arg_path "/tmp/test")"
if command -v setsid >/dev/null 2>&1; then
  has "linux platform: PLATFORM_DETACH uses setsid" "setsid" "${PLATFORM_DETACH[*]:-}"
  has "linux platform: PLATFORM_DETACH_WAIT uses setsid -w" "setsid -w" "${PLATFORM_DETACH_WAIT[*]:-}"
fi

setup
export FAKE_QUOTA_TOKENS="acc1"
export CODEX_RUN_MAX_SWITCH=1
start=$SECONDS
runit >/dev/null 2>&1 || true
elapsed=$((SECONDS - start))
[ "$elapsed" -lt 15 ] && pass "process-group kill: stopped codex immediately (${elapsed}s < 15s)" || fail "process-group kill: stopped codex immediately" "took ${elapsed}s"
unset FAKE_QUOTA_TOKENS CODEX_RUN_MAX_SWITCH

echo "== platforms/linux/install.sh (into temp bin dirs, never the real ~/.local/bin)"
INST_LIN="$(mktemp -d)"; TMPS+=("$INST_LIN")
REPO_ABS="$(cd "$HERE/.." && pwd)"
if bash "$HERE/../platforms/linux/install.sh" "$INST_LIN/lin" >/dev/null 2>&1; then
  pass "platforms/linux/install.sh runs"
else
  fail "platforms/linux/install.sh runs"
fi

if [ "$ON_WINDOWS" = 1 ]; then
  echo "  skip symlink target check: Git Bash ln -s copies files unless Developer Mode symlinks are enabled"
else
  for cmd in codexr codex-run codex-task; do
    eq "platforms/linux/install.sh links $cmd to bin/$cmd" "$REPO_ABS/bin/$cmd" "$(readlink -f "$INST_LIN/lin/$cmd")"
  done
fi

for cmd in codexr codex-run codex-task; do
  has "linked $cmd answers help" "$cmd" "$("$INST_LIN/lin/$cmd" --help 2>&1 | head -1)"
done

mkdir -p "$INST_LIN/guard" && echo mine >"$INST_LIN/guard/codexr"
if bash "$HERE/../platforms/linux/install.sh" "$INST_LIN/guard" >/dev/null 2>&1; then
  fail "platforms/linux/install.sh refuses to replace a regular file"
else
  pass "platforms/linux/install.sh refuses to replace a regular file"
fi
eq "the regular file is left as it was" "mine" "$(cat "$INST_LIN/guard/codexr")"

echo "== install.sh (unified root installer)"
if bash "$HERE/../install.sh" "$INST_LIN/top" >/dev/null 2>&1; then
  pass "install.sh runs directly"
else
  fail "install.sh runs directly"
fi

if [ "$ON_WINDOWS" = 1 ]; then
  echo "  skip symlink target check: Git Bash ln -s copies files unless Developer Mode symlinks are enabled"
else
  for cmd in codexr codex-run codex-task; do
    eq "install.sh links $cmd to bin/$cmd" "$REPO_ABS/bin/$cmd" "$(readlink -f "$INST_LIN/top/$cmd")"
  done
fi

for cmd in codexr codex-run codex-task; do
  has "install.sh (direct) linked $cmd answers help" "$cmd" "$("$INST_LIN/top/$cmd" --help 2>&1 | head -1)"
done

if CODEXR_INSTALL_DIR="$INST_LIN/cloned" CODEXR_REPO_URL="$REPO_ABS" bash -s -- "$INST_LIN/piped" < "$HERE/../install.sh" >/dev/null 2>&1; then
  pass "install.sh runs when piped via stdin"
else
  fail "install.sh runs when piped via stdin"
fi
eq "install.sh (piped) clones repo into CODEXR_INSTALL_DIR" "yes" "$([ -d "$INST_LIN/cloned/.git" ] && echo yes || echo no)"
has "install.sh (piped) linked codexr answers help" "codexr" "$("$INST_LIN/piped/codexr" --help 2>&1 | head -1)"

if CODEXR_INSTALL_DIR="$INST_LIN/cloned" CODEXR_REPO_URL="$REPO_ABS" bash -s -- "$INST_LIN/piped-update" < "$HERE/../install.sh" >/dev/null 2>&1; then
  pass "install.sh (piped) updates existing clone"
else
  fail "install.sh (piped) updates existing clone"
fi
has "install.sh (piped update) linked codexr answers help" "codexr" "$("$INST_LIN/piped-update/codexr" --help 2>&1 | head -1)"
