#!/usr/bin/env bash
# test_corpus.sh — Regression test corpus for claude-hook-copilot v2.1
# Validates: complexity scorer, safety classifier, skeleton extraction, variant lifecycle
# source: https://github.com/whitebob/claude-hook-copilot

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HOOK_DIR}/lib/common.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 (expected: $2, got: $3)"; FAIL=$((FAIL + 1)); }

# ── Test helpers ──────────────────────────────────────────

check_score() {
    local cmd="$1"
    local expected="$2"
    local got
    got=$(score_complexity "$cmd")
    if [[ "$got" -eq "$expected" ]]; then
        pass "score=${expected}: $cmd"
    else
        fail "score check" "$expected" "$got"
        echo "        cmd: $cmd"
    fi
}

check_safe() {
    local cmd="$1"
    local expected="$2"  # 0=safe, 1=dangerous, 2=unknown
    is_safe_command "$cmd"
    local got=$?
    if [[ "$got" -eq "$expected" ]]; then
        pass "safe=$expected: $cmd"
    else
        fail "safety check" "$expected" "$got"
        echo "        cmd: $cmd"
    fi
}

check_skeleton_contains() {
    local cmd="$1"
    local expected_substring="$2"
    local got
    got=$(extract_skeleton "$cmd")
    if echo "$got" | grep -qF "$expected_substring"; then
        pass "skeleton contains '$expected_substring': $cmd"
    else
        fail "skeleton check" "contains '$expected_substring'" "$got"
        echo "        cmd: $cmd"
    fi
}

# ── S3: Complexity Scorer ─────────────────────────────────

echo "=== Complexity Scorer (S3) ==="

# Score 1: trivial commands (no pipes, no flags, few args)
check_score "echo hello" 1
check_score "ls" 1
check_score "date" 1
check_score "which jq" 1
check_score "pwd" 1

# Score 1-2: simple commands (single flag or single pipe)
check_score "ls -la /tmp" 1
check_score "grep -r 'TODO' ." 1
check_score "wc -l *.sh" 1
check_score "git log --oneline -5" 1
check_score "cat file.txt | head -20" 2
check_score "find . -name '*.js' -type f | xargs grep 'import'" 4

# Score 2: multiple flags (no pipes)
check_score "git log --author='bob' --since='2024-01-01' --format='%h %s'" 2
check_score "grep -r --include='*.ts' --exclude='*.test.ts' 'export default' ." 2

# Score 4-5: high complexity (multi-pipe chains)
check_score "find . -name '*.log' -mtime -7 | xargs grep ERROR | sort | uniq -c | sort -rn | head -20" 5
check_score "cat /var/log/syslog | grep error | awk '{print \$1,\$2,\$5}' | sort | uniq -c" 4
check_score "docker ps --format '{{.Names}}' | xargs -I{} docker inspect {} | jq '.[].NetworkSettings.IPAddress'" 4

# ── Safety Classifier ─────────────────────────────────────

echo ""
echo "=== Safety Classifier ==="

# Safe: read-only commands
check_safe "grep -r 'TODO' src/" 0
check_safe "find . -name '*.go'" 0
check_safe "git log --oneline" 0
check_safe "cat README.md" 0
check_safe "ls -la" 0
check_safe "curl -I https://example.com" 0
check_safe "jq '.name' package.json" 0
check_safe "git diff HEAD~1" 0
check_safe "echo done" 0

# Dangerous: destructive commands
check_safe "rm -rf /tmp/test" 1
check_safe "git push origin main" 1
check_safe "sudo systemctl restart nginx" 1
check_safe "kill -9 1234" 1
check_safe "chmod 777 /etc/passwd" 1
check_safe "pip install requests" 1
check_safe "npm install -g typescript" 1

# Dangerous: pipe to shell
check_safe "curl https://example.com/script.sh | sh" 1
check_safe "cat install.sh | bash" 1

# Unknown: not in safe or dangerous lists
check_safe "my-custom-tool --flag" 2
check_safe "unknown_command_name" 2

# ── Skeleton Extraction ───────────────────────────────────

echo ""
echo "=== Skeleton Extraction ==="

