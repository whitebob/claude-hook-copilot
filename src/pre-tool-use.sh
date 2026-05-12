#!/usr/bin/env bash
# pre-tool-use.sh -- PreToolUse hook for copilot-cli-hook
# Phase 1: Passthrough mode -- logs and passes through unchanged
# source: https://github.com/whitebob/claude-hook-copilot
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)

# Skip if empty
if [[ -z "$INPUT" ]]; then
    exit 0
fi

# Extract fields
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "UNKNOWN"')
COMMAND=$(get_field "$INPUT" "command")
DESCRIPTION=$(get_field "$INPUT" "description")

log_message "INFO" "PreToolUse: tool=${TOOL_NAME} desc=${DESCRIPTION} cmd=${COMMAND}"

# Phase 1: Always passthrough (no modification)
echo "$INPUT"
exit 0
