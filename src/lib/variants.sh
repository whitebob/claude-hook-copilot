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
