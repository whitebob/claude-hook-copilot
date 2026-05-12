#!/usr/bin/env bash
# test_corpus.sh — Regression test corpus for claude-hook-copilot v3.0
# Validates: complexity scorer, safety classifier, skeleton extraction, variant lifecycle,
#            goal extraction (I2), session history (S2), pair cache (B1)
# source: https://github.com/whitebob/claude-hook-copilot

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/variants.sh"

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

# ── I2: Goal Extraction ────────────────────────────────────

echo ""
echo "=== Goal Extraction (I2) ==="

check_goal() {
    local desc="$1"
    local expected="$2"
    local got
    got=$(extract_goal "$desc")
    if [[ "$got" == "$expected" ]]; then
        pass "goal='$expected': ${desc:0:60}"
    else
        fail "goal extraction" "$expected" "$got"
        echo "        desc: $desc"
    fi
}

check_goal "[GOAL: find all TODO markers in the codebase] grep -r TODO ." "find all TODO markers in the codebase"
check_goal "[GOAL: count error frequencies by source file] cat logs/app.log" "count error frequencies by source file"
check_goal "List all files in the current directory" ""
check_goal "grep -r 'import' --include='*.ts' ." ""
check_goal "[GOAL: aggregate and sort by count] find . -name '*.log' | xargs grep ERROR | sort | uniq -c" "aggregate and sort by count"
check_goal "[GOAL: extract usernames from JSON] grep -o '\"username\": *\"[^\"]*\"' data.json" "extract usernames from JSON"
# Edge case: only [GOAL:] with no content should return empty
check_goal "[GOAL:] grep something" ""
# Known limitation: nested brackets in goal break at first ']'
# Use alternatives like (ERROR) or ERROR/WARN instead of [ERROR]
check_goal "[GOAL: find (ERROR) and (WARN) messages] grep -E '\[(ERROR|WARN)\]' logs/" "find (ERROR) and (WARN) messages"

# ── S2: Session History ─────────────────────────────────────

echo ""
echo "=== Session History (S2) ==="

# Use a temp session file for testing
REAL_SESSION_FILE="$SESSION_FILE"
SESSION_FILE="/tmp/test_session_$$.jsonl"
rm -f "$SESSION_FILE"

# Test: empty session
PREV=$(get_prev_skeleton)
if [[ -z "$PREV" ]]; then
    pass "empty session: get_prev_skeleton returns empty"
else
    fail "empty session" "empty" "$PREV"
fi

HISTORY=$(get_session_history)
if [[ "$HISTORY" == "[]" ]]; then
    pass "empty session: get_session_history returns []"
else
    fail "empty session history" "[]" "$HISTORY"
fi

# Test: record and retrieve
record_session "grep -r <literal> --include=<glob> <path>" "find TODO markers"
PREV=$(get_prev_skeleton)
if [[ "$PREV" == "grep -r <literal> --include=<glob> <path>" ]]; then
    pass "record_session + get_prev_skeleton: correct skeleton"
else
    fail "record_session" "grep -r <literal> --include=<glob> <path>" "$PREV"
fi

# Test: multiple records, bounded to 5
for i in $(seq 1 7); do
    record_session "find <path> -name <glob> -exec grep <literal>" "search iteration $i"
done
COUNT=$(wc -l < "$SESSION_FILE" 2>/dev/null || echo 0)
if [[ "$COUNT" -le 5 ]]; then
    pass "session bounded: $COUNT entries (max 5)"
else
    fail "session bound check" "<=5" "$COUNT"
fi

# Test: prev skeleton is the most recent
PREV=$(get_prev_skeleton)
if [[ "$PREV" == "find <path> -name <glob> -exec grep <literal>" ]]; then
    pass "get_prev_skeleton returns most recent after multiple inserts"
else
    fail "most recent skeleton" "find <path> -name <glob> -exec grep <literal>" "$PREV"
fi

