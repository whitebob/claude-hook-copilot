# claude-hook-copilot

A bridge layer that connects Claude Code's top-down reasoning with Copilot CLI's bottom-up command optimization — via Claude Code's hooks mechanism.

```
      ▐▛███▜▌             ╭─╮╭─╮
     ▝▜█████▛▘            ╰─╯╰─╯
       ▘▘ ▝▝              █ ▘▝ █
                          ▔▔▔▔

    C L A U D E           C O P I L O T
        └─────────┬─────────┘
           hook-copilot bridge
```

## Design Philosophy

```
         TOP-DOWN                              BOTTOM-UP
    (intent → execution)                  (tool knowledge → command)

   ┌──────────────────┐                ┌──────────────────┐
   │   Claude Code     │                │   Copilot CLI     │
   │                    │                │                    │
   │  Understands WHAT  │                │  Knows HOW to      │
   │  you want to do   │                │  express it best   │
   │                    │                │                    │
   │  Decomposes goals  │                │  Mastery of CLI    │
   │  Plans steps       │                │  tools & flags     │
   │  Reasons about     │                │  Optimal pipelines │
   │  architecture      │                │  Elegant one-liners│
   └────────┬───────────┘                └────────┬───────────┘
            │                                     │
            │    ┌─────────────────────┐          │
            │    │  claude-hook-copilot │          │
            └───►│                     │◄─────────┘
                 │   PreToolUse hook   │
                 │         │           │
                 │   Skeleton IR       │
                 │         │           │
                 │   Variant Cache ────┘
                 │         │
                 │   Optimized Command │
                 └─────────┬───────────┘
                           │
                           ▼
                 ┌──────────────────┐
                 │  Bash Execution   │
                 └─────────┬─────────┘
                           │
                 ┌─────────▼─────────┐
                 │  PostToolUse hook │
                 │  Feedback loop    │
                 │  Confidence update│
                 └───────────────────┘

   Two ecosystems. Zero direct integration.
   The hook is the only contact surface.
   Each side does what it does best.
```

### The Coordination Problem

Claude doesn't know the bridge exists. From its perspective, every Bash command it writes goes directly to execution — so it must invest cognitive budget in getting bash syntax, flags, tool selection, and pipeline construction exactly right. If it doesn't, the user blames Claude alone.

```
   What Claude Sees                   What the Bridge Sees
   ┌────────────────────┐            ┌────────────────────────────┐
   │ User: "find TODOs"  │            │ stdin: {tool_name, cmd,     │
   │                     │            │   description, tool_call_id} │
   │ Claude thinks:      │            │                            │
   │ "I must write       │            │ variants.jsonl: history of  │
   │  correct bash or    │            │ what worked before          │
   │  the user will      │            │                            │
   │  blame ME"          │            │ Copilot CLI: can optimize   │
   │                     │            │ this command                │
   │ Blind spot:         │            │                            │
   │ Bridge exists ──────┼───────────►│ Blind spot:                │
   │ Copilot available   │            │ Claude's full task context  │
   └────────────────────┘            └────────────────────────────┘
```

This is a coordination trap: both systems want the user to succeed, but Claude can't delegate because it doesn't know the delegate exists.

### What's Essential vs. What's Conventional

Not all of Claude's command-writing effort is necessary. Decompose what a Bash command requires:

| Layer | Requirement | Verdict |
|-------|------------|---------|
| Bash must receive parseable input | `grep` not `grepp` | **Essential** — Bash won't execute invalid syntax |
| Claude must pick the right tool | `grep` vs `rg` vs `fd` | **Conventional** — Copilot knows tools better |
| Claude must get flags exactly right | `--include` vs `--glob` | **Conventional** — Copilot handles this |
| Claude must build optimal pipelines | 5 pipes vs 1 awk | **Conventional** — Copilot excels here |

**Claude only needs to produce valid, executable bash — not optimal bash.** The gap between "valid" and "optimal" is where the bridge adds value. Claude's attention is wasted on the three conventional layers.

### Specialization Enforcement

Without the bridge, each system must compensate for the other's absence. Claude stretches into tool expertise; Copilot stretches into intent understanding. Both become mediocre at what the other does best.

