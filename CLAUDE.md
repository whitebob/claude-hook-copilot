# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the development repository for `claude-hook-copilot` — a Claude Code hook bridge that connects Claude's top-down reasoning with Copilot CLI's bottom-up command optimization.

## Development

- Source: `src/` (bash hook scripts)
- Deploy: `bash install.sh` copies to `~/.claude/copilot-cli-hook/`
- Tests: `bash src/tests/test_corpus.sh`
- Sandbox: `bash sandbox/run_tests.sh`

## Architecture

```
src/
├── pre-tool-use.sh       # PreToolUse hook (orchestrator)
├── post-tool-use.sh      # PostToolUse hook (feedback)
├── lib/
│   ├── common.sh         # Logging, classification, skeleton IR, goal extraction
│   ├── copilot.sh        # Copilot CLI integration
│   ├── variants.sh       # Variant library, session history, pair cache
│   └── bridge-instructions.md  # Deployed as BRIDGE.md (user-facing intent protocol)
└── tests/
    └── test_corpus.sh    # Regression tests
```
