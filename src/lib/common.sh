#!/usr/bin/env bash
# common.sh -- shared utilities for copilot-cli-hook
# source: https://github.com/whitebob/claude-hook-copilot

# ── Logging ──────────────────────────────────────────────

HOOK_DIR="${HOOK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${HOOK_DIR}/logs/copilot-hook.log"

# ── Time Budget (H1: prevents hook timeout cascade) ─────

HOOK_TIME_BUDGET="${HOOK_TIME_BUDGET:-10}"  # seconds before auto-passthrough
HOOK_START_TIME="${HOOK_START_TIME:-$SECONDS}"

# Check if we're within the time budget. Call before expensive operations.
# Returns: 0 if OK to proceed, 1 if budget exceeded (caller should passthrough)
check_time_budget() {
    local elapsed=$((SECONDS - HOOK_START_TIME))
    if [[ $elapsed -ge $HOOK_TIME_BUDGET ]]; then
        log_message "WARN" "Time budget exceeded (${elapsed}s >= ${HOOK_TIME_BUDGET}s), forcing passthrough"
        return 1
    fi
    return 0
}

# ── Atomic Write (H3: prevents file corruption) ──────────

# Write JSON content atomically to a file (tmp + mv).
# Args: $1 = filepath, $2 = content (JSON string)
atomic_write_json() {
    local filepath="$1"
    local content="$2"
    local tmp="${filepath}.tmp.$$"
    echo "$content" > "$tmp" 2>/dev/null && mv "$tmp" "$filepath" 2>/dev/null || true
}

# Append JSON line atomically to a file.
# Args: $1 = filepath, $2 = content (JSON string)
atomic_append_json() {
    local filepath="$1"
    local content="$2"
    echo "$content" >> "$filepath" 2>/dev/null || true
}