```
   Without Bridge:                    With Bridge:
   ─────────────────                  ─────────────
   Claude ────────────────────        Claude ── intent ────┐
     │  "I must know grep flags"        │  "I describe what"  │
     │  "I must pick optimal tool"      │                     │
     │  "I must build the pipeline"     │                     ▼
     │                          ┌──────────────────────────────┐
     │                          │           BRIDGE             │
     │                          │    cache + route + feedback  │
     │                          └──────────────────────────────┘
     │                                         │
   Copilot ───────────────────                 ▼
     │  "I only see the command"    Copilot ── execution ────┐
     │  "I have no task context"      │  "I execute exactly"   │
     │                                │  "I learn from results" │
```

The bridge is not primarily an optimizer. **The bridge is a specialization enforcement mechanism.** It creates a protocol boundary that lets each system double down on its core competence:

- **Claude** focuses on intent understanding, task decomposition, and architectural reasoning — freed from bash trivia
- **Copilot** focuses on tool selection, flag optimization, and pipeline construction — with a feedback loop it never had before
- **The bridge's deeper value**: It prevents the capability convergence that would make both systems compete for the same niche

## Architecture

```
~/.claude/
├── settings.local.json          # Hook registration (generated by install.sh)
└── copilot-cli-hook/            # Deployed hook scripts
    ├── pre-tool-use.sh          # Intercepts Bash calls before execution
    ├── post-tool-use.sh         # Captures results after execution
    ├── lib/
    │   ├── common.sh            # Logging, classification, skeleton IR, goal extraction, bridge state
    │   ├── copilot.sh           # Copilot CLI integration (goal-aware optimize_command)
    │   └── variants.sh          # Variant library (cache, feedback, session history, pair cache, cleanup)
    ├── BRIDGE.md                # Intent protocol instructions (non-invasive, never touches CLAUDE.md)
    ├── variants.jsonl           # Runtime: cached command optimizations
    ├── feedback.jsonl           # Runtime: execution feedback history
    ├── latency.jsonl            # Runtime: Copilot response time tracking (S4)
    ├── session.jsonl            # Runtime: recent skeleton+goal triples (S2)
    ├── pair_cache.jsonl         # Runtime: (prev, curr) pair optimizations (B1)
    ├── .bridge/                 # Runtime: pre→post hook state passing
    └── logs/
        └── copilot-hook.log     # Runtime: operational logs
```

## Full Workflow

