#!/usr/bin/env bash
# post-tool-use.sh -- PostToolUse hook for copilot-cli-hook
# Phase 1: Passthrough mode -- logs execution result
# source: https://github.com/whitebob/claude-hook-copilot
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "UNKNOWN"')
EXIT_CODE=$(echo "$INPUT" | jq -r '.result.exit_code // "N/A"')
COMMAND=$(get_field "$INPUT" "command")

log_message "INFO" "PostToolUse: tool=${TOOL_NAME} exit_code=${EXIT_CODE} cmd=${COMMAND}"

# Phase 1: Always passthrough (no modification)
exit 0
