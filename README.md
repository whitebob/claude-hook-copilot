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
