# Core tests for codexr, codex-run, and codex-task (platform-independent).
# Sourced by test/run.sh.

for _part in core-codexr.sh core-list.sh core-run.sh core-task.sh; do
  _file="${HERE:-$(dirname "${BASH_SOURCE[0]}")}/$_part"
  if [ -f "$_file" ]; then
    . "$_file"
  fi
done
unset _part _file
