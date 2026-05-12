#!/usr/bin/env bash
# pre-tool-use.sh -- PreToolUse hook for copilot-cli-hook
# v3.0: Intent protocol (goal extraction, enhanced prompts, session history, pair cache)
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

# I2: Extract [GOAL: ...] from description for enhanced Copilot prompts
GOAL=$(extract_goal "$DESCRIPTION")
if [[ -n "$GOAL" ]]; then
    log_message "INFO" "PreToolUse: goal extracted=[${GOAL}]"
fi

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

# Extract skeleton early (used by both S3/S5 and cache lookup)
SKELETON=$(extract_skeleton "$COMMAND")

# B1: Get previous skeleton for pair cache lookup
PREV_SKELETON=$(get_prev_skeleton 2>/dev/null || true)

# S3: Complexity scorer — skip simple commands (score ≤ 2)
COMPLEXITY=$(score_complexity "$COMMAND")
log_message "INFO" "PreToolUse: complexity_score=${COMPLEXITY} cmd=${COMMAND}"

if [[ "$COMPLEXITY" -le 2 ]]; then
    # S5: Simple-cached exception — use cache even for simple commands if conf ≥ 0.7
    _saved_threshold="$CONFIDENCE_THRESHOLD"
    CONFIDENCE_THRESHOLD="${S5_CONFIDENCE_THRESHOLD:-0.7}"
    CACHED=$(lookup_variant "$SKELETON" 2>/dev/null || true)
    CONFIDENCE_THRESHOLD="$_saved_threshold"
    if [[ -n "$CACHED" ]]; then
        log_message "INFO" "PreToolUse: S5 cached exception (score=${COMPLEXITY}, conf≥threshold)"
        write_bridge_state "$TOOL_CALL_ID" "$SKELETON" "$COMMAND" "$CACHED" "$PREV_SKELETON"
        OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$CACHED" '.tool_input.command = $cmd' 2>/dev/null || echo "$INPUT")
        echo "$OUTPUT"
        exit 0
    fi

    log_message "INFO" "PreToolUse: skipping optimization (low complexity, score=${COMPLEXITY})"
    echo "$INPUT"
    exit 0
fi

# H1: Check time budget before expensive operations
if ! check_time_budget; then
    echo "$INPUT"
    exit 0
fi

# Check variant cache (score ≥ 3, may still have cache hit)
# B1: Try pair cache first (higher specificity than single cache)
CACHED=""
if [[ -n "$PREV_SKELETON" ]]; then
    CACHED=$(lookup_pair_variant "$PREV_SKELETON" "$SKELETON" 2>/dev/null || true)
    if [[ -n "$CACHED" ]]; then
        log_message "INFO" "PreToolUse: pair cache hit, using cached optimization"
    fi
fi

# Fall back to single cache if pair cache missed
if [[ -z "$CACHED" ]]; then
    CACHED=$(lookup_variant "$SKELETON" 2>/dev/null || true)
    if [[ -n "$CACHED" ]]; then
        log_message "INFO" "PreToolUse: variant cache hit, using cached optimization"
    fi
fi

if [[ -n "$CACHED" ]]; then
    OPTIMIZED="$CACHED"

    write_bridge_state "$TOOL_CALL_ID" "$SKELETON" "$COMMAND" "$OPTIMIZED" "$PREV_SKELETON"

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
OPTIMIZED=$(optimize_command "$COMMAND" "$DESCRIPTION" "$GOAL")
OPT_RESULT=$?

if [[ $OPT_RESULT -eq 0 && "$OPTIMIZED" != "$COMMAND" ]]; then
    log_message "INFO" "PreToolUse: Copilot optimized cmd=[${OPTIMIZED}]"

    record_variant "$SKELETON" "$COMMAND" "$OPTIMIZED"

    # B1: Record pair cache entry if we have a previous skeleton
    if [[ -n "$PREV_SKELETON" ]]; then
        record_pair_variant "$PREV_SKELETON" "$SKELETON" "$OPTIMIZED"
    fi

    # S2: Record to session history for future pair lookups
    record_session "$SKELETON" "$GOAL"

    write_bridge_state "$TOOL_CALL_ID" "$SKELETON" "$COMMAND" "$OPTIMIZED" "$PREV_SKELETON"

    OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$OPTIMIZED" '.tool_input.command = $cmd' 2>/dev/null || echo "$INPUT")
    echo "$OUTPUT"
    exit 0
fi

# S2: Record session even on passthrough (score ≥ 3, but optimization failed)
if [[ "$COMPLEXITY" -ge 3 ]]; then
    record_session "$SKELETON" "$GOAL"
fi

# Passthrough unchanged
echo "$INPUT"
exit 0
