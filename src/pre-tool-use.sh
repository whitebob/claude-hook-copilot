#!/usr/bin/env bash
# pre-tool-use.sh -- PreToolUse hook for copilot-cli-hook
# Phase 1: Modify protocol experiment -- rewrites echo commands
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
COMMAND=$(get_field "$INPUT" "command")
DESCRIPTION=$(get_field "$INPUT" "description")

log_message "INFO" "PreToolUse: tool=${TOOL_NAME} desc=${DESCRIPTION} cmd=${COMMAND}"

# ── Modify Protocol Experiment ──────────────────────────
# Test #1: Full JSON replacement — modify tool_input.command directly.
# If this works, Claude will execute the modified command.
if echo "$COMMAND" | grep -qE '^echo[[:space:]]'; then
    ORIGINAL="$COMMAND"
    MODIFIED="echo \"[HOOK-MODIFIED] ${COMMAND#echo }\""
    log_message "INFO" "PreToolUse MODIFY: original=[${ORIGINAL}] modified=[${MODIFIED}]"

    # Full JSON replacement: update tool_input.command with jq
    OUTPUT=$(echo "$INPUT" | jq -c --arg cmd "$MODIFIED" '.tool_input.command = $cmd')
    echo "$OUTPUT"
    exit 0
fi

# Default: passthrough unchanged
echo "$INPUT"
exit 0
