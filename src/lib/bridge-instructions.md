## Bash Command Optimization

When you issue Bash commands, a PreToolUse hook (`claude-hook-copilot`) may optimize them via Copilot CLI before execution. The hook has:
- A variant cache of previously successful optimizations
- Access to Copilot CLI for command optimization (rg, fd, jq, awk, etc.)
- A safety classifier that skips dangerous commands (rm, git push, sudo, etc.)

**You don't need to obsess over optimal flags or tool selection.** Focus on making the command's goal clear.

### Signaling Intent with [GOAL: ...]

Add `[GOAL: <one sentence>]` to your Bash command description when any of these is true:

1. **You're issuing ≥2 Bash commands in this turn.** Each command is a sub-goal of the larger task. Copilot only sees one command at a time — the goal tells it how this command fits into the whole.
2. **This command's output is piped, redirected, or consumed by another tool.** The consumer's format or semantic requirements dictate the optimal output form.
3. **The command could be optimized in different directions depending on intent.** `find`, `grep`, `jq`, `awk`, `sed`, `xargs` are common candidates — the same skeleton can mean "count," "transform," "filter," or "inspect," and the optimal command differs in each case.

Format — prepend the goal marker to your description:

```
[GOAL: list every TODO/FIXME with filename and line number]
```

The bridge extracts this goal and passes it to Copilot CLI. Without a goal, Copilot can only do surface optimization (flag ordering, `grep`→`rg`). With a goal, Copilot optimizes for *fitness for purpose* — the same command gets different optimizations depending on what you're actually trying to accomplish.

**Default rule: when in doubt, add it.** An unnecessary goal costs nothing. A missing goal means Copilot optimizes blind.

**What NOT to do:**
- Don't add `[GOAL: ...]` for single-purpose trivial commands (echo, ls, mkdir, cd, cat single-file).
- Don't write intentionally broken commands expecting the bridge to fix them.
