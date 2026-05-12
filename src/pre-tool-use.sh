#!/usr/bin/env bash
# pre-tool-use.sh -- PreToolUse hook for copilot-cli-hook
# Phase 2: Copilot CLI optimization for safe commands
# source: https://github.com/whitebob/claude-hook-copilot
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"
source "${HOOK_DIR}/lib/copilot.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "UNKNOWN"')
COMMAND=$(get_field "$INPUT" "command")
DESCRIPTION=$(get_field "$INPUT" "description")

log_message "INFO" "PreToolUse: tool=${TOOL_NAME} desc=${DESCRIPTION} cmd=${COMMAND}"

# Only optimize Bash tool calls
if [[ "$TOOL_NAME" != "Bash" ]]; then
    echo "$INPUT"
    exit 0
fi

# Only optimize safe (read-only) commands
is_safe_command "$COMMAND"
SAFE_RESULT=$?

if [[ $SAFE_RESULT -ne 0 ]]; then
    log_message "INFO" "PreToolUse: skipping optimization (not safe, code=${SAFE_RESULT})"
    echo "$INPUT"
    exit 0
fi

# Try Copilot CLI optimization
OPTIMIZED=$(optimize_command "$COMMAND" "$DESCRIPTION")
OPT_RESULT=$?

if [[ $OPT_RESULT -eq 0 && "$OPTIMIZED" != "$COMMAND" ]]; then
    log_message "INFO" "PreToolUse: optimized cmd=[${OPTIMIZED}]"

    # Full JSON replacement with optimized command
    OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$OPTIMIZED" '.tool_input.command = $cmd')
    echo "$OUTPUT"
    exit 0
fi

# Passthrough unchanged
echo "$INPUT"
exit 0
