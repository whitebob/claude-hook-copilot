#!/usr/bin/env bash
# install.sh -- deploy claude-hook-copilot to ~/.claude/copilot-cli-hook/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/src"
TARGET_DIR="${HOME}/.claude/copilot-cli-hook"
SETTINGS_FILE="${HOME}/.claude/settings.local.json"

echo "=== claude-hook-copilot installer ==="

# 1. Create target directory
mkdir -p "${TARGET_DIR}/lib"
mkdir -p "${TARGET_DIR}/logs"
echo "[OK] Created ${TARGET_DIR}"

# 2. Copy all source files
cp "${SOURCE_DIR}/pre-tool-use.sh" "${TARGET_DIR}/pre-tool-use.sh"
cp "${SOURCE_DIR}/post-tool-use.sh" "${TARGET_DIR}/post-tool-use.sh"
cp "${SOURCE_DIR}/lib/"*.sh "${TARGET_DIR}/lib/" 2>/dev/null || true
chmod +x "${TARGET_DIR}/pre-tool-use.sh"
chmod +x "${TARGET_DIR}/post-tool-use.sh"
echo "[OK] Copied hook scripts"

# 3. Generate settings.local.json with hooks configuration
PRE_CMD="bash ${TARGET_DIR}/pre-tool-use.sh"
POST_CMD="bash ${TARGET_DIR}/post-tool-use.sh"
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
  }' > "${SETTINGS_FILE}"
echo "[OK] Generated ${SETTINGS_FILE}"

echo "=== Install complete ==="
echo "Hooks registered for Bash PreToolUse + PostToolUse"
echo "To rollback: rm ${SETTINGS_FILE}"
