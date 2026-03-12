# Architecture

## Pipeline

```
User prompt → Profile selected → Loaders run (parallel) → Diff engine → Cache split → Output assembly → Hook injection → Context window
```

## Components

### Profiles
Task-specific loader combinations. Each profile defines which loaders to run and at what detail level.

- **dev** — git + tests + env + project (general development)
- **debug** — full env + docker logs + error scanning + processes
- **review** — git diff + branch comparison + tests
- **deploy** — git + deps + docker + APIs + build readiness
- **minimal** — cwd + branch only (<200 tokens)

### Loaders
Individual environment sensors. Each extracts one dimension of context:

| Loader | Senses | Output |
|--------|--------|--------|
| git-context | Git state | Branch, status, commits, diffs, stash |
| test-status | Test frameworks | Framework, pass/fail, coverage, last run |
| env-summary | System environment | OS, shell, runtimes, package managers |
| docker-status | Docker | Containers, compose, images, logs |
| deps-audit | Dependencies | Lock files, counts, outdated, vulnerabilities |
| project-summary | Project structure | Files, tech stack, entry points, configs |
| api-health | Network services | Port scan, endpoint health, latency |

### Libraries

| Library | Purpose |
|---------|---------|
| diff-engine.sh | Hash-based change detection, skip unchanged loaders |
| token-budget.sh | Cumulative token tracking, auto-downgrade |
| cache-split.sh | STABLE/VOLATILE section splitting |
| cost-tracker.sh | Session cost estimation and budget enforcement |
| loader-intelligence.sh | Relevance detection, message prediction |
| predictor.sh | Keyword-based loader prediction |
| event-router.sh | Hook event to loader mapping |
| unified-engine.sh | Umwelt + Sigil combined assembly |
| parallel.sh | File-based semaphore parallel execution |
| config.sh | 4-level configuration merge |
| output.sh | Text/JSON formatting with stable/volatile markers |

### Supporting Scripts

| Script | Purpose |
|--------|---------|
| umwelt-adaptive.sh | Model-aware adaptive profile routing |
| umwelt-cache-warm.sh | SessionStart cache pre-warming |
| umwelt-precompact.sh | PreCompact context preservation |
