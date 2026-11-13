#!/usr/bin/env bash
# Install codexr, codex-run and codex-task as small wrappers that run this clone (Windows, Git Bash).
#
# Usage: platforms/windows/install.sh [BIN_DIR]     (default: ~/.local/bin)
# Or use the top-level install.sh which auto-detects the platform.
#
# Git Bash cannot make working symlinks here, so each command is a one-line script that execs bin/<name> in this clone.
# Both bash wrappers ($BIN_DIR/<name>) and Windows cmd/PowerShell wrappers ($BIN_DIR/<name>.cmd) are created.
# The clone path is written into the wrappers: run this script again if the clone is moved. It only writes those wrappers.
# It never logs in, never saves or forgets a login, and never reads auth.json.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BIN_DIR="${1:-$HOME/.local/bin}"
COMMANDS=(codexr codex-run codex-task)

missing=0
for c in jq git; do
  if ! command -v "$c" >/dev/null; then echo "missing: $c (required; winget install jqlang.jq for jq)" >&2; missing=1; fi
done
[ "$missing" = 0 ] || exit 1

for n in "${COMMANDS[@]}"; do
  for f in "$n" "$n.cmd"; do
    if [ -e "$BIN_DIR/$f" ] && [ ! -L "$BIN_DIR/$f" ]; then
      # a file this script did not write (a previous wrapper is also a plain file, so check its content first)
      if ! grep -q "$REPO/bin/$n" "$BIN_DIR/$f" 2>/dev/null; then
        echo "refusing to replace $BIN_DIR/$f: it is not a wrapper for this clone" >&2
        exit 1
      fi
    fi
  done
done

mkdir -p "$BIN_DIR"
for n in "${COMMANDS[@]}"; do
  printf '#!/usr/bin/env bash\nexec "%s/bin/%s" "$@"\n' "$REPO" "$n" > "$BIN_DIR/$n"
  chmod +x "$BIN_DIR/$n"
  cat << CMD_EOF > "$BIN_DIR/$n.cmd"
@echo off
rem $n for PowerShell / cmd: runs the bash script with Git Bash (avoids WSL bash.exe)
if exist "%ProgramFiles%\\Git\\bin\\bash.exe" (
  "%ProgramFiles%\\Git\\bin\\bash.exe" "$REPO/bin/$n" %*
) else if exist "%LocalAppData%\\Programs\\Git\\bin\\bash.exe" (
  "%LocalAppData%\\Programs\\Git\\bin\\bash.exe" "$REPO/bin/$n" %*
) else (
  bash "$REPO/bin/$n" %*
)
exit /b %ERRORLEVEL%
CMD_EOF
  chmod +x "$BIN_DIR/$n.cmd"
  echo "wrote $BIN_DIR/$n -> $REPO/bin/$n"
  echo "wrote $BIN_DIR/$n.cmd -> $REPO/bin/$n"
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on PATH; add it before using the commands" ;;
esac