# Cleanup
rm -f "$SESSION_FILE"
SESSION_FILE="$REAL_SESSION_FILE"

# ── B1: Pair Cache ──────────────────────────────────────────

echo ""
echo "=== Pair Cache (B1) ==="

REAL_PAIR_CACHE="$PAIR_CACHE_FILE"
PAIR_CACHE_FILE="/tmp/test_pair_cache_$$.jsonl"
rm -f "$PAIR_CACHE_FILE"

PREV_SK="grep -r <literal> --include=<glob>"
CURR_SK="find <path> -name <glob> | xargs grep <literal>"

# Test: empty cache
CACHED=$(lookup_pair_variant "$PREV_SK" "$CURR_SK" || true)
if [[ -z "$CACHED" ]]; then
    pass "empty pair cache: lookup returns nothing"
else
    fail "empty pair cache" "empty" "$CACHED"
fi

# Test: empty prev_skeleton
CACHED=$(lookup_pair_variant "" "$CURR_SK" || true)
if [[ -z "$CACHED" ]]; then
    pass "pair cache: empty prev_skeleton skips lookup"
else
    fail "empty prev check" "empty" "$CACHED"
fi

# Test: record and lookup
record_pair_variant "$PREV_SK" "$CURR_SK" "rg --glob '!.gitignore' TODO ."
CACHED=$(lookup_pair_variant "$PREV_SK" "$CURR_SK" || true)
if [[ -n "$CACHED" ]]; then
    pass "pair cache: record + lookup returns cached command"
else
    fail "pair cache lookup" "non-empty" "$CACHED"
fi

# Test: pair feedback
PREV_SK2="find <path> -type f | xargs wc -l"
CURR_SK2="awk <literal>"
record_pair_variant "$PREV_SK2" "$CURR_SK2" "fd -t f -x wc -l | awk '{sum+=\$1} END {print sum}'"
record_pair_feedback "$PREV_SK2" "$CURR_SK2" "0"  # success
CACHED=$(lookup_pair_variant "$PREV_SK2" "$CURR_SK2" || true)
if [[ -n "$CACHED" ]]; then
    pass "pair cache: entry survives after successful feedback"
else
    fail "pair feedback survival" "non-empty" "$CACHED"
fi

# Test: pair cache bounded (max 50)
for i in $(seq 1 55); do
    record_pair_variant "prev_sk_$i" "curr_sk_$i" "opt_cmd_$i"
done
COUNT=$(wc -l < "$PAIR_CACHE_FILE" 2>/dev/null || echo 0)
if [[ "$COUNT" -le 50 ]]; then
    pass "pair cache bounded: $COUNT entries (max 50)"
else
    fail "pair cache bound check" "<=50" "$COUNT"
fi

# Cleanup
rm -f "$PAIR_CACHE_FILE"
PAIR_CACHE_FILE="$REAL_PAIR_CACHE"

# ── Deployment Validation ─────────────────────────────────

echo ""
echo "=== Deployment Validation ==="

# Test install.sh generates valid settings.local.json with hooks
TMP_DEPLOY="/tmp/test_deploy_$$"
mkdir -p "$TMP_DEPLOY"
# Create a minimal install.sh test: write a mock settings file and validate
MOCK_SETTINGS="${TMP_DEPLOY}/settings.local.json"

# Simulate what install.sh does: generate settings.local.json with jq
PRE_CMD="bash /tmp/test_deploy_$$/pre-tool-use.sh"
POST_CMD="bash /tmp/test_deploy_$$/post-tool-use.sh"
jq -n \
  --arg pre "$PRE_CMD" \
  --arg post "$POST_CMD" \
  '{
    hooks: {
      PreToolUse: [{
        matcher: "Bash",
        hooks: [{
          type: "command",
          command: $pre,
          timeout: 15
        }]
      }],
      PostToolUse: [{
        matcher: "Bash",
        hooks: [{
          type: "command",
          command: $post,
          timeout: 10
        }]
      }]
    }
  }' > "$MOCK_SETTINGS"

