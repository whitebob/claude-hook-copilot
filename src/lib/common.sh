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
    "^git stash list" "^git config (--get|--get-all|--get-regexp|--list|-l)\b"
    "^git remote([[:space:]]*$| -v([[:space:]]|$)| show([[:space:]]|$)| get-url([[:space:]]|$))"
    # read-only HTTP
    "^curl -[sI]" "^curl --head" "^curl --silent"
    # informational
    "^echo "     "^printf "   "^date "     "^which "
    "^type "     "^command " "^env$"      "^printenv"
    # processors
    "^jq "       "^yq "
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
    "^docker rm"
    "^shutdown " "^reboot "   "^halt "
    "^mkfs"      "^fdisk "    "^parted "   "^mount " "^umount "
    "^pip install" "^pip3 install" "^npm install -g" "^gem install"
    "^cargo install" "^yarn global add"
    "^eval "     "^source "   "^\. "       "^exec "
)

# Trim leading/trailing whitespace
_trim_command() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Split command on top-level &&, ||, ; and single & (not &&), respecting quotes/backticks.
_split_compound() {
    local cmd="$1"
    local current=""
    local in_single=0
    local in_double=0
    local in_backtick=0
    local escaped=0
    local i ch next segment

    for ((i=0; i<${#cmd}; i++)); do
        ch="${cmd:i:1}"
        next="${cmd:i+1:1}"

        if [[ $escaped -eq 1 ]]; then
            current+="$ch"
            escaped=0
            continue
        fi

        if [[ $in_single -eq 1 ]]; then
            current+="$ch"
            [[ "$ch" == "'" ]] && in_single=0
            continue
        fi

        if [[ $in_double -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\"" ]]; then
                in_double=0
            fi
            continue
        fi

        if [[ $in_backtick -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\`" ]]; then
                in_backtick=0
            fi
            continue
        fi

        case "$ch" in
            "'")
                in_single=1
                current+="$ch"
                ;;
            "\"")
                in_double=1
                current+="$ch"
                ;;
            "\`")
                in_backtick=1
                current+="$ch"
                ;;
            ";")
                segment=$(_trim_command "$current")
                [[ -n "$segment" ]] && printf '%s\n' "$segment"
                current=""
                ;;
            "&")
                segment=$(_trim_command "$current")
                [[ -n "$segment" ]] && printf '%s\n' "$segment"
                current=""
                [[ "$next" == "&" ]] && ((i++))
                ;;
            "|")
                if [[ "$next" == "|" ]]; then
                    segment=$(_trim_command "$current")
                    [[ -n "$segment" ]] && printf '%s\n' "$segment"
                    current=""
                    ((i++))
                else
                    current+="$ch"
                fi
                ;;
            *)
                current+="$ch"
                ;;
        esac
    done

    segment=$(_trim_command "$current")
    [[ -n "$segment" ]] && printf '%s\n' "$segment"
}

# Split command on top-level | (not ||), respecting quotes/backticks.
_split_pipeline() {
    local cmd="$1"
    local current=""
    local in_single=0
    local in_double=0
    local in_backtick=0
    local escaped=0
    local i ch next segment

    for ((i=0; i<${#cmd}; i++)); do
        ch="${cmd:i:1}"
        next="${cmd:i+1:1}"

        if [[ $escaped -eq 1 ]]; then
            current+="$ch"
            escaped=0
            continue
        fi

        if [[ $in_single -eq 1 ]]; then
            current+="$ch"
            [[ "$ch" == "'" ]] && in_single=0
            continue
        fi

        if [[ $in_double -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\"" ]]; then
                in_double=0
            fi
            continue
        fi

        if [[ $in_backtick -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\`" ]]; then
                in_backtick=0
            fi
            continue
        fi

        case "$ch" in
            "'")
                in_single=1
                current+="$ch"
                ;;
            "\"")
                in_double=1
                current+="$ch"
                ;;
            "\`")
                in_backtick=1
                current+="$ch"
                ;;
            "|")
                if [[ "$next" == "|" ]]; then
                    current+="$ch"
                else
                    segment=$(_trim_command "$current")
                    [[ -n "$segment" ]] && printf '%s\n' "$segment"
                    current=""
                fi
                ;;
            *)
                current+="$ch"
                ;;
        esac
    done

    segment=$(_trim_command "$current")
    [[ -n "$segment" ]] && printf '%s\n' "$segment"
}

# Tokenize by whitespace at top level (respecting quotes/backticks).
_split_words() {
    local cmd="$1"
    local current=""
    local in_single=0
    local in_double=0
    local in_backtick=0
    local escaped=0
    local i ch token

    for ((i=0; i<${#cmd}; i++)); do
        ch="${cmd:i:1}"

        if [[ $escaped -eq 1 ]]; then
            current+="$ch"
            escaped=0
            continue
        fi

        if [[ $in_single -eq 1 ]]; then
            current+="$ch"
            [[ "$ch" == "'" ]] && in_single=0
            continue
        fi

        if [[ $in_double -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\"" ]]; then
                in_double=0
            fi
            continue
        fi

        if [[ $in_backtick -eq 1 ]]; then
            current+="$ch"
            if [[ "$ch" == "\\" ]]; then
                escaped=1
            elif [[ "$ch" == "\`" ]]; then
                in_backtick=0
            fi
            continue
        fi

        case "$ch" in
            "'")
                in_single=1
                current+="$ch"
                ;;
            "\"")
                in_double=1
                current+="$ch"
                ;;
            "\`")
                in_backtick=1
                current+="$ch"
                ;;
            [[:space:]])
                token=$(_trim_command "$current")
                [[ -n "$token" ]] && printf '%s\n' "$token"
                current=""
                ;;
            *)
                current+="$ch"
                ;;
        esac
    done

    token=$(_trim_command "$current")
    [[ -n "$token" ]] && printf '%s\n' "$token"
}

_leading_word() {
    local cmd="$1"
    local first
    first=$(_split_words "$cmd" | head -1)
    echo "$first"
}

_is_gh_api_mutating() {
    local cmd="$1"
    if ! echo "$cmd" | grep -qE '^gh api '; then
        return 1
    fi
    if echo "$cmd" | grep -qiE '(^|[[:space:]])(-X|--method)(=|[[:space:]]+)(POST|PUT|PATCH|DELETE)\b'; then
        return 0
    fi
    return 1
}

_is_sed_inplace() {
    local cmd="$1"
    if ! echo "$cmd" | grep -qE '^sed(\s|$)'; then
        return 1
    fi
    if echo "$cmd" | grep -qE '(^|[[:space:]])(-i[^[:space:]]*|--in-place(=[^[:space:]]*)?)([[:space:]]|$)'; then
        return 0
    fi
    return 1
}

_is_awk_dangerous() {
    local cmd="$1"
    if ! echo "$cmd" | grep -qE '^awk(\s|$)'; then
        return 1
    fi
    if echo "$cmd" | grep -qE 'system[[:space:]]*\(|\|[[:space:]]*"|getline[^|]*\|[[:space:]]*"'; then
        return 0
    fi
    return 1
}

_is_tee_dangerous() {
    local cmd="$1"
    local escaped_home
    if ! echo "$cmd" | grep -qE '^tee(\s|$)'; then
        return 1
    fi
    escaped_home=$(printf '%s' "${HOME:-}" | sed 's/[][(){}.^$*+?|\\]/\\&/g')
    if echo "$cmd" | grep -qE '(^|[[:space:]])(/etc|/usr|/var|/dev|/boot|/sys|/proc)(/|$)|(\$HOME|\$\{HOME\}|~)/\.[^[:space:]]+'; then
        return 0
    fi
    if [[ -n "$escaped_home" ]] && echo "$cmd" | grep -qE "(^|[[:space:]])${escaped_home}/\\.[^[:space:]]+"; then
        return 0
    fi
    return 1
}

_is_process_substitution_shell() {
    local cmd="$1"
    if echo "$cmd" | grep -qE '^(bash|sh|zsh|dash|ksh|fish)\b.*<\('; then
        return 0
    fi
    return 1
}

_is_xargs_dangerous() {
    local cmd="$1"
    if ! echo "$cmd" | grep -qE '^xargs(\s|$)'; then
        return 1
    fi

    local -a tokens
    local i=1
    local token
    mapfile -t tokens < <(_split_words "$cmd")

    while [[ $i -lt ${#tokens[@]} ]]; do
        token="${tokens[$i]}"
        if [[ "$token" == "--" ]]; then
            ((i++))
            break
        fi
        if [[ "$token" == -* ]]; then
            case "$token" in
                -I|-i|-n|-L|-P|-d|-E|-s|-S|--replace|--max-args|--max-lines|--max-procs|--delimiter|--eof|--max-chars|--arg-file)
                    ((i+=2))
                    continue
                    ;;
                --replace=*|--max-args=*|--max-lines=*|--max-procs=*|--delimiter=*|--eof=*|--max-chars=*|--arg-file=*)
                    ((i++))
                    continue
                    ;;
                *)
                    ((i++))
                    continue
                    ;;
            esac
        fi
        break
    done

    if [[ $i -lt ${#tokens[@]} ]]; then
        local subcmd
        subcmd="${tokens[*]:$i}"

        case "${tokens[$i]}" in
            rm|rmdir|unlink|mv|dd|chmod|chown|chgrp|kill|pkill|killall|sudo|su|eval|source|exec|.|sh|bash|zsh|dash|ksh|fish)
                return 0
                ;;
        esac

        _classify_single_stage "$subcmd"
        [[ $? -eq 1 ]] && return 0
    fi
    return 1
}

_classify_single_stage() {
    local cmd="$1"

    if [[ -z "$cmd" ]]; then
        return 2
    fi

    if _is_process_substitution_shell "$cmd"; then
        return 1
    fi

    if echo "$cmd" | grep -qE '>[^>&]'; then
        return 1
    fi

    if _is_gh_api_mutating "$cmd" || _is_sed_inplace "$cmd" || _is_awk_dangerous "$cmd" || _is_tee_dangerous "$cmd" || _is_xargs_dangerous "$cmd"; then
        return 1
    fi

    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            return 1
        fi
    done

    for pattern in "${SAFE_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            return 0
        fi
    done

    return 2
}

_classify_segment() {
    local segment="$1"
    local unknown=0
    local -a stages
    local i rc leading

    mapfile -t stages < <(_split_pipeline "$segment")
    if [[ ${#stages[@]} -eq 0 ]]; then
        return 2
    fi

    for ((i=0; i<${#stages[@]}; i++)); do
        leading=$(_leading_word "${stages[$i]}")
        if [[ $i -gt 0 && "$leading" =~ ^(sh|bash|sudo|zsh|ksh|dash|fish)$ ]]; then
            return 1
        fi

        _classify_single_stage "${stages[$i]}"
        rc=$?
        if [[ $rc -eq 1 ]]; then
            return 1
        elif [[ $rc -eq 2 ]]; then
            unknown=1
        fi
    done

    if [[ $unknown -eq 1 ]]; then
        return 2
    fi
    return 0
}

# Returns: 0 = safe (should optimize), 1 = dangerous (never optimize), 2 = unknown (passthrough)
is_safe_command() {
    local cmd="$1"
    local unknown=0
    local rc
    local -a segments

    cmd=$(_trim_command "$cmd")

    mapfile -t segments < <(_split_compound "$cmd")
    if [[ ${#segments[@]} -eq 0 ]]; then
        return 2
    fi

    for segment in "${segments[@]}"; do
        _classify_segment "$segment"
        rc=$?
        if [[ $rc -eq 1 ]]; then
            log_message "INFO" "Command flagged dangerous: $cmd"
            return 1
        elif [[ $rc -eq 2 ]]; then
            unknown=1
        fi
    done

    if [[ $unknown -eq 1 ]]; then
        return 2
    fi
    return 0
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

# ── Complexity Scorer (S3: scores command optimization value) ─

# Scores a command 1-5 based on pipe count, subcommand count, flags, and arguments.
#   score ≤ 2 → skip optimization (simple enough, passthrough)
#   score ≥ 3 → allow optimization (cache lookup → Copilot CLI)
score_complexity() {
    local cmd="$1"
    local score=1

    # Count pipes (each pipe adds structural complexity)
    local pipes
    pipes=$(echo "$cmd" | grep -o '|' | wc -l)

    # Count subcommands $() and backticks
    local subcommands
    subcommands=$(echo "$cmd" | grep -oE '\$\(|`' | wc -l)

    # Count flags (long and short, first char after dash must be a letter)
    local flags
    flags=$(echo "$cmd" | grep -oE '\s--?[a-zA-Z][a-zA-Z0-9-]*' | wc -l)

    # Count non-flag, non-operator arguments
    local args
    args=$(echo "$cmd" | sed 's/|/ /g; s/&&/ /g; s/||/ /g; s/;/ /g' | tr ' ' '\n' | grep -vE '^-|^$' | wc -l)

    # Pipe scoring: 0 pipes = 0, 1-2 = +1, 3+ = +2
    if [[ $pipes -ge 3 ]]; then
        score=$((score + 2))
    elif [[ $pipes -ge 1 ]]; then
        score=$((score + 1))
    fi

    # Subcommand scoring: $() or backticks
    if [[ $subcommands -ge 1 ]]; then
        score=$((score + 1))
    fi

    # Flag scoring: 2+ flags suggest configurable intent
    if [[ $flags -ge 2 ]]; then
        score=$((score + 1))
    fi

    # Argument scoring: 6+ non-flag args suggest complex filtering/selection
    if [[ $args -ge 6 ]]; then
        score=$((score + 1))
    fi

    # Clamp to [1, 5]
    if [[ $score -gt 5 ]]; then
        score=5
    fi
    if [[ $score -lt 1 ]]; then
        score=1
    fi

    echo "$score"
}

# ── Goal Extraction (I2: parses [GOAL: ...] from description) ─

# Extract goal text from a command description.
# Matches [GOAL: <goal text>] anywhere in the description.
# Output: goal text on stdout (empty string if no marker found)
extract_goal() {
    local desc="$1"
    local goal
    goal=$(echo "$desc" | grep -oP '\[GOAL:\s*\K[^]]+' | head -1 2>/dev/null || true)
    if [[ -n "$goal" ]]; then
        goal=$(echo "$goal" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    echo "$goal"
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
# Args: tool_call_id, skeleton, original_command, optimized_command, [prev_skeleton]
write_bridge_state() {
    local call_id="$1"
    local skeleton="$2"
    local original="$3"
    local optimized="$4"
    local prev_skeleton="${5:-}"

    mkdir -p "$BRIDGE_DIR" 2>/dev/null || true
    local content
    content=$(jq -nc \
        --arg sk "$skeleton" \
        --arg orig "$original" \
        --arg opt "$optimized" \
        --arg psk "$prev_skeleton" \
        '{skeleton: $sk, original_command: $orig, optimized_command: $opt, prev_skeleton: $psk}' 2>/dev/null) || true
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
