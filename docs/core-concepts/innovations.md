# Ten Innovations

All innovations are derived from reverse engineering of Claude Code's internal architecture (561K+ lines of source code).

## 1. Diff-Based Injection
Caches previous loader outputs using SHA-256 hashes. On subsequent calls, only changed loaders produce output. Result: **80-90% token savings** on repeated scans.

## 2. Token-Aware Profiling
Tracks cumulative token injection per session. Auto-downgrades profiles when approaching budget limits:
- 50% budget → debug downgrades to dev
- 75% budget → any profile downgrades to minimal
- 90% budget → silent mode (no output)

## 3. Cache-Friendly Output
Splits context into STABLE (OS, shell, runtimes — cached after first call) and VOLATILE (git status, ports — always fresh). Enables **90% prompt cache hit rate** by keeping the stable prefix identical across calls.

## 4. Event-Optimized Loading
Maps hook events to appropriate scanning depth:
- `SessionStart` → full environment scan
- `UserPromptSubmit` → lightweight diff only
- `SubagentStart` → minimal context
- `PreCompact` → preserve critical state

## 5. Model-Aware Profiles
Detects Claude model tier (Opus/Sonnet/Haiku) and auto-selects context depth:
- Opus → debug profile (full context, large window)
- Sonnet → dev profile (balanced)
- Haiku → minimal profile (token-constrained)

## 6. Cost-Conscious Scanning
Tracks injection cost per session using Sonnet pricing ($3/M input tokens). Auto-reduces scanning at thresholds:
- < $0.10 → full mode
- $0.10–$0.25 → reduced (skip docker, api-health, deps-audit)
- $0.25–$0.50 → minimal (git + project only)
- > $0.50 → silent (no injection)

## 7. Intelligent Loaders
Loaders detect their own relevance before running:
- Docker loader skips if Docker isn't installed/running
- API health skips if no services respond on common ports
- Test status skips if no test framework detected
- Deps audit skips if no package manager files exist

## 8. Predictive Context Loading
Analyzes user message keywords to predict which loaders matter:
- "fix the failing tests" → git-context, test-status, project-summary
- "check docker containers" → git-context, docker-status
- "debug the API" → git-context, api-health, env-summary

## 9. Smart PreCompact
Preserves critical environment state before Claude Code's context compaction. Ensures the AI retains awareness of project state even after conversation compression.

## 10. Unified Context Engine
Combines Umwelt environment data with Sigil prompt templates into a single optimized injection. Assembly order matches Claude's internal prompt section structure. Priority-based trimming ensures the most important context survives budget constraints.
