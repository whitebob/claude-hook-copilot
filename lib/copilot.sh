#!/usr/bin/env bash
# copilot.sh -- Copilot CLI integration for command optimization
# source: https://github.com/whitebob/claude-hook-copilot

# How long to wait for Copilot CLI (seconds)
COPILOT_TIMEOUT="${COPILOT_TIMEOUT:-12}"

# S4: Latency tracking
LATENCY_FILE="${HOOK_DIR}/latency.jsonl"
COPILOT_MAX_AVG_LATENCY="${COPILOT_MAX_AVG_LATENCY:-10}"  # seconds, auto-disable above this
LATENCY_WINDOW_SIZE="${LATENCY_WINDOW_SIZE:-10}"           # number of recent calls to average

# Record a Copilot latency data point.
# Args: $1 = latency in seconds (float), $2 = success (0 or 1)
track_latency() {
    local latency="$1"
    local success="${2:-1}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -nc \
        --arg ts "$now" \
        --argjson lat "$latency" \
        --argjson ok "$success" \
        '{timestamp: $ts, latency_s: $lat, success: $ok}' \
        >> "$LATENCY_FILE" 2>/dev/null || true
}

# Check if Copilot CLI latency is healthy (moving average ≤ max).
# Returns: 0 if healthy, 1 if too slow (caller should skip Copilot and passthrough)
is_copilot_latency_healthy() {
    if [[ ! -f "$LATENCY_FILE" ]]; then
        return 0  # No data yet, assume healthy
    fi

    local avg
    avg=$(tail -n "$LATENCY_WINDOW_SIZE" "$LATENCY_FILE" 2>/dev/null | \
        jq -r '.latency_s // 0' 2>/dev/null | \
        awk '{sum+=$1; n++} END {if (n>0) printf "%.2f", sum/n; else print "0"}')

    if [[ -z "$avg" || "$avg" == "0" ]]; then
        return 0
    fi

    if (( $(echo "$avg > $COPILOT_MAX_AVG_LATENCY" | bc -l 2>/dev/null || echo 0) )); then
        log_message "WARN" "Copilot latency unhealthy: avg=${avg}s > max=${COPILOT_MAX_AVG_LATENCY}s, auto-disabling"
        return 1
    fi

    return 0
}

# Optimize a shell command using Copilot CLI.
# Args: $1 = command, $2 = description (optional context), $3 = goal (optional, from [GOAL: ...])
# Output: optimized command on stdout (or original if optimization fails)
# Returns: 0 if optimized, 1 if passthrough (timeout/error/unavailable)
optimize_command() {
    local cmd="$1"
    local desc="${2:-}"
    local goal="${3:-}"

    # Guard: gh CLI must be available
    if ! command -v gh &>/dev/null; then
        log_message "WARN" "Copilot: gh CLI not found, passing through"
        echo "$cmd"
        return 1
    fi

    # Guard: copilot extension must be installed
    if ! gh copilot --version &>/dev/null; then
        log_message "WARN" "Copilot: gh copilot extension not available, passing through"
        echo "$cmd"
        return 1
    fi

    # S4: Check latency health before calling Copilot
    if ! is_copilot_latency_healthy; then
        log_message "WARN" "Copilot: latency too high, skipping optimization"
        echo "$cmd"
        return 1
    fi

    # Build prompt (I2/P1: goal-aware prompt construction)
    local prompt
    if [[ -n "$goal" ]]; then
        # Truncate goal to 200 chars to prevent oversized prompts
        local safe_goal="${goal:0:200}"
        if [[ -n "$desc" ]]; then
            prompt="Task goal: ${safe_goal}. Context: ${desc}. Optimize this shell command for the goal: ${cmd}. Output ONLY the optimized command, no explanation."
        else
            prompt="Task goal: ${safe_goal}. Optimize this shell command for the goal: ${cmd}. Output ONLY the optimized command, no explanation."
        fi
    elif [[ -n "$desc" ]]; then
        prompt="optimize this shell command: ${cmd}. context: ${desc}. output ONLY the optimized command, no explanation."
    else
        prompt="optimize this shell command: ${cmd}. output ONLY the optimized command, no explanation."
    fi

    # Call Copilot CLI with timeout (S4: track latency)
    local output
    local start_time=$SECONDS
    if output=$(timeout "$COPILOT_TIMEOUT" gh copilot -p "$prompt" --output-format json --allow-all-tools 2>/dev/null); then
        local elapsed=$((SECONDS - start_time))
        # Extract the final answer from JSONL streaming output.
        # Copilot CLI emits assistant.message_delta events with deltaContent.
        local optimized
        optimized=$(echo "$output" | jq -r 'select(.type == "assistant.message_delta") | .data.deltaContent' 2>/dev/null | tr -d '\n')

        if [[ -n "$optimized" && "$optimized" != "null" ]]; then
            # Strip leading/trailing whitespace (also any leading newline artifacts)
            optimized=$(echo "$optimized" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$optimized" ]]; then
                track_latency "$elapsed" 1
                log_message "INFO" "Copilot: optimized=[${optimized}] latency=${elapsed}s"
                echo "$optimized"
                return 0
            fi
        fi
        track_latency "$elapsed" 0
        log_message "WARN" "Copilot: failed to extract optimized command from response"
    else
        local elapsed=$((SECONDS - start_time))
        track_latency "$elapsed" 0
        log_message "WARN" "Copilot: timeout or error (${COPILOT_TIMEOUT}s limit, took ${elapsed}s)"
    fi

    # Passthrough on any failure
    echo "$cmd"
    return 1
}