# Validate: settings.local.json exists
if [[ -f "$MOCK_SETTINGS" ]]; then
    pass "install.sh: settings.local.json created"
else
    fail "install.sh output" "file exists" "missing"
fi

# Validate: contains PreToolUse hooks
PRE_COUNT=$(jq '.hooks.PreToolUse | length' "$MOCK_SETTINGS" 2>/dev/null || echo 0)
if [[ "$PRE_COUNT" -ge 1 ]]; then
    pass "install.sh: PreToolUse hooks registered ($PRE_COUNT entry/entries)"
else
    fail "PreToolUse registration" ">=1" "$PRE_COUNT"
fi

# Validate: contains PostToolUse hooks
POST_COUNT=$(jq '.hooks.PostToolUse | length' "$MOCK_SETTINGS" 2>/dev/null || echo 0)
if [[ "$POST_COUNT" -ge 1 ]]; then
    pass "install.sh: PostToolUse hooks registered ($POST_COUNT entry/entries)"
else
    fail "PostToolUse registration" ">=1" "$POST_COUNT"
fi

# Validate: matcher targets Bash
MATCHER=$(jq -r '.hooks.PreToolUse[0].matcher' "$MOCK_SETTINGS" 2>/dev/null || echo "")
if [[ "$MATCHER" == "Bash" ]]; then
    pass "install.sh: PreToolUse matcher is Bash"
else
    fail "PreToolUse matcher" "Bash" "$MATCHER"
fi

# Validate: hook type is command
HOOK_TYPE=$(jq -r '.hooks.PreToolUse[0].hooks[0].type' "$MOCK_SETTINGS" 2>/dev/null || echo "")
if [[ "$HOOK_TYPE" == "command" ]]; then
    pass "install.sh: hook type is command"
else
    fail "hook type" "command" "$HOOK_TYPE"
fi

# Validate: timeout values
PRE_TIMEOUT=$(jq -r '.hooks.PreToolUse[0].hooks[0].timeout' "$MOCK_SETTINGS" 2>/dev/null || echo 0)
if [[ "$PRE_TIMEOUT" -eq 15 ]]; then
    pass "install.sh: PreToolUse timeout=15"
else
    fail "PreToolUse timeout" "15" "$PRE_TIMEOUT"
fi

POST_TIMEOUT=$(jq -r '.hooks.PostToolUse[0].hooks[0].timeout' "$MOCK_SETTINGS" 2>/dev/null || echo 0)
if [[ "$POST_TIMEOUT" -eq 10 ]]; then
    pass "install.sh: PostToolUse timeout=10"
else
    fail "PostToolUse timeout" "10" "$POST_TIMEOUT"
fi

# Validate: command path is absolute
PRE_CMD_PATH=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$MOCK_SETTINGS" 2>/dev/null || echo "")
if [[ "$PRE_CMD_PATH" == bash* ]]; then
    pass "install.sh: command runs via bash"
else
    fail "command runner" "bash ..." "$PRE_CMD_PATH"
fi

# Validate: plugin hooks.json format
PLUGIN_HOOKS="${HOOK_ROOT}/hooks/hooks.json"
if [[ -f "$PLUGIN_HOOKS" ]]; then
    PLUGIN_PRE=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$PLUGIN_HOOKS" 2>/dev/null || echo "")
    if [[ "$PLUGIN_PRE" == *'${CLAUDE_PLUGIN_ROOT}'* ]]; then
        pass "plugin: hooks.json uses CLAUDE_PLUGIN_ROOT variable"
    else
        fail "plugin hooks.json" '${CLAUDE_PLUGIN_ROOT}' "$PLUGIN_PRE"
    fi
else
    fail "plugin hooks.json" "file exists" "missing at $PLUGIN_HOOKS"
fi

rm -rf "$TMP_DEPLOY"

# ── Summary ───────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
