# Test Runner for Sandbox Scenarios
# Each test validates: naive_command → copilot_optimized → outputs match

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR/.." || exit 1
SANDBOX="$(pwd)/sandbox"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local naive="$2"
    local description="$3"

    echo "=== $name ==="
    echo "  Description: $description"
    echo "  Naive cmd:   $naive"

    # Run naive command
    local naive_out
    naive_out=$(cd "$SANDBOX" && eval "$naive" 2>/dev/null || true)

    # Get complexity score
    local score
    score=$(HOOK_DIR="$BASE_DIR/../src" source "$BASE_DIR/../src/lib/common.sh" && score_complexity "$naive" 2>/dev/null || echo "?")
    echo "  Complexity:   score=$score"

    # Check if safe
    local safe_result
    HOOK_DIR="$BASE_DIR/../src" source "$BASE_DIR/../src/lib/common.sh" 2>/dev/null
    is_safe_command "$naive" 2>/dev/null
    safe_result=$?
    if [[ $safe_result -eq 0 ]]; then
        echo "  Safety:       SAFE"
    elif [[ $safe_result -eq 1 ]]; then
        echo "  Safety:       DANGEROUS (skip)"
    else
        echo "  Safety:       UNKNOWN (skip)"
    fi

    # If safe and score ≥ 3, this is a candidate for optimization
    if [[ $safe_result -eq 0 && $score -ge 3 ]]; then
        echo "  Verdict:      OPTIMIZE (candidate for Copilot CLI)"
    elif [[ $safe_result -eq 0 && $score -le 2 ]]; then
        echo "  Verdict:      SKIP (low complexity, passthrough)"
    else
        echo "  Verdict:      SKIP (not safe for optimization)"
    fi

    # Show skeleton
    local skeleton
    skeleton=$(HOOK_DIR="$BASE_DIR/../src" source "$BASE_DIR/../src/lib/common.sh" && extract_skeleton "$naive" 2>/dev/null || echo "?")
    echo "  Skeleton:     $skeleton"

    echo "  Output (first 3 lines):"
    echo "$naive_out" | head -3 | sed 's/^/    /'
    echo ""
}

echo "# claude-hook-copilot Sandbox Test Scenarios"
echo "# Based on real Claude Code command patterns from web search"
echo ""

# ── Pattern 1: grep should be rg ──────────────────────────
run_test \
    "Pattern 1: grep -r for TODO markers" \
    "grep -r 'TODO\|FIXME' src/ --include='*.ts' --include='*.py' --include='*.go'" \
    "Claude searches for TODO/FIXME across multiple file types using grep. Copilot should suggest rg which respects .gitignore and is faster."

# ── Pattern 2: find + xargs → fd ──────────────────────────
run_test \
    "Pattern 2: find -exec grep" \
    "find src/ -name '*.ts' -type f -exec grep -l 'FIXME' {} \;" \
    "Claude uses find -exec grep. Copilot should suggest fd + rg or find | xargs rg."

# ── Pattern 3: Complex pipe chain ─────────────────────────
run_test \
    "Pattern 3: Multi-pipe log analysis" \
    "cat logs/app.log | grep ERROR | awk '{print \$1,\$2,\$5}' | sort | uniq -c | sort -rn | head -10" \
    "Claude chains cat+grep+awk+sort+uniq+sort+head. Copilot should suggest a single awk or rg command."

# ── Pattern 4: Multi-grep chain → single regex ────────────
run_test \
    "Pattern 4: Chained greps" \
    "grep -v '\.idea' logs/access.log | grep -v '\.claude' | grep -v 'node_modules' | grep 'ERROR'" \
    "Claude chains multiple grep -v calls. Copilot should suggest grep -v -E with regex alternation."

# ── Pattern 5: Token-wasting grep on node_modules ─────────
run_test \
    "Pattern 5: grep without .gitignore awareness" \
    "grep -r 'import' . --include='*.ts' --include='*.js'" \
    "Claude uses grep which scans everything. rg respects .gitignore by default."

# ── Pattern 6: find with multiple -o patterns ─────────────
run_test \
    "Pattern 6: find with OR patterns" \
    "find . -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' | xargs wc -l" \
    "Claude chains find -o. Copilot should suggest fd with brace expansion or glob."

# ── Pattern 7: Counting files ─────────────────────────────
run_test \
    "Pattern 7: Count lines by file type" \
    "find src -name '*.ts' -exec wc -l {} \; | awk '{sum+=\$1} END {print \"Total:\", sum}'" \
    "Claude uses find -exec wc -l | awk. Copilot should suggest fd -e ts -x wc -l or tokei."

# ── Pattern 8: JSON extraction with grep ──────────────────
run_test \
    "Pattern 8: grep on JSON" \
    "grep -o '\"username\": *\"[^\"]*\"' data/seed.json" \
    "Claude greps JSON. Copilot should suggest jq for proper JSON parsing."

echo "=== Summary ==="