```
                        PreToolUse Hook
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                   │
   │   Claude issues Bash command                                      │
   │          │                                                        │
   │          ▼                                                        │
   │   ┌──────────────┐                                                │
   │   │  Read stdin   │  {tool_name, tool_input: {command, desc}}     │
   │   └──────┬───────┘                                                │
   │          │                                                        │
   │          ▼                                                        │
   │   ┌──────────────┐     ┌─────────────┐                           │
   │   │ is_safe_cmd? │────►│ DANGEROUS    │──► PASSTHROUGH           │
   │   └──────┬───────┘     │ rm, git push │    (echo original JSON)   │
   │          │ safe        │ sudo, kill   │                           │
   │          ▼             └─────────────┘                           │
   │   ┌──────────────┐                                                │
   │   │ extract       │  "grep -r TODO . --include='*.ts'"            │
   │   │ skeleton()    │  → "grep -r <literal> --include=<literal>"   │
   │   └──────┬───────┘                                                │
   │          │                                                        │
   │          ▼                                                        │
   │   ┌──────────────┐                                                │
   │   │ lookup variant│  variants.jsonl                               │
   │   │ in cache?     │  {skeleton, optimized_cmd, confidence}        │
   │   └──┬────────┬──┘                                                │
   │      │        │                                                   │
   │   HIT│        │MISS                                               │
   │      │        │                                                   │
   │      │        ▼                                                   │
   │      │   ┌──────────────┐                                         │
   │      │   │ Copilot CLI   │  gh copilot -p "optimize..."           │
   │      │   │ optimize      │  timeout ${COPILOT_TIMEOUT}s           │
   │      │   └──┬────────┬──┘                                         │
   │      │      │        │                                            │
   │      │    OK│        │FAIL/TIMEOUT                                │
   │      │      │        │                                            │
   │      │      │        └──────────────► PASSTHROUGH                │
   │      │      │                          (echo original JSON)       │
   │      │      ▼                                                     │
   │      │   ┌──────────────┐                                         │
   │      │   │ record variant│  variants.jsonl ← new entry (0.5)     │
   │      │   │ write bridge  │  .bridge/{tool_call_id}.json          │
   │      │   └──────┬───────┘                                         │
   │      │          │                                                 │
   │      └──────────┼──────────┐                                     │
   │                 │          │                                      │
   │                 ▼          ▼                                      │
   │          ┌──────────────────────┐                                 │
   │          │  Replace command in   │  jq '.tool_input.command = $opt'│
   │          │  JSON, echo stdout    │                                 │
   │          └──────────┬───────────┘                                 │
   │                     │                                              │
   └─────────────────────┼──────────────────────────────────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Bash runs    │
                  │  optimized    │
                  │  command      │
                  └──────┬───────┘
                         │
                         ▼
                   PostToolUse Hook
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                   │
   │   ┌──────────────┐                                                │
   │   │  Read stdin   │  {tool_name, result: {exit_code, stdout}}     │
   │   └──────┬───────┘                                                │
   │          │                                                        │
   │          ▼                                                        │
   │   ┌──────────────┐                                                │
   │   │ read bridge   │  .bridge/{tool_call_id}.json                  │
   │   │ state         │  {skeleton, original_cmd, optimized_cmd}     │
   │   └──────┬───────┘                                                │
   │          │                                                        │
   │          ▼                                                        │
   │   ┌──────────────────────────────────┐                           │
   │   │  record_feedback()                │                           │
   │   │                                    │                           │
   │   │  exit_code=0 → confidence +0.1    │                           │
   │   │  exit_code≠0 → confidence -0.2    │                           │
   │   │                                    │                           │
   │   │  confidence < 0.4 → skip cache    │                           │
   │   │  confidence < 0.2 → auto-prune    │                           │
   │   └──────────────────────────────────┘                           │
   │                                                                   │
   │   exit 0  (always passthrough — no modification)                  │
   └──────────────────────────────────────────────────────────────────┘
```

## Command Classification

| Category | Examples | Action |
|----------|---------|--------|
| **Safe** (optimize) | `grep`, `find`, `git log`, `jq`, `curl -I`, `ls`, `cat`, `wc`, `sort` | Skeleton → cache/Copilot |
| **Dangerous** (skip) | `rm`, `mv`, `git push`, `sudo`, `kill`, `chmod`, `pip install` | Always passthrough |
| **Pipe-to-shell** (skip) | `... \| sh`, `... \| bash`, `... \| sudo` | Always passthrough |
| **Redirection** (skip) | `cmd > file`, `cmd >> file` | Always passthrough |
| **Unknown** (skip) | Anything not in safe/dangerous lists | Always passthrough |

## Variant Library

The variant library is a self-improving file-based knowledge base.

```
variants.jsonl  (one JSON object per line)

{
  "skeleton":        "grep -r <literal> --include=<literal>",   ← normalized IR
  "original_command": "grep -r TODO . --include='*.ts'",
  "optimized_command":"rg --glob '*.ts' 'TODO' .",              ← Copilot's output
  "confidence":       0.7,           ← 0.5 new, ±0.1/±0.2 per result
  "last_used":       "2026-05-12T11:00:00Z",
  "success_count":    2,
  "failure_count":    0
}
```

**Confidence lifecycle:**
```
      ┌─────────┐
      │ 0.5 NEW  │  First Copilot optimization recorded
      └────┬─────┘
           │
    ┌──────┴──────┐
    ▼              ▼
┌───────┐     ┌──────────┐
│ SUCCESS│     │ FAILURE   │
│ +0.1   │     │ -0.2      │
└───┬───┘     └─────┬─────┘
    │               │
    ▼               ▼
  ≥0.6 good     ≤0.3 degraded
  (cache hit)   (cache skip, re-query Copilot)
    │               │
    ▼               ▼
  ≥0.9 frozen    ≤0.2 pruned (auto-delete)
```