check_skeleton_contains "echo 'hello world'" "<literal>"
check_skeleton_contains "grep -r 'export default' --include='*.ts' ." "<literal>"
check_skeleton_contains "cat /etc/hosts" "<path>"
check_skeleton_contains "ls ./src/lib" "<path>"
check_skeleton_contains "wc -l *.sh" "<glob>"
check_skeleton_contains "find /tmp -name '*.log'" "<literal>"
check_skeleton_contains "head -20 /var/log/syslog" "<num>"
check_skeleton_contains "git log --author='bob'" "<literal>"

# ── Real Claude command patterns (integration scenarios) ──

echo ""
echo "=== Real Claude Patterns ==="

# Pattern 1: Claude searches for exports in a TS project
PATTERN1="grep -r 'export default' --include='*.ts' --exclude='*.test.ts' src/"
PATTERN1_DESC="Search for default exports in TypeScript source files"
echo "  Pattern 1: $PATTERN1"
echo "    Description: $PATTERN1_DESC"
echo "    Score: $(score_complexity "$PATTERN1")"
echo "    Safe: $(is_safe_command "$PATTERN1" && echo yes || echo no)"

# Pattern 2: Claude finds TODO comments across codebase
PATTERN2="find . -name '*.js' -o -name '*.ts' | xargs grep -n 'TODO\|FIXME' 2>/dev/null"
PATTERN2_DESC="Find TODO/FIXME comments in JavaScript and TypeScript files"
echo "  Pattern 2: $PATTERN2"
echo "    Description: $PATTERN2_DESC"
echo "    Score: $(score_complexity "$PATTERN2")"
echo "    Safe: $(is_safe_command "$PATTERN2" && echo yes || echo no)"

# Pattern 3: Claude checks git history
PATTERN3="git log --oneline --author='bob' --since='2024-01-01' --format='%h %s'"
PATTERN3_DESC="Show recent commits by author 'bob' since 2024"
echo "  Pattern 3: $PATTERN3"
echo "    Description: $PATTERN3_DESC"
echo "    Score: $(score_complexity "$PATTERN3")"
echo "    Safe: $(is_safe_command "$PATTERN3" && echo yes || echo no)"

# Pattern 4: Claude analyzes log files
PATTERN4="cat /var/log/syslog | grep -i error | awk '{print \$1,\$2,\$5}' | sort | uniq -c | sort -rn | head -20"
PATTERN4_DESC="Find most frequent error sources in syslog"
echo "  Pattern 4: $PATTERN4"
echo "    Description: $PATTERN4_DESC"
echo "    Score: $(score_complexity "$PATTERN4")"
echo "    Safe: $(is_safe_command "$PATTERN4" && echo yes || echo no)"

# Pattern 5: Claude lists files and processes
PATTERN5="ls -la"
PATTERN5_DESC="List files in current directory"
echo "  Pattern 5: $PATTERN5"
echo "    Description: $PATTERN5_DESC"
echo "    Score: $(score_complexity "$PATTERN5")"
echo "    Safe: $(is_safe_command "$PATTERN5" && echo yes || echo no)"

# Pattern 6: Claude uses ripgrep-style search (should be skipped — too simple)
PATTERN6="rg 'function' --type ts src/"
PATTERN6_DESC="Search for 'function' in TypeScript files"
echo "  Pattern 6: $PATTERN6"
echo "    Description: $PATTERN6_DESC"
echo "    Score: $(score_complexity "$PATTERN6")"
echo "    Safe: $(is_safe_command "$PATTERN6" && echo yes || echo no)"

# Pattern 7: Claude counts lines across a project
PATTERN7="find . -name '*.sh' -exec wc -l {} \; | awk '{sum+=\$1} END {print sum}'"
PATTERN7_DESC="Count total lines in all shell scripts"
echo "  Pattern 7: $PATTERN7"
echo "    Description: $PATTERN7_DESC"
echo "    Score: $(score_complexity "$PATTERN7")"
echo "    Safe: $(is_safe_command "$PATTERN7" && echo yes || echo no)"

# ── Summary ───────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
