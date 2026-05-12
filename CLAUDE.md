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
