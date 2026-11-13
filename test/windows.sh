# Windows platform tests for codexr, codex-run, and codex-task.
# Sourced by test/run.sh.
#
# Covers Windows-specific functionality:
#   - platforms/windows/platform.sh interface (paths, detaching, process tree kill)
#   - platforms/windows/install.sh wrappers (bash scripts and .cmd wrappers)

echo "== platforms/windows/platform.sh interface"
. "$HERE/../platforms/windows/platform.sh"
platform_init
eq "windows platform: PLATFORM_DETACH is empty" "0" "${#PLATFORM_DETACH[@]}"
eq "windows platform: PLATFORM_DETACH_WAIT is empty" "0" "${#PLATFORM_DETACH_WAIT[@]}"
eq "windows platform: platform_kill_tree returns 1 when no winpid" "1" "$(platform_kill_tree 999999 >/dev/null 2>&1; echo $?)"

if [ "$ON_WINDOWS" = 0 ]; then
  echo "  skip native Windows cygpath conversion on non-Windows"
  eq "windows platform: platform_arg_path fallback on non-Windows" "/tmp/test" "$(platform_arg_path "/tmp/test")"
else
  eq "windows platform: platform_arg_path formats path via cygpath" "$(cygpath -m /tmp/test)" "$(platform_arg_path "/tmp/test")"
fi

echo "== platforms/windows/install.sh (into temp bin dirs, never the real ~/.local/bin)"
INST_WIN="$(mktemp -d)"; TMPS+=("$INST_WIN")
REPO_ABS="$(cd "$HERE/.." && pwd)"
if bash "$HERE/../platforms/windows/install.sh" "$INST_WIN/win" >/dev/null 2>&1; then
  pass "platforms/windows/install.sh writes the wrappers"
else
  fail "platforms/windows/install.sh writes the wrappers"
fi

for cmd in codexr codex-run codex-task; do
  has "windows wrapper points at this clone's bin/$cmd" "exec \"$REPO_ABS/bin/$cmd\"" "$(cat "$INST_WIN/win/$cmd")"
  has "windows .cmd wrapper points at this clone's bin/$cmd" "$REPO_ABS/bin/$cmd" "$(cat "$INST_WIN/win/$cmd.cmd")"
  has "windows .cmd wrapper invokes Git Bash explicitly" "Git\\bin\\bash.exe" "$(cat "$INST_WIN/win/$cmd.cmd")"
  has "windows wrapper answers help" "$cmd" "$("$INST_WIN/win/$cmd" --help 2>&1 | head -1)"
done

mkdir -p "$INST_WIN/guard-wincmd" && echo mine >"$INST_WIN/guard-wincmd/codexr.cmd"
if bash "$HERE/../platforms/windows/install.sh" "$INST_WIN/guard-wincmd" >/dev/null 2>&1; then
  fail "platforms/windows/install.sh refuses to replace an unrelated codexr.cmd"
else
  pass "platforms/windows/install.sh refuses to replace an unrelated codexr.cmd"
fi
eq "the unrelated codexr.cmd file is left as it was" "mine" "$(cat "$INST_WIN/guard-wincmd/codexr.cmd")"