## Installation

```bash
git clone https://github.com/whitebob/claude-hook-copilot.git
cd claude-hook-copilot
bash install.sh
```

**What install.sh does:**
1. Copies hook scripts to `~/.claude/copilot-cli-hook/`
2. Generates `~/.claude/settings.local.json` with PreToolUse + PostToolUse hooks
3. Creates `logs/` directory for operational logging

**Requirements:**
- `gh` CLI (v2.x+) with `copilot` extension installed
- `jq` (v1.6+)
- `bash` (v4+)

## Rollback

```bash
# Disable all hooks
rm ~/.claude/settings.local.json

# Passthrough-only mode (log, don't optimize)
export COPILOT_BRIDGE_MODE=passthrough

# Skip optimization for a single command
# Add [no-optimize] anywhere in the command description
```

## Failure Degradation

| Failure | Response | v2.1 Protection |
|---------|----------|-----------------|
| Copilot CLI unavailable | Passthrough original command | — |
| Copilot timeout (12s) | Passthrough original command | S4: auto-disable if avg latency >10s |
| Copilot avg latency > 10s | Skip Copilot, passthrough | S4: `is_copilot_latency_healthy()` gate |
| JSONL parse error | Passthrough, log warning | H4: `safe_jq()` never crashes |
| Hook script error | Exit 0 with original input (H2) | H2: ERROR trap |
| Hook approaching 15s timeout | Force passthrough (H1) | H1: `check_time_budget()` at 10s |
| Variant low confidence | Skip cache, re-query Copilot | — |
| Variant file corruption | Skip cache, re-query Copilot | H3: atomic writes prevent corruption |
| Bridge state lost | Skip feedback recording | H3: tmp+mv prevents partial writes |
| Simple command (score ≤ 2) | Passthrough directly (S3) | S3: complexity scorer |
| Proven simple command (conf ≥ 0.7) | Use cached optimization (S5) | S5: cached exception |

## Known Limitations

- **Copilot CLI latency**: First query takes 6-12 seconds; variant cache hits reduce this to zero; pair cache (v3.1) further improves hit rate for sequential commands; S4 auto-disables if avg > 10s
- **Hook survival**: Hooks are loaded at session start; may not survive Claude Code session compaction
- **Claude awareness**: BRIDGE.md (v3.0) tells Claude about the bridge when deployed to `~/.claude/copilot-cli-hook/`. Claude's adoption of [GOAL: ...] markers depends on whether it reads this file. Users can optionally `source` it from their CLAUDE.md for stronger visibility
- **Goal parsing limitation**: Nested brackets `[GOAL: find [ERROR] messages]` break at first `]` — use parentheses or other alternatives in goal text
- **Single-command optimization**: Pair cache (v3.1) addresses two-command sequences; longer sequences (Markov) are deferred to Turn 4
- **Skeleton granularity**: Same skeleton may match commands with different intent; goal-aware caching (Turn 4) could improve this
- **Complexity threshold static**: Score threshold (≤2 skip) is fixed; auto-calibration needs scorer deployment data first (deferred to Turn 4)

## Changelog

### v2.1 Decision Pipeline (Current)

