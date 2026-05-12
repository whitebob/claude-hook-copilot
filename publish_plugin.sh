#!/usr/bin/env bash
# publish_plugin.sh — publish essential files from main to plugin branch
# Run on main branch. Builds a clean plugin distribution and pushes to plugin branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Pre-flight checks ─────────────────────────────────

BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
    echo "ERROR: must be on main branch (currently on ${BRANCH})"
    exit 1
fi

if ! git diff-index --quiet HEAD --; then
    echo "ERROR: working tree is dirty. Commit or stash changes first."
    exit 1
fi

VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
COMMIT_SHORT=$(git rev-parse --short HEAD)
echo "=== publish_plugin.sh v${VERSION} (main @ ${COMMIT_SHORT}) ==="

# ── Build plugin in temp directory ─────────────────────

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "[1/4] Building plugin structure..."

mkdir -p "$TMPDIR/.claude-plugin"
mkdir -p "$TMPDIR/hooks"
mkdir -p "$TMPDIR/lib"

# Plugin manifest
cp .claude-plugin/plugin.json "$TMPDIR/.claude-plugin/"

# Hook registration
cp hooks/hooks.json "$TMPDIR/hooks/"

# Hook scripts (rename: drop .sh extension for plugin convention)
cp src/pre-tool-use.sh  "$TMPDIR/hooks/pre-tool-use"
cp src/post-tool-use.sh "$TMPDIR/hooks/post-tool-use"
chmod +x "$TMPDIR/hooks/pre-tool-use" "$TMPDIR/hooks/post-tool-use"

# Library scripts
cp src/lib/common.sh    "$TMPDIR/lib/"
cp src/lib/copilot.sh   "$TMPDIR/lib/"
cp src/lib/variants.sh  "$TMPDIR/lib/"

# Plugin CLAUDE.md: combine project context + bridge user instructions
cat > "$TMPDIR/CLAUDE.md" << 'CLAUDE_EOF'
# claude-hook-copilot

A Claude Code hook bridge that connects your top-down reasoning with Copilot CLI's bottom-up command optimization.

## What This Plugin Does

When you issue Bash commands, a PreToolUse hook optimizes them via Copilot CLI before execution:
- **Variant cache** — previously successful optimizations are cached with confidence scoring
- **Copilot CLI integration** — `rg`, `fd`, `jq`, `awk` and other tool optimizations
- **Safety classifier** — dangerous commands (rm, git push, sudo, etc.) are never touched
- **Complexity scorer** — simple commands (score ≤ 2) pass through unchanged
- **Pair cache** — sequential command pairs share cached optimizations

## How You Can Help: [GOAL: ...] Markers

You don't need to obsess over optimal flags or tool selection. Focus on making the command's goal clear.

When your Bash command has a non-obvious goal, prepend this marker to your description:

```
[GOAL: find all TODO and FIXME markers in TypeScript and Python source files]
```

The bridge extracts this goal and passes it to Copilot CLI, producing better-optimized commands.

**This is especially valuable for:**
- Multi-step data processing pipelines (cat|grep|awk|sort|uniq chains)
- File search with complex filtering (find -exec, multi-grep)
- Log analysis and aggregation
- Git history exploration

**What to do:**
- Add `[GOAL: <one-sentence description of what you want to achieve>]` to descriptions
- Write valid, executable bash — don't sacrifice correctness
- Let the bridge handle `grep` vs `rg`, `find` vs `fd`, flag selection, pipeline simplification

**What NOT to do:**
- Don't write intentionally broken commands expecting fixes
- Don't use `[GOAL: ...]` for trivial commands (echo, ls, cat single files)
- Don't skip writing a command entirely — the bridge optimizes, not generates from scratch

## Architecture

```
Claude Code (intent) → PreToolUse hook → Copilot CLI (optimization) → execution → PostToolUse feedback
```

- **PreToolUse**: intercepts Bash calls, scores complexity, checks cache, calls Copilot
- **PostToolUse**: records exit codes, updates variant confidence (±0.1/±0.2)
- **Variant library**: self-improving file-based knowledge base (variants.jsonl)
- **Pair cache**: remembers (prev_cmd, curr_cmd) optimization pairs
- **Session history**: tracks recent command skeletons for temporal context

