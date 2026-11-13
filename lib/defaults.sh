# Shared defaults for codexr, codex-run and codex-task. Sourced by the three commands; never run on its own.
# Default model and reasoning effort for every codex call (see docs/design.md, section 1).
CODEXR_DEFAULT_MODEL="${CODEXR_MODEL:-gpt-6-luna}"
CODEXR_DEFAULT_EFFORT="${CODEXR_EFFORT:-xhigh}"