```
                          ┌─────────────────────────┐
                          │  Claude issues Bash cmd  │
                          └────────────┬────────────┘
                                       │
                                       ▼
                          ┌─────────────────────────┐
                          │  PreToolUse Hook reads   │
                          │  stdin JSON              │
                          └────────────┬────────────┘
                                       │
                                       ▼
                          ┌─────────────────────────┐
                          │  H1: Time budget check   │
                          │  (>10s? → passthrough)  │
                          └────────────┬────────────┘
                                       │ OK
                                       ▼
                          ┌─────────────────────────┐
                          │  Bash tool only?         │──► No → PASSTHROUGH
                          └────────────┬────────────┘
                                       │ Yes
                                       ▼
                          ┌─────────────────────────┐
                          │  is_safe_command()?      │──► DANGEROUS → SKIP
                          │  (S0: safety classify)  │
                          └────────────┬────────────┘
                                       │ Safe
                                       ▼
                          ┌─────────────────────────┐
                          │  extract_skeleton()      │
                          │  normalize cmd → IR      │
                          └────────────┬────────────┘
                                       │
                                       ▼
                          ┌─────────────────────────┐
                          │  S3: score_complexity()  │
                          │  pipes+flags+subs+args   │
                          └────────────┬────────────┘
                                       │
                         ┌─────────────┴─────────────┐
                         │                           │
                         ▼ score ≤ 2                 ▼ score ≥ 3
              ┌──────────────────────┐    ┌──────────────────────┐
              │  S5: cached except?   │    │  lookup_variant()     │
              │  conf ≥ 0.7 in cache? │    │  in variants.jsonl?   │
              └──────────┬───────────┘    └──────────┬───────────┘
                         │                           │
               ┌─────────┴─────────┐       ┌─────────┴─────────┐
               │                   │       │                   │
               ▼ Yes               ▼ No    ▼ HIT               ▼ MISS
        ┌────────────┐    ┌────────────┐ ┌──────────┐  ┌──────────────┐
        │ USE CACHED │    │ PASSTHROUGH│ │USE CACHED│  │ S4: latency  │
        │ (exception)│    │ (skip)     │ │OPTIMIZED │  │ healthy?     │
        └────────────┘    └────────────┘ └──────────┘  └──────┬───────┘
                                                              │
                                                    ┌─────────┴─────────┐
                                                    │ Yes               │ No (avg>10s)
                                                    ▼                   ▼
                                             ┌──────────────┐  ┌──────────────┐
                                             │ Copilot CLI  │  │ PASSTHROUGH  │
                                             │ optimize     │  │ (skip)       │
                                             │ (12s timeout)│  └──────────────┘
                                             └──────┬───────┘
                                                    │
                                           ┌────────┴────────┐
                                           │ OK              │ FAIL/TIMEOUT
                                           ▼                 ▼
                                    ┌──────────────┐  ┌──────────────┐
                                    │ record       │  │ PASSTHROUGH  │
                                    │ variant (0.5)│  │              │
                                    │ write bridge │  └──────────────┘
                                    └──────┬───────┘
                                           │
                                           ▼
                                    ┌──────────────┐
                                    │ jq replace   │
                                    │ command in   │
                                    │ JSON → stdout│
                                    └──────────────┘
                                           │
                                           ▼
                                    ┌──────────────┐
                                    │ Bash executes │
                                    │ optimized cmd │
                                    └──────┬───────┘
                                           │
                                           ▼
                              ┌─────────────────────────┐
                              │  PostToolUse Hook        │
                              │  read bridge state       │
                              │  record_feedback()       │
                              │  ±confidence update      │
                              │  opportunistic cleanup   │
                              └─────────────────────────┘
```

### v2.1 Defense-in-Depth Layers

```
   ┌─────────────────────────────────────────────────────────────┐
   │                    DEFENSE LAYERS                           │
   │                                                             │
   │  Layer 1: EARLY EXIT                                        │
   │  ┌───────────────────────────────────────────────────────┐  │
   │  │ H1: Time budget >10s → passthrough (prevents timeout) │  │
   │  │ S3: Complexity ≤2 → passthrough (simple commands)     │  │
   │  │ Safety: rm/git push/sudo → passthrough (dangerous)    │  │
   │  │ Non-Bash tools → passthrough (Read/Write/Edit)        │  │
   │  └───────────────────────────────────────────────────────┘  │
   │                          │                                  │
   │                          ▼                                  │
   │  Layer 2: CACHE FIRST                                       │
   │  ┌───────────────────────────────────────────────────────┐  │
   │  │ Variant cache hit → use optimized (skip Copilot CLI)  │  │
   │  │ S5: Simple commands + high conf → still use cache     │  │
   │  └───────────────────────────────────────────────────────┘  │
   │                          │                                  │
   │                          ▼                                  │
   │  Layer 3: GUARDED OPTIMIZATION                              │
   │  ┌───────────────────────────────────────────────────────┐  │
   │  │ S4: Latency health check → too slow → skip            │  │
   │  │ Copilot CLI timeout 12s → passthrough on failure      │  │
   │  └───────────────────────────────────────────────────────┘  │
   │                          │                                  │
   │                          ▼                                  │
   │  Layer 4: RESILIENCE                                        │
   │  ┌───────────────────────────────────────────────────────┐  │
   │  │ H2: ERROR trap → never exit non-zero (always 0)       │  │
   │  │ H3: Atomic writes → tmp+mv (no corruption)            │  │
   │  │ H4: safe_jq → parse failure → default value           │  │
   │  └───────────────────────────────────────────────────────┘  │
   └─────────────────────────────────────────────────────────────┘
```

