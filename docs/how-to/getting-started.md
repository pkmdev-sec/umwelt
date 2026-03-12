# Getting Started

## Prerequisites

- Bash 4+ (macOS ships with Bash 3 — `brew install bash`)
- jq (recommended) or python3 (fallback)
- Claude Code CLI installed

## Installation

```bash
git clone https://github.com/pkmdev-sec/umwelt.git ~/.claude/umwelt
~/.claude/umwelt/umwelt install
```

This creates a symlink at `~/.local/bin/umwelt`. Ensure `~/.local/bin` is in your PATH.

## First Scan

```bash
# See what's available
umwelt list

# Run a single loader
umwelt git-context

# Run a full profile
umwelt profile dev
```

## Using with Claude Code

### Bang Syntax

Prefix commands with `!` backticks to inject output as context:

```
!`umwelt profile dev` What should I work on next?
!`umwelt git-context --diff` Review my staged changes
```

### Hook-Based (Automatic)

Install hooks so context loads automatically:

```bash
# Inject git context on every prompt
umwelt install-hook UserPromptSubmit git-context

# Full scan when session starts
umwelt install-hook SessionStart project-summary
```

### Ad-Hoc Compose

Mix and match loaders:

```bash
umwelt compose git-context test-status deps-audit
```

## Enable Diff Mode

Save tokens on repeated calls:

```bash
umwelt --diff profile dev
```

First call: full scan (~740 tokens). Subsequent calls: only changes (~80 tokens).

## Set Token Budget

```bash
umwelt --budget 5000 profile dev
```

Auto-downgrades profiles when approaching 5000 tokens cumulative.

## Next Steps

- Read [Architecture](../core-concepts/architecture.md) for the full component map
- Read [Innovations](../core-concepts/innovations.md) for the 10 features
- Read [Loaders Reference](../reference/loaders.md) for all loader options
- Read [Profiles Reference](../reference/profiles.md) for all profile details
