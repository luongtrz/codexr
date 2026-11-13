# Linux platform layer. Sourced by bin/codexr and bin/codex-run; never run on its own.
#
# setsid gives codex its own process group (codex-run kills the group) and, for codexr's quota calls, no controlling terminal:
# several codex processes measuring in parallel otherwise change and restore the terminal mode and garble it. Not every
# system has setsid (macOS, Git Bash), so the arrays stay empty when it is missing.
PLATFORM_DETACH=()      # codex-run
PLATFORM_DETACH_WAIT=() # codexr: waits until codex has finished
if command -v setsid >/dev/null; then PLATFORM_DETACH=(setsid); PLATFORM_DETACH_WAIT=(setsid -w); fi

platform_init() { :; } # nothing to prepare on Linux

# Path of a directory as codex should receive it. Linux paths need no conversion.
platform_arg_path() { printf '%s\n' "$1"; }

# Stop the whole process tree of codex started as bash PID $1. Windows only: on Linux the caller uses the process group,
# so this returns 1 ("not handled").
platform_kill_tree() { return 1; }