### v2.1 Component Interaction Map

```
                      ┌──────────────────┐
                      │   pre-tool-use.sh │
                      │   (orchestrator)  │
                      └────────┬─────────┘
                               │ sources
               ┌───────────────┼───────────────┐
               │               │               │
               ▼               ▼               ▼
       ┌──────────────┐ ┌────────────┐ ┌──────────────┐
       │ common.sh    │ │ copilot.sh │ │ variants.sh  │
       │              │ │            │ │              │
       │ • is_safe    │ │ • optimize │ │ • lookup     │
       │ • skeleton   │ │ • track    │ │ • record     │
       │ • score      │ │ • health   │ │ • feedback   │
       │ • budget     │ │            │ │ • cleanup    │
       │ • safe_jq    │ │            │ │              │
       └──────┬───────┘ └─────┬──────┘ └──────┬───────┘
              │               │               │
              │               │               │
              ▼               ▼               ▼
       ┌────────────────────────────────────────────────┐
       │              Persistent State                  │
       │                                                │
       │  variants.jsonl  ←── cache + confidence        │
       │  feedback.jsonl  ←── execution history         │
       │  latency.jsonl   ←── Copilot response times    │
       │  session.jsonl   ←── recent skeletons (S2)     │
       │  pair_cache.jsonl←── pair-based cache (B1)     │
       │  .bridge/*.json  ←── pre→post communication    │
       │  logs/*.log      ←── operational logging       │
       └────────────────────────────────────────────────┘
```

### v3.0 Intent Protocol

```
   Claude                                 Bridge                          Copilot
   ──────                                 ──────                          ───────
   
   BRIDGE.md (in ~/.claude/
   copilot-cli-hook/) tells
   Claude about [GOAL: ...]
       │
       ▼
   Description: "[GOAL: find
   all TODO markers] grep
   -r 'TODO' --include='*.ts' ."
       │
       │  PreToolUse hook
       └─────────┬─────────────────────────────────────────────┐
                 │                                             │
                 ▼                                             ▼
          extract_goal()                              optimize_command()
          "[GOAL: find all                            "Task goal: find all
           TODO markers]"                              TODO markers.
                                                       Optimize: grep -r..."
                 │                                             │
                 │                                             ▼
                 │                                    Copilot CLI receives
                 │                                    goal-aware prompt
                 │                                             │
                 │                                             ▼
                 │                                    rg --glob '*.ts'
                 │                                    'TODO' .
                 │                                             │
                 └─────────┬───────────────────────────────────┘
                           │
                           ▼
                    Optimized command
                    executes in Bash
```

**I1: BRIDGE.md Deployment** — A standalone `BRIDGE.md` file deployed to `~/.claude/copilot-cli-hook/BRIDGE.md`. Tells Claude about the bridge and `[GOAL: ...]` markers. Never touches the user's CLAUDE.md — install.sh deploys it alongside hook scripts, and it can be deleted independently (same symmetry as settings.local.json).

**I2: Goal Extraction** — `extract_goal()` parses `[GOAL: <text>]` from descriptions. Simple regex, zero overhead, backward-compatible.

**P1: Enhanced Prompt Builder** — When a goal is present, Copilot CLI receives: `"Task goal: ${goal}. Optimize this shell command for the goal: ${cmd}."` — richer context, better optimizations.

### v3.1 Session Awareness

**S2: Session History** — `session.jsonl` tracks the last 5 (skeleton, goal, timestamp) triples for score≥3 commands. Bounded circular buffer. Enables pair cache.

