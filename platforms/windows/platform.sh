# Windows platform layer (Git Bash / MSYS / Cygwin). Sourced by bin/codexr and bin/codex-run; never run on its own.
#
# Git Bash has no setsid: codex is started plainly, and its process tree is stopped with taskkill (platform_kill_tree).
PLATFORM_DETACH=()
PLATFORM_DETACH_WAIT=()

platform_init() {
  # a native Windows jq.exe prints CRLF; the \r would end up inside names and numbers (-b / --binary prevents that)
  if command jq -b -n . >/dev/null 2>&1; then jq() { command jq -b "$@"; }; fi
}

# Path of a directory as the native codex.exe should receive it: cygpath -m gives the form with forward slashes.
platform_arg_path() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

# Stop the whole process tree of the codex.exe started as bash PID $1 (taskkill), then reap it. Returns 1 when that is not
# possible (no taskkill, or no Windows PID for the process), so the caller falls back to the process group.
platform_kill_tree() {
  local pid="$1"
  if [ ! -r "/proc/$pid/winpid" ] || ! command -v taskkill >/dev/null; then return 1; fi
  taskkill //T //F //PID "$(cat "/proc/$pid/winpid")" >/dev/null 2>&1 || true
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 0
}