## Failure Degradation

Every failure mode degrades to passthrough (original command executes unchanged):
- Copilot CLI unavailable/timeout → passthrough
- Average latency > 10s → auto-disable Copilot
- Hook approaching 15s timeout → force passthrough
- Any unexpected error → passthrough (ERROR trap, never blocks tools)

## Requirements

- `gh` CLI (v2.x+) with `copilot` extension installed
- `jq` (v1.6+)
- `bash` (v4+)

## Source

https://github.com/whitebob/claude-hook-copilot
CLAUDE_EOF

# Simplified README for plugin users
cat > "$TMPDIR/README.md" << 'README_EOF'
# claude-hook-copilot

A Claude Code plugin that bridges Claude's top-down reasoning with Copilot CLI's bottom-up command optimization.

## Installation

```
/plugin install github:whitebob/claude-hook-copilot@plugin
```

Or add the marketplace and install:
```
/plugin add marketplace github:whitebob/claude-hook-copilot
/plugin install claude-hook-copilot
```

## What It Does

Optimizes your Bash commands automatically:
- `grep -r 'TODO' .` → `rg 'TODO' .`
- `find . -name '*.ts' | xargs grep 'FIXME'` → `rg --glob '*.ts' 'FIXME' .`
- Complex pipe chains → simplified single-command equivalents

Uses Copilot CLI to suggest better tools, flags, and pipelines.

## Requirements

- GitHub CLI (`gh`) with Copilot extension (`gh copilot`)
- `jq`
- `bash` 4+

## Uninstall

```
/plugin uninstall claude-hook-copilot
```

## How It Works

```
Bash command → PreToolUse hook → Copilot CLI optimize → execute → PostToolUse feedback → cache
```

- Safe commands (grep, find, git log, etc.) are optimized
- Dangerous commands (rm, git push, sudo, etc.) pass through unchanged
- Simple commands (ls, echo, cat) pass through unchanged
- Failed optimizations degrade to original command

## [GOAL: ...] Markers

Add intent to your command descriptions for better optimizations:

```
[GOAL: aggregate error counts by source file]
```

The bridge passes this context to Copilot CLI for richer results.

## Source

https://github.com/whitebob/claude-hook-copilot
README_EOF

# Plugin .gitignore — runtime files only
cat > "$TMPDIR/.gitignore" << 'GITIGNORE_EOF'
# Runtime state (created at plugin execution time)
logs/
.bridge/
variants.jsonl
feedback.jsonl
latency.jsonl
session.jsonl
pair_cache.jsonl
GITIGNORE_EOF

echo "[2/4] Plugin structure built:"
find "$TMPDIR" -type f | sed "s|$TMPDIR||" | sort

# ── Publish to plugin branch ───────────────────────────

echo "[3/4] Publishing to plugin branch..."

# Create or switch to plugin branch
if git show-ref --verify --quiet refs/heads/plugin; then
    git checkout plugin
else
    git checkout --orphan plugin
    git rm -rf . 2>/dev/null || true
fi

# Clear the branch
git rm -rf . 2>/dev/null || true

# Copy new content
cp -r "$TMPDIR"/. "$PWD/" 2>/dev/null || true
cp -r "$TMPDIR"/.claude-plugin "$PWD/" 2>/dev/null || true

# Stage and commit
git add -A
git commit -m "publish: v${VERSION} from main @ ${COMMIT_SHORT}

- Plugin manifest: .claude-plugin/plugin.json
- Hooks: PreToolUse + PostToolUse for Bash tool
- Lib: common.sh, copilot.sh, variants.sh
- CLAUDE.md: auto-loaded by Claude Code (bridge + [GOAL:] docs)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

echo "[4/4] Pushing plugin branch..."

# Force push plugin branch (this is a generated branch)
git push origin plugin --force

# Return to main
git checkout main

echo ""
echo "=== Done ==="
echo "Plugin v${VERSION} published to origin/plugin"
echo "Install: /plugin install github:whitebob/claude-hook-copilot@plugin"
