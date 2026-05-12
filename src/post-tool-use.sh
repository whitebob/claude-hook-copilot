#!/usr/bin/env bash
# post-tool-use.sh -- PostToolUse hook for copilot-cli-hook
# Phase 3: Feedback recording for variant library
# source: https://github.com/whitebob/claude-hook-copilot
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"
source "${HOOK_DIR}/lib/variants.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "UNKNOWN"')
EXIT_CODE=$(echo "$INPUT" | jq -r '.result.exit_code // "N/A"')
TOOL_CALL_ID=$(echo "$INPUT" | jq -r '.tool_call_id // ""')
COMMAND=$(get_field "$INPUT" "command")

log_message "INFO" "PostToolUse: tool=${TOOL_NAME} exit_code=${EXIT_CODE} cmd=${COMMAND}"

# Check if this command was optimized (bridge state from pre-tool-use)
if [[ -n "$TOOL_CALL_ID" ]]; then
    BRIDGE=$(read_bridge_state "$TOOL_CALL_ID")
    if [[ -n "$BRIDGE" ]]; then
        SKELETON=$(echo "$BRIDGE" | jq -r '.skeleton // ""')
        ORIGINAL_CMD=$(echo "$BRIDGE" | jq -r '.original_command // ""')
        OPTIMIZED_CMD=$(echo "$BRIDGE" | jq -r '.optimized_command // ""')

        if [[ -n "$SKELETON" && -n "$ORIGINAL_CMD" && -n "$OPTIMIZED_CMD" ]]; then
            # Capture a brief result summary (first 200 chars of stdout if available)
            RESULT_SUMMARY=$(echo "$INPUT" | jq -r '.result.stdout // ""' 2>/dev/null | head -c 200)

            record_feedback "$SKELETON" "$ORIGINAL_CMD" "$OPTIMIZED_CMD" "$EXIT_CODE" "$RESULT_SUMMARY"

            # Opportunistic cleanup (~1 in 20 calls)
            if [[ $((RANDOM % 20)) -eq 0 ]]; then
                cleanup_variants &
            fi
        fi
    fi
fi

# Phase 3: No modification — always passthrough
exit 0
