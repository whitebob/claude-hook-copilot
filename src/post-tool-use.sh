#!/usr/bin/env bash
# post-tool-use.sh -- PostToolUse hook for copilot-cli-hook
# v3.0: Pair cache feedback + hard defenses (ERROR trap, safe_jq)
# source: https://github.com/whitebob/claude-hook-copilot

# H2: ERROR trap — never let hook exit non-zero
trap 'exit 0' ERR

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"
source "${HOOK_DIR}/lib/variants.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
    exit 0
fi

# H4: safe JSON extraction
TOOL_NAME=$(safe_jq "$INPUT" '.tool_name // "UNKNOWN"' "UNKNOWN")
EXIT_CODE=$(safe_jq "$INPUT" '.result.exit_code // "N/A"' "N/A")
TOOL_CALL_ID=$(safe_jq "$INPUT" '.tool_call_id // ""' "")
COMMAND=$(get_field "$INPUT" "command")

log_message "INFO" "PostToolUse: tool=${TOOL_NAME} exit_code=${EXIT_CODE} cmd=${COMMAND}"

# Check if this command was optimized (bridge state from pre-tool-use)
if [[ -n "$TOOL_CALL_ID" ]]; then
    BRIDGE=$(read_bridge_state "$TOOL_CALL_ID")
    if [[ -n "$BRIDGE" ]]; then
        SKELETON=$(safe_jq "$BRIDGE" '.skeleton // ""' "")
        ORIGINAL_CMD=$(safe_jq "$BRIDGE" '.original_command // ""' "")
        OPTIMIZED_CMD=$(safe_jq "$BRIDGE" '.optimized_command // ""' "")

        if [[ -n "$SKELETON" && -n "$ORIGINAL_CMD" && -n "$OPTIMIZED_CMD" ]]; then
            RESULT_SUMMARY=$(safe_jq "$INPUT" '.result.stdout // ""' "" | head -c 200)

            record_feedback "$SKELETON" "$ORIGINAL_CMD" "$OPTIMIZED_CMD" "$EXIT_CODE" "$RESULT_SUMMARY"

            # B1: Record pair feedback if this was a pair cache hit
            PREV_SK=$(safe_jq "$BRIDGE" '.prev_skeleton // ""' "")
            if [[ -n "$PREV_SK" ]]; then
                record_pair_feedback "$PREV_SK" "$SKELETON" "$EXIT_CODE"
            fi

            # Opportunistic cleanup (~1 in 20 calls)
            if [[ $((RANDOM % 20)) -eq 0 ]]; then
                cleanup_variants &
            fi
        fi
    fi
fi

exit 0
