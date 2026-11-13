#!/usr/bin/env bash
# Unified install script for codexr, codex-run, and codex-task.
# Auto-detects the operating system and delegates to the platform-specific installer.
# Supports local checkout execution and piped one-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/luongtrz/codexr/main/install.sh | bash
#
# Usage: ./install.sh [BIN_DIR]        (default: ~/.local/bin)
set -euo pipefail

REPO=""
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" 2>/dev/null && pwd || true)"
fi

if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/bin/codexr" ] && [ -f "$SELF_DIR/platforms/linux/install.sh" ]; then
  REPO="$SELF_DIR"
else
  # Piped one-liner execution (curl -fsSL ... | bash)
  missing=0
  for c in git jq; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "error: '$c' is required to install codexr but was not found on PATH." >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    echo "Please install git and jq before running this installer." >&2
    exit 1
  fi

  REPO="${CODEXR_INSTALL_DIR:-$HOME/tools/codex-acct}"
  REPO_URL="${CODEXR_REPO_URL:-https://github.com/luongtrz/codexr.git}"

  if [ -d "$REPO/.git" ]; then
    echo "Updating existing codexr clone in $REPO..."
    git -C "$REPO" pull --ff-only 2>/dev/null || echo "warning: could not pull latest changes from $REPO_URL (offline or local modifications); continuing with existing checkout." >&2
  else
    echo "Cloning codexr into $REPO..."
    mkdir -p "$(dirname "$REPO")"
    git clone "$REPO_URL" "$REPO"
  fi
fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    exec bash "$REPO/platforms/windows/install.sh" "$@"
    ;;
  *)
    exec bash "$REPO/platforms/linux/install.sh" "$@"
    ;;
esac
