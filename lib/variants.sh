#!/usr/bin/env bash
# variants.sh -- file-based variant library for command optimization caching
# source: https://github.com/whitebob/claude-hook-copilot

VARIANTS_FILE="${HOOK_DIR}/variants.jsonl"
FEEDBACK_FILE="${HOOK_DIR}/feedback.jsonl"
CONFIDENCE_NEW="${CONFIDENCE_NEW:-0.5}"
CONFIDENCE_BOOST="${CONFIDENCE_BOOST:-0.1}"
CONFIDENCE_PENALTY="${CONFIDENCE_PENALTY:-0.2}"
CONFIDENCE_THRESHOLD="${CONFIDENCE_THRESHOLD:-0.4}"
CONFIDENCE_PRUNE="${CONFIDENCE_PRUNE:-0.2}"

# Look up a cached variant by skeleton.
# Output: optimized_command on stdout
# Returns: 0 if found (confidence >= threshold), 1 if not found or too low confidence
lookup_variant() {
    local skeleton="$1"

    if [[ ! -f "$VARIANTS_FILE" ]]; then
        return 1
    fi

    local result
    result=$(grep -F "\"skeleton\":\"${skeleton}\"" "$VARIANTS_FILE" 2>/dev/null | tail -1)

    if [[ -z "$result" ]]; then
        return 1
    fi

    local confidence
    confidence=$(safe_jq "$result" '.confidence // 0' "0")

    if (( $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        local optimized
        optimized=$(safe_jq "$result" '.optimized_command' "")
        log_message "INFO" "Variant hit: skeleton=[${skeleton}] confidence=${confidence}"
        echo "$optimized"
        return 0
    fi

    log_message "INFO" "Variant skip: skeleton=[${skeleton}] confidence=${confidence} (below threshold)"
    return 1
}

# Record a new variant or update existing.
# Args: skeleton, original_command, optimized_command
record_variant() {
    local skeleton="$1"
    local original="$2"
    local optimized="$3"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Remove existing entry for this skeleton (idempotent update)
    if [[ -f "$VARIANTS_FILE" ]]; then
        sed -i "/\"skeleton\":\"${skeleton}\"/d" "$VARIANTS_FILE"
    fi

    jq -nc \
        --arg sk "$skeleton" \
        --arg orig "$original" \
        --arg opt "$optimized" \
        --arg now "$now" \
        --argjson conf "$CONFIDENCE_NEW" \
        '{skeleton: $sk, original_command: $orig, optimized_command: $opt, confidence: $conf, last_used: $now, success_count: 0, failure_count: 0}' \
        >> "$VARIANTS_FILE"

    log_message "INFO" "Variant recorded: skeleton=[${skeleton}] confidence=${CONFIDENCE_NEW}"
}

# Record feedback and update variant confidence.
# Args: skeleton, original_command, optimized_command, exit_code, result_summary
record_feedback() {
    local skeleton="$1"
    local original="$2"
    local optimized="$3"
    local exit_code="$4"
    local summary="${5:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Append feedback entry
    jq -nc \
        --arg ts "$now" \
        --arg sk "$skeleton" \
        --arg orig "$original" \
        --arg opt "$optimized" \
        --arg ec "$exit_code" \
        --arg summary "$summary" \
        '{timestamp: $ts, skeleton: $sk, original_command: $orig, optimized_command: $opt, exit_code: $ec, result_summary: $summary}' \
        >> "$FEEDBACK_FILE"

    # Update variant confidence
    if [[ ! -f "$VARIANTS_FILE" ]]; then
        return 0
    fi

    local current
    current=$(grep -F "\"skeleton\":\"${skeleton}\"" "$VARIANTS_FILE" 2>/dev/null | tail -1)
    if [[ -z "$current" ]]; then
        return 0
    fi

    local new_confidence
    local success_count
    local failure_count
    if [[ "$exit_code" == "0" ]]; then
        success_count=$(safe_jq "$current" '.success_count // 0' "0")
        success_count=$((success_count + 1))
        new_confidence=$(safe_jq "$current" ".confidence + ${CONFIDENCE_BOOST}" "0")
        failure_count=$(safe_jq "$current" '.failure_count // 0' "0")
    else
        failure_count=$(safe_jq "$current" '.failure_count // 0' "0")
        failure_count=$((failure_count + 1))
        new_confidence=$(safe_jq "$current" ".confidence - ${CONFIDENCE_PENALTY}" "0")
        success_count=$(safe_jq "$current" '.success_count // 0' "0")
    fi

    # Clamp confidence to [0, 1]
    new_confidence=$(echo "if ($new_confidence > 1) 1 else if ($new_confidence < 0) 0 else $new_confidence" | bc -l)

    # Remove if below prune threshold
    if (( $(echo "$new_confidence < $CONFIDENCE_PRUNE" | bc -l 2>/dev/null || echo 0) )); then
        sed -i "/\"skeleton\":\"${skeleton}\"/d" "$VARIANTS_FILE"
        log_message "INFO" "Variant pruned: skeleton=[${skeleton}] confidence=${new_confidence}"
        return 0
    fi

    # Update the entry in-place
    local updated
    updated=$(echo "$current" | jq -c \
        --argjson conf "$new_confidence" \
        --arg now "$now" \
        --argjson sc "$success_count" \
        --argjson fc "$failure_count" \
        '.confidence = $conf | .last_used = $now | .success_count = $sc | .failure_count = $fc' 2>/dev/null || echo "")

    # Replace the old entry
    sed -i "/\"skeleton\":\"${skeleton}\"/d" "$VARIANTS_FILE"
    echo "$updated" >> "$VARIANTS_FILE"

    log_message "INFO" "Variant feedback: skeleton=[${skeleton}] exit_code=${exit_code} new_confidence=${new_confidence}"
}

# Periodic cleanup: remove variants with confidence < 0.3 not used in 90 days.
# Called opportunistically (e.g., 1 in 50 invocations).
cleanup_variants() {
    if [[ ! -f "$VARIANTS_FILE" ]]; then
        return 0
    fi

    local cutoff
    cutoff=$(date -u -d '90 days ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || return 0

    local tmpfile="${VARIANTS_FILE}.tmp"
    while IFS= read -r line; do
        local conf last_used
        conf=$(safe_jq "$line" '.confidence // 0' "0")
        last_used=$(safe_jq "$line" '.last_used // ""' "")
        if (( $(echo "$conf < 0.3" | bc -l 2>/dev/null || echo 0) )) && [[ "$last_used" < "$cutoff" ]]; then
            log_message "INFO" "Variant cleanup: removing skeleton=[$(safe_jq "$line" '.skeleton' "unknown")]"
            continue
        fi
        echo "$line"
    done < "$VARIANTS_FILE" > "$tmpfile"
    mv "$tmpfile" "$VARIANTS_FILE"
}

# ── Session History (S2: tracks recent skeletons for temporal context) ─

SESSION_FILE="${HOOK_DIR}/session.jsonl"
SESSION_MAX_ENTRIES="${SESSION_MAX_ENTRIES:-5}"

# Record a command skeleton to session history.
# Args: skeleton, goal (optional, may be empty)
record_session() {
    local skeleton="$1"
    local goal="${2:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -nc \
        --arg sk "$skeleton" \
        --arg goal "$goal" \
        --arg ts "$now" \
        '{skeleton: $sk, goal: $goal, timestamp: $ts}' \
        >> "$SESSION_FILE" 2>/dev/null || true

    # Truncate to max entries (keep only the last N lines)
    if [[ -f "$SESSION_FILE" ]]; then
        local count
        count=$(wc -l < "$SESSION_FILE" 2>/dev/null || echo 0)
        if [[ $count -gt $SESSION_MAX_ENTRIES ]]; then
            local tmp="${SESSION_FILE}.tmp.$$"
            tail -n "$SESSION_MAX_ENTRIES" "$SESSION_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SESSION_FILE" 2>/dev/null || true
        fi
    fi
}

# Get the most recent skeleton from session history.
# Output: skeleton string on stdout (empty if no history)
get_prev_skeleton() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo ""
        return 0
    fi
    local prev
    prev=$(tail -1 "$SESSION_FILE" 2>/dev/null | jq -r '.skeleton // ""' 2>/dev/null || echo "")
    echo "$prev"
}

# Get full session history as JSON array (newest first).
# Output: JSON array on stdout, empty array if no history
get_session_history() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo "[]"
        return 0
    fi
    local history
    history=$(tac "$SESSION_FILE" 2>/dev/null | jq -sc '.' 2>/dev/null || echo "[]")
    echo "$history"
}

# ── Pair Cache (B1: pairs of consecutive commands share cached optimizations) ─

PAIR_CACHE_FILE="${HOOK_DIR}/pair_cache.jsonl"
PAIR_CACHE_MAX_ENTRIES="${PAIR_CACHE_MAX_ENTRIES:-50}"

# Look up a cached optimization by (prev_skeleton, curr_skeleton) pair.
# Args: prev_skeleton, curr_skeleton
# Output: optimized_command on stdout
# Returns: 0 if found, 1 if not found
lookup_pair_variant() {
    local prev_sk="$1"
    local curr_sk="$2"

    if [[ -z "$prev_sk" || ! -f "$PAIR_CACHE_FILE" ]]; then
        return 1
    fi

    local pair_key="${prev_sk}|||${curr_sk}"
    local result
    result=$(grep -F "\"pair_key\":\"${pair_key}\"" "$PAIR_CACHE_FILE" 2>/dev/null | tail -1)

    if [[ -z "$result" ]]; then
        return 1
    fi

    local confidence
    confidence=$(safe_jq "$result" '.confidence // 0' "0")

    if (( $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        local optimized
        optimized=$(safe_jq "$result" '.optimized_command' "")
        log_message "INFO" "Pair cache hit: prev=[${prev_sk}] curr=[${curr_sk}] confidence=${confidence}"
        echo "$optimized"
        return 0
    fi

    return 1
}

# Record or update a pair cache entry.
# Args: prev_skeleton, curr_skeleton, optimized_command
record_pair_variant() {
    local prev_sk="$1"
    local curr_sk="$2"
    local optimized="$3"
    local pair_key="${prev_sk}|||${curr_sk}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Remove existing entry for this pair key
    if [[ -f "$PAIR_CACHE_FILE" ]]; then
        sed -i "/\"pair_key\":\"${pair_key}\"/d" "$PAIR_CACHE_FILE" 2>/dev/null || true
    fi

    jq -nc \
        --arg pk "$pair_key" \
        --arg prev "$prev_sk" \
        --arg curr "$curr_sk" \
        --arg opt "$optimized" \
        --arg now "$now" \
        --argjson conf "$CONFIDENCE_NEW" \
        '{pair_key: $pk, prev_skeleton: $prev, curr_skeleton: $curr, optimized_command: $opt, confidence: $conf, last_used: $now, success_count: 0, failure_count: 0}' \
        >> "$PAIR_CACHE_FILE" 2>/dev/null || true

    # Truncate if over max
    if [[ -f "$PAIR_CACHE_FILE" ]]; then
        local count
        count=$(wc -l < "$PAIR_CACHE_FILE" 2>/dev/null || echo 0)
        if [[ $count -gt $PAIR_CACHE_MAX_ENTRIES ]]; then
            local tmp="${PAIR_CACHE_FILE}.tmp.$$"
            tail -n "$PAIR_CACHE_MAX_ENTRIES" "$PAIR_CACHE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$PAIR_CACHE_FILE" 2>/dev/null || true
        fi
    fi

    log_message "INFO" "Pair cache recorded: prev=[${prev_sk}] curr=[${curr_sk}]"
}

# Record feedback for a pair cache entry.
# Args: prev_skeleton, curr_skeleton, exit_code
record_pair_feedback() {
    local prev_sk="$1"
    local curr_sk="$2"
    local exit_code="$3"
    local pair_key="${prev_sk}|||${curr_sk}"

    if [[ ! -f "$PAIR_CACHE_FILE" ]]; then
        return 0
    fi

    local current
    current=$(grep -F "\"pair_key\":\"${pair_key}\"" "$PAIR_CACHE_FILE" 2>/dev/null | tail -1)
    if [[ -z "$current" ]]; then
        return 0
    fi

    local new_confidence
    local success_count
    local failure_count
    if [[ "$exit_code" == "0" ]]; then
        success_count=$(safe_jq "$current" '.success_count // 0' "0")
        success_count=$((success_count + 1))
        new_confidence=$(safe_jq "$current" ".confidence + ${CONFIDENCE_BOOST}" "0")
        failure_count=$(safe_jq "$current" '.failure_count // 0' "0")
    else
        failure_count=$(safe_jq "$current" '.failure_count // 0' "0")
        failure_count=$((failure_count + 1))
        new_confidence=$(safe_jq "$current" ".confidence - ${CONFIDENCE_PENALTY}" "0")
        success_count=$(safe_jq "$current" '.success_count // 0' "0")
    fi

    # Clamp confidence to [0, 1]
    new_confidence=$(echo "if ($new_confidence > 1) 1 else if ($new_confidence < 0) 0 else $new_confidence" | bc -l)

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Remove if below prune threshold
    if (( $(echo "$new_confidence < $CONFIDENCE_PRUNE" | bc -l 2>/dev/null || echo 0) )); then
        sed -i "/\"pair_key\":\"${pair_key}\"/d" "$PAIR_CACHE_FILE" 2>/dev/null || true
        log_message "INFO" "Pair cache pruned: pair_key=[${pair_key}] confidence=${new_confidence}"
        return 0
    fi

    # Update the entry
    local updated
    updated=$(echo "$current" | jq -c \
        --argjson conf "$new_confidence" \
        --arg now "$now" \
        --argjson sc "$success_count" \
        --argjson fc "$failure_count" \
        '.confidence = $conf | .last_used = $now | .success_count = $sc | .failure_count = $fc' 2>/dev/null || echo "")

    sed -i "/\"pair_key\":\"${pair_key}\"/d" "$PAIR_CACHE_FILE" 2>/dev/null || true
    echo "$updated" >> "$PAIR_CACHE_FILE" 2>/dev/null || true

    log_message "INFO" "Pair cache feedback: pair_key=[${pair_key}] exit_code=${exit_code} new_confidence=${new_confidence}"
}
