#!/usr/bin/env bash
# pre-tool-use.sh -- PreToolUse hook for copilot-cli-hook
# v2.1: Complexity scorer + hard defenses (time budget, ERROR trap, atomic writes)
# source: https://github.com/whitebob/claude-hook-copilot

# H1: Time budget tracking starts immediately
HOOK_START_TIME=$SECONDS

# H2: ERROR trap — never let hook exit non-zero. Any unexpected error
# returns the original input unchanged (passthrough).
ORIGINAL_INPUT=""
trap 'if [[ -n "$ORIGINAL_INPUT" ]]; then echo "$ORIGINAL_INPUT"; fi; exit 0' ERR

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"
source "${HOOK_DIR}/lib/copilot.sh"
source "${HOOK_DIR}/lib/variants.sh"

# Read stdin (hook input JSON)
INPUT=$(cat)
ORIGINAL_INPUT="$INPUT"

if [[ -z "$INPUT" ]]; then
    exit 0
fi

# H4: safe JSON extraction
TOOL_NAME=$(safe_jq "$INPUT" '.tool_name // "UNKNOWN"' "UNKNOWN")
TOOL_CALL_ID=$(safe_jq "$INPUT" '.tool_call_id // ""' "")
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

# H1: Check time budget before expensive operations
if ! check_time_budget; then
    echo "$INPUT"
    exit 0
fi

# Extract skeleton for variant lookup
SKELETON=$(extract_skeleton "$COMMAND")

# Check variant cache first
CACHED=$(lookup_variant "$SKELETON" 2>/dev/null || true)
if [[ -n "$CACHED" ]]; then
    log_message "INFO" "PreToolUse: variant cache hit, using cached optimization"
    OPTIMIZED="$CACHED"

    write_bridge_state "$TOOL_CALL_ID" "$SKELETON" "$COMMAND" "$OPTIMIZED"

    OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$OPTIMIZED" '.tool_input.command = $cmd' 2>/dev/null || echo "$INPUT")
    echo "$OUTPUT"
    exit 0
fi

# H1: Re-check budget before calling Copilot CLI (most expensive operation)
if ! check_time_budget; then
    echo "$INPUT"
    exit 0
fi

# Cache miss — try Copilot CLI optimization
OPTIMIZED=$(optimize_command "$COMMAND" "$DESCRIPTION")
OPT_RESULT=$?

if [[ $OPT_RESULT -eq 0 && "$OPTIMIZED" != "$COMMAND" ]]; then
    log_message "INFO" "PreToolUse: Copilot optimized cmd=[${OPTIMIZED}]"

    record_variant "$SKELETON" "$COMMAND" "$OPTIMIZED"
    write_bridge_state "$TOOL_CALL_ID" "$SKELETON" "$COMMAND" "$OPTIMIZED"

    OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$OPTIMIZED" '.tool_input.command = $cmd' 2>/dev/null || echo "$INPUT")
    echo "$OUTPUT"
    exit 0
fi

# Passthrough unchanged
echo "$INPUT"
exit 0
