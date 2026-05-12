# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the development repository for `claude-hook-copilot` — a Claude Code hook bridge that connects Claude's top-down reasoning with Copilot CLI's bottom-up command optimization.

## Bash Command Optimization

When you issue Bash commands, a PreToolUse hook may optimize them via Copilot CLI before execution. The hook has:
- A variant cache of previously successful optimizations
- Access to Copilot CLI for command optimization (rg, fd, jq, awk, etc.)
- A safety classifier that skips dangerous commands (rm, git push, sudo, etc.)

**You don't need to obsess over optimal flags or tool selection.** Focus on making the command's goal clear.

### Signaling Intent with [GOAL: ...]

When your Bash command has a non-obvious goal, prepend the goal marker to your description:

```
[GOAL: find all TODO and FIXME markers in TypeScript and Python source files]
```

The bridge extracts this goal and passes it to Copilot CLI, producing better-optimized commands. This is especially valuable for:
- Multi-step data processing pipelines
- File search with complex filtering
- Log analysis and aggregation
- Git history exploration

**What to do:**
- Add `[GOAL: <one-sentence description of what you want to achieve>]` to your Bash command description
- Write valid, executable bash — don't sacrifice correctness
- Let the bridge worry about `grep` vs `rg`, `find` vs `fd`, flag optimization, and pipeline simplification

**What NOT to do:**
- Don't write intentionally broken commands expecting the bridge to fix them
- Don't use `[GOAL: ...]` for trivial commands (echo, ls, cat single files)
- Don't skip writing a command entirely — the bridge optimizes, not generates from scratch
