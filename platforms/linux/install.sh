#!/usr/bin/env bash
# Link codexr, codex-run and codex-task from this clone into a bin directory (Linux).
#
# Usage: platforms/linux/install.sh [BIN_DIR]        (default: ~/.local/bin)
# Or use the top-level install.sh which auto-detects the platform.
#
# It only creates symbolic links. It never logs in, never saves or forgets a login, and never reads an auth file.
# A regular file that already has one of the three names is left alone and the script stops.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BIN_DIR="${1:-$HOME/.local/bin}"
COMMANDS=(codexr codex-run codex-task)

missing=0
for c in jq git; do
  if ! command -v "$c" >/dev/null; then echo "missing: $c (required)" >&2; missing=1; fi
done
[ "$missing" = 0 ] || exit 1
for c in timeout setsid; do
  command -v "$c" >/dev/null || echo "note: $c not found; codexr uses it when present (coreutils / util-linux)"
done

for n in "${COMMANDS[@]}"; do
  if [ -e "$BIN_DIR/$n" ] && [ ! -L "$BIN_DIR/$n" ]; then
    echo "refusing to replace $BIN_DIR/$n: it is a regular file, not a link from this script" >&2
    exit 1
  fi
done

mkdir -p "$BIN_DIR"
for n in "${COMMANDS[@]}"; do
  ln -sf "$REPO/bin/$n" "$BIN_DIR/$n"
  echo "linked $BIN_DIR/$n -> $REPO/bin/$n"
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on PATH; add it before using the commands" ;;
esac