**B1: Pair Cache** — `pair_cache.jsonl` caches optimizations keyed on `(prev_skeleton, curr_skeleton)` pairs. Queried before single cache. Bounded to 50 entries. Same confidence lifecycle as single cache.

**Pair cache query flow:**
```
   pair cache hit? ──► use cached pair optimization
       │ miss
       ▼
   single cache hit? ──► use cached single optimization
       │ miss
       ▼
   Copilot CLI → record both single + pair variants
```

## Changelog

### v3.0 — "The Intent Protocol" (2026-05-12)

**I1: BRIDGE.md Deployment** — Standalone `BRIDGE.md` deployed to `~/.claude/copilot-cli-hook/BRIDGE.md`. Never touches user's CLAUDE.md. Deleted on uninstall alongside settings.local.json.

**I2: [GOAL: ...] Parsing** — `extract_goal()` in common.sh extracts goal text from Bash command descriptions. Lightweight regex, backward-compatible (no marker = no change).

**P1: Enhanced Prompt Builder** — `optimize_command()` accepts optional goal parameter. Goal-aware prompt: `"Task goal: ${goal}. Optimize this shell command for the goal: ${cmd}."` Truncated to 200 chars.

**S2: Session History** — `session.jsonl` tracks last 5 skeletons with goals. Bounded circular buffer. Foundation for all temporal features.

**B1: Pair Cache** — `pair_cache.jsonl` caches `(prev_skeleton, curr_skeleton)` → optimized command. 50-entry bound. Confidence lifecycle mirrors single cache.

**Test Coverage** — 62 regression tests (62 pass, 0 fail): goal extraction (8), session history (6), pair cache (5), plus all v2.1 tests.

**Design** — `第三轮设计判断.md` documents the full orthogonal→composition→murphy→lazyeval→spiral analysis chain.

### v2.1 — "Murphy's Armor" (2026-05-12)

**S0: Hard Defenses (H1-H4)**
| Defense | Mechanism | Protects Against |
|---------|-----------|-----------------|
| H1 Time Watchdog | `check_time_budget()` — auto-passthrough after 10s | Hook timeout cascade (≥15s kills all Bash) |
| H2 ERROR Trap | `trap 'echo "$ORIGINAL_INPUT"; exit 0' ERR` | Accidental non-zero exit = blocked tool call |
| H3 Atomic Writes | `write → .tmp → mv` for all files | Bridge state corruption under concurrent writes |
| H4 jq Tolerance | `safe_jq()` wrapper with `\|\| true` fallback | Parse failures crashing post-tool-use |

**S1: Test Corpus** — 44 regression tests covering:
- Complexity scorer (16 test cases, scores 1-5)
- Safety classifier (20 test cases: safe/dangerous/unknown)
- Skeleton extraction (8 test cases: literal/path/glob/num placeholders)
- 7 real Claude command patterns with classification verification

**S3: Complexity Scorer** — `score_complexity()` rates commands 1-5:
- Dimensions: pipe count, flag count, subcommand count, argument count
- Threshold: score ≤ 2 → skip optimization (passthrough)
- Threshold: score ≥ 3 → allow optimization (cache → Copilot CLI)

**S4: Latency Tracker** — `~/.claude/copilot-cli-hook/latency.jsonl`:
- Sliding window average of last 10 Copilot calls
- Auto-disable Copilot optimization when avg latency > 10s
- Tracks success/failure per call

**S5: Simple-Cached Exception** — score ≤ 2 but conf ≥ 0.7:
- Even simple commands use cached optimizations when highly trusted
- Avoids re-optimizing proven command patterns

### v1.0 — Initial Release (2026-05-11)

- Phase 1: Passthrough hooks with JSON flow verification
- Phase 2: Copilot CLI command optimization for safe commands
- Phase 3: Feedback loop and variant library with confidence scoring

## Development

```
/workspace/Sandbox/claude-hook-copilot/   # Git repo (edit here)
├── src/                                   # Source files
├── install.sh                             # Deploy to ~/.claude/
└── README.md

Workflow: edit in repo → install.sh → test in Claude Code → commit + push
```
