#!/usr/bin/env bash
# copilot.sh -- Copilot CLI integration for command optimization
# source: https://github.com/whitebob/claude-hook-copilot

# How long to wait for Copilot CLI (seconds)
COPILOT_TIMEOUT="${COPILOT_TIMEOUT:-12}"

# Optimize a shell command using Copilot CLI.
# Args: $1 = command, $2 = description (optional context)
# Output: optimized command on stdout (or original if optimization fails)
# Returns: 0 if optimized, 1 if passthrough (timeout/error/unavailable)
optimize_command() {
    local cmd="$1"
    local desc="${2:-}"

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

    # Build prompt
    local prompt
    if [[ -n "$desc" ]]; then
        prompt="optimize this shell command: ${cmd}. context: ${desc}. output ONLY the optimized command, no explanation."
    else
        prompt="optimize this shell command: ${cmd}. output ONLY the optimized command, no explanation."
    fi

    # Call Copilot CLI with timeout
    local output
    if output=$(timeout "$COPILOT_TIMEOUT" gh copilot -p "$prompt" --output-format json --allow-all-tools 2>/dev/null); then
        # Extract the final answer from JSONL streaming output.
        # Copilot CLI emits assistant.message_delta events with deltaContent.
        local optimized
        optimized=$(echo "$output" | jq -r 'select(.type == "assistant.message_delta") | .data.deltaContent' 2>/dev/null | tr -d '\n')

        if [[ -n "$optimized" && "$optimized" != "null" ]]; then
            # Strip leading/trailing whitespace (also any leading newline artifacts)
            optimized=$(echo "$optimized" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$optimized" ]]; then
                log_message "INFO" "Copilot: optimized=[${optimized}]"
                echo "$optimized"
                return 0
            fi
        fi
        log_message "WARN" "Copilot: failed to extract optimized command from response"
    else
        log_message "WARN" "Copilot: timeout or error (${COPILOT_TIMEOUT}s limit)"
    fi

    # Passthrough on any failure
    echo "$cmd"
    return 1
}
