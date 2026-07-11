#!/usr/bin/env bash
# PreToolUse hook wrapper for the reviewer gate.
#
# Claude Code fires PreToolUse before every tool call and pipes the event as
# JSON on stdin. This wrapper only acts when the tool is Bash AND the command
# looks like a ship action (git commit / git push / deploy). For those, it runs
# the reviewer gate against the project. A non-zero exit blocks the tool call
# and the gate's explanation is shown to Claude.
#
# Everything else passes through untouched (exit 0).
set -u

INPUT="$(cat)"

# Extract fields without requiring jq (fall back to jq if present).
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
else
  TOOL="$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
fi

# Only gate Bash ship-commands.
[ "$TOOL" = "Bash" ] || exit 0
case "$CMD" in
  *"git commit"*|*"git push"*|*deploy*) ;;
  *) exit 0 ;;
esac

REPO="${CLAUDE_PROJECT_DIR:-.}"
exec "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/verify-reviewer-gate.sh" "$REPO"