# Safe jq wrapper (H4: never crash on parse failure).
# Args: $1 = json string, $2 = jq filter, $3 = default value (optional)
safe_jq() {
    local json="$1"
    local filter="$2"
    local default="${3:-}"
    local result
    result=$(echo "$json" | jq -r "$filter" 2>/dev/null) || true
    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# ── Command Classification ───────────────────────────────

# Safe command patterns (read-only, informational, non-destructive)
SAFE_PATTERNS=(
    # search tools
    "^grep "     "^rg "       "^ack "      "^ag "
    # filesystem listing
    "^find "     "^fd "       "^locate "   "^ls "
    "^tree "     "^du "       "^df "
    # readers
    "^cat "      "^head "     "^tail "     "^less "
    # text processing (read-only)
    "^wc "       "^sort "     "^uniq "     "^cut "
    "^tr "       "^sed "      "^awk "
    # read-only git
    "^git log"   "^git diff"  "^git show"  "^git status"
    "^git branch" "^git tag"  "^git blame" "^git grep"
    "^git stash list" "^git remote" "^git config"
    # read-only HTTP
    "^curl -[sI]" "^curl --head" "^curl --silent"
    # informational
    "^echo "     "^printf "   "^date "     "^which "
    "^type "     "^command " "^env$"      "^printenv"
    # processors
    "^jq "       "^yq "       "^python3 -c" "^node -e"
    # archive listing
    "^tar -t"    "^zipinfo "  "^unzip -l"
    # read-only docker
    "^docker ps" "^docker images" "^docker inspect"
    # gh read-only
    "^gh pr view" "^gh pr list" "^gh issue view" "^gh issue list"
    "^gh api "   "^gh repo view" "^gh search "
)

# Dangerous command patterns (destructive, never optimize)
DANGEROUS_PATTERNS=(
    "^rm "       "^rmdir "    "^unlink "
    "^mv "       "^dd "
    "^git push"  "^git commit" "^git rebase" "^git reset"
    "^git clean" "^git stash drop" "^git stash clear"
    "^chmod "    "^chown "    "^chgrp "
    "^sudo "     "^su "
    "^kill "     "^pkill "    "^killall "
    "^shutdown " "^reboot "   "^halt "
    "^mkfs"      "^fdisk "    "^parted "   "^mount " "^umount "
    "^pip install" "^pip3 install" "^npm install -g" "^gem install"
    "^cargo install" "^yarn global add"
)

# Returns: 0 = safe (should optimize), 1 = dangerous (never optimize), 2 = unknown (passthrough)
is_safe_command() {
    local cmd="$1"
    # Strip leading whitespace
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//')

    # Check for pipe-to-shell (always dangerous)
    if echo "$cmd" | grep -qE '\|[[:space:]]*(sh|bash|sudo)'; then
        log_message "INFO" "Command flagged dangerous (pipe to shell): $cmd"
        return 1
    fi

    # Check for output redirection to filesystem (potentially destructive)
    if echo "$cmd" | grep -qE '>[^>&]'; then
        log_message "INFO" "Command flagged dangerous (output redirection): $cmd"
        return 1
    fi

    # Check dangerous patterns first
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            log_message "INFO" "Command flagged dangerous: $cmd"
            return 1
        fi
    done

    # Check safe patterns
    for pattern in "${SAFE_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            return 0
        fi
    done

    # Unknown command -- passthrough (don't optimize what we don't understand)
    return 2
}

# ── Command Skeleton Extraction ──────────────────────────

# Normalizes a command into its structural skeleton.
# Replaces literals with <literal>, paths with <path>, globs with <glob>,
# numbers with <num>, flags preserved.
extract_skeleton() {
    local cmd="$1"
    local skeleton="$cmd"

    # Replace quoted strings (single and double) with <literal>
    skeleton=$(echo "$skeleton" | sed "s/'[^']*'/<literal>/g")
    skeleton=$(echo "$skeleton" | sed 's/"[^"]*"/<literal>/g')

    # Replace globs (*.ts, *.js, etc.) with <glob> (do this before path replacement)
    skeleton=$(echo "$skeleton" | sed 's/\*[.][a-zA-Z0-9][a-zA-Z0-9]*/<glob>/g')

    # Replace paths (starting with /, ./, ../) with <path>
    skeleton=$(echo "$skeleton" | sed 's|[./][./]*[a-zA-Z0-9._/][a-zA-Z0-9._/]*|<path>|g')

    # Replace pure numbers (standalone integers) with <num>
    skeleton=$(echo "$skeleton" | sed 's/[0-9][0-9]*/<num>/g')

    # Clean up: collapse repeated <path><path> into single <path>
    skeleton=$(echo "$skeleton" | sed 's|<path><path>|<path>|g')

    echo "$skeleton"
}

# ── JSON Helpers ─────────────────────────────────────────

# Extract a field from hook stdin JSON, trying both tool_input and input conventions
get_field() {
    local json="$1"
    local field="$2"
    # Try tool_input first, fall back to input
    local val
    val=$(echo "$json" | jq -r ".tool_input.${field} // .input.${field} // \"\"")
    echo "$val"
}

# ── Bridge State (pre-tool-use → post-tool-use) ─────────

BRIDGE_DIR="${HOOK_DIR}/.bridge"

# Write bridge state so post-tool-use knows what optimization was applied.
# Args: tool_call_id, skeleton, original_command, optimized_command
write_bridge_state() {
    local call_id="$1"
    local skeleton="$2"
    local original="$3"
    local optimized="$4"

    mkdir -p "$BRIDGE_DIR" 2>/dev/null || true
    local content
    content=$(jq -nc \
        --arg sk "$skeleton" \
        --arg orig "$original" \
        --arg opt "$optimized" \
        '{skeleton: $sk, original_command: $orig, optimized_command: $opt}' 2>/dev/null) || true
    if [[ -n "$content" ]]; then
        atomic_write_json "${BRIDGE_DIR}/${call_id}.json" "$content"
    fi
}

# Read bridge state for a given tool_call_id.
# Output: JSON on stdout (empty if not found)
read_bridge_state() {
    local call_id="$1"
    local path="${BRIDGE_DIR}/${call_id}.json"
    if [[ -f "$path" ]]; then
        cat "$path" 2>/dev/null
        rm -f "$path" 2>/dev/null
    fi
}
